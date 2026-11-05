// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// The few questions Lota's bindings ask of a Ruby value that Rice does not
// answer, and the Ruby value the engine keeps alive, in one place, so each
// binding reaches Ruby's C API through this header alone.

#ifndef LOTA_NATIVE_RUBY_HPP
#define LOTA_NATIVE_RUBY_HPP

#include "native/binding.hpp"

#include <mutex>
#include <string>
#include <unordered_set>
#include <vector>

namespace lota::native::ruby {

inline bool is_nil(const Rice::Object &value) { return NIL_P(value.value()); }

inline bool is_array(const Rice::Object &value) {
  return rb_obj_is_kind_of(value.value(), rb_cArray) == Qtrue;
}

// The number of elements of +array+, and the one at +index+. Read one at
// a time, rather than copied out, each stays where Ruby's collector can
// see it, in +array+, however long a caller takes over the rest.
inline long length(const Rice::Array &array) { return RARRAY_LEN(array.value()); }

inline Rice::Object entry(const Rice::Array &array, long index) {
  return {rb_ary_entry(array.value(), index)};
}

inline bool is_string(const Rice::Object &value) {
  return rb_obj_is_kind_of(value.value(), rb_cString) == Qtrue;
}

inline bool is_numeric(const Rice::Object &value) {
  return rb_obj_is_kind_of(value.value(), rb_cNumeric) == Qtrue;
}

// Whether +value+ is true or false itself, as Lua's lua_isboolean asks.
inline bool is_boolean(const Rice::Object &value) {
  return value.value() == Qtrue || value.value() == Qfalse;
}

inline bool is_true(const Rice::Object &value) { return value.value() == Qtrue; }

inline bool is_symbol(const Rice::Object &value) { return RB_SYMBOL_P(value.value()); }

// The name of the Symbol +value+.
inline std::string symbol_name(const Rice::Object &value) {
  return Rice::detail::From_Ruby<std::string>().convert(rb_sym2str(value.value()));
}

// Whether +value+ is a +klass+, or of a class under it, as Ruby's is_a?
// asks; nil is a NilClass, where Rice's own is_a refuses nil.
inline bool is_kind_of(const Rice::Object &value, const Rice::Class &klass) {
  return rb_obj_is_kind_of(value.value(), klass.value()) == Qtrue;
}

// The name of +value+'s class, for a TypeError's message.
inline std::string class_name(const Rice::Object &value) { return rb_obj_classname(value.value()); }

// Ruby's truth, which is Lua's: everything but nil and false.
inline bool truthy(const Rice::Object &value) { return RTEST(value.value()); }

inline Rice::Object nil() { return {Qnil}; }

// The elements of +array+, to index with bounds checked.
inline std::vector<Rice::Object> elements(const Rice::Array &array) {
  std::vector<Rice::Object> values;
  values.reserve(static_cast<std::size_t>(array.size()));
  for (const auto item : array) {
    values.emplace_back(item.value());
  }
  return values;
}

[[noreturn]] inline void raise_type_error(const std::string &message) {
  throw Rice::Exception(rb_eTypeError, "%s", message.c_str());
}

[[noreturn]] inline void raise_argument_error(const std::string &message) {
  throw Rice::Exception(rb_eArgError, "%s", message.c_str());
}

// Something the engine holds that holds Ruby values, which Ruby's garbage
// collector must see however long the engine keeps it (Marks, below).
class Marked {
public:
  Marked() = default;
  Marked(const Marked &) = delete;
  Marked(Marked &&) = delete;
  Marked &operator=(const Marked &) = delete;
  Marked &operator=(Marked &&) = delete;

  // Marks the Ruby values it holds. It runs while Ruby collects, when no
  // Ractor runs Ruby code, so it must neither allocate nor call Ruby.
  virtual void mark() const = 0;

protected:
  ~Marked() = default;
};

// The roots of Ruby's garbage collector that live in the engine, in every
// Ractor at once: one hidden object, which Init_native makes and Ruby
// marks on every collection, marks each Marked object there is.
//
// rb_gc_register_address, which roots one address, is not for this: it
// links the address into one list the whole VM shares, with no lock
// (Ruby 4.0.7, gc.c:3444-3488), so two Ractors that root values at once
// corrupt it, and a lock of Lota's own around it could not help, for it
// allocates, and a collection that started there would wait for the
// other Ractor, which waits for the lock. Here the lock guards a set that
// only C++ allocates for, so whoever holds it never waits on Ruby, and the
// collector, which stops every Ractor first, takes it only once no
// Ractor's Ruby code does.
class Marks {
public:
  static Marks &instance() {
    static Marks marks;
    return marks;
  }

  Marks(const Marks &) = delete;
  Marks(Marks &&) = delete;
  Marks &operator=(const Marks &) = delete;
  Marks &operator=(Marks &&) = delete;
  ~Marks() = default;

  // Makes the object Ruby marks them from, once, from Init_native, on the
  // main Ractor. Ruby never frees it.
  void install() {
    if (installed_) {
      return;
    }
    const VALUE marker = rb_data_typed_object_wrap(0, this, &TYPE);
    rb_gc_register_mark_object(marker);
    installed_ = true;
  }

  void add(const Marked *marked) {
    const std::scoped_lock lock(mutex_);
    marked_.insert(marked);
  }

  // It may run while Ruby collects another object whose release destroys
  // +marked+, and allocates nothing.
  void remove(const Marked *marked) noexcept {
    const std::scoped_lock lock(mutex_);
    marked_.erase(marked);
  }

private:
  Marks() = default;

  static void mark_all(void *data) {
    auto *marks = static_cast<Marks *>(data);
    const std::scoped_lock lock(marks->mutex_);
    for (const Marked *marked : marks->marked_) {
      marked->mark();
    }
  }

  // Ruby's own TypedData struct, which it names without a prefix.
  // NOLINTNEXTLINE(readability-identifier-naming)
  static constexpr rb_data_type_t TYPE = {
      .wrap_struct_name = "Lota::Native marks",
      .function = {.dmark = &mark_all,
                   .dfree = nullptr,
                   .dsize = nullptr,
                   .dcompact = nullptr,
                   .reserved = {}},
      .parent = nullptr,
      .data = nullptr,
      .flags = 0,
  };

  std::mutex mutex_;
  std::unordered_set<const Marked *> marked_;
  bool installed_ = false;
};

// A Ruby value that stays alive while this object does: a root of Ruby's
// garbage collector, as a Lua reference keeps its value in the registry.
// It may be made and destroyed in any Ractor (Marks), and its destructor
// allocates nothing, so it may run while Ruby collects another object
// whose release destroys this one. The value is pinned, so GC.compact
// never moves it, as rb_gc_register_address pinned it before.
class Root final : public Marked {
public:
  explicit Root(const Rice::Object &value) : value_(value.value()) { Marks::instance().add(this); }

  Root(const Root &) = delete;
  Root(Root &&) = delete;
  Root &operator=(const Root &) = delete;
  Root &operator=(Root &&) = delete;

  ~Root() { Marks::instance().remove(this); }

  [[nodiscard]] Rice::Object value() const { return {value_}; }

  // Lets the value go, while this object lives on.
  void clear() { value_ = Qnil; }

  void mark() const override { rb_gc_mark(value_); }

private:
  VALUE value_;
};

} // namespace lota::native::ruby

#endif // LOTA_NATIVE_RUBY_HPP
