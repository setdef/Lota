// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// The few questions Lota's bindings ask of a Ruby value that Rice does not
// answer, and the Ruby value the engine keeps alive, in one place, so each
// binding reaches Ruby's C API through this header alone.

#ifndef LOTA_NATIVE_RUBY_HPP
#define LOTA_NATIVE_RUBY_HPP

#include "native/binding.hpp"

#include <ruby/thread.h>

#include <string>
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

// Runs the interrupts Ruby has pending for this thread, as Ruby does as it
// returns from a call that released the GVL; an exception one raises
// reaches C++ as Rice's, rather than as a longjmp through C++ frames.
inline void check_interrupts() { Rice::detail::protect(rb_thread_check_ints); }

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

// A Ruby value that stays alive while this object does: a root of Ruby's
// garbage collector, as a Lua reference keeps its value in the registry.
// Its destructor only unregisters the address, which allocates nothing, so
// it may run while Ruby collects another object whose release destroys
// this one.
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
