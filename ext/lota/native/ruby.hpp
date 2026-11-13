// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// The few questions Lota's bindings ask of a Ruby value that Rice does not
// answer, and the Ruby value the engine keeps alive, in one place, so each
// binding reaches Ruby's C API through this header alone.

#ifndef LOTA_NATIVE_RUBY_HPP
#define LOTA_NATIVE_RUBY_HPP

#include "native/binding.hpp"

#include <ruby/ractor.h>
#include <ruby/thread.h>

#include <atomic>
#include <cstdint>
#include <memory>
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

// A Ruby thread, which holds a Data in perform_atomic, compared by
// identity; no_thread() is none.
using ThreadId = VALUE;

inline ThreadId no_thread() { return Qfalse; }

// The Ruby thread running this code.
inline ThreadId current_thread() { return rb_thread_current(); }

// A Ruby value as the C API holds it, and the description of a typed
// data object's type, for the bindings that keep Ruby values in C++.
using Value = VALUE;
using DataType = rb_data_type_t;

// The type of the typed data object +object+.
inline const DataType *data_type(Value object) { return RTYPEDDATA_TYPE(object); }

// Marks +value+ for Ruby's collector, from a Marked's mark.
inline void mark(VALUE value) { rb_gc_mark(value); }

// Whether Ractors share +value+, as Ractor.shareable? answers. Ruby 4.0's
// inline rb_ractor_shareable_p (ruby/ractor.h:249-262) declares
// rb_ractor_shareable_p_continue inside its own body, outside the header's
// extern "C" block, so from C++ it names a mangled symbol that no Ruby
// exports; Ruby's method links everywhere.
inline bool shareable(const Rice::Object &value) {
  const Rice::Object ractor(Rice::detail::protect(rb_path2class, "Ractor"));
  return truthy(ractor.call("shareable?", value));
}

// Runs the interrupts Ruby has pending for this thread, as Ruby does as it
// returns from a call that released the GVL; an exception one raises
// reaches C++ as Rice's, rather than as a longjmp through C++ frames.
inline void check_interrupts() { Rice::detail::protect(rb_thread_check_ints); }

// Calls +function+, a mutable lambda, with the GVL released, as Ruby's own
// sleep waits, and then runs Ruby's pending interrupts, as an exception of
// Rice's rather than a longjmp through C++ frames. Nothing can cut
// +function+ short.
template <typename Function> void without_gvl(Function &function) {
  const auto call = [](void *data) -> void * {
    (*static_cast<Function *>(data))();
    return nullptr;
  };
  Rice::detail::protect(rb_thread_call_without_gvl, +call, static_cast<void *>(&function),
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
    rb_gc_register_mark_object(rb_data_typed_object_wrap(0, this, type()));
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

  // Ruby's description of the hidden object, every field but these two
  // zero, whichever fields this Ruby's rb_data_type_t has.
  static const rb_data_type_t *type() {
    static const rb_data_type_t described = [] {
      rb_data_type_t type{};
      type.wrap_struct_name = "Lota::Native marks";
      type.function.dmark = &mark_all;
      return type;
    }();
    return &described;
  }

  mutable std::mutex mutex_;
  std::unordered_set<const Marked *> marked_;
  bool installed_ = false;
};

// A number for the Ractor running this code, the same each time it asks,
// and never another Ractor's, even one that has ended: a count kept in the
// Ractor's local storage, which frees it as the Ractor ends.
inline std::uint64_t current_ractor() {
  static const rb_ractor_local_storage_type type = {
      .mark = nullptr,
      .free =
          [](void *number) {
            const std::unique_ptr<std::uint64_t> owned(static_cast<std::uint64_t *>(number));
          },
  };
  static rb_ractor_local_key_t key = rb_ractor_local_storage_ptr_newkey(&type);
  static std::atomic<std::uint64_t> made{0};
  const auto *number = static_cast<const std::uint64_t *>(rb_ractor_local_storage_ptr(key));
  if (number == nullptr) {
    auto owned = std::make_unique<std::uint64_t>(++made);
    number = owned.get();
    rb_ractor_local_storage_ptr_set(key, owned.release());
  }
  return *number;
}

// A Ruby value that stays alive while this object does: a root of Ruby's
// garbage collector, as a Lua reference keeps its value in the registry.
// Its destructor only unregisters the address, which allocates nothing, so
// it may run while Ruby collects another object whose release destroys
// this one.
//
// Only the Ractor that set the value may read it. The engine object that
// holds it, a Body with user data or a World with callbacks, may reach
// another Ractor, as LÖVE's channels carry it to another thread, but the
// value is the setting Ractor's own: Ruby lets no other Ractor touch an
// object it does not share, and its collector is the one that marks it.
// In LÖVE the value lives in the registry of the Lua state that set it, so
// no other state uses it either. Reading it elsewhere raises
// Ractor::IsolationError, saying so.
class Root {
public:
  explicit Root(const Rice::Object &value) : value_(value.value()), owner_(current_ractor()) {
    rb_gc_register_address(&value_);
  }

  Root(const Root &) = delete;
  Root(Root &&) = delete;
  Root &operator=(const Root &) = delete;
  Root &operator=(Root &&) = delete;

  ~Root() { rb_gc_unregister_address(&value_); }

  [[nodiscard]] Rice::Object value() const {
    if (owner_ != current_ractor()) {
      const Rice::Object isolation(Rice::detail::protect(rb_path2class, "Ractor::IsolationError"));
      throw Rice::Exception(isolation.value(),
                            "this Ruby value was set in another thread, whose Ractor alone may "
                            "use it");
    }
    return {value_};
  }

  // Lets the value go, while this object lives on.
  void clear() { value_ = Qnil; }

private:
  VALUE value_;
  std::uint64_t owner_;
};

} // namespace lota::native::ruby

#endif // LOTA_NATIVE_RUBY_HPP
