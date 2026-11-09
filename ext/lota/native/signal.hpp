// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// What a Ruby thread waits on in Lota's own C++, without its Ractor's GVL,
// so that a thread that waits holds up neither its Ractor's other threads
// nor Ruby's collector, which waits for every Ractor that holds its GVL.

#ifndef LOTA_NATIVE_SIGNAL_HPP
#define LOTA_NATIVE_SIGNAL_HPP

#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <mutex>
#include <optional>

namespace lota::native {

// A mutex, and a count of the changes it guards, which each change a
// waiter may wait for adds to.
class Signal {
public:
  using Clock = std::chrono::steady_clock;

  // Locks what the signal guards: the state of whatever holds it, and its
  // count of changes.
  [[nodiscard]] std::unique_lock<std::mutex> lock() { return std::unique_lock(mutex_); }

  // How many changes there have been. Read it under lock.
  [[nodiscard]] std::uint64_t count() const { return changes_; }

  // Counts a change and wakes every waiter. Call it under lock.
  void changed() {
    ++changes_;
    condition_.notify_all();
  }

  // Waits, without Ruby's GVL and not under lock, until a change after
  // +seen+, until +deadline+ passes, or until Ruby interrupts this thread;
  // then runs Ruby's pending interrupts, which may raise, as an exception
  // of Rice's. Ruby's collector does not wait for a thread that waits here
  // (Ruby 4.0.7, thread.c, blocking_region_begin), so a Ractor that waits
  // stops no other.
  void wait(std::uint64_t seen, std::optional<Clock::time_point> deadline);

private:
  struct Waiting;
  static void *wait_without_gvl(void *data);
  static void interrupt(void *data);

  std::mutex mutex_;
  std::uint64_t changes_ = 0;
  std::condition_variable condition_;
};

} // namespace lota::native

#endif // LOTA_NATIVE_SIGNAL_HPP
