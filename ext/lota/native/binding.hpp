// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// Rice, as Lota's bindings include it: with LÖVE's memory model
// (doc/contributors/design/engine.md) in place before any binding can wrap a
// love::Object.
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
#include <ruby/ractor.h>
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

#include "common/Data.h"
#include "common/Exception.h"
#include "common/Module.h"
#include "common/Object.h" // IWYU pragma: export
#include "common/types.h"

#include "native/luajit.hpp"

// The engine classes of the modules LÖVE confines to its main thread, so
// that every binding sees the same list (ReleasedOnMainThread, below).
#include "graphics/Buffer.h"
#include "graphics/Font.h"
#include "graphics/GraphicsReadback.h"
#include "graphics/Mesh.h"
#include "graphics/ParticleSystem.h"
#include "graphics/Quad.h"
#include "graphics/Shader.h"
#include "graphics/SpriteBatch.h"
#include "graphics/TextBatch.h"
#include "graphics/Texture.h"
#include "graphics/Video.h"

// The physics classes whose wrappers keep another object alive
// (Companion, below).
#include "physics/box2d/Body.h"
#include "physics/box2d/Contact.h"
#include "physics/box2d/Shape.h"
#include "physics/box2d/World.h"

// Whether AddressSanitizer instruments this build: GCC says so with
// __SANITIZE_ADDRESS__, and Clang with __has_feature.
#if defined(__SANITIZE_ADDRESS__)
#define LOTA_ASAN 1
#elif defined(__has_feature)
#if __has_feature(address_sanitizer)
#define LOTA_ASAN 1
#endif
#endif
#ifdef LOTA_ASAN
#include <sanitizer/asan_interface.h>
#include <sanitizer/common_interface_defs.h>
#endif

#include <algorithm>
#include <array>
#include <atomic>
#include <bit>
#include <concepts>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <memory>
#include <mutex>
#include <optional>
#include <span>
#include <stdexcept>
#include <string>
#include <string_view>
#include <type_traits>
#include <unordered_set>
#include <utility>
#include <vector>

#if defined(__APPLE__) || defined(__ANDROID__)
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
// initialized SDL, and true on any thread before that.
// macOS asks pthread_main_np; on Linux the main thread is the one whose
// thread ID is the process's ID (gettid(2)).
#ifdef __APPLE__
inline bool on_main_thread() { return pthread_main_np() == 1; }
inline void record_main_thread() {}
#elif defined(_WIN32)
// Windows names no main thread, and ties a window to the thread that made
// it, whichever that is. Lota takes the thread that loads the extension,
// which is Ruby's main thread, the one ruby.exe started on, when require
// runs there, as it does from lib/lota.rb.
inline const unsigned long loading_thread = GetCurrentThreadId();
inline bool on_main_thread() { return GetCurrentThreadId() == loading_thread; }
inline void record_main_thread() {}
#elif defined(__ANDROID__)
// An Android app's main thread is its UI thread, which Java keeps and on
// which no game may block. Fledge's Android host runs Ruby on a thread of
// its own, which SDL's Android video takes for its main thread (Fledge's
// ADR 025, section 4), as LÖVE's Android build runs Lua on the thread SDL
// starts its main function on; so the main thread here is Ruby's.
// libfledgeext.so, which holds the extension, is loaded on the UI thread
// before Ruby starts, so a static initializer, as on Windows, would record
// the UI thread; Init_native records the thread that require
// "lota/native" runs on, Ruby's own, before any binding exists.
inline pthread_t main_thread{};
inline bool on_main_thread() { return pthread_equal(pthread_self(), main_thread) != 0; }
inline void record_main_thread() { main_thread = pthread_self(); }
#else
inline bool on_main_thread() { return gettid() == getpid(); }
inline void record_main_thread() {}
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
// own formatting, as an Array, as rule 4 of
// doc/contributors/design/translation.md returns a function's several values on
// failure too.
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
template <> struct ReleasedOnMainThread<love::graphics::GraphicsReadback> : std::true_type {};
template <> struct ReleasedOnMainThread<love::graphics::Video> : std::true_type {};

// Whether Ractors share the wrappers of engine objects of class T, as
// love.thread's channels pass LÖVE's objects between threads
// (doc/contributors/design/engine.md, "Threads and Ractors"): a
// love::Data, which guards its bytes with LÖVE's own lock
// (src/common/Data.h), or a class of Lota's that says it guards itself,
// with a static member +shareable+. Their Ruby type is
// RUBY_TYPED_FROZEN_SHAREABLE and each wrapper is frozen as it is made
// (wrap_engine_object), so Ruby shares it rather than refusing it.
// Wrappers of every other class stay in the Ractor that made them.
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
// the main thread to carry out (doc/contributors/design/engine.md). Ruby frees
// a wrapper on whichever thread triggered the collection; the queue takes over
// the wrapper's reference, so the object outlives the wrapper until the main
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
// object's love::Object address, which a WeakMap compares by identity,
// and holds weakly like its values, so the key must be an immediate,
// whose equal values are identical and never collected (key, below).
//
// Init_native turns it on for Lota::Native. Another bundle, such as the
// test extension, makes a new wrapper each time it wraps an object, once
// it turns Rice's registry off itself.
//
// Each Ractor keeps a map of its own, in its Ractor-local storage, as each
// of LÖVE's threads keeps the userdata of its own Lua state. One map for
// every Ractor does not work: a WeakMap has no lock, so two Ractors that
// wrap objects at once corrupt it and crash Ruby, and a wrapper is not
// shareable, so one map would hand one Ractor's wrapper to another, which
// Ruby forbids (test/native/ractor_test.rb). So the same object read in two
// Ractors has a wrapper in each, as it has a userdata in each of LÖVE's
// Lua states.
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
  // runs in Init_native, on the main Ractor, before any other Ractor can
  // call into Lota::Native.
  void keep() {
    if (key_ != nullptr) {
      return;
    }
    Rice::detail::Registries::instance.instances.mode = Rice::detail::InstanceRegistry::Mode::Off;
    key_ = rb_ractor_local_storage_value_newkey();
  }

  // The live wrapper of +object+ in this Ractor, or Qnil.
  [[nodiscard]] VALUE find(love::Object *object) const {
    if (key_ == nullptr) {
      return Qnil;
    }
    return Rice::Object(map()).call("[]", key(object)).value();
  }

  // Remembers +wrapper+ as the wrapper of +object+ in this Ractor while it
  // lives.
  void remember(love::Object *object, VALUE wrapper) const {
    if (key_ != nullptr) {
      Rice::Object(map()).call("[]=", key(object), Rice::Object(wrapper));
    }
  }

  // Forgets +wrapper+ as the wrapper of +object+, which a game released,
  // so the object gets a new wrapper the next time Ruby is handed it, as
  // w__release removes the object from LÖVE's REGISTRY_OBJECTS table
  // (vendor/love/src/common/runtime.cpp:170-197).
  void forget(love::Object *object, VALUE wrapper) const {
    if (key_ != nullptr && find(object) == wrapper) {
      Rice::Object(map()).call("delete", key(object));
    }
  }

private:
  WrapperIdentities() = default;

  // The address as an Integer where Ruby holds one that large as a
  // Fixnum, an immediate, which is every address on macOS and Linux. On
  // Windows a long has 32 bits, and Ruby's Fixnums 31 (RUBY_FIXNUM_MAX is
  // LONG_MAX / 2, ruby/internal/arithmetic/long.h), so an address there is
  // a Bignum, a new object each time, which the map neither finds again
  // nor keeps. There the key is the address as a Float, which 64-bit Ruby
  // holds as an immediate flonum, and which holds exactly every address
  // below 2^53, beyond any a process has.
  static Rice::Object key(love::Object *object) {
    static_assert(USE_FLONUM != 0, "a Float key must be an immediate");
    const auto address = std::bit_cast<std::uintptr_t>(object);
    constexpr auto fixnum_max = static_cast<std::uintptr_t>(std::numeric_limits<long>::max() / 2);
    if (address <= fixnum_max) {
      return {LONG2NUM(static_cast<long>(address))};
    }
    return {DBL2NUM(static_cast<double>(address))};
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
};

// What every wrapper of an engine object answers, whatever the object's
// class, for the methods LÖVE gives every object (define_engine_class).
class EngineWrapper : public Rice::detail::WrapperBase {
public:
  using WrapperBase::WrapperBase;

  // The engine object, as LÖVE's Proxy holds it, or nullptr once the
  // wrapper is released, as w__release leaves the Proxy's object.
  [[nodiscard]] virtual love::Object *object() const = 0;

  // Ends the wrapper's use of its object, as w__release does
  // (vendor/love/src/common/runtime.cpp:170-197), and returns whether it
  // was in use. +self+ is the wrapper's own Ruby object. The reference
  // goes at once, or, while a native call uses the wrapper, as soon as
  // the last such call returns (pin, unpin).
  bool release(VALUE self) {
    if (released_.exchange(true)) {
      return false;
    }
    forget(self);
    if (busy_.load() == 0) {
      let_go();
    } else {
      pending_ = true;
    }
    return true;
  }

  // Marks the wrapper in use by a native call in progress, which may hold
  // the engine object's pointer (EngineCall, below).
  void pin() { busy_.fetch_add(1); }

  // Ends one native call's use, and lets go of the reference a release
  // left for the last of them.
  void unpin() {
    if (busy_.fetch_sub(1) == 1 && pending_.exchange(false)) {
      let_go();
    }
  }

  // The data types of every engine class this bundle binds
  // (define_engine_class), which tell its wrappers from any other typed
  // data, such as a Proc's.
  static std::unordered_set<const rb_data_type_t *> &types() {
    static std::unordered_set<const rb_data_type_t *> engine_types;
    return engine_types;
  }

  // The wrapper of +value+, a Lota::Native object, or nullptr for any
  // other value.
  static EngineWrapper *of(VALUE value) {
    if (!RB_TYPE_P(value, T_DATA) || !RTYPEDDATA_P(value) ||
        !types().contains(RTYPEDDATA_TYPE(value))) {
      return nullptr;
    }
    return dynamic_cast<EngineWrapper *>(Rice::detail::getWrapper(value));
  }

protected:
  [[nodiscard]] bool released() const { return released_.load(); }

  // Forgets +self+ as the wrapper of its object (WrapperIdentities).
  virtual void forget(VALUE self) = 0;

  // Drops the wrapper's reference to its object.
  virtual void let_go() = 0;

private:
  std::atomic<bool> released_ = false;
  std::atomic<bool> pending_ = false;
  std::atomic<int> busy_ = 0;
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
//
// A game's release, LÖVE's Object:release, ends the wrapper's use of its
// object at once: every later call through the wrapper raises LÖVE's
// error, the object gets a new wrapper the next time Ruby is handed it,
// and the reference goes, as w__release lets go of it at once. Lota's
// bindings can be in the middle of using the object when a release
// runs: a method that yields, a callback, a conversion of an argument
// that calls Ruby, or another thread scheduled between two Ruby calls
// can each run one while a binding further up the stack still holds the
// pointer it read. So every native call marks the wrappers it is given
// in use for as long as it runs (EngineCall), and a release that finds
// its wrapper in use lets go of the reference when the last of those
// calls returns.
template <EngineObject T> class ObjectWrapper : public EngineWrapper {
  static_assert(!std::is_const_v<T>,
                "love::Object counts references in non-const retain() and release(), so "
                "bind functions that return engine objects as non-const pointers");

public:
  ObjectWrapper(rb_data_type_t *rb_data_type, T *object, love::Acquire acquire)
      : EngineWrapper(rb_data_type), companion_(Companion<T>::of(*object), love::Acquire::RETAIN),
        reference_(object, acquire) {}

  ObjectWrapper(const ObjectWrapper &) = delete;
  ObjectWrapper(ObjectWrapper &&) = delete;
  ObjectWrapper &operator=(const ObjectWrapper &) = delete;
  ObjectWrapper &operator=(ObjectWrapper &&) = delete;

  // reference_ releases the object. Off the main thread, an object of a
  // main-thread module first joins the release queue, which retains it, so
  // reference_'s release cannot be the last. WrapperIdentities forgot this
  // wrapper when the collector found it dead, before it was freed.
  ~ObjectWrapper() override { drop(); }

  // Rice's own check (rice/detail/Wrapper.ipp:137-150), then LÖVE's for a
  // released object, which luax_checktype makes of every argument it
  // reads (vendor/love/src/common/runtime.h:576-577, "Cannot use object
  // after it has been released."), as the RuntimeError Lota
  // raises for LÖVE's errors.
  void *get(rb_data_type_t *requested_type) override {
    if (rb_typeddata_inherited_p(this->rb_data_type_, requested_type) == 0) {
      throw Rice::Exception(rb_eTypeError, "wrong argument type %s (expected %s)",
                            this->rb_data_type_->wrap_struct_name,
                            requested_type->wrap_struct_name);
    }
    if (released()) {
      throw Rice::Exception(rb_eRuntimeError, "Cannot use object after it has been released.");
    }
    return reference_.get();
  }

  [[nodiscard]] love::Object *object() const override {
    return released() ? nullptr : reference_.get();
  }

protected:
  // A released object gets a new wrapper the next time Ruby is handed it.
  void forget(VALUE self) override { WrapperIdentities::instance().forget(reference_.get(), self); }

  // reference_ releases the object, once. Off the main thread, an object
  // of a main-thread module first joins the release queue, which retains
  // it, so reference_'s release cannot be the last.
  void let_go() override { drop(); }

private:
  void drop() {
    if (reference_.get() == nullptr) {
      return;
    }
    if constexpr (ReleasedOnMainThread<T>::value) {
      if (!on_main_thread()) {
        ReleaseQueue::instance().push(reference_.get());
      }
    }
    reference_.set(nullptr);
  }

  // Declared first, so it is released after reference_.
  love::StrongRef<love::Object> companion_;
  love::StrongRef<T> reference_;
};

// SPDX-SnippetBegin
// SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
// SPDX-License-Identifier: Zlib
//
// Ported from luax_register_type, w__tostring, w__type, w__typeOf, w__eq,
// and w__release (vendor/love/src/common/runtime.cpp:57-88, 170-197, and
// 489-552), and changed to define Ruby methods on a Rice class instead of
// filling a Lua metatable.

// Defines Lota::Native's class +name+ under +parent+ for the engine class
// T, with the methods every LÖVE object has: +object_type+, LÖVE's name
// for T, and +type_of?+, whether T is the type of that name or one of its
// parents (rule 33 of doc/contributors/design/translation.md); +to_s+ and +==+,
// its __tostring and __eq (rule 38); and +release+. Every engine class Lota
// binds is defined through here, once, so every one answers them. Base, when
// given, is the bound class Ruby's class inherits from, as Rice's
// define_class_under takes it.
//
// LÖVE registers each type it pushes to Lua before pushing one, which
// initializes the type (luax_register_type), and love::Type::byName finds
// only an initialized type (common/types.cpp); initializing T initializes
// its parents too. So T is initialized here, and type_of? finds T and every
// parent by name, as typeOf does once LÖVE has registered T. A name no
// type has is false, as luax_type's nullptr is. As in LÖVE, +object_type+ names
// the class the object was bound as (luax_pushtype pushes T::type), not
// the object's most derived class.
//
// Each method takes the wrapper's Ruby object rather than the engine
// object, as LÖVE's take the Proxy, so each still answers once the
// object is released: its type, its name with NULL for the address, and
// +release+ itself, false. Lua compares two userdata with __eq only when
// they are not the same userdata and share the metamethod (LuaJIT 2.1,
// src/lj_meta.c, lj_meta_equal), and LÖVE's metatable for each type has a
// function of its own there, so +==+ is true of the same wrapper, and
// otherwise of a wrapper of the same class around the same object, while
// neither is released.
template <EngineObject T, typename Base = void>
Rice::Data_Type<T> define_engine_class(const Rice::Module &parent, const char *name) {
  T::type.init();
  Rice::Data_Type<T> bound = Rice::define_class_under<T, Base>(parent, name);
  EngineWrapper::types().insert(Rice::Data_Type<T>::ruby_data_type());
  if constexpr (Shareable<T>::value) {
    Rice::Data_Type<T>::ruby_data_type()->flags |= RUBY_TYPED_FROZEN_SHAREABLE;
  }
  return bound
      .define_method("object_type", [](VALUE /*self*/) { return std::string(T::type.getName()); })
      .define_method(
          "type_of?",
          [](VALUE /*self*/, const std::string &type_name) {
            const love::Type *type = love::Type::byName(type_name.c_str());
            return type != nullptr && T::type.isa(*type);
          },
          Rice::Arg("name"))
      .define_method("to_s",
                     [](VALUE self) {
                       const EngineWrapper *wrapper = EngineWrapper::of(self);
                       const love::Object *object =
                           wrapper == nullptr ? nullptr : wrapper->object();
                       return std::string(T::type.getName()) + ": " + luajit::pointer(object);
                     })
      .define_method(
          "==",
          [](VALUE self, VALUE other) {
            if (self == other) {
              return true;
            }
            if (rb_obj_class(self) != rb_obj_class(other)) {
              return false;
            }
            const EngineWrapper *mine = EngineWrapper::of(self);
            const EngineWrapper *theirs = EngineWrapper::of(other);
            if (mine == nullptr || theirs == nullptr) {
              return false;
            }
            return mine->object() == theirs->object() && mine->object() != nullptr;
          },
          Rice::Arg("other").setValue())
      .define_method("release", [](VALUE self) {
        EngineWrapper *wrapper = EngineWrapper::of(self);
        return wrapper != nullptr && wrapper->release(self);
      });
}

// SPDX-SnippetEnd

// A native call's use of the engine objects it is given: its receiver,
// and each argument, or engine object inside Arrays an argument holds,
// down to Arrays of Arrays of Arrays, that is a wrapper
// (EngineWrapper::pin), until end(). No binding reads an engine object
// from a Hash. It holds only VALUEs, on the stack or in a Ruby Array, so
// it needs no destructor, which an exception Ruby raises through the
// call's frame would skip, and the collector, which scans the stack,
// keeps every wrapper alive meanwhile. It allocates nothing unless the
// call is given more than a few wrappers.
class EngineCall {
public:
  EngineCall(VALUE self, std::span<const VALUE> arguments) {
    add(self);
    for (const VALUE argument : arguments) {
      add_within(argument, 3);
    }
  }

  [[nodiscard]] bool empty() const { return count_ == 0; }

  // Ends the call's use of every wrapper it marked.
  void end() const {
    for (std::size_t i = 0; i < std::min(count_, few_.size()); i++) {
      unpin(few_.at(i));
    }
    if (more_ != Qnil) {
      for (long i = 0; i < RARRAY_LEN(more_); i++) {
        unpin(rb_ary_entry(more_, i));
      }
    }
  }

private:
  static void unpin(VALUE value) {
    if (EngineWrapper *wrapper = EngineWrapper::of(value)) {
      wrapper->unpin();
    }
  }

  // Marks +value+ in use if it is a wrapper, and otherwise each wrapper
  // among the elements of +value+, an Array, and theirs, +levels+ deep.
  // Each level is a loop of its own, so that no function calls itself.
  void add_within(VALUE value, int levels) {
    if (add(value) || levels == 0 || !RB_TYPE_P(value, T_ARRAY)) {
      return;
    }
    for (long i = 0; i < RARRAY_LEN(value); i++) {
      add_elements(rb_ary_entry(value, i), levels - 1);
    }
  }

  void add_elements(VALUE value, int levels) {
    if (add(value) || levels == 0 || !RB_TYPE_P(value, T_ARRAY)) {
      return;
    }
    for (long i = 0; i < RARRAY_LEN(value); i++) {
      add_last(rb_ary_entry(value, i), levels - 1);
    }
  }

  void add_last(VALUE value, int levels) {
    if (add(value) || levels == 0 || !RB_TYPE_P(value, T_ARRAY)) {
      return;
    }
    for (long i = 0; i < RARRAY_LEN(value); i++) {
      add(rb_ary_entry(value, i));
    }
  }

  // Marks +value+ in use, and returns whether it is a wrapper.
  bool add(VALUE value) {
    EngineWrapper *wrapper = EngineWrapper::of(value);
    if (wrapper == nullptr) {
      return false;
    }
    wrapper->pin();
    if (count_ < few_.size()) {
      few_.at(count_) = value;
    } else {
      if (more_ == Qnil) {
        more_ = rb_ary_new();
      }
      rb_ary_push(more_, value);
    }
    count_++;
    return true;
  }

  std::array<VALUE, 4> few_{};
  std::size_t count_ = 0;
  VALUE more_ = Qnil;
};

namespace engine_call_detail {

struct Super {
  int argc;
  const VALUE *argv;
  int kw_splat;
};

inline VALUE call_super(VALUE data) {
  const auto *given = std::bit_cast<const Super *>(data);
  return rb_call_super_kw(given->argc, given->argv, given->kw_splat);
}

inline VALUE end_call(VALUE data) {
  std::bit_cast<const EngineCall *>(data)->end();
  return Qnil;
}

// Under AddressSanitizer, on any thread but the main one, tells ASan the
// stack this engine call runs on; elsewhere it does nothing.
//
// A Ractor other than the main one runs its Ruby threads on stacks Ruby
// switches between itself (M:N threads, Ruby 4.0.7, thread_pthread.c:
// 1215-1216, which every such Ractor uses). Ruby tells ASan of each switch,
// with __sanitizer_start_switch_fiber and __sanitizer_finish_switch_fiber,
// only when Ruby itself is built with ASan (thread_pthread.c:1221-1236),
// and the Ruby the sanitized suite runs is not, so ASan takes the stack to
// be the native thread's own. A C++ throw or Ruby's longjmp from an engine
// call then asks __asan_handle_no_return to clear the frames it abandons,
// from below the jump to the stack's top, and ASan, finding that top
// hundreds of megabytes away, warns that it is "ignoring" the request.
// The abandoned frames keep their redzones, and the next jump in the same
// call, as Rice turns the C++ exception into Ruby's, finds them under
// ASan's own frame, where GCC's ASan checks the sigaltstack it calls, and
// reports a stack-buffer-underflow no code of Lota's or LÖVE's made.
//
// So each engine call tells ASan of its stack itself, through the same two
// calls, as Ruby would: from 1 MB below this frame, as deep as Ruby's
// machine stacks go, to a page above it, past the engine call's own frame.
// Ruby keeps the real bounds to itself.
// A jump then clears the frames between it and this one, as it clears up
// to the stack's top on the main thread, and the bounds hold until the
// next engine call on this native thread declares its own
// (test/sanitizers/sanitizer_test.rb shows overflows there still found).
inline void declare_stack() {
#ifdef LOTA_ASAN
  if (on_main_thread()) {
    return;
  }
  constexpr std::size_t BELOW = std::size_t{1} << 20U;
  constexpr std::size_t ABOVE = 4096;
  auto *const frame = static_cast<char *>(__builtin_frame_address(0));
  __sanitizer_start_switch_fiber(nullptr, frame - BELOW, BELOW + ABOVE);
  __sanitizer_finish_switch_fiber(nullptr, nullptr, nullptr);
#endif
}

// Every method and function install_engine_calls wraps: marks the
// engine objects it is given in use, calls the bound function, and ends
// that use however it returns.
inline VALUE engine_call(int argc, const VALUE *argv, VALUE self) {
  declare_stack();
  const int kw_splat = rb_keyword_given_p();
  const EngineCall call(self, std::span(argv, static_cast<std::size_t>(argc)));
  if (call.empty()) {
    return rb_call_super_kw(argc, argv, kw_splat);
  }
  const Super super{.argc = argc, .argv = argv, .kw_splat = kw_splat};
  return rb_ensure(call_super, std::bit_cast<VALUE>(&super), end_call, std::bit_cast<VALUE>(&call));
}

// Prepends to +target+, a class or a singleton class, a module whose
// methods, one for each public method +target+ defines, call
// engine_call, then the method each overrides.
inline void wrap_methods(VALUE target) {
  const Rice::Array names(Rice::Object(target).call("public_instance_methods", false));
  if (RARRAY_LEN(names.value()) == 0) {
    return;
  }
  const VALUE wrapping = rb_module_new();
  for (long i = 0; i < RARRAY_LEN(names.value()); i++) {
    const char *name = rb_id2name(SYM2ID(rb_ary_entry(names.value(), i)));
    rb_define_method(wrapping, name, engine_call, -1);
  }
  rb_prepend_module(target, wrapping);
}

} // namespace engine_call_detail

// Wraps every method and function of +module+, and of every module and
// class among its constants and theirs, in engine_call, so that a
// release a call runs into cannot let go of an object the call uses
// (ObjectWrapper). Call it once everything under +module+ is defined.
inline void install_engine_calls(const Rice::Module &module) {
  std::vector<Rice::Module> pending{module};
  std::unordered_set<VALUE> seen{module.value()};
  while (!pending.empty()) {
    const Rice::Module current = pending.back();
    pending.pop_back();
    engine_call_detail::wrap_methods(rb_singleton_class(current.value()));
    if (current.is_a(rb_cClass)) {
      engine_call_detail::wrap_methods(current.value());
    }
    const Rice::Array names(current.call("constants", false));
    for (const auto name : names) {
      const Rice::Object value = current.call("const_get", Rice::Object(name.value()), false);
      if (value.is_a(rb_cModule) && seen.insert(value.value()).second) {
        pending.emplace_back(value.value());
      }
    }
  }
}

// Freezes +wrapper+, a new wrapper of an engine object of the data type
// +type+, when Ractors share wrappers of its class (Shareable), so Ruby
// counts it shareable from the start.
inline void freeze_if_shareable(VALUE wrapper, const rb_data_type_t *type) {
  if ((type->flags & RUBY_TYPED_FROZEN_SHAREABLE) != 0) {
    rb_obj_freeze(wrapper);
  }
}

// Sets whether the methods defined while it lives may be called from a
// Ractor other than the main one (rb_ext_ractor_safe, Ruby 4.0.7,
// load.c:1259-1263), and turns it back on when it ends, as Init_native
// leaves it. Ruby reads the setting as each method is defined
// (vm_method.c:955-975), and raises Ractor::UnsafeError when another
// Ractor calls one defined without it.
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
// alone, where another Ractor that calls it meets Ractor::UnsafeError
// (doc/contributors/design/engine.md, "Threads and Ractors").
//
// LÖVE keeps love.window and love.graphics off every thread but the main
// one (vendor/love/src/modules/thread/LuaThread.cpp:71-73), and so does
// Lota, by the check that keeps them off Ruby's other threads
// (require_main_thread): a Ractor other than the main one runs on a thread
// of its own, so their bindings are bound for every Ractor and raise
// ThreadError there, as on a Ruby thread.
//
// Lota keeps on the main Ractor the modules LÖVE lets threads use but
// whose code is not safe there:
//
// - keyboard, mouse, and system call SDL functions that SDL says should
//   be called only on the main thread: text input and the screen keyboard
//   in SDL_keyboard.h; cursors, warping, grabbing, and relative mode in
//   SDL_mouse.h; the clipboard in SDL_clipboard.h; and SDL_OpenURL in
//   SDL_misc.h.
// - joystick, touch, and sensor read state LÖVE keeps without a lock and
//   the main thread's event pump changes: JoystickModule's joysticks
//   (joystick/sdl/JoystickModule.h, changed by event/sdl/Event.cpp as
//   devices come and go), Touch's touches (touch/sdl/Touch.h, changed on
//   every finger event), and Sensor's open sensors (sensor/sdl/Sensor.h,
//   changed by setEnabled).
inline bool ractor_safe_module(std::string_view name) {
  static constexpr std::array<std::string_view, 14> SAFE = {
      "audio", "data",    "event", "filesystem", "font",  "graphics", "image",
      "math",  "physics", "sound", "thread",     "timer", "video",    "window",
  };
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
  lota::native::freeze_if_shareable(wrapped, type.second);
  identities.remember(data, wrapped);
  return wrapped;
}

// The wrapper of the engine object +data+ as LÖVE pushes it with
// luax_pushtype(L, T::type, data) (vendor/love/src/common/runtime.cpp,
// luax_pushtype): the one it already has, while that lives, or a new one
// of the Ruby class bound for T, whatever class +data+ is of in C++, as
// love.data's functions push a ByteData as a plain Data. +isOwner+ is as
// wrap_engine_object takes it.
template <typename T>
  requires lota::native::EngineObject<T>
VALUE wrap_engine_object_as(T *data, bool isOwner) {
  const auto &identities = lota::native::WrapperIdentities::instance();
  if (const VALUE found = identities.find(data); found != Qnil) {
    if (isOwner) {
      data->release();
    }
    return found;
  }
  const VALUE wrapped = wrap(Data_Type<T>::klass(), Data_Type<T>::ruby_data_type(), data, isOwner);
  lota::native::freeze_if_shareable(wrapped, Data_Type<T>::ruby_data_type());
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
