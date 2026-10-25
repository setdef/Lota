// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// LotaNativeTest: test-only bindings (native_test/CMakeLists.txt).

#include "native/binding.hpp"

#include "math/RandomGenerator.h"

#include <atomic>
#include <stdexcept>
#include <string>
#include <system_error>
#include <vector>

#include <spawn.h>
#include <sys/fcntl.h>
#include <unistd.h>

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

// Starts a generation: counting begins again from zero.
long begin_generation() {
  constructions() = 0;
  destructions() = 0;
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

private:
  long generation_ = generation();
  int marker_ = 1;
};

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

// Lota::Native's RandomGenerator, from the other bundle. That bundle has
// its own Rice registries, so this one cannot unwrap through them, but both
// are compiled from the same Rice header, so its wrapper's virtual get()
// returns the pointer here as it would there.
// NOLINTNEXTLINE(misc-include-cleaner)
RandomGenerator *foreign_random_generator(VALUE value) {
  const Rice::Object generator(value);
  const Rice::Module native = Rice::define_module_under(Rice::define_module("Lota"), "Native");
  if (!generator.is_a(native.const_get("RandomGenerator"))) {
    throw std::invalid_argument("expected a Lota::Native::RandomGenerator");
  }
  Rice::detail::WrapperBase *wrapper = Rice::detail::getWrapper(generator.value());
  // Rice's get() takes the type it checks against as non-const, though it
  // only reads it; Ruby hands the object's own type out as const.
  // NOLINTNEXTLINE(cppcoreguidelines-pro-type-const-cast,misc-include-cleaner)
  auto *type = const_cast<rb_data_type_t *>(RTYPEDDATA_TYPE(generator.value()));
  return static_cast<RandomGenerator *>(wrapper->get(type));
}

int held_reference_count() { return held() ? held()->getReferenceCount() : 0; }

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
#ifdef POSIX_SPAWN_CLOEXEC_DEFAULT
  // The child inherits only the three descriptors the actions above set,
  // not a pipe another thread is spawning with at the same moment.
  check(posix_spawnattr_setflags(attributes.get(), POSIX_SPAWN_CLOEXEC_DEFAULT),
        "posix_spawnattr_setflags");
#endif
  Words arguments(command);
  Words variables(environment);
  ProcessId pid = 0;
  check(posix_spawnp(&pid, command.front().c_str(), actions.get(), attributes.get(),
                     arguments.get(), variables.get()),
        command.front().c_str());
  return pid;
}

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
  Rice::Module test = Rice::define_module("LotaNativeTest");

  Rice::define_class_under<Counted>(test, "Counted")
      .define_constructor(Rice::Constructor<Counted>())
      .define_method("reference_count", &Counted::getReferenceCount)
      .define_singleton_function("constructions", [] { return constructions().load(); })
      .define_singleton_function("destructions", [] { return destructions().load(); })
      .define_singleton_function("begin_generation", &begin_generation);

  test.define_module_function(
          "hold", [](Counted *counted) { held().set(counted); }, Rice::Arg("counted"))
      .define_module_function(
          "hold_random_generator",
          [](VALUE generator) { held().set(foreign_random_generator(generator)); },
          // Rice passes the Ruby object itself (docs/bindings/methods.md).
          Rice::Arg("generator").setValue())
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
      .define_module_function("spawn", &spawn, Rice::Arg("command"), Rice::Arg("output"),
                              Rice::Arg("environment"));
}
