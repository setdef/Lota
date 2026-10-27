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

#include "common/Exception.h"
#include "common/Module.h"
#include "common/Object.h" // IWYU pragma: export
#include "common/types.h"

// The engine classes of the modules LÖVE confines to its main thread, so
// that every binding sees the same list (ReleasedOnMainThread, below).
#include "graphics/Font.h"
#include "graphics/Quad.h"
#include "graphics/SpriteBatch.h"
#include "graphics/Texture.h"

#include <concepts>
#include <cstddef>
#include <memory>
#include <mutex>
#include <optional>
#include <stdexcept>
#include <string>
#include <type_traits>
#include <vector>

#include <pthread.h>

namespace lota::native {

// A LÖVE engine object: anything that counts its references with
// love::Object (vendor/love/src/common/Object.h).
template <typename T>
concept EngineObject = std::derived_from<std::remove_cv_t<T>, love::Object>;

// Whether this is the process's main thread, the one the operating system
// started the process on. macOS runs windows and graphics only there. SDL's
// own SDL_IsMainThread cannot say: it answers for whichever thread first
// initialized SDL, and true on any thread before that (Plan 001, spike 2).
inline bool on_main_thread() { return pthread_main_np() == 1; }

// Raises ThreadError unless this is the main thread. +module+ names the
// Lota module the caller belongs to, for the message.
inline void require_main_thread(const char *module) {
  if (!on_main_thread()) {
    throw Rice::Exception(rb_eThreadError, "%s runs only on the main thread", module);
  }
}

// The value of an argument the binding generator made optional only
// because it follows an optional one, as a Ruby method's positional
// parameters must (tasks/bindings/port.rb, trailing_optional), in a form
// that requires it: LÖVE reads it with a check there. A missing one raises
// ArgumentError, naming it as Rice names a missing argument.
template <typename T> T required(const std::optional<T> &argument, const std::string &name) {
  if (!argument.has_value()) {
    throw std::invalid_argument("Missing argument. Name: " + name + ".");
  }
  return *argument;
}

// What luax_ioError returns (vendor/love/src/modules/filesystem/
// wrap_File.cpp:34-46): nil and the message +format+ makes of +arguments+,
// which LÖVE formats with lua_pushvfstring and Lota with love::Exception's
// own formatting, as an Array, as ADR 001's rule 4 returns a function's
// several values on failure too.
template <typename... Arguments> Rice::Array io_error(const char *format, Arguments... arguments) {
  const love::Exception error(format, arguments...);
  Rice::Array results;
  results.push(Rice::Object(), false);
  results.push(Rice::String(error.what()), false);
  return results;
}

// Whether engine objects of class T are released only on the main thread.
// LÖVE's thread module keeps love.graphics and love.window off every other
// thread (vendor/love/src/modules/thread/LuaThread.cpp:72-73), and Lua
// collects only on the main thread, so in LÖVE their objects are always
// released there. Every class bound from those two modules is listed here,
// in this one header, so that every translation unit agrees.
template <typename T> struct ReleasedOnMainThread : std::false_type {};
template <> struct ReleasedOnMainThread<love::graphics::Texture> : std::true_type {};
template <> struct ReleasedOnMainThread<love::graphics::Font> : std::true_type {};
template <> struct ReleasedOnMainThread<love::graphics::Quad> : std::true_type {};
template <> struct ReleasedOnMainThread<love::graphics::SpriteBatch> : std::true_type {};

// Releases that Ruby's garbage collector asked for off the main thread, for
// the main thread to carry out (ADR 001, section 5). Ruby frees a wrapper
// on whichever thread triggered the collection; the queue takes over the
// wrapper's reference, so the object outlives the wrapper until the main
// thread drains the queue.
//
// Each bundle has its own queue, as it has its own copy of LÖVE's engine
// (cmake/LotaExtension.cmake): the function-local static below is hidden
// in each.
class ReleaseQueue {
public:
  static ReleaseQueue &instance() {
    static ReleaseQueue queue;
    return queue;
  }

  ReleaseQueue(const ReleaseQueue &) = delete;
  ReleaseQueue(ReleaseQueue &&) = delete;
  ReleaseQueue &operator=(const ReleaseQueue &) = delete;
  ReleaseQueue &operator=(ReleaseQueue &&) = delete;
  ~ReleaseQueue() = default;

  // Holds a reference to +object+ until the next drain. It runs in a
  // wrapper's destructor, which must not throw; if the queue cannot grow,
  // the object keeps the reference for good, since a leak is safer than a
  // release on the wrong thread.
  void push(love::Object *object) noexcept {
    try {
      const std::scoped_lock lock(mutex_);
      queued_.emplace_back(object, love::Acquire::RETAIN);
    } catch (...) {
      object->retain();
    }
  }

  // Releases every queued reference, on the main thread, and returns how
  // many there were. The references are taken out of the queue before any
  // is released, so a destructor that frees another wrapper cannot touch
  // the queue while it is locked.
  std::size_t drain() {
    require_main_thread("Lota::Native.drain_release_queue");
    std::vector<love::StrongRef<love::Object>> drained;
    {
      const std::scoped_lock lock(mutex_);
      drained.swap(queued_);
    }
    return drained.size();
  }

  // How many releases wait for the next drain.
  std::size_t size() {
    const std::scoped_lock lock(mutex_);
    return queued_.size();
  }

private:
  ReleaseQueue() = default;

  std::mutex mutex_;
  std::vector<love::StrongRef<love::Object>> queued_;
};

// Opens the LÖVE module Opened (of kind Base) for the rest of the process,
// unless it is already open, and returns it. Its constructor registers it
// as the module's instance (love::Module, common/Module.cpp), where the
// rest of the engine finds it; the registry keeps the pointer, not a
// reference, so the reference the module starts with is the one that
// keeps it open. LÖVE, too, keeps its modules until the game quits.
template <std::derived_from<love::Module> Base, std::derived_from<Base> Opened>
Base *open_module(love::Module::ModuleType type) {
  if (auto *opened = love::Module::getInstance<Base>(type)) {
    return opened;
  }
  return std::make_unique<Opened>().release();
}

// The memory rule, in one place: a Ruby wrapper holds one reference to its
// engine object, from the moment Ruby wraps it until Ruby's garbage
// collector frees the wrapper.
//
// Rice frees a wrapper by deleting it in the typed data's dfree function,
// ruby_free_internal (Rice 4.12.0, rice/Data_Type.ipp:18-22, installed at
// :58), so this destructor runs when Ruby collects the object. The reference is LÖVE's
// own love::StrongRef, which retains or adopts as it is told and releases
// when destroyed, exactly as LÖVE's C++ holds objects.
template <EngineObject T> class ObjectWrapper : public Rice::detail::WrapperBase {
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
  // the instance before letting it go; reference_ then releases it. Off the
  // main thread, an object of a main-thread module first joins the release
  // queue, which retains it, so reference_'s release cannot be the last.
  ~ObjectWrapper() override {
    Rice::detail::Registries::instance.instances.remove(reference_.get());
    if constexpr (ReleasedOnMainThread<T>::value) {
      if (!on_main_thread()) {
        ReleaseQueue::instance().push(reference_.get());
      }
    }
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

// SPDX-SnippetBegin
// SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
// SPDX-License-Identifier: Zlib
//
// Ported from luax_register_type, w__type, and w__typeOf
// (vendor/love/src/common/runtime.cpp:65-80, 489-491, and 538-544), and
// changed to define Ruby methods on a Rice class instead of filling a Lua
// metatable.

// Defines Lota::Native's class +name+ under +parent+ for the engine class
// T, with the methods every LÖVE object has (ADR 001, rule 16): +type+,
// LÖVE's name for T, and +type_of?+, whether T is the type of that name or
// one of its parents. Every engine class Lota binds is defined through
// here, once, so every one answers both. Base, when given, is the bound
// class Ruby's class inherits from, as Rice's define_class_under takes it.
//
// LÖVE registers each type it pushes to Lua before pushing one, which
// initializes the type (luax_register_type), and love::Type::byName finds
// only an initialized type (common/types.cpp); initializing T initializes
// its parents too. So T is initialized here, and type_of? finds T and every
// parent by name, as typeOf does once LÖVE has registered T. A name no
// type has is false, as luax_type's nullptr is. As in LÖVE, +type+ names
// the class the object was bound as (luax_pushtype pushes T::type), not
// the object's most derived class.
template <EngineObject T, typename Base = void>
Rice::Data_Type<T> define_engine_class(const Rice::Module &parent, const char *name) {
  T::type.init();
  return Rice::define_class_under<T, Base>(parent, name)
      .define_method("type", [](const T & /*self*/) { return std::string(T::type.getName()); })
      .define_method(
          "type_of?",
          [](const T & /*self*/, const std::string &type_name) {
            const love::Type *type = love::Type::byName(type_name.c_str());
            return type != nullptr && T::type.isa(*type);
          },
          Rice::Arg("name"));
}

// SPDX-SnippetEnd

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
  requires lota::native::EngineObject<T>
class Wrapper<T *> : public lota::native::ObjectWrapper<T> {
public:
  Wrapper(rb_data_type_t *rb_data_type, T *data, bool isOwner)
      : lota::native::ObjectWrapper<T>(rb_data_type, data,
                                       isOwner ? love::Acquire::NORETAIN : love::Acquire::RETAIN) {}
};

// A reference that C++ keeps (wrapReference, rice/detail/Wrapper.ipp:
// 207-218): retained like a pointer.
template <typename T>
  requires lota::native::EngineObject<T>
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
  requires lota::native::EngineObject<T>
class Wrapper<T> : public WrapperBase {
  static_assert(!lota::native::EngineObject<T>,
                "engine objects cross into Ruby by pointer, never by value or as an "
                "owned reference; bind a function that returns T*");
};

} // namespace Rice::detail

#endif // LOTA_NATIVE_BINDING_HPP
