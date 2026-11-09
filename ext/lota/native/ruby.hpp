// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// The few questions Lota's bindings ask of a Ruby value that Rice does not
// answer, and the Ruby value the engine keeps alive, in one place, so each
// binding reaches Ruby's C API through this header alone.

#ifndef LOTA_NATIVE_RUBY_HPP
#define LOTA_NATIVE_RUBY_HPP

#include "native/binding.hpp"

#include <ruby/thread.h>

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

inline bool is_hash(const Rice::Object &value) {
  return rb_obj_is_kind_of(value.value(), rb_cHash) == Qtrue;
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

// Marks +value+ for Ruby's collector, from a Marked's mark.
inline void mark(VALUE value) { rb_gc_mark(value); }

// The Ruby thread running this code, which holds a Data or a Channel in
// perform_atomic, compared by identity.
inline VALUE current_thread() { return rb_thread_current(); }

// Whether Ractors share +value+, as Ractor.shareable? answers. Ruby 4.0's
// inline rb_ractor_shareable_p (ruby/ractor.h:249-262) declares
// rb_ractor_shareable_p_continue inside its own body, outside the header's
// extern "C" block, so from C++ it names a mangled symbol that no Ruby
// exports; Ruby's method links everywhere.
inline bool shareable(const Rice::Object &value) {
  const Rice::Object ractor(Rice::detail::protect(rb_path2class, "Ractor"));
  return truthy(ractor.call("shareable?", value));
}

// Calls +function+ with +data+ with the GVL released, as Ruby's own sleep
// waits, and then runs Ruby's pending interrupts, as an exception of
// Rice's rather than a longjmp through C++ frames. Nothing can cut
// +function+ short.
inline void without_gvl(void *(*function)(void *), void *data) {
  Rice::detail::protect(rb_thread_call_without_gvl, function, data,
                        static_cast<rb_unblock_function_t *>(nullptr),
                        static_cast<void *>(nullptr));
}

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
  // Ruby code runs, so it must neither allocate nor call Ruby.
  virtual void mark() const = 0;

protected:
  ~Marked() = default;
};

// The Marked objects there are, which one hidden object, made by
// Init_native and marked by Ruby on every collection, marks.
//
// A Marked object is made and destroyed in any Ractor, so a lock guards
// the set. It guards a set only C++ allocates for, so whoever holds it
// never waits on Ruby, and the collector, which stops every Ractor first,
// takes it only once no Ractor's Ruby code does; a lock that Ruby could
// wait on while it allocated would let a collection that started there
// wait for the other Ractor, which would wait for the lock. A Marked
// object marks only shareable values, as Ruby 4.1 asks of what a root
// shared by every Ractor holds (Feature #22277).
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
    rb_gc_register_mark_object(rb_data_typed_object_wrap(0, this, &TYPE));
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
    const auto *marks = static_cast<Marks *>(data);
    const std::scoped_lock lock(marks->mutex_);
    for (const Marked *marked : marks->marked_) {
      marked->mark();
    }
  }

  static constexpr rb_data_type_t TYPE = {
      .wrap_struct_name = "Lota::Native marks",
      .function =
          {
              .dmark = &mark_all,
              .dfree = nullptr,
              .dsize = nullptr,
              .dcompact = nullptr,
              .reserved = {},
          },
      .parent = nullptr,
      .data = nullptr,
      .flags = 0,
  };

  mutable std::mutex mutex_;
  std::unordered_set<const Marked *> marked_;
  bool installed_ = false;
};

// A Ruby value that stays alive while this object does: a root of Ruby's
// garbage collector, as a Lua reference keeps its value in the registry.
// It holds a value of the Ractor that made it, or a shareable one, as
// Ruby 4.1 asks of an address it roots (Feature #22277). Its destructor
// only unregisters the address, which allocates nothing, so it may run
// while Ruby collects another object whose release destroys this one.
class Root {
public:
  explicit Root(const Rice::Object &value) : value_(value.value()) {
    rb_gc_register_address(&value_);
  }

  Root(const Root &) = delete;
  Root(Root &&) = delete;
  Root &operator=(const Root &) = delete;
  Root &operator=(Root &&) = delete;

  ~Root() { rb_gc_unregister_address(&value_); }

  [[nodiscard]] Rice::Object value() const { return {value_}; }

  // Lets the value go, while this object lives on.
  void clear() { value_ = Qnil; }

private:
  VALUE value_;
};

} // namespace lota::native::ruby

#endif // LOTA_NATIVE_RUBY_HPP
