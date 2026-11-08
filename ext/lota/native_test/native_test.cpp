// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// LotaNativeTest: test-only bindings (native_test/CMakeLists.txt).

#include "native/binding.hpp"
#include "native/errors.hpp"
#include "native/luajit.hpp"
#include "native_test/dialogs.hpp"
#ifndef __APPLE__
#include "native_test/selections.hpp"
#endif

#include "filesystem/FileData.h"
#include "graphics/Font.h"
#include "graphics/Mesh.h"
#include "graphics/Texture.h"
#include "image/ImageData.h"
#include "math/RandomGenerator.h"

#include <algorithm>
#include <atomic>
#include <bit>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <initializer_list>
#include <iterator>
#include <map>
#include <memory>
#include <span>
#include <stdexcept>
#include <string>
#include <system_error>
#include <thread>
#include <type_traits>
#include <utility>
#include <vector>

#include <SDL3/SDL_error.h>
#include <SDL3/SDL_events.h>
#include <SDL3/SDL_init.h>
#include <SDL3/SDL_joystick.h>
#include <SDL3/SDL_keyboard.h>
#include <SDL3/SDL_keycode.h>
#include <SDL3/SDL_mouse.h>
#include <SDL3/SDL_rect.h>
#include <SDL3/SDL_scancode.h>
#include <SDL3/SDL_stdinc.h>
#include <SDL3/SDL_timer.h>
#include <SDL3/SDL_touch.h>
#include <SDL3/SDL_video.h>

#include <spawn.h>
#include <unistd.h>
// O_RDONLY, which macOS's SDK declares in sys/fcntl.h and glibc in fcntl.h.
#ifdef __APPLE__
#include <CoreFoundation/CFBase.h>
#include <sys/fcntl.h>
#else
#include <fcntl.h>
#endif

// The parity harness's audio device (loopback.cpp), which the harness
// loads with DYLD_INSERT_LIBRARIES on macOS and LD_PRELOAD on Linux. A Ruby
// extension leaves undefined what it does not link (on macOS with
// -undefined dynamic_lookup), so this bundle finds it in whichever image
// has it, and the weak reference makes it nullptr in a process the harness
// did not load it into.
#ifdef __APPLE__
extern "C" __attribute__((weak_import)) long lota_loopback_render(const char *path, double dt);
// The parity harness's Metal watch (metal_watch.mm), found the same way.
// Its status is an MTLCommandBufferStatus, an NSUInteger (MTLCommandBuffer.h).
extern "C" __attribute__((weak_import)) void
lota_metal_watch_check(int waited, unsigned long status, long code);
// Metal's MTLCreateSystemDefaultDevice (Metal/MTLDevice.h), which this C++
// file declares as returning the device as a Core Foundation reference, the
// caller's to release, and finds the same way, so that the watch, when
// loaded, interposes its calls.
extern "C" __attribute__((weak_import)) CFTypeRef MTLCreateSystemDefaultDevice();
#else
extern "C" __attribute__((weak)) long lota_loopback_render(const char *path, double dt);
#endif

namespace {

using love::math::RandomGenerator;

// Counted objects count per generation, so a test counts only what it
// made: an object an earlier test left for the collector, destroyed during
// this test, is not counted.
std::atomic<long> &generation() {
  static std::atomic<long> current{0};
  return current;
}

std::atomic<long> &constructions() {
  static std::atomic<long> count{0};
  return count;
}

std::atomic<long> &destructions() {
  static std::atomic<long> count{0};
  return count;
}

// How many Confined objects of this generation were destroyed off the main
// thread.
std::atomic<long> &off_main_thread_destructions() {
  static std::atomic<long> count{0};
  return count;
}

// Starts a generation: counting begins again from zero.
long begin_generation() {
  constructions() = 0;
  destructions() = 0;
  off_main_thread_destructions() = 0;
  return ++generation();
}

// An engine object that counts how many of its generation were constructed
// and destroyed.
class Counted : public love::Object {
public:
  Counted() { ++constructions(); }
  Counted(const Counted &) = delete;
  Counted(Counted &&) = delete;
  Counted &operator=(const Counted &) = delete;
  Counted &operator=(Counted &&) = delete;
  ~Counted() override {
    if (generation_ == generation()) {
      ++destructions();
    }
  }

  // Read in this bundle's own code, so ASan checks the read.
  [[nodiscard]] int marker() const { return marker_; }

  // The generation it was made in. (Not named generation(), which would
  // hide the counter that generation_ is initialized from.)
  [[nodiscard]] long made_in() const { return generation_; }

private:
  long generation_ = generation();
  int marker_ = 1;
};

// An engine object of a main-thread module, as far as the memory rule is
// concerned (ReleasedOnMainThread, below): it counts its constructions and
// destructions in the same generation as Counted, and how many of its
// destructions ran off the main thread.
class Confined : public love::Object {
public:
  Confined() { ++constructions(); }

  // The generation it was made in. (Not named generation(), which would
  // hide the counter that generation_ is initialized from.)
  [[nodiscard]] long made_in() const { return generation_; }

  Confined(const Confined &) = delete;
  Confined(Confined &&) = delete;
  Confined &operator=(const Confined &) = delete;
  Confined &operator=(Confined &&) = delete;
  ~Confined() override {
    if (generation_ == generation()) {
      ++destructions();
      if (!lota::native::on_main_thread()) {
        ++off_main_thread_destructions();
      }
    }
  }

private:
  long generation_ = generation();
};

} // namespace

// Confined is released only on the main thread, as a Texture is. This
// bundle has one translation unit, so every wrapper of Confined sees this.
template <> struct lota::native::ReleasedOnMainThread<Confined> : std::true_type {};

namespace {

// The one engine object C++ holds on its own, as LÖVE's modules hold
// objects with love::StrongRef.
love::StrongRef<love::Object> &held() {
  static love::StrongRef<love::Object> reference;
  return reference;
}

Counted *held_counted() {
  auto *counted = dynamic_cast<Counted *>(held().get());
  if (counted == nullptr) {
    throw std::runtime_error("no Counted is held");
  }
  return counted;
}

// An object of class +name+ from Lota::Native, the other bundle. That
// bundle has its own Rice registries, so this one cannot unwrap through
// them, but both are compiled from the same Rice header, so its wrapper's
// virtual get() returns the pointer here as it would there.
template <typename T>
// NOLINTNEXTLINE(misc-include-cleaner)
T *foreign(VALUE value, const char *name) {
  const Rice::Object object(value);
  // +name+ may name a class inside a module of Lota::Native, such as
  // Graphics::Font, which Ruby's constants are looked up in one by one.
  Rice::Object expected = Rice::define_module_under(Rice::define_module("Lota"), "Native");
  const std::string path(name);
  for (std::size_t start = 0; start <= path.size();) {
    const std::size_t end = std::min(path.find("::", start), path.size());
    expected = Rice::Module(expected.value()).const_get(path.substr(start, end - start));
    start = end + 2;
  }
  if (!object.is_a(expected)) {
    throw std::invalid_argument(std::string("expected a Lota::Native::") + name);
  }
  Rice::detail::WrapperBase *wrapper = Rice::detail::getWrapper(object.value());
  // Rice's get() takes the type it checks against as non-const, though it
  // only reads it; Ruby hands the object's own type out as const.
  // NOLINTNEXTLINE(cppcoreguidelines-pro-type-const-cast,misc-include-cleaner)
  auto *type = const_cast<rb_data_type_t *>(RTYPEDDATA_TYPE(object.value()));
  return static_cast<T *>(wrapper->get(type));
}

// Engine objects C++ holds on its own, many at once.
std::vector<love::StrongRef<love::Object>> &observed() {
  static std::vector<love::StrongRef<love::Object>> references;
  return references;
}

// Holds +object+, a Lota::Native object of class +name+.
template <typename T> void observe(VALUE value, const char *name) {
  observed().emplace_back(foreign<T>(value, name), love::Acquire::RETAIN);
}

// Each observed object's reference count, in the order they were observed.
std::vector<int> observed_reference_counts() {
  std::vector<int> counts;
  counts.reserve(observed().size());
  for (const auto &reference : observed()) {
    counts.push_back(reference->getReferenceCount());
  }
  return counts;
}

int held_reference_count() { return held() ? held()->getReferenceCount() : 0; }

// Decodes +file_data+, a Lota::Native::FileData, as w_newImageData would,
// but with this bundle's copy of the engine, whose love.image module is
// never opened: ImageData's own constructor then raises LÖVE's error
// (vendor/love/src/modules/image/ImageData.cpp:115-116), which this
// bundle's handler translates as Lota::Native's does.
void decode_without_the_image_module(VALUE file_data) {
  const love::StrongRef<love::image::ImageData> decoded(
      new love::image::ImageData(foreign<love::filesystem::FileData>(file_data, "FileData")),
      love::Acquire::NORETAIN);
}

// Starting a process from rake test:native's Ruby. Ruby starts every
// process with fork (process.c, retry_fork_async_signal_safe). On macOS,
// ASan's fork handler locks every block of its stack store before the
// fork and unlocks them in the child from a pthread_atfork handler, which
// libSystem runs after its own child handlers (Libsystem init.c,
// libSystem_atfork_child). Those handlers allocate and free, and ASan
// stores the stack of each call. When a stack starts a new block, the
// child takes that block's lock, held in the name of a parent thread the
// child does not have, and libplatform kills the child before exec
// ("os_unfair_lock is corrupt"). posix_spawn runs none of this process's
// code in the child, so no fork handler runs.

// pid_t, named through getpid: macOS declares pid_t itself only in a
// private header, sys/_types/_pid_t.h.
using ProcessId = decltype(getpid());

// Throws when a posix_spawn function fails.
void check(int error, const char *call) {
  if (error != 0) {
    throw std::system_error(error, std::generic_category(), call);
  }
}

// A posix_spawn file-action list, destroyed with its scope.
class FileActions {
public:
  FileActions() {
    check(posix_spawn_file_actions_init(&actions_), "posix_spawn_file_actions_init");
  }
  FileActions(const FileActions &) = delete;
  FileActions(FileActions &&) = delete;
  FileActions &operator=(const FileActions &) = delete;
  FileActions &operator=(FileActions &&) = delete;
  ~FileActions() { posix_spawn_file_actions_destroy(&actions_); }

  posix_spawn_file_actions_t *get() { return &actions_; }

private:
  posix_spawn_file_actions_t actions_{};
};

// A posix_spawn attribute set, destroyed with its scope.
class Attributes {
public:
  Attributes() { check(posix_spawnattr_init(&attributes_), "posix_spawnattr_init"); }
  Attributes(const Attributes &) = delete;
  Attributes(Attributes &&) = delete;
  Attributes &operator=(const Attributes &) = delete;
  Attributes &operator=(Attributes &&) = delete;
  ~Attributes() { posix_spawnattr_destroy(&attributes_); }

  posix_spawnattr_t *get() { return &attributes_; }

private:
  posix_spawnattr_t attributes_{};
};

// Copies of strings and the null-terminated array of pointers to them that
// posix_spawn takes for arguments and environment.
class Words {
public:
  explicit Words(const std::vector<std::string> &words) : words_(words) {
    pointers_.reserve(words_.size() + 1);
    for (std::string &word : words_) {
      pointers_.push_back(word.data());
    }
    pointers_.push_back(nullptr);
  }
  Words(const Words &) = delete;
  Words(Words &&) = delete;
  Words &operator=(const Words &) = delete;
  Words &operator=(Words &&) = delete;
  ~Words() = default;

  char *const *get() { return pointers_.data(); }

private:
  std::vector<std::string> words_;
  std::vector<char *> pointers_;
};

// Starts command[0], found on this process's PATH, with arguments
// command[1..] and exactly +environment+ (NAME=value strings). Its
// standard input reads /dev/null, and its standard output and standard
// error both write to the descriptor +output+. Returns its process ID for
// Process.wait2.
ProcessId spawn(const std::vector<std::string> &command, int output,
                const std::vector<std::string> &environment) {
  if (command.empty()) {
    throw std::invalid_argument("spawn needs a command");
  }
  FileActions actions;
  check(posix_spawn_file_actions_addopen(actions.get(), STDIN_FILENO, "/dev/null", O_RDONLY, 0),
        "posix_spawn_file_actions_addopen");
  check(posix_spawn_file_actions_adddup2(actions.get(), output, STDOUT_FILENO),
        "posix_spawn_file_actions_adddup2");
  check(posix_spawn_file_actions_adddup2(actions.get(), output, STDERR_FILENO),
        "posix_spawn_file_actions_adddup2");
  Attributes attributes;
  // The child inherits only the three descriptors the actions above set,
  // not a pipe another thread is spawning with at the same moment: macOS
  // closes every other one with POSIX_SPAWN_CLOEXEC_DEFAULT, and glibc
  // (2.34 and newer) with a file action that closes every descriptor from
  // the first after standard error (posix_spawn_file_actions_addclosefrom_np).
#ifdef POSIX_SPAWN_CLOEXEC_DEFAULT
  check(posix_spawnattr_setflags(attributes.get(), POSIX_SPAWN_CLOEXEC_DEFAULT),
        "posix_spawnattr_setflags");
#else
  check(posix_spawn_file_actions_addclosefrom_np(actions.get(), STDERR_FILENO + 1),
        "posix_spawn_file_actions_addclosefrom_np");
#endif
  Words arguments(command);
  Words variables(environment);
  ProcessId pid = 0;
  check(posix_spawnp(&pid, command.front().c_str(), actions.get(), attributes.get(),
                     arguments.get(), variables.get()),
        command.front().c_str());
  return pid;
}

// Holds the key with SDL scancode +scancode+ down, or lets it up, in the
// keyboard state SDL keeps and love.keyboard.isDown reads
// (keyboard/sdl/Keyboard.cpp:56-72). SDL is one shared framework, so its
// state is the same for Lota::Native as for this bundle. A test cannot
// press a key, and SDL has no public way to set its state: a key event
// pushed into SDL's queue leaves the state alone, and one SDL reads from
// macOS counts only while the window has keyboard focus, which no test can
// promise. So this writes the state SDL_GetKeyboardState returns, which is
// SDL's own array (SDL 3.4.10, src/events/SDL_keyboard.c,
// SDL_GetKeyboardState), as the parity harness's Lua side does
// (test/parity/lua/conf.lua). The next key event SDL reads for that key
// sets it again.
void hold(int scancode, bool down) {
  int count = 0;
  const bool *state = SDL_GetKeyboardState(&count);
  if (scancode <= SDL_SCANCODE_UNKNOWN || scancode >= count) {
    throw std::out_of_range("no such scancode: " + std::to_string(scancode));
  }
  // NOLINTNEXTLINE(cppcoreguidelines-pro-type-const-cast)
  const std::span<bool> keys(const_cast<bool *>(state), static_cast<std::size_t>(count));
  *std::next(keys.begin(), scancode) = down;
}

// The scancode of the key that types the character +codepoint+ on this
// machine's keyboard layout, as love.keyboard.isDown finds the scancode of
// a key (keyboard/sdl/Keyboard.cpp:65).
int scancode(int codepoint) {
  return static_cast<int>(SDL_GetScancodeFromKey(static_cast<SDL_Keycode>(codepoint), nullptr));
}

// The bytes of +image_data+, a Lota::Native::ImageData, as LÖVE's
// Data:getString returns them (vendor/love/src/modules/data/wrap_Data.cpp:40-59),
// so the parity harness compares two frames in one comparison instead of
// pixel by pixel.
std::string image_data_bytes(VALUE image_data) {
  const love::image::ImageData *image = foreign<love::image::ImageData>(image_data, "ImageData");
  return {static_cast<const char *>(image->getData()), image->getSize()};
}

// Events SDL reads from the system, pushed into SDL's queue instead, so
// that LÖVE's own Event::convert (vendor/love/src/modules/event/sdl/
// Event.cpp) turns each into the message a game would receive. A test
// cannot click, type into an input method, resize a window it does not
// own the screen for, or turn a display. SDL is one shared framework, so
// its queue is the same for Lota::Native as for this bundle.

// Pushes +event+, stamped with the time now, or throws SDL's error.
void push(SDL_Event &event) {
  event.common.timestamp = SDL_GetTicksNS();
  if (!SDL_PushEvent(&event)) {
    throw std::runtime_error(SDL_GetError());
  }
}

// A double click's second press of SDL mouse button +button+ (3 is the
// right button, which LÖVE numbers 2), at (10.5, 20.25) in the window.
void press_mouse(int button) {
  constexpr float x = 10.5F;
  constexpr float y = 20.25F;
  SDL_Event event{};
  event.button.type = SDL_EVENT_MOUSE_BUTTON_DOWN;
  event.button.button = static_cast<Uint8>(button);
  event.button.down = true;
  event.button.clicks = 2;
  event.button.x = x;
  event.button.y = y;
  push(event);
}

// SDL's event for mouse button +button+, numbered as LÖVE numbers it (1
// the left, 2 the right, 3 the middle), going down, when +down+ is true,
// or coming up, where SDL's mouse state says the pointer is, as macOS
// would report a single click to the window. LÖVE's Event::convert turns
// it into mousepressed or mousereleased, with SDL's button numbers turned
// back into LÖVE's (vendor/love/src/modules/event/sdl/Event.cpp:354-384).
// SDL keeps the buttons that are down to itself, so love.mouse.isDown does
// not see the press. The parity harness clicks with it, after moving the
// pointer with love.mouse.setPosition, which updates SDL's mouse state;
// its Lua side pushes the same event through LuaJIT's FFI
// (test/parity/lua/conf.lua).
void click_mouse(int button, bool down) {
  constexpr int right = 2;
  constexpr int middle = 3;
  Uint8 sdl_button = SDL_BUTTON_LEFT;
  if (button == right) {
    sdl_button = SDL_BUTTON_RIGHT;
  } else if (button == middle) {
    sdl_button = SDL_BUTTON_MIDDLE;
  } else {
    sdl_button = static_cast<Uint8>(button);
  }
  SDL_Event event{};
  event.button.type = down ? SDL_EVENT_MOUSE_BUTTON_DOWN : SDL_EVENT_MOUSE_BUTTON_UP;
  event.button.button = sdl_button;
  event.button.down = down;
  event.button.clicks = 1;
  SDL_GetMouseState(&event.button.x, &event.button.y);
  push(event);
}

// The id of the touch device the pushed finger events below name. SDL
// knows no such device, so SDL_GetTouchDeviceType answers
// SDL_TOUCH_DEVICE_INVALID for it (SDL 3.4.10, src/events/SDL_touch.c),
// which LÖVE reads as a touchscreen (touch/sdl/Touch.cpp, getDeviceType):
// the events stand for a finger on the glass of a phone or a tablet.
constexpr SDL_TouchID pushed_touch_device = 42;

// The first window, which a finger on a touchscreen lands in.
SDL_WindowID first_window_id() {
  int count = 0;
  const std::unique_ptr<SDL_Window *, void (*)(void *)> windows(SDL_GetWindows(&count), SDL_free);
  SDL_Window *window = (windows && count > 0) ? *windows : nullptr;
  return (window == nullptr) ? 0 : SDL_GetWindowID(window);
}

// The numbers in +values+, as floats, which Rice converts from Integers or
// Floats.
std::vector<float> floats(Rice::Array values) {
  const Rice::Array list = std::move(values);
  std::vector<float> numbers;
  for (const auto item : list) {
    numbers.push_back(Rice::detail::From_Ruby<float>().convert(item.value()));
  }
  return numbers;
}

// SDL's event for finger +finger+ on a touchscreen landing (+phase+
// "down"), moving ("motion"), lifting ("up"), or being cancelled by the
// system ("canceled"), with +values+ its x and y across the window, from 0
// to 1, how far it moved along each, and its pressure, as iOS would
// report it (SDL 3.4.10,
// src/video/uikit/SDL_uikitview.m). SDL's own touch code sends such an
// event from the system's (SDL_SendTouch, src/events/SDL_touch.c), which
// SDL does not export, so the event is pushed into SDL's queue, where
// LÖVE's Event::convert turns it into touchpressed, touchmoved, or
// touchreleased (vendor/love/src/modules/event/sdl/Event.cpp:394-441). A
// pushed event leaves out what SDL_SendTouch does beside it: the mouse
// events SDL makes of the first finger (push_touch_mouse stands for those)
// and SDL's own list of fingers, which LÖVE does not read.
void push_finger(const std::string &phase, SDL_FingerID finger, std::vector<float> numbers) {
  const std::map<std::string, SDL_EventType> types{
      {"down", SDL_EVENT_FINGER_DOWN},
      {"motion", SDL_EVENT_FINGER_MOTION},
      {"up", SDL_EVENT_FINGER_UP},
      {"canceled", SDL_EVENT_FINGER_CANCELED},
  };
  SDL_Event event{};
  event.tfinger.type = types.at(phase);
  event.tfinger.touchID = pushed_touch_device;
  event.tfinger.fingerID = finger;
  event.tfinger.x = numbers.at(0);
  event.tfinger.y = numbers.at(1);
  event.tfinger.dx = numbers.at(2);
  event.tfinger.dy = numbers.at(3);
  event.tfinger.pressure = numbers.at(4);
  event.tfinger.windowID = first_window_id();
  push(event);
}

// The mouse events SDL makes of a finger landing (+down+ true) or lifting
// at +position+, its x and y in the window's coordinates, as SDL_SendTouch
// sends them
// for the first finger down while SDL_HINT_TOUCH_MOUSE_EVENTS is on, as it
// is unless a program turns it off (SDL 3.4.10, src/events/SDL_touch.c,
// SDL_SendTouch, and src/events/SDL_mouse.c, SDL_TouchMouseEventsChanged):
// the pointer moving there, then the left button, both from
// SDL_TOUCH_MOUSEID, which LÖVE passes on as istouch
// (vendor/love/src/modules/event/sdl/Event.cpp:330-384). A finger that
// lifts sends the button alone.
void push_touch_mouse(bool down, Rice::Array position) {
  const std::vector<float> point = floats(std::move(position));
  if (down) {
    SDL_Event motion{};
    motion.motion.type = SDL_EVENT_MOUSE_MOTION;
    motion.motion.which = SDL_TOUCH_MOUSEID;
    motion.motion.windowID = first_window_id();
    motion.motion.x = point.at(0);
    motion.motion.y = point.at(1);
    push(motion);
  }
  SDL_Event button{};
  button.button.type = down ? SDL_EVENT_MOUSE_BUTTON_DOWN : SDL_EVENT_MOUSE_BUTTON_UP;
  button.button.which = SDL_TOUCH_MOUSEID;
  button.button.windowID = first_window_id();
  button.button.button = SDL_BUTTON_LEFT;
  button.button.down = down;
  button.button.clicks = 1;
  button.button.x = point.at(0);
  button.button.y = point.at(1);
  push(button);
}

// SDL's event for the left mouse button going down or up at +position+,
// its x and y in the window's coordinates, from a real mouse (mouse 1), as
// macOS reports a click.
void push_mouse_click(bool down, Rice::Array position) {
  const std::vector<float> point = floats(std::move(position));
  SDL_Event button{};
  button.button.type = down ? SDL_EVENT_MOUSE_BUTTON_DOWN : SDL_EVENT_MOUSE_BUTTON_UP;
  button.button.which = 1;
  button.button.windowID = first_window_id();
  button.button.button = SDL_BUTTON_LEFT;
  button.button.down = down;
  button.button.clicks = 1;
  button.button.x = point.at(0);
  button.button.y = point.at(1);
  push(button);
}

// The ids of the touch devices SDL knows. SDL adds SDL_MOUSE_TOUCHID among
// them exactly while it turns mouse events into touches
// (SDL_HINT_MOUSE_TOUCH_EVENTS, SDL 3.4.10, src/events/SDL_mouse.c,
// SDL_MouseTouchEventsChanged), which it does by default on iOS and
// Android and not elsewhere; SDL_MOUSE_TOUCHID is (SDL_TouchID)-1, which
// Ruby receives as the largest Uint64.
Rice::Array touch_devices() {
  int count = 0;
  const std::unique_ptr<SDL_TouchID, void (*)(void *)> devices(SDL_GetTouchDevices(&count),
                                                               SDL_free);
  Rice::Array ids;
  const std::span<SDL_TouchID> listed(devices.get(), devices ? static_cast<std::size_t>(count) : 0);
  for (const SDL_TouchID id : listed) {
    ids.push(static_cast<std::uint64_t>(id), false);
  }
  return ids;
}

// The size of the first window in its own coordinates, which SDL reports
// a mouse's position in, as [width, height].
Rice::Array window_size() {
  int count = 0;
  const std::unique_ptr<SDL_Window *, void (*)(void *)> windows(SDL_GetWindows(&count), SDL_free);
  SDL_Window *window = (windows && count > 0) ? *windows : nullptr;
  int width = 0;
  int height = 0;
  if (window == nullptr || !SDL_GetWindowSize(window, &width, &height)) {
    throw std::runtime_error(SDL_GetError());
  }
  Rice::Array result;
  result.push(width, false);
  result.push(height, false);
  return result;
}

// Joysticks SDL makes in software (SDL_AttachVirtualJoystick, SDL 3.4.10,
// src/joystick/virtual/SDL_virtualjoystick.c), which SDL reports as it
// reports a device plugged in, so that LÖVE's own joystick module and
// Event::convert (vendor/love/src/modules/event/sdl/Event.cpp:618-757)
// meet them as they would a controller; no test machine has one. Each is
// opened here too, as SDL sets a virtual joystick's buttons, axes, and hats
// through an open handle, and reports the change at its next pump.
std::map<SDL_JoystickID, SDL_Joystick *> &virtual_joysticks() {
  static std::map<SDL_JoystickID, SDL_Joystick *> joysticks;
  return joysticks;
}

// Attaches a virtual joystick named +name+ and returns its instance id: a
// gamepad, with an Xbox controller's 15 buttons and 6 axes, which SDL maps
// as a gamepad (SDL_JOYSTICK_TYPE_GAMEPAD), when +gamepad+ is true, and
// otherwise a joystick SDL knows no mapping for, with 2 axes, 4 buttons,
// and a hat. Both have rumble motors that refuse every request, so that a
// test sees the answer SDL gives LÖVE (SDL_RumbleJoystick) passed on.
SDL_JoystickID attach_virtual_joystick(bool gamepad, const std::string &name) {
  constexpr Uint16 gamepad_buttons = 15;
  constexpr Uint16 gamepad_axes = 6;
  constexpr Uint16 joystick_buttons = 4;
  constexpr Uint16 joystick_axes = 2;
  SDL_VirtualJoystickDesc desc{};
  // SDL_INIT_INTERFACE, which zeroes the description, as desc{} has, and
  // sets its version to its size, in a do-while that clang-tidy refuses.
  desc.version = sizeof(desc);
  desc.type = gamepad ? SDL_JOYSTICK_TYPE_GAMEPAD : SDL_JOYSTICK_TYPE_UNKNOWN;
  desc.naxes = gamepad ? gamepad_axes : joystick_axes;
  desc.nbuttons = gamepad ? gamepad_buttons : joystick_buttons;
  desc.nhats = gamepad ? 0 : 1;
  desc.name = name.c_str();
  desc.Rumble = [](void * /*userdata*/, Uint16 /*low*/, Uint16 /*high*/) { return false; };
  const SDL_JoystickID id = SDL_AttachVirtualJoystick(&desc);
  if (id == 0) {
    throw std::runtime_error(SDL_GetError());
  }
  SDL_Joystick *joystick = SDL_OpenJoystick(id);
  if (joystick == nullptr) {
    throw std::runtime_error(SDL_GetError());
  }
  virtual_joysticks()[id] = joystick;
  return id;
}

// The open handle of the virtual joystick +id+, or std::out_of_range.
SDL_Joystick *virtual_joystick(SDL_JoystickID id) { return virtual_joysticks().at(id); }

// Unplugs the virtual joystick +id+.
void detach_virtual_joystick(SDL_JoystickID id) {
  SDL_CloseJoystick(virtual_joystick(id));
  virtual_joysticks().erase(id);
  if (!SDL_DetachVirtualJoystick(id)) {
    throw std::runtime_error(SDL_GetError());
  }
}

// Holds button +button+ of the virtual joystick +id+, counting from 0,
// down or lets it up.
void set_virtual_button(SDL_JoystickID id, int button, bool down) {
  if (!SDL_SetJoystickVirtualButton(virtual_joystick(id), button, down)) {
    throw std::runtime_error(SDL_GetError());
  }
}

// Moves axis +axis+ of the virtual joystick +id+, counting from 0, to
// +value+, from -32768 to 32767.
void set_virtual_axis(SDL_JoystickID id, int axis, int value) {
  if (!SDL_SetJoystickVirtualAxis(virtual_joystick(id), axis, static_cast<Sint16>(value))) {
    throw std::runtime_error(SDL_GetError());
  }
}

// Points hat +hat+ of the virtual joystick +id+, counting from 0, at
// +value+, SDL's SDL_HAT_ bits (1 is up).
void set_virtual_hat(SDL_JoystickID id, int hat, int value) {
  if (!SDL_SetJoystickVirtualHat(virtual_joystick(id), hat, static_cast<Uint8>(value))) {
    throw std::runtime_error(SDL_GetError());
  }
}

// An input method editing the text "lota", with the cursor after its first
// character and no selection (-1, as SDL marks a length it does not set).
// The text is a literal, which outlives the event, as SDL needs of a
// string it did not allocate.
void edit_text() {
  SDL_Event event{};
  event.edit.type = SDL_EVENT_TEXT_EDITING;
  event.edit.text = "lota";
  event.edit.start = 1;
  event.edit.length = -1;
  push(event);
}

// SDL's key event for the key with scancode +scancode+ going down, when
// +down+ is true, or coming up, as macOS would report it to a window with
// keyboard focus. LÖVE's Event::convert reads only the event's key and
// scancode (vendor/love/src/modules/event/sdl/Event.cpp:284-317); the key
// is the one SDL itself would put in the event (SDL_SendKeyboardKey calls
// SDL_GetKeyFromScancode with key_event true), so that the key name LÖVE
// gives follows this machine's layout, as a real press's would. Pushing
// the event bypasses keyboard focus, which SDL checks only for events it
// reads from the system, so the parity harness's presses reach a window
// the player is not looking at; the harness's Lua side pushes the same
// event through LuaJIT's FFI (test/parity/lua/conf.lua).
void press_key(int scancode, bool down) {
  SDL_Event event{};
  event.key.type = down ? SDL_EVENT_KEY_DOWN : SDL_EVENT_KEY_UP;
  event.key.scancode = static_cast<SDL_Scancode>(scancode);
  event.key.key = SDL_GetKeyFromScancode(event.key.scancode, SDL_KMOD_NONE, true);
  event.key.down = down;
  push(event);
}

// Makes this program active, with its first window holding keyboard
// focus (lota::native_test::activate, dialogs.mm), and pumps SDL's events,
// leaving them queued, until SDL hears that the window has focus, for up
// to a second. Each try also has SDL ask the system again whether the
// window can be seen (lota::native_test::reread_occlusion). Whether it
// has focus.
bool focus_window() {
  lota::native_test::activate();
  constexpr int tries = 100;
  constexpr Uint32 wait = 10;
  for (int i = 0; i < tries; ++i) {
    SDL_PumpEvents();
    lota::native_test::reread_occlusion();
    int count = 0;
    const std::unique_ptr<SDL_Window *, void (*)(void *)> windows(SDL_GetWindows(&count), SDL_free);
    SDL_Window *window = (windows && count > 0) ? *windows : nullptr;
    if (window != nullptr && (SDL_GetWindowFlags(window) & SDL_WINDOW_INPUT_FOCUS) != 0) {
      return true;
    }
    SDL_Delay(wait);
  }
  return false;
}

// Undoes focus_window: gives keyboard focus back to the program that had
// it (lota::native_test::give_up_focus, dialogs.mm), shows the window
// again, and pumps SDL's
// events, leaving them queued, until SDL hears that the window lost focus,
// for up to a second. SDL lets go of every key held down when its window
// loses focus (SDL 3.4.10, src/events/SDL_keyboard.c, SDL_SetKeyboardFocus
// and SDL_ResetKeyboard), so a window left with focus would let go of a
// key a later test holds whenever the person at the computer clicks
// elsewhere. Whether the window lost focus.
bool unfocus_window() {
  lota::native_test::give_up_focus();
  constexpr int tries = 100;
  constexpr Uint32 wait = 10;
  bool lost = false;
  for (int i = 0; i < tries && !lost; ++i) {
    SDL_PumpEvents();
    int count = 0;
    const std::unique_ptr<SDL_Window *, void (*)(void *)> windows(SDL_GetWindows(&count), SDL_free);
    SDL_Window *window = (windows && count > 0) ? *windows : nullptr;
    lost = window == nullptr || (SDL_GetWindowFlags(window) & SDL_WINDOW_INPUT_FOCUS) == 0;
    if (!lost) {
      SDL_Delay(wait);
    }
  }
  // A program that stops being a regular one has its windows ordered out,
  // which SDL reports as hiding the first window a moment later, so the
  // window is shown again, which SDL_WINDOW_ACTIVATE_WHEN_SHOWN
  // (test/test_helper.rb) keeps from activating the program. A window that
  // is never hidden is left as it is.
  constexpr int hide_tries = 30;
  for (int i = 0; i < hide_tries; ++i) {
    SDL_PumpEvents();
    int count = 0;
    const std::unique_ptr<SDL_Window *, void (*)(void *)> windows(SDL_GetWindows(&count), SDL_free);
    SDL_Window *window = (windows && count > 0) ? *windows : nullptr;
    if (window != nullptr && (SDL_GetWindowFlags(window) & SDL_WINDOW_HIDDEN) != 0) {
      SDL_ShowWindow(window);
      SDL_PumpEvents();
      break;
    }
    SDL_Delay(wait);
  }
  return lost;
}

// The system redrawing the window during a live resize: SDL's window
// exposed event with its first datum 1, which LÖVE's event watch
// (event/sdl/Event.cpp:100-103) answers with the event module's modal
// draw, calling the callback a game set with love.event.setModalDrawCallback,
// but only from the thread that pumps events and only while a pump is
// under way. A test cannot resize a window by hand, and SDL runs a function
// another thread asks of its main thread from inside its next pump
// (SDL_RunOnMainThread, SDL 3.4.10, src/events/SDL_events.c,
// SDL_RunMainThreadCallbacks), so a thread asks that, and the event goes
// into SDL's queue from inside Lota::Event.pump, as the system's would.
// The callback runs during that pump; its results, or its error, are the
// pump's to pass on (Event::pump, event/sdl/Event.cpp:158-182).
void push_live_resize_expose(void * /*userdata*/) {
  int count = 0;
  const std::unique_ptr<SDL_Window *, void (*)(void *)> windows(SDL_GetWindows(&count), SDL_free);
  SDL_Window *window = (windows && count > 0) ? *windows : nullptr;
  SDL_Event event{};
  event.window.type = SDL_EVENT_WINDOW_EXPOSED;
  event.window.windowID = (window == nullptr) ? 0 : SDL_GetWindowID(window);
  event.window.data1 = 1;
  push(event);
}

// Queues the live resize's redraw for the next pump, and returns once it
// is queued.
void request_modal_draw() {
  bool queued = false;
  std::thread([&queued] {
    queued = SDL_RunOnMainThread(&push_live_resize_expose, nullptr, false);
  }).join();
  if (!queued) {
    throw std::runtime_error(SDL_GetError());
  }
}

// The area SDL keeps for text input in the first window, where the system
// places its candidate window, as [x, y, w, h] in the window's
// coordinates. Keyboard::setTextInput's form with a rectangle sets it
// (keyboard/sdl/Keyboard.cpp:147-165) with SDL_SetTextInputArea, which
// stores it whether or not the system shows anything there, and nothing
// in Lota or LÖVE reads it back.
Rice::Array text_input_area() {
  int count = 0;
  const std::unique_ptr<SDL_Window *, void (*)(void *)> windows(SDL_GetWindows(&count), SDL_free);
  SDL_Window *window = (windows && count > 0) ? *windows : nullptr;
  SDL_Rect area{};
  int cursor = 0;
  if (window == nullptr || !SDL_GetTextInputArea(window, &area, &cursor)) {
    throw std::runtime_error(SDL_GetError());
  }
  Rice::Array result;
  for (const int value : {area.x, area.y, area.w, area.h}) {
    result.push(value, false);
  }
  return result;
}

// The first window's size in pixels changing to the size it already has,
// so that LÖVE's handler (Event::convertWindowEvent) reads the window's
// real size and nothing changes.
void resize_window() {
  int count = 0;
  // SDL_GetWindows allocates the list, which SDL_free releases.
  const std::unique_ptr<SDL_Window *, void (*)(void *)> windows(SDL_GetWindows(&count), SDL_free);
  SDL_Window *window = (windows && count > 0) ? *windows : nullptr;
  if (window == nullptr) {
    throw std::runtime_error("no window is open");
  }
  SDL_Event event{};
  event.window.type = SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED;
  event.window.windowID = SDL_GetWindowID(window);
  SDL_GetWindowSizeInPixels(window, &event.window.data1, &event.window.data2);
  push(event);
}

// The primary display turning to landscape.
void rotate_display() {
  SDL_Event event{};
  event.display.type = SDL_EVENT_DISPLAY_ORIENTATION;
  event.display.displayID = SDL_GetPrimaryDisplay();
  event.display.data1 = SDL_ORIENTATION_LANDSCAPE;
  push(event);
}

// SDL's message for the last request it refused on this thread, or ""
// once SDL_ClearError has run. SDL_GL_SetSwapInterval refuses on a
// driver that cannot wait for the display (SDL 3.4.10,
// src/video/x11/SDL_x11opengl.c, X11_GL_SetSwapInterval), which LÖVE's
// Window::setVSync does not check (src/modules/window/sdl/Window.cpp,
// lines 1094-1108), so the message is the one sign that the request
// reached the driver.
std::string sdl_error() { return SDL_GetError(); }

void clear_sdl_error() { SDL_ClearError(); }

// The swap interval SDL answers for the current OpenGL context, which is
// what LÖVE's Window::getVSync answers with one (Window.cpp, lines
// 1128-1135), or 0 without one, as SDL_GL_GetSwapInterval leaves it.
int swap_interval() {
  int interval = 0;
  return SDL_GL_GetSwapInterval(&interval) ? interval : 0;
}

// Mixes +dt+ seconds of game time on the parity harness's loopback device
// into the file +path+ (lota_loopback_render, loopback.cpp), as the
// harness's Lua side does through LuaJIT's FFI (test/parity/lua/conf.lua).
// How many sample frames it mixed; raises when the device is not loaded
// into this process, or has not been opened or cannot write its file.
long render_loopback(const std::string &path, double dt) {
  if (lota_loopback_render == nullptr) {
    throw std::runtime_error(
        "liblota_loopback is not loaded (DYLD_INSERT_LIBRARIES or LD_PRELOAD)");
  }
  const long count = lota_loopback_render(path.c_str(), dt);
  if (count < 0) {
    throw std::runtime_error("the loopback device is not open, or cannot write its file");
  }
  return count;
}

#ifdef __APPLE__
// Counts and reports a Metal command buffer that ended with the status
// +status+ and, unless +code+ is 0, an error of Metal's domain with that
// code, as the parity harness's Metal watch does for one it saw end
// (lota_metal_watch_check, metal_watch.mm), after a wait for it when
// +waited+. Raises when the watch is not loaded into this process.
void check_metal_command_buffer(bool waited, unsigned long status, long code) {
  if (lota_metal_watch_check == nullptr) {
    throw std::runtime_error("liblota_metal_watch is not loaded (DYLD_INSERT_LIBRARIES)");
  }
  lota_metal_watch_check(waited ? 1 : 0, status, code);
}

// Makes Metal's default device, as LÖVE's Metal graphics does
// (vendor/love/src/modules/graphics/metal/Graphics.mm:293-309), and
// releases it. Raises where Metal is not loaded.
void create_metal_device() {
  if (MTLCreateSystemDefaultDevice == nullptr) {
    throw std::runtime_error("Metal is not loaded");
  }
  const CFTypeRef device = MTLCreateSystemDefaultDevice();
  if (device != nullptr) {
    CFRelease(device);
  }
}

// Has the process make Metal's default device again as it exits, from a
// handler std::atexit runs after every exit-time destructor and handler
// registered after this call, as a framework's own exit-time code may.
void create_metal_device_at_exit() {
  if (MTLCreateSystemDefaultDevice == nullptr) {
    throw std::runtime_error("Metal is not loaded");
  }
  if (std::atexit([] {
        const CFTypeRef device = MTLCreateSystemDefaultDevice();
        if (device != nullptr) {
          CFRelease(device);
        }
      }) != 0) {
    throw std::runtime_error("std::atexit could not register the handler");
  }
}
#endif

// Takes the arguments Lota::Native::Graphics.rectangle takes, converted by
// Rice the same way, and does nothing with them, so rake bench can time a
// call from Ruby into C++ apart from LÖVE's own drawing
// (tasks/bench.rb).
void noop_rectangle(const std::string & /*mode*/, double /*x*/, double /*y*/, double /*width*/,
                    double /*height*/) {}

// Deliberate bugs, for the sanitizer tests alone.

// Frees the held Counted, then reads it.
int use_after_free() {
  const Counted *counted = held_counted();
  held().set(nullptr);
  return counted->marker();
}

// INT_MAX + 1 overflows.
int add_one(int number) { return number + 1; }

constexpr bool sanitized() {
#ifdef LOTA_SANITIZE
  return true;
#else
  return false;
#endif
}

} // namespace

extern "C" __attribute__((visibility("default"))) void Init_lota_native_test() {
  lota::native::install_error_translation();
  // A new wrapper for each object this bundle wraps, which the memory
  // tests count, and none of Rice's registry, whose entries outlive the
  // wrappers the collector found dead (lota::native::WrapperIdentities,
  // native/binding.hpp); Rice keeps the objects it adopts there by default.
  Rice::detail::Registries::instance.instances.mode = Rice::detail::InstanceRegistry::Mode::Off;
  Rice::Module test = Rice::define_module("LotaNativeTest");

  Rice::define_class_under<Confined>(test, "Confined")
      .define_constructor(Rice::Constructor<Confined>())
      .define_method("generation", &Confined::made_in)
      .define_singleton_function("off_main_thread_destructions",
                                 [] { return off_main_thread_destructions().load(); })
      .define_singleton_function("drain_release_queue",
                                 [] { return lota::native::ReleaseQueue::instance().drain(); })
      .define_singleton_function("queued_releases",
                                 [] { return lota::native::ReleaseQueue::instance().size(); });

  Rice::define_class_under<Counted>(test, "Counted")
      .define_constructor(Rice::Constructor<Counted>())
      .define_method("reference_count", &Counted::getReferenceCount)
      .define_method("generation", &Counted::made_in)
      .define_singleton_function("constructions", [] { return constructions().load(); })
      .define_singleton_function("destructions", [] { return destructions().load(); })
      .define_singleton_function("begin_generation", &begin_generation);

  test.define_singleton_function("noop_rectangle", &noop_rectangle, Rice::Arg("mode"),
                                 Rice::Arg("x"), Rice::Arg("y"), Rice::Arg("width"),
                                 Rice::Arg("height"));

  test.define_module_function(
          "hold", [](Counted *counted) { held().set(counted); }, Rice::Arg("counted"))
      .define_module_function(
          "hold_random_generator",
          [](VALUE generator) {
            held().set(foreign<RandomGenerator>(generator, "RandomGenerator"));
          },
          // Rice passes the Ruby object itself (docs/bindings/methods.md).
          Rice::Arg("generator").setValue())
      .define_module_function(
          "observe_texture",
          [](VALUE texture) { observe<love::graphics::Texture>(texture, "Texture"); },
          Rice::Arg("texture").setValue())
      .define_module_function(
          "observe_font", [](VALUE font) { observe<love::graphics::Font>(font, "Graphics::Font"); },
          Rice::Arg("font").setValue())
      .define_module_function(
          "observe_mesh", [](VALUE mesh) { observe<love::graphics::Mesh>(mesh, "Mesh"); },
          Rice::Arg("mesh").setValue())
      .define_module_function(
          "observe_image_data",
          [](VALUE image_data) { observe<love::image::ImageData>(image_data, "ImageData"); },
          Rice::Arg("image_data").setValue())
      .define_module_function(
          "observe_file_data",
          [](VALUE file_data) { observe<love::filesystem::FileData>(file_data, "FileData"); },
          Rice::Arg("file_data").setValue())
      .define_module_function("observed_reference_counts",
                              [] {
                                const std::vector<int> counts = observed_reference_counts();
                                Rice::Array array;
                                for (const int count : counts) {
                                  array.push(count, false);
                                }
                                return array;
                              })
      .define_module_function(
          "decode_without_the_image_module",
          [](VALUE file_data) { decode_without_the_image_module(file_data); },
          Rice::Arg("file_data").setValue())
      .define_module_function(
          "translate_love_names",
          [](const std::string &message) { return lota::native::translate_love_names(message); },
          Rice::Arg("message"))
      // How LuaJIT's %p writes +address+ (lota::native::luajit::pointer).
      .define_module_function(
          "luajit_pointer",
          [](unsigned long long address) {
            return lota::native::luajit::pointer(
                std::bit_cast<const void *>(static_cast<std::uintptr_t>(address)));
          },
          Rice::Arg("address"))
      // The address of the engine object a Lota::Native object wraps, as
      // LÖVE's Proxy holds it, or 0 once released.
      .define_module_function(
          "engine_address",
          [](VALUE native) -> unsigned long long {
            // Lota::Native's engine types are another bundle's, which
            // EngineWrapper::of does not know.
            const auto *wrapper =
                dynamic_cast<lota::native::EngineWrapper *>(Rice::detail::getWrapper(native));
            return wrapper == nullptr ? 0 : std::bit_cast<std::uintptr_t>(wrapper->object());
          },
          Rice::Arg("native").setValue())
      .define_module_function("forget_observed", [] { observed().clear(); })
      .define_module_function("drop", [] { held().set(nullptr); })
      .define_module_function("held_reference_count", &held_reference_count)
      // A pointer C++ keeps: Ruby retains it.
      .define_module_function("held", &held_counted)
      // A reference C++ keeps: Ruby retains it too.
      .define_module_function("held_reference", []() -> Counted & { return *held_counted(); })
      // A bug: claims the held Counted's reference without being given one,
      // so collecting the wrapper releases a reference C++ still counts on.
      .define_module_function("mistakenly_adopted", &held_counted, Rice::Return().takeOwnership())
      .define_module_function("use_after_free", &use_after_free)
      .define_module_function("add_one", &add_one, Rice::Arg("number"))
      .define_module_function("sanitized?", &sanitized)
      .define_module_function("hold", &hold, Rice::Arg("scancode"), Rice::Arg("down"))
      .define_module_function("scancode", &scancode, Rice::Arg("codepoint"))
      .define_module_function("press_mouse", &press_mouse, Rice::Arg("button"))
      .define_module_function("press_key", &press_key, Rice::Arg("scancode"), Rice::Arg("down"))
      .define_module_function("push_finger", &push_finger, Rice::Arg("phase"), Rice::Arg("finger"),
                              Rice::Arg("values"))
      .define_module_function("push_touch_mouse", &push_touch_mouse, Rice::Arg("down"),
                              Rice::Arg("position"))
      .define_module_function("push_mouse_click", &push_mouse_click, Rice::Arg("down"),
                              Rice::Arg("position"))
      .define_module_function("touch_devices", &touch_devices)
      .define_module_function("attach_virtual_joystick", &attach_virtual_joystick,
                              Rice::Arg("gamepad"), Rice::Arg("name"))
      .define_module_function("detach_virtual_joystick", &detach_virtual_joystick, Rice::Arg("id"))
      .define_module_function("set_virtual_button", &set_virtual_button, Rice::Arg("id"),
                              Rice::Arg("button"), Rice::Arg("down"))
      .define_module_function("set_virtual_axis", &set_virtual_axis, Rice::Arg("id"),
                              Rice::Arg("axis"), Rice::Arg("value"))
      .define_module_function("set_virtual_hat", &set_virtual_hat, Rice::Arg("id"),
                              Rice::Arg("hat"), Rice::Arg("value"))
      .define_module_function("window_size", &window_size)
      .define_module_function("click_mouse", &click_mouse, Rice::Arg("button"), Rice::Arg("down"))
      .define_module_function("render_loopback", &render_loopback, Rice::Arg("path"),
                              Rice::Arg("dt"))
#ifdef __APPLE__
      .define_module_function("check_metal_command_buffer", &check_metal_command_buffer,
                              Rice::Arg("waited"), Rice::Arg("status"), Rice::Arg("code"))
      .define_module_function("create_metal_device", &create_metal_device)
      .define_module_function("create_metal_device_at_exit", &create_metal_device_at_exit)
#endif
      .define_module_function("press_return_on_dialogs",
                              &lota::native_test::press_return_on_dialogs)
      .define_module_function("dialogs_answered", &lota::native_test::dialogs_answered)
      .define_module_function("focus_window", &focus_window)
      .define_module_function("unfocus_window", &unfocus_window)
      .define_module_function("stay_in_background", &lota::native_test::stay_in_background)
      .define_module_function("window_state", &lota::native_test::window_state)
      .define_module_function("ignore_mouse_events", &lota::native_test::ignore_mouse_events,
                              Rice::Arg("ignore"))
#ifndef __APPLE__
      .define_module_function("tolerate_vanished_requestors",
                              &lota::native_test::tolerate_vanished_requestors)
      .define_module_function("request_clipboard_and_vanish",
                              &lota::native_test::request_clipboard_and_vanish)
#endif
      .define_module_function("edit_text", &edit_text)
      .define_module_function("resize_window", &resize_window)
      .define_module_function("request_modal_draw", &request_modal_draw)
      .define_module_function("rotate_display", &rotate_display)
      .define_module_function("sdl_error", &sdl_error)
      .define_module_function("clear_sdl_error", &clear_sdl_error)
      .define_module_function("swap_interval", &swap_interval)
      .define_module_function("text_input_area", &text_input_area)
      .define_module_function("image_data_bytes", &image_data_bytes,
                              Rice::Arg("image_data").setValue())
      .define_module_function("spawn", &spawn, Rice::Arg("command"), Rice::Arg("output"),
                              Rice::Arg("environment"));

  // Its functions stay found after a test compacts the heap, as
  // Lota::Native's do (Init_native).
  lota::native::pin_singleton_classes(test);
}
