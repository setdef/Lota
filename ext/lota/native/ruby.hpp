// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// The few questions Lota's bindings ask of a Ruby value that Rice does not
// answer, and the Ruby value the engine keeps alive, in one place, so each
// binding reaches Ruby's C API through this header alone.

#ifndef LOTA_NATIVE_RUBY_HPP
#define LOTA_NATIVE_RUBY_HPP

#include "native/binding.hpp"

#include <string>
#include <vector>

namespace lota::native::ruby {

inline bool is_nil(const Rice::Object &value) { return NIL_P(value.value()); }

inline bool is_array(const Rice::Object &value) {
  return rb_obj_is_kind_of(value.value(), rb_cArray) == Qtrue;
}

inline bool is_numeric(const Rice::Object &value) {
  return rb_obj_is_kind_of(value.value(), rb_cNumeric) == Qtrue;
}

// Whether +value+ is true or false itself, as Lua's lua_isboolean asks.
inline bool is_boolean(const Rice::Object &value) {
  return value.value() == Qtrue || value.value() == Qfalse;
}

inline bool is_true(const Rice::Object &value) { return value.value() == Qtrue; }

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
