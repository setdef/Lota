// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// Rice, as Lota's bindings include it: with LÖVE's memory model (ADR 001,
// section 5) in place before any binding can wrap a love::Object.
//
// Every binding includes this header instead of Rice's own. A translation
// unit that included <rice/rice.hpp> alone would wrap love::Object pointers
// with Rice's default Wrapper, which deletes what Ruby owns instead of
// releasing it.

#ifndef LOTA_NATIVE_BINDING_HPP
#define LOTA_NATIVE_BINDING_HPP

// A binding that includes this header uses Rice and love::Object through
// it, so it re-exports them (include-what-you-use's export pragma, which
// clang-tidy's misc-include-cleaner reads).
//
// rice/stl.hpp converts std::string, among others; it follows rice/rice.hpp.
#include <rice/rice.hpp> // IWYU pragma: export
#include <rice/stl.hpp>  // IWYU pragma: export

#include "common/Object.h" // IWYU pragma: export

#include <concepts>
#include <type_traits>

namespace lota::native {

// A LÖVE engine object: anything that counts its references with
// love::Object (vendor/love/src/common/Object.h).
template <typename T>
concept LoveObject = std::derived_from<std::remove_cv_t<T>, love::Object>;

// The memory rule, in one place: a Ruby wrapper holds one reference to its
// engine object, from the moment Ruby wraps it until Ruby's garbage
// collector frees the wrapper.
//
// Rice frees a wrapper by deleting it in the typed data's dfree function,
// ruby_free_internal (Rice 4.12.0, rice/Data_Type.ipp:18-22, installed at
// :58), so this destructor runs when Ruby collects the object. The reference is LÖVE's
// own love::StrongRef, which retains or adopts as it is told and releases
// when destroyed, exactly as LÖVE's C++ holds objects.
template <LoveObject T> class ObjectWrapper : public Rice::detail::WrapperBase {
  static_assert(!std::is_const_v<T>,
                "love::Object counts references in non-const retain() and release(), so "
                "bind functions that return engine objects as non-const pointers");

public:
  ObjectWrapper(rb_data_type_t *rb_data_type, T *object, love::Acquire acquire)
      : WrapperBase(rb_data_type), reference_(object, acquire) {}

  ObjectWrapper(const ObjectWrapper &) = delete;
  ObjectWrapper(ObjectWrapper &&) = delete;
  ObjectWrapper &operator=(const ObjectWrapper &) = delete;
  ObjectWrapper &operator=(ObjectWrapper &&) = delete;

  // As Rice's own wrappers do (rice/detail/Wrapper.ipp:117-135), forget
  // the instance before letting it go; reference_ then releases it.
  ~ObjectWrapper() override {
    Rice::detail::Registries::instance.instances.remove(reference_.get());
  }

  // Rice's own check (rice/detail/Wrapper.ipp:137-150).
  void *get(rb_data_type_t *requested_type) override {
    if (rb_typeddata_inherited_p(this->rb_data_type_, requested_type) == 0) {
      throw Rice::Exception(rb_eTypeError, "wrong argument type %s (expected %s)",
                            this->rb_data_type_->wrap_struct_name,
                            requested_type->wrap_struct_name);
    }
    return reference_.get();
  }

private:
  love::StrongRef<T> reference_;
};

} // namespace lota::native

namespace Rice::detail {

// Constrained partial specializations (C++20) are more specialized than
// Rice's unconstrained ones (rice/detail/Wrapper.hpp:36-71), so Rice picks these
// for every love::Object subclass and its own for everything else.

// A pointer: what LÖVE's API returns. Rice constructs this wrapper with
// isOwner true for a constructor (wrapConstructed) or a function bound with
// Return().takeOwnership(), and false otherwise (rice/detail/Wrapper.ipp:
// wrap at 267-280, wrapConstructed at 347-374). An owned pointer comes with the reference its
// creator counted (love::Object starts at one), so the wrapper adopts it;
// any other pointer is retained.
template <typename T>
  requires lota::native::LoveObject<T>
class Wrapper<T *> : public lota::native::ObjectWrapper<T> {
public:
  Wrapper(rb_data_type_t *rb_data_type, T *data, bool isOwner)
      : lota::native::ObjectWrapper<T>(rb_data_type, data,
                                       isOwner ? love::Acquire::NORETAIN : love::Acquire::RETAIN) {}
};

// A reference that C++ keeps (wrapReference, rice/detail/Wrapper.ipp:
// 207-218): retained like a pointer.
template <typename T>
  requires lota::native::LoveObject<T>
class Wrapper<T &> : public lota::native::ObjectWrapper<T> {
public:
  Wrapper(rb_data_type_t *rb_data_type, T &data)
      : lota::native::ObjectWrapper<T>(rb_data_type, &data, love::Acquire::RETAIN) {}
};

// A value: Rice would copy the engine object into the wrapper and destroy
// the copy with the wrapper, whatever its reference count said. LÖVE hands
// out engine objects by pointer, so a binding that would copy one does not
// compile.
template <typename T>
  requires lota::native::LoveObject<T>
class Wrapper<T> : public WrapperBase {
  static_assert(!lota::native::LoveObject<T>,
                "engine objects cross into Ruby by pointer, never by value or as an "
                "owned reference; bind a function that returns T*");
};

} // namespace Rice::detail

#endif // LOTA_NATIVE_BINDING_HPP
