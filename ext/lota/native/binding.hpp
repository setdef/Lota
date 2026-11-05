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
//
// GCC 16, for MinGW, warns -Warray-bounds inside Ruby's own inline
// functions (ruby/internal/fl_type.h:466, core/rarray.h:263) wherever Rice
// inlines them into its own (Rice::Object::vcall, rice.hpp:16264): it
// takes RBASIC(obj) of a VALUE it cannot rule out being a special
// constant for a pointer to address zero ("source object is likely at
// address zero"). Both are system headers, but GCC reports a warning it
// finds after inlining at the inlined line regardless. Rice's and Ruby's
// headers are first included here, so turning the warning off around these
// two lines turns it off for their code alone: GCC decides by the line a
// warning is reported at, and every other line keeps it, as an error.
#if defined(__MINGW32__) && !defined(__clang__)
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Warray-bounds"
#endif
#include <rice/rice.hpp> // IWYU pragma: export
#include <rice/stl.hpp>  // IWYU pragma: export
#if defined(__MINGW32__) && !defined(__clang__)
#pragma GCC diagnostic pop
#endif

// On Windows Ruby's headers include <windows.h> (ruby/win32.h), whose
// winnt.h defines KEY_EXECUTE, a registry access right, as a macro, which
// would replace LÖVE's enumerator love::keyboard::Keyboard::KEY_EXECUTE
// (keyboard/Keyboard.h:457). LÖVE's own sources include LÖVE's headers
// without Ruby's, so only Lota's need this.
#ifdef _WIN32
#undef KEY_EXECUTE
#endif

#include <ruby/ractor.h>

#include "common/Data.h"
#include "common/Exception.h"
#include "common/Module.h"
#include "common/Object.h" // IWYU pragma: export
#include "common/types.h"

// The engine classes of the modules LÖVE confines to its main thread, so
// that every binding sees the same list (ReleasedOnMainThread, below).
#include "graphics/Buffer.h"
#include "graphics/Font.h"
#include "graphics/Mesh.h"
#include "graphics/ParticleSystem.h"
#include "graphics/Quad.h"
#include "graphics/Shader.h"
#include "graphics/SpriteBatch.h"
#include "graphics/TextBatch.h"
#include "graphics/Texture.h"

// The physics classes whose wrappers keep another object alive
// (Companion, below).
#include "physics/box2d/Body.h"
#include "physics/box2d/Contact.h"
#include "physics/box2d/Shape.h"
#include "physics/box2d/World.h"

#include <algorithm>
#include <array>
#include <bit>
#include <concepts>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <mutex>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>
#include <type_traits>
#include <unordered_set>
#include <utility>
#include <vector>

#ifdef __APPLE__
#include <pthread.h>
#elif defined(_WIN32)
#include <windows.h> // Ruby's own headers include it on Windows (ruby/win32.h)
#else
#include <unistd.h>
#endif

namespace lota::native {

// A LÖVE engine object: anything that counts its references with
// love::Object (vendor/love/src/common/Object.h).
template <typename T>
concept EngineObject = std::derived_from<std::remove_cv_t<T>, love::Object>;

// Whether this is the process's main thread, the one the operating system
// started the process on. macOS runs windows and graphics only there. SDL's
// own SDL_IsMainThread cannot say: it answers for whichever thread first
// initialized SDL, and true on any thread before that (Plan 001, spike 2).
// macOS asks pthread_main_np; on Linux the main thread is the one whose
// thread ID is the process's ID (gettid(2)).
#ifdef __APPLE__
inline bool on_main_thread() { return pthread_main_np() == 1; }
#elif defined(_WIN32)
// Windows names no main thread, and ties a window to the thread that made
// it, whichever that is. Lota takes the thread that loads the extension,
// which is Ruby's main thread, the one ruby.exe started on, when require
// runs there, as it does from lib/lota.rb.
inline const unsigned long loading_thread = GetCurrentThreadId();
inline bool on_main_thread() { return GetCurrentThreadId() == loading_thread; }
#else
inline bool on_main_thread() { return gettid() == getpid(); }
#endif

// Raises ThreadError unless this is the main thread. +module+ names the
// Lota module the caller belongs to, for the message.
inline void require_main_thread(const char *module) {
  if (!on_main_thread()) {
    throw Rice::Exception(rb_eThreadError, "%s runs only on the main thread", module);
  }
}

// The value of an argument the binding generator made optional, because
// it follows an optional one, as a Ruby method's positional parameters
// must (tasks/bindings/port.rb, trailing_optional), or because LÖVE tests
// whether it is given, in a form that requires it: LÖVE reads it with a
// check there. A missing one raises ArgumentError, naming it as Rice
// names a missing argument, where LÖVE's check raises. It returns a
// reference into the argument, so a string's c_str() outlives the read.
template <typename T> const T &required(const std::optional<T> &argument, const std::string &name) {
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
template <> struct ReleasedOnMainThread<love::graphics::TextBatch> : std::true_type {};
template <> struct ReleasedOnMainThread<love::graphics::Quad> : std::true_type {};
template <> struct ReleasedOnMainThread<love::graphics::Shader> : std::true_type {};
template <> struct ReleasedOnMainThread<love::graphics::SpriteBatch> : std::true_type {};
template <> struct ReleasedOnMainThread<love::graphics::Buffer> : std::true_type {};
template <> struct ReleasedOnMainThread<love::graphics::Mesh> : std::true_type {};
template <> struct ReleasedOnMainThread<love::graphics::ParticleSystem> : std::true_type {};

// Whether Ractors share the wrappers of engine objects of class T (ADR
// 001, section 6): a love::Data, which guards its bytes with LÖVE's own
// lock (src/common/Data.h), or a class of Lota's that says it guards
// itself, with a static member +shareable+, as Lota's Channel and Thread
// do. Their Ruby type is RUBY_TYPED_FROZEN_SHAREABLE and each wrapper is
// frozen, so Ruby shares it between Ractors rather than refusing it, and
// its methods keep working under the object's own lock. Wrappers of every
// other class stay in the Ractor that made them.
template <typename T> struct Shareable {
  static constexpr bool value =
      std::derived_from<T, love::Data> || requires { requires T::shareable; };
};

// The object a wrapper of an engine object of class T also holds a
// reference to, so that it outlives the wrapper's own object, or nullptr.
// LÖVE's Contact keeps a pointer to its World, which it uses when it is
// destroyed (physics/box2d/Contact.cpp, Contact::invalidate), and holds no
// reference to it. Lua finalizes objects in the reverse order it made them,
// so a Contact goes before the World that made it; Ruby's collector frees
// what it collects in no such order, so a Contact's wrapper holds its World.
template <typename T> struct Companion {
  static love::Object *of(T & /*object*/) { return nullptr; }
};
template <> struct Companion<love::physics::box2d::Contact> {
  static love::Object *of(love::physics::box2d::Contact &contact) {
    if (!contact.isValid()) {
      return nullptr;
    }
    love::physics::box2d::Shape *a = nullptr;
    love::physics::box2d::Shape *b = nullptr;
    contact.getShapes(a, b);
    return a->getBody()->getWorld();
  }
};

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

// The one Ruby wrapper of each engine object while that wrapper lives, as
// LÖVE pushes one Lua userdata for each object (luax_pushtype looks the
// object up in its REGISTRY_OBJECTS table, vendor/love/src/common/
// runtime.cpp:647-690), so the same Body or Joystick read back twice is
// the same Ruby object, as Lua's == sees it.
//
// It must forget a wrapper the moment Ruby's collector finds it dead,
// not when the collector frees it. Ruby sweeps lazily: a collection marks
// every live object, then frees the rest page by page while the program
// runs on, so a wrapper found dead can sit unswept for many frames. Rice's
// own InstanceRegistry (Rice 4.12.0, rice/detail/InstanceRegistry.ipp:
// 6-31) is a std::map that neither marks its VALUEs nor learns of their
// death before the wrapper's dfree erases them, so a lookup in that window
// handed back a wrapper about to be freed, and the sweep then freed it
// while Ruby held it again: a game that read its joysticks every frame
// crashed seconds in, in method lookup on the freed object's class.
// Ruby's ObjectSpace::WeakMap drops each object the marking found dead
// before the sweep begins, and moves its values along when GC.compact
// moves them, which is what an identity map needs. It is keyed by the
// object's love::Object address, as an Integer, which a WeakMap compares
// by identity; Integers of that size are immediates, so equal ones are
// identical.
//
// Init_native turns it on for Lota::Native. Another bundle, such as the
// test extension, makes a new wrapper each time it wraps an object, once
// it turns Rice's registry off itself.
//
// Each Ractor keeps a map of its own, in its Ractor-local storage, as each
// of LÖVE's threads keeps the userdata of its own Lua state. A WeakMap is
// not shareable, and neither are most wrappers, so one map for every
// Ractor would hand one Ractor's wrapper to another, and two Ractors would
// change one Hash at once. So the same object read in two Ractors has a
// wrapper in each, as it has a userdata in each of LÖVE's Lua states, and
// LÖVE's == compares the objects they wrap (w__eq, src/common/runtime.cpp:
// 82-88), as Lota's Channel and Thread do.
class WrapperIdentities {
public:
  static WrapperIdentities &instance() {
    static WrapperIdentities identities;
    return identities;
  }

  WrapperIdentities(const WrapperIdentities &) = delete;
  WrapperIdentities(WrapperIdentities &&) = delete;
  WrapperIdentities &operator=(const WrapperIdentities &) = delete;
  WrapperIdentities &operator=(WrapperIdentities &&) = delete;
  ~WrapperIdentities() = default;

  // Starts keeping each wrapper's identity, and stops Rice's registry
  // from keeping any, since its stale entries are what this replaces. It
  // runs in Init_native, on the main Ractor, before any other exists.
  void keep() {
    if (kept_) {
      return;
    }
    Rice::detail::Registries::instance.instances.mode = Rice::detail::InstanceRegistry::Mode::Off;
    key_ = rb_ractor_local_storage_value_newkey();
    kept_ = true;
  }

  // The live wrapper of +object+ in this Ractor, or Qnil.
  [[nodiscard]] VALUE find(love::Object *object) const {
    if (!kept_) {
      return Qnil;
    }
    return Rice::Object(map()).call("[]", key(object)).value();
  }

  // Remembers +wrapper+ as the wrapper of +object+ in this Ractor while it
  // lives.
  void remember(love::Object *object, VALUE wrapper) const {
    if (kept_) {
      Rice::Object(map()).call("[]=", key(object), Rice::Object(wrapper));
    }
  }

private:
  WrapperIdentities() = default;

  static Rice::Object key(love::Object *object) {
    return {ULL2NUM(std::bit_cast<std::uintptr_t>(object))};
  }

  // This Ractor's map, made the first time the Ractor wraps an object.
  // Ractor-local storage marks it.
  [[nodiscard]] VALUE map() const {
    VALUE map = Qnil;
    if (rb_ractor_local_storage_value_lookup(key_, &map) && !NIL_P(map)) {
      return map;
    }
    const VALUE weak_map = Rice::detail::protect(rb_path2class, "ObjectSpace::WeakMap");
    map = Rice::detail::protect(rb_class_new_instance, 0, static_cast<const VALUE *>(nullptr),
                                weak_map);
    rb_ractor_local_storage_value_set(key_, map);
    return map;
  }

  rb_ractor_local_key_t key_ = nullptr;
  bool kept_ = false;
};

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
      : WrapperBase(rb_data_type), companion_(Companion<T>::of(*object), love::Acquire::RETAIN),
        reference_(object, acquire) {}

  ObjectWrapper(const ObjectWrapper &) = delete;
  ObjectWrapper(ObjectWrapper &&) = delete;
  ObjectWrapper &operator=(const ObjectWrapper &) = delete;
  ObjectWrapper &operator=(ObjectWrapper &&) = delete;

  // reference_ releases the object. Off the main thread, an object of a
  // main-thread module first joins the release queue, which retains it, so
  // reference_'s release cannot be the last. WrapperIdentities forgot this
  // wrapper when the collector found it dead, before it was freed.
  ~ObjectWrapper() override {
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
  // Declared first, so it is released after reference_.
  love::StrongRef<love::Object> companion_;
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
// T, with the methods every LÖVE object has (ADR 001, rule 16):
// +object_type+, LÖVE's name for T, and +type_of?+, whether T is the type
// of that name or one of its parents. Every engine class Lota binds is
// defined through here, once, so every one answers both. Base, when given, is the bound
// class Ruby's class inherits from, as Rice's define_class_under takes it.
//
// LÖVE registers each type it pushes to Lua before pushing one, which
// initializes the type (luax_register_type), and love::Type::byName finds
// only an initialized type (common/types.cpp); initializing T initializes
// its parents too. So T is initialized here, and type_of? finds T and every
// parent by name, as typeOf does once LÖVE has registered T. A name no
// type has is false, as luax_type's nullptr is. As in LÖVE, +object_type+ names
// the class the object was bound as (luax_pushtype pushes T::type), not
// the object's most derived class.
template <EngineObject T, typename Base = void>
Rice::Data_Type<T> define_engine_class(const Rice::Module &parent, const char *name) {
  T::type.init();
  Rice::Data_Type<T> klass =
      Rice::define_class_under<T, Base>(parent, name)
          .define_method("object_type",
                         [](const T & /*self*/) { return std::string(T::type.getName()); })
          .define_method(
              "type_of?",
              [](const T & /*self*/, const std::string &type_name) {
                const love::Type *type = love::Type::byName(type_name.c_str());
                return type != nullptr && T::type.isa(*type);
              },
              Rice::Arg("name"));
  if constexpr (Shareable<T>::value) {
    Rice::Data_Type<T>::ruby_data_type()->flags |= RUBY_TYPED_FROZEN_SHAREABLE;
  }
  return klass;
}

// SPDX-SnippetEnd

// Whether +wrapper+, a wrapper of an engine object, is one Ractors share
// (Shareable): Lota freezes each as it makes it (wrap_engine_object), so
// Ruby counts it shareable from the start.
inline bool shareable_type(const rb_data_type_t *type) {
  return (type->flags & RUBY_TYPED_FROZEN_SHAREABLE) != 0;
}

// Sets whether the methods defined while it lives may be called from a
// Ractor other than the main one (rb_ext_ractor_safe, Ruby 4.0.7,
// load.c:1259-1263), and turns it back on when it ends, as Init_native
// leaves it. Ruby reads the setting as each method is defined
// (vm_method.c:955-975), and raises Ractor::UnsafeError when another
// Ractor calls one defined without it (vm_insnhelper.c:3555-3563).
class RactorSafety {
public:
  explicit RactorSafety(bool safe) { rb_ext_ractor_safe(safe); }
  RactorSafety(const RactorSafety &) = delete;
  RactorSafety(RactorSafety &&) = delete;
  RactorSafety &operator=(const RactorSafety &) = delete;
  RactorSafety &operator=(RactorSafety &&) = delete;
  ~RactorSafety() { rb_ext_ractor_safe(true); }
};

// Whether LÖVE's module +name+ (its folder in src/modules) is bound for
// every Ractor, as LÖVE lets every thread load it, or for the main Ractor
// alone (ADR 001, section 6), where another Ractor that calls it meets
// Ractor::UnsafeError. LÖVE keeps love.window and love.graphics off every
// thread but the main one (vendor/love/src/modules/thread/LuaThread.cpp:
// 72-73), and so does Lota. Lota also keeps on the main Ractor the
// modules LÖVE lets threads use but whose code is not safe there:
//
// - keyboard, mouse, and system call SDL functions that SDL says should
//   be called only on the main thread: 14 in SDL_keyboard.h (text input,
//   the screen keyboard), 24 in SDL_mouse.h (cursors, warping, grabbing,
//   relative mode), 11 in SDL_clipboard.h, and SDL_OpenURL in SDL_misc.h
//   (SDL 3.4.10).
// - joystick, touch, and sensor read state LÖVE keeps without a lock and
//   the main thread's event pump changes: JoystickModule's joysticks
//   (joystick/sdl/JoystickModule.h:75-82, changed by event/sdl/
//   Event.cpp:716-728 as devices come and go), Touch's touches
//   (touch/sdl/Touch.h:59, changed by Event.cpp:416 on every finger
//   event), and Sensor's open sensors (sensor/sdl/Sensor.h:57, changed
//   by setEnabled).
inline bool ractor_safe_module(std::string_view name) {
  static constexpr std::array<std::string_view, 11> SAFE = {
      "audio", "data",    "event", "filesystem", "font", "image",
      "math",  "physics", "sound", "thread",     "timer"};
  return std::ranges::find(SAFE, name) != SAFE.end();
}

// Defines LÖVE's module +name+'s bindings with +define+, safe for every
// Ractor or for the main one, as ractor_safe_module says.
template <typename Define>
void define_module(std::string_view name, Define define, const Rice::Module &native) {
  const RactorSafety safety(ractor_safe_module(name));
  define(native);
}

// Pins the singleton class of +module+, and of every module and class
// among its constants and theirs, so that GC.compact never moves one. Rice
// keys each function it binds by the address of the class it defines the
// function on (rice/detail/NativeRegistry.ipp:66-78), and finds it again
// by the class Ruby says the method was called in (Native::resolve,
// rice/detail/Native.ipp:43-63). Ruby pins a named class or module, but
// not the singleton class that holds a module's functions and a class's
// singleton methods: once a compaction moved one, every function on it
// raised "Could not find method call". Call it once everything under
// +module+ is defined.
inline void pin_singleton_classes(const Rice::Module &module) {
  std::vector<Rice::Module> pending{module};
  std::unordered_set<VALUE> seen{module.value()};
  while (!pending.empty()) {
    const Rice::Module current = pending.back();
    pending.pop_back();
    rb_gc_register_mark_object(Rice::detail::protect(rb_singleton_class, current.value()));
    const Rice::Array names(current.call("constants", false));
    for (const auto name : names) {
      const Rice::Object value = current.call("const_get", Rice::Object(name.value()), false);
      if (value.is_a(rb_cModule) && seen.insert(value.value()).second) {
        pending.emplace_back(value.value());
      }
    }
  }
}

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

// The wrapper of the engine object +data+, which a binding returns or
// Rice::Array#push appends: the one it already has, while that lives
// (lota::native::WrapperIdentities), or a new one, made as Rice's own
// To_Ruby<T*> makes it (Rice 4.12.0, rice/Data_Object.ipp:209-252): an
// object of the Ruby class of the object's dynamic type, wrapping it with
// Wrapper<T*>, above (detail::wrap, rice/detail/Wrapper.ipp:267-280, which
// asks Rice's registry first, and finds nothing there once it is off).
// +isOwner+ says the caller passes on a reference of its own, which the
// new wrapper adopts; an existing wrapper already holds one, so that
// reference is released instead, keeping the memory rule's one reference
// for each wrapper.
template <typename U>
  requires lota::native::EngineObject<U>
VALUE wrap_engine_object(U *data, bool isOwner) {
  // ObjectWrapper says so too, but GCC stops at the const errors below
  // before it instantiates the wrapper.
  static_assert(!std::is_const_v<U>,
                "love::Object counts references in non-const retain() and release(), so "
                "bind functions that return engine objects as non-const pointers");
  if (data == nullptr) {
    return Qnil;
  }
  const auto &identities = lota::native::WrapperIdentities::instance();
  if (const VALUE found = identities.find(data); found != Qnil) {
    if (isOwner) {
      data->release();
    }
    return found;
  }
  const std::pair<VALUE, rb_data_type_t *> type = Registries::instance.types.figureType(*data);
  const VALUE wrapped = wrap(type.first, type.second, data, isOwner);
  if (lota::native::shareable_type(type.second)) {
    rb_obj_freeze(wrapped);
  }
  identities.remember(data, wrapped);
  return wrapped;
}

// Converts an engine object a binding returns by pointer, the way LÖVE's
// API returns them, adopting it when the function is bound with
// Return().takeOwnership().
template <typename T>
  requires lota::native::EngineObject<T>
class To_Ruby<T *> {
public:
  To_Ruby() = default;
  explicit To_Ruby(Arg *arg) : arg_(arg) {}

  template <typename U> VALUE convert(U *data) {
    return wrap_engine_object(data, arg_ != nullptr && arg_->isOwner());
  }

private:
  Arg *arg_ = nullptr;
};

// The same, for a pointer Rice::Array#push is given as an lvalue, as a
// loop over a std::vector of engine objects gives it (Rice's own,
// rice/Data_Object.ipp:254-302).
template <typename T>
  requires lota::native::EngineObject<T>
class To_Ruby<T *&> {
public:
  To_Ruby() = default;
  explicit To_Ruby(Arg *arg) : arg_(arg) {}

  template <typename U> VALUE convert(U *data) {
    return wrap_engine_object(data, arg_ != nullptr && arg_->isOwner());
  }

private:
  Arg *arg_ = nullptr;
};

// Converts an engine object a binding returns by reference, which C++
// keeps, so the wrapper retains it, as Wrapper<T &> does (Rice's own,
// rice/Data_Object.ipp:146-178).
template <typename T>
  requires lota::native::EngineObject<T>
class To_Ruby<T &> {
public:
  To_Ruby() = default;
  explicit To_Ruby(Arg * /*arg*/) {}

  template <typename U> VALUE convert(U &data) { return wrap_engine_object(&data, false); }
};

} // namespace Rice::detail

#endif // LOTA_NATIVE_BINDING_HPP
