// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/signal.hpp"

#include "native/binding.hpp"
#include "native/ruby.hpp"

#include <ruby/thread.h>

#include <cstdint>
#include <mutex>
#include <optional>

namespace lota::native {

// What a Ruby thread waits for in Signal::wait.
struct Signal::Waiting {
  Signal *signal = nullptr;
  std::uint64_t seen = 0;
  std::optional<Clock::time_point> deadline;
  bool interrupted = false;
};

void *Signal::wait_without_gvl(void *data) {
  auto *waiting = static_cast<Waiting *>(data);
  Signal &signal = *waiting->signal;
  std::unique_lock lock(signal.mutex_);
  const auto changed = [waiting, &signal] {
    return signal.changes_ != waiting->seen || waiting->interrupted;
  };
  if (waiting->deadline.has_value()) {
    signal.condition_.wait_until(lock, *waiting->deadline, changed);
  } else {
    signal.condition_.wait(lock, changed);
  }
  return nullptr;
}

// Ruby's unblocking function: another thread calls it to interrupt this
// one's wait, for Thread#raise, Thread#kill, or the Ractor's end.
void Signal::interrupt(void *data) {
  auto *waiting = static_cast<Waiting *>(data);
  Signal &signal = *waiting->signal;
  {
    const std::scoped_lock lock(signal.mutex_);
    waiting->interrupted = true;
  }
  signal.condition_.notify_all();
}

void Signal::wait(std::uint64_t seen, std::optional<Clock::time_point> deadline) {
  Waiting waiting{.signal = this, .seen = seen, .deadline = deadline, .interrupted = false};
  // The 2 form leaves the interrupts to rb_thread_check_ints, which Rice's
  // protect turns into a C++ exception rather than a longjmp through
  // these frames.
  rb_thread_call_without_gvl2(&wait_without_gvl, &waiting, &interrupt, &waiting);
  ruby::check_interrupts();
}

} // namespace lota::native
