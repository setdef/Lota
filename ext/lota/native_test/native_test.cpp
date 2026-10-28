// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// LotaNativeTest: test-only bindings (native_test/CMakeLists.txt).

#include "native/binding.hpp"
#include "native/errors.hpp"
#include "native_test/dialogs.hpp"
#ifndef __APPLE__
#include "native_test/selections.hpp"
#endif

#include "filesystem/FileData.h"
#include "graphics/Font.h"
#include "graphics/Texture.h"
#include "image/ImageData.h"
#include "math/RandomGenerator.h"

#include <algorithm>
#include <atomic>
#include <cstddef>
#include <iterator>
#include <memory>
#include <span>
#include <stdexcept>
#include <string>
#include <system_error>
#include <type_traits>
#include <vector>

#include <SDL3/SDL_error.h>
#include <SDL3/SDL_events.h>
#include <SDL3/SDL_keyboard.h>
#include <SDL3/SDL_keycode.h>
#include <SDL3/SDL_mouse.h>
#include <SDL3/SDL_scancode.h>
#include <SDL3/SDL_stdinc.h>
#include <SDL3/SDL_timer.h>
#include <SDL3/SDL_video.h>

#include <spawn.h>
#include <unistd.h>
// O_RDONLY, which macOS's SDK declares in sys/fcntl.h and glibc in fcntl.h.
#ifdef __APPLE__
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
// to a second. Whether it does.
bool focus_window() {
  lota::native_test::activate();
  constexpr int tries = 100;
  constexpr Uint32 wait = 10;
  for (int i = 0; i < tries; ++i) {
    SDL_PumpEvents();
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
// it (lota::native_test::give_up_focus, dialogs.mm), and pumps SDL's
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
  for (int i = 0; i < tries; ++i) {
    SDL_PumpEvents();
    int count = 0;
    const std::unique_ptr<SDL_Window *, void (*)(void *)> windows(SDL_GetWindows(&count), SDL_free);
    SDL_Window *window = (windows && count > 0) ? *windows : nullptr;
    if (window == nullptr || (SDL_GetWindowFlags(window) & SDL_WINDOW_INPUT_FOCUS) == 0) {
      return true;
    }
    SDL_Delay(wait);
  }
  return false;
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
      .define_module_function("click_mouse", &click_mouse, Rice::Arg("button"), Rice::Arg("down"))
      .define_module_function("render_loopback", &render_loopback, Rice::Arg("path"),
                              Rice::Arg("dt"))
      .define_module_function("press_return_on_dialogs",
                              &lota::native_test::press_return_on_dialogs)
      .define_module_function("dialogs_answered", &lota::native_test::dialogs_answered)
      .define_module_function("focus_window", &focus_window)
      .define_module_function("unfocus_window", &unfocus_window)
      .define_module_function("stay_in_background", &lota::native_test::stay_in_background)
#ifndef __APPLE__
      .define_module_function("tolerate_vanished_requestors",
                              &lota::native_test::tolerate_vanished_requestors)
      .define_module_function("request_clipboard_and_vanish",
                              &lota::native_test::request_clipboard_and_vanish)
#endif
      .define_module_function("edit_text", &edit_text)
      .define_module_function("resize_window", &resize_window)
      .define_module_function("rotate_display", &rotate_display)
      .define_module_function("image_data_bytes", &image_data_bytes,
                              Rice::Arg("image_data").setValue())
      .define_module_function("spawn", &spawn, Rice::Arg("command"), Rice::Arg("output"),
                              Rice::Arg("environment"));

  // Its functions stay found after a test compacts the heap, as
  // Lota::Native's do (Init_native).
  lota::native::pin_singleton_classes(test);
}
