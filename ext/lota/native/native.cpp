// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// Lota::Native: LÖVE's engine, bound to Ruby with Rice (ADR 006).

#include "native/audio.hpp"
#include "native/binding.hpp"
#include "native/buffer.hpp"
#include "native/data.hpp"
#include "native/deprecation.hpp"
#include "native/errors.hpp"
#include "native/event.hpp"
#include "native/filesystem.hpp"
#include "native/font.hpp"
#include "native/generated/bindings.hpp"
#include "native/graphics.hpp"
#include "native/image.hpp"
#include "native/joystick.hpp"
#include "native/keyboard.hpp"
#include "native/math.hpp"
#include "native/mouse.hpp"
#include "native/particle_system.hpp"
#include "native/physics.hpp"
#include "native/random_generator.hpp"
#include "native/ruby.hpp"
#include "native/sensor.hpp"
#include "native/shader.hpp"
#include "native/sound.hpp"
#include "native/system.hpp"
#include "native/texture.hpp"
#include "native/thread.hpp"
#include "native/timer.hpp"
#include "native/touch.hpp"
#include "native/video.hpp"
#include "native/window.hpp"

#include "common/Module.h"
#include "common/version.h"

#include <algorithm>
#include <array>
#include <cstddef>
#include <set>
#include <string>
#include <utility>

namespace {

// The point where the main thread carries out the releases Ruby's garbage
// collector asked for on other threads (doc/contributors/design/engine.md). The
// game loop calls it once a frame; until then, whoever drives the engine does,
// and lib/lota.rb drains it at exit.
std::size_t drain_release_queue() { return lota::native::ReleaseQueue::instance().drain(); }

std::size_t queued_releases() { return lota::native::ReleaseQueue::instance().size(); }

// SPDX-SnippetBegin
// SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
// SPDX-License-Identifier: Zlib
//
// The modules boot.lua opens (vendor/love/src/modules/love/boot.lua:
// 348-368), in the opposite order, with the filesystem, which love.boot
// opens first (line 46), last.

struct Closing {
  love::Module::ModuleType type;
  const char *name;
};

constexpr std::array<Closing, 20> CLOSING_ORDER = {
    {
        {.type = love::Module::M_PHYSICS, .name = "physics"},
        {.type = love::Module::M_MATH, .name = "math"},
        {.type = love::Module::M_GRAPHICS, .name = "graphics"},
        {.type = love::Module::M_WINDOW, .name = "window"},
        {.type = love::Module::M_FONT, .name = "font"},
        {.type = love::Module::M_VIDEO, .name = "video"},
        {.type = love::Module::M_IMAGE, .name = "image"},
        {.type = love::Module::M_AUDIO, .name = "audio"},
        {.type = love::Module::M_SENSOR, .name = "sensor"},
        {.type = love::Module::M_SYSTEM, .name = "system"},
        {.type = love::Module::M_SOUND, .name = "sound"},
        {.type = love::Module::M_TOUCH, .name = "touch"},
        {.type = love::Module::M_MOUSE, .name = "mouse"},
        {.type = love::Module::M_JOYSTICK, .name = "joystick"},
        {.type = love::Module::M_KEYBOARD, .name = "keyboard"},
        {.type = love::Module::M_EVENT, .name = "event"},
        {.type = love::Module::M_TIMER, .name = "timer"},
        {.type = love::Module::M_THREAD, .name = "thread"},
        {.type = love::Module::M_DATA, .name = "data"},
        {.type = love::Module::M_FILESYSTEM, .name = "filesystem"},
    },
};

// SPDX-SnippetEnd

// The modules close_modules let go of that something else still held, as
// the window holds graphics. Lota holds no reference to them any more, so
// they are never let go of twice.
std::set<love::Module *> &lingering() {
  static std::set<love::Module *> modules;
  return modules;
}

// Drops from lingering() the modules that have closed since.
void forget_closed() {
  std::erase_if(lingering(), [](love::Module *module) {
    return std::ranges::none_of(CLOSING_ORDER, [module](const Closing &closing) {
      return love::Module::getInstance<love::Module>(closing.type) == module;
    });
  });
}

// Closes the engine as lua_close closes LÖVE's main Lua state when a game
// quits or restarts (src/love.cpp:291): first it releases every engine
// object this Ractor's wrappers hold, as closing the state collects every
// userdata, so no object outlives a module it needs, and a wrapper that
// is still reachable answers as a released one; then the release queue;
// then it lets go of each module, in the opposite order to the one
// boot.lua opened them in, as Lua collects the modules after the objects
// they made. A module something else holds goes when that lets go of it,
// as graphics goes with the window. The thread module stays while a
// thread runs (Lota::Native::Thread.close). Returns the names of the
// modules still open.
Rice::Array close_modules() {
  lota::native::require_main_thread("Lota::Native");
  const Rice::Array wrappers(lota::native::WrapperIdentities::instance().wrappers());
  for (const Rice::Object &wrapper : lota::native::ruby::elements(wrappers)) {
    if (lota::native::EngineWrapper *engine = lota::native::EngineWrapper::of(wrapper.value())) {
      engine->release(wrapper.value());
    }
  }
  lota::native::ReleaseQueue::instance().drain();
  forget_closed();

  for (const Closing &closing : CLOSING_ORDER) {
    if (closing.type == love::Module::M_THREAD) {
      lota::native::close_thread_module();
      continue;
    }
    auto *module = love::Module::getInstance<love::Module>(closing.type);
    if (module != nullptr && !lingering().contains(module)) {
      module->release();
    }
  }

  Rice::Array open;
  for (const Closing &closing : CLOSING_ORDER) {
    const bool still = closing.type == love::Module::M_THREAD
                           ? !lota::native::close_thread_module()
                           : love::Module::getInstance<love::Module>(closing.type) != nullptr;
    if (still) {
      open.push(Rice::String(closing.name), false);
    }
  }
  for (const Closing &closing : CLOSING_ORDER) {
    if (auto *module = love::Module::getInstance<love::Module>(closing.type)) {
      lingering().insert(module);
    }
  }
  return open;
}

} // namespace

// Ruby calls this when it loads the bundle (require "lota/native"). It is
// the only symbol the bundle exports (cmake/LotaExtension.cmake).
extern "C" __attribute__((visibility("default"))) void Init_native() {
  // Every method defined from here on may be called from any Ractor, so
  // that other Ractors reach every module as LÖVE's threads do (ADR 007).
  // Graphics and window raise ThreadError there, as off the main thread
  // (native/binding.hpp, require_main_thread).
  const lota::native::RactorSafety safety(true);
  // The values the engine keeps for Ruby in C++ (native/ruby.hpp, Marks).
  lota::native::ruby::Marks::instance().install();
  // Before any binding can ask whether it runs there (native/binding.hpp).
  lota::native::record_main_thread();
  // Before any binding, so that every error the engine raises reaches Ruby
  // with LÖVE's Lua names translated (native/errors.hpp).
  lota::native::install_error_translation();
  // One Ruby wrapper for each engine object while it lives, as LÖVE pushes
  // one Lua userdata for each (native/binding.hpp, WrapperIdentities).
  lota::native::WrapperIdentities::instance().keep();
  Rice::Module native = Rice::define_module_under(Rice::define_module("Lota"), "Native");
  lota::native::define_random_generator(native);
  lota::native::define_math(native);
  lota::native::define_data(native);
  lota::native::define_filesystem(native);
  lota::native::define_image(native);
  lota::native::define_font(native);
  lota::native::define_timer(native);
  lota::native::define_deprecation(native);
  lota::native::define_thread(native);
  lota::native::define_event(native);
  lota::native::define_keyboard(native);
  lota::native::define_joystick(native);
  lota::native::define_mouse(native);
  lota::native::define_touch(native);
  lota::native::define_sensor(native);
  lota::native::define_sound(native);
  lota::native::define_audio(native);
  lota::native::define_system(native);
  lota::native::define_window(native);
  lota::native::define_graphics(native);
  lota::native::define_texture(native);
  lota::native::define_shader(native);
  lota::native::define_buffer(native);
  lota::native::define_particle_system(native);
  lota::native::define_video(native);
  lota::native::define_physics(native);
  // After the hand-written bindings, which define the classes the
  // generated ones add methods to.
  lota::native::define_generated(native);

  // love._version (vendor/love/src/modules/love/love.cpp:546-547), the
  // engine's version, which boot.lua's settings default to.
  Rice::String version(std::string{love::VERSION});
  version.freeze();
  native.const_set("VERSION", version);

  // love._version_major, _version_minor, _version_revision, and
  // _version_codename (love.cpp:549-557), which love.getVersion gives
  // (love.cpp:300-307).
  native.const_set("VERSION_MAJOR", Rice::detail::to_ruby(love::VERSION_MAJOR));
  native.const_set("VERSION_MINOR", Rice::detail::to_ruby(love::VERSION_MINOR));
  native.const_set("VERSION_REVISION", Rice::detail::to_ruby(love::VERSION_REV));
  Rice::String codename(std::string{love::VERSION_CODENAME});
  codename.freeze();
  native.const_set("VERSION_CODENAME", codename);

  // love._version_compat (love.cpp:596-602), the versions a game's
  // t.version may name without boot.lua's compatibility warning, which
  // love.isVersionCompatible compares it with (love.cpp:309-352).
  Rice::Array compatibility;
  // The list ends with a null pointer, as love.cpp's loop over it expects.
  for (const char *entry : love::VERSION_COMPATIBILITY) {
    if (entry == nullptr) {
      break;
    }
    Rice::String name(std::string{entry});
    name.freeze();
    compatibility.push(std::move(name), false);
  }
  compatibility.freeze();
  native.const_set("VERSION_COMPATIBILITY", compatibility);

  native.define_singleton_function("drain_release_queue", &drain_release_queue)
      .define_singleton_function("queued_releases", &queued_releases)
      .define_singleton_function("close_modules", &close_modules);

  // Last, once every function is bound.
  lota::native::install_engine_calls(native);
  lota::native::pin_singleton_classes(native);
}
