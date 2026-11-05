// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/thread.hpp"

#include "native/binding.hpp"
#include "native/ruby.hpp"

#include "common/Exception.h"
#include "common/Module.h"
#include "common/Object.h"
#include "common/Variant.h"
#include "common/int.h"
#include "common/types.h"
#include "event/Event.h"
#include "thread/threads.h"

#include <ruby/thread.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <bit>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <map>
#include <mutex>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace lota::native {

struct Signal::Waiting {
  Signal *signal;
  std::uint64_t seen;
  std::optional<Clock::time_point> deadline;
  bool interrupted;
};

void *Signal::wait_without_gvl(void *data) {
  auto *waiting = static_cast<Waiting *>(data);
  Signal &signal = *waiting->signal;
  std::unique_lock lock(signal.mutex);
  const auto changed = [waiting, &signal] {
    return signal.changes != waiting->seen || waiting->interrupted;
  };
  if (waiting->deadline.has_value()) {
    signal.condition_.wait_until(lock, *waiting->deadline, changed);
  } else {
    signal.condition_.wait(lock, changed);
  }
  return nullptr;
}

// Ruby's unblocking function: another thread calls it to interrupt this
// one's wait, for Thread#raise, Thread#kill, the Ractor's end, or the
// code another Ractor asks this one to run.
void Signal::interrupt(void *data) {
  auto *waiting = static_cast<Waiting *>(data);
  Signal &signal = *waiting->signal;
  {
    const std::scoped_lock lock(signal.mutex);
    waiting->interrupted = true;
  }
  signal.condition_.notify_all();
}

void Signal::wait(std::uint64_t seen, std::optional<Clock::time_point> deadline) {
  Waiting waiting{.signal = this, .seen = seen, .deadline = deadline, .interrupted = false};
  // The 2 form leaves the interrupts to rb_thread_check_ints, which
  // Rice's protect turns into a C++ exception rather than a longjmp
  // through these frames.
  rb_thread_call_without_gvl2(&wait_without_gvl, &waiting, &interrupt, &waiting);
  Rice::detail::protect(rb_thread_check_ints);
}

namespace {

using Clock = Signal::Clock;

// The time +timeout+ seconds from now, for a timeout of zero or more;
// LÖVE's loops wait no longer than that (Channel.cpp:51-66, 95-113). One
// of more than a century waits a century, which no Clock overflows.
std::optional<Clock::time_point> deadline_after(std::optional<double> timeout) {
  if (!timeout.has_value()) {
    return std::nullopt;
  }
  constexpr double CENTURY = 100.0 * 365.25 * 24 * 60 * 60;
  const std::chrono::duration<double> seconds(std::min(*timeout, CENTURY));
  return Clock::now() + std::chrono::duration_cast<Clock::duration>(seconds);
}

// Whether a timeout is given and lets LÖVE's loop run, which
// <tt>while (timeout >= 0)</tt> refuses a negative or NaN one.
bool expired(std::optional<double> timeout) { return timeout.has_value() && !(*timeout >= 0); }

} // namespace

// SPDX-SnippetBegin
// SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
// SPDX-License-Identifier: Zlib
//
// Ported from love::thread::Channel (vendor/love/src/modules/thread/
// Channel.cpp:29-168).

love::Type Channel::type("Channel", &love::Object::type);

Channel::Channel() { ruby::Marks::instance().add(this); }

Channel::~Channel() { ruby::Marks::instance().remove(this); }

template <typename Step>
bool Channel::when_free(Step step, std::optional<Clock::time_point> deadline) {
  const VALUE me = rb_thread_current();
  while (true) {
    std::uint64_t seen = 0;
    bool held_elsewhere = false;
    {
      const std::scoped_lock lock(signal_.mutex);
      held_elsewhere = owner_ != 0 && owner_ != me;
      if (!held_elsewhere && step()) {
        return true;
      }
      if (!held_elsewhere && deadline.has_value() && Clock::now() >= *deadline) {
        return false;
      }
      seen = signal_.changes;
    }
    signal_.wait(seen, held_elsewhere ? std::nullopt : deadline);
  }
}

love::uint64 Channel::push_locked(VALUE value) {
  queue_.push_back(value);
  signal_.changed();
  return ++sent_;
}

bool Channel::pop_locked(VALUE &value) {
  if (queue_.empty()) {
    return false;
  }
  value = queue_.front();
  queue_.pop_front();
  received_++;
  signal_.changed();
  return true;
}

love::uint64 Channel::push(VALUE value) {
  love::uint64 id = 0;
  when_free(
      [&] {
        id = push_locked(value);
        return true;
      },
      std::nullopt);
  return id;
}

bool Channel::supply(VALUE value, std::optional<double> timeout) {
  const std::optional<Clock::time_point> deadline = deadline_after(timeout);
  love::uint64 id = 0;
  bool supplied = false;
  const bool done = when_free(
      [&] {
        if (id == 0) {
          id = push_locked(value);
        }
        if (received_ >= id) {
          supplied = true;
          return true;
        }
        return expired(timeout);
      },
      deadline);
  return done && supplied;
}

VALUE Channel::pop() {
  VALUE value = Qnil;
  when_free(
      [&] {
        pop_locked(value);
        return true;
      },
      std::nullopt);
  return value;
}

VALUE Channel::demand(std::optional<double> timeout) {
  if (expired(timeout)) {
    return Qnil;
  }
  VALUE value = Qnil;
  when_free([&] { return pop_locked(value); }, deadline_after(timeout));
  return value;
}

VALUE Channel::peek() {
  VALUE value = Qnil;
  when_free(
      [&] {
        if (!queue_.empty()) {
          value = queue_.front();
        }
        return true;
      },
      std::nullopt);
  return value;
}

int Channel::count() {
  int size = 0;
  when_free(
      [&] {
        size = static_cast<int>(queue_.size());
        return true;
      },
      std::nullopt);
  return size;
}

bool Channel::has_read(love::uint64 id) {
  bool read = false;
  when_free(
      [&] {
        read = received_ >= id;
        return true;
      },
      std::nullopt);
  return read;
}

void Channel::clear() {
  when_free(
      [&] {
        // We're already empty.
        if (queue_.empty()) {
          return true;
        }
        queue_.clear();
        // Finish all the supply waits.
        received_ = sent_;
        signal_.changed();
        return true;
      },
      std::nullopt);
}

void Channel::lock() {
  const VALUE me = rb_thread_current();
  when_free(
      [&] {
        owner_ = me;
        depth_++;
        return true;
      },
      std::nullopt);
}

void Channel::unlock() {
  const std::scoped_lock lock(signal_.mutex);
  if (owner_ != rb_thread_current() || depth_ == 0) {
    return;
  }
  if (--depth_ == 0) {
    owner_ = 0;
    signal_.changed();
  }
}

// SPDX-SnippetEnd

void Channel::mark() const {
  const std::scoped_lock lock(signal_.mutex);
  for (const VALUE value : queue_) {
    rb_gc_mark(value);
  }
}

// SPDX-SnippetBegin
// SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
// SPDX-License-Identifier: Zlib
//
// Ported from love::thread::LuaThread (vendor/love/src/modules/thread/
// LuaThread.cpp:36-148) and love::thread::sdl::Thread (sdl/Thread.cpp:
// 50-105).

// LuaThread's type, "Thread", is a Threadable (LuaThread.cpp:36).
love::Type Thread::type("Thread", &love::thread::Threadable::type);

Thread::Thread(std::string name, std::string code)
    : name_(std::move(name)), code_(std::move(code)) {}

bool Thread::begin() {
  const std::scoped_lock lock(signal_.mutex);
  if (running_) {
    return false;
  }
  error_.clear();
  has_error_ = false;
  running_ = true;
  return true;
}

void Thread::finish(const std::optional<std::string> &error) {
  {
    const std::scoped_lock lock(signal_.mutex);
    error_ = error.value_or("");
    has_error_ = error.has_value();
  }
  if (error.has_value()) {
    on_error(*error);
  }
  const std::scoped_lock lock(signal_.mutex);
  running_ = false;
  signal_.changed();
}

void Thread::wait() {
  while (true) {
    std::uint64_t seen = 0;
    {
      const std::scoped_lock lock(signal_.mutex);
      if (!running_) {
        return;
      }
      seen = signal_.changes;
    }
    signal_.wait(seen, std::nullopt);
  }
}

bool Thread::running() {
  const std::scoped_lock lock(signal_.mutex);
  return running_;
}

std::optional<std::string> Thread::error() {
  const std::scoped_lock lock(signal_.mutex);
  if (!has_error_) {
    return std::nullopt;
  }
  return error_;
}

void Thread::on_error(const std::string &error) {
  auto *eventmodule = love::Module::getInstance<love::event::Event>(love::Module::M_EVENT);
  if (eventmodule == nullptr) {
    return;
  }

  const std::vector<love::Variant> vargs = {love::Variant(&Thread::type, this),
                                            love::Variant(error.c_str(), error.length())};

  const love::StrongRef<love::event::Message> msg(new love::event::Message("threaderror", vargs),
                                                  love::Acquire::NORETAIN);
  eventmodule->push(msg);
}

// SPDX-SnippetEnd

namespace {

// Whether love.thread is open, as LÖVE's ThreadModule exists once
// luaopen_love_thread made it (wrap_ThreadModule.cpp:107-128).
std::atomic<bool> opened{false};

void open() { opened = true; }

bool is_open() { return opened; }

void require_open() {
  if (!opened) {
    throw love::Exception("Lota::Thread is not open.");
  }
}

// SPDX-SnippetBegin
// SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
// SPDX-License-Identifier: Zlib
//
// Ported from love::thread::ThreadModule (vendor/love/src/modules/thread/
// ThreadModule.cpp:29-58) and w_newThread, w_newChannel, and w_getChannel
// (wrap_ThreadModule.cpp:42-94), which Lota::Thread reads the code of.

// The named channels, which live as long as the process, as ThreadModule's
// live as long as the module.
struct NamedChannels {
  std::mutex mutex;
  std::map<std::string, love::StrongRef<Channel>> channels;
};

NamedChannels &named_channels() {
  static NamedChannels named;
  return named;
}

Channel *get_channel(const std::string &name) {
  require_open();
  NamedChannels &named = named_channels();
  const std::scoped_lock lock(named.mutex);

  auto it = named.channels.find(name);
  if (it != named.channels.end()) {
    return it->second.get();
  }

  auto *c = new Channel();
  named.channels[name].set(c, love::Acquire::NORETAIN);
  return c;
}

Channel *new_channel() {
  require_open();
  return new Channel();
}

Thread *new_thread(const std::string &name, const std::string &code) {
  require_open();
  return new Thread(name, code);
}

// SPDX-SnippetEnd

// A message's value, which must be one Ractors share: Lota::Thread::Channel
// makes it one before it gets here.
VALUE shareable(const Rice::Object &value) {
  if (!rb_ractor_shareable_p(value.value())) {
    throw Rice::Exception(rb_eArgError, "a Channel carries only values Ractors share");
  }
  return value.value();
}

love::uint64 channel_push(Channel &channel, Rice::Object given) {
  const Rice::Object value = std::move(given);
  return channel.push(shareable(value));
}

bool channel_supply(Channel &channel, Rice::Object given, std::optional<double> timeout) {
  const Rice::Object value = std::move(given);
  return channel.supply(shareable(value), timeout);
}

// SPDX-SnippetBegin
// SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
// SPDX-License-Identifier: Zlib
//
// Ported from w__tostring and w__eq (vendor/love/src/common/runtime.cpp:
// 56-88), which every type of LÖVE's has: an object's type and address,
// and whether two wrap the same object.
template <typename T> std::string to_s(T &object) {
  std::array<char, 64> text{};
  std::snprintf(text.data(), text.size(), "%s: %p", T::type.getName(),
                static_cast<void *>(&object));
  return {text.data()};
}

template <typename T> bool same(T &object, Rice::Object given) {
  const Rice::Object other = std::move(given);
  if (!ruby::is_kind_of(other, Rice::Data_Type<T>::klass())) {
    return false;
  }
  return Rice::Data_Object<T>(other).get() == &object;
}

// SPDX-SnippetEnd

// A number for Ruby's Hash, the same for two wrappers of one object.
template <typename T> std::uintptr_t identity(T &object) {
  return std::bit_cast<std::uintptr_t>(&object);
}

} // namespace

void define_thread(const Rice::Module &native) {
  Rice::Module thread_module =
      Rice::define_module_under(native, "Thread")
          .define_singleton_function("open", &open)
          .define_singleton_function("open?", &is_open)
          .define_singleton_function("channel", &get_channel, Rice::Arg("name"))
          .define_singleton_function("new_channel", &new_channel, Rice::Return().takeOwnership())
          .define_singleton_function("new_thread", &new_thread, Rice::Return().takeOwnership(),
                                     Rice::Arg("name"), Rice::Arg("code"));

  define_engine_class<Channel>(thread_module, "Channel")
      .define_method("push", &channel_push, Rice::Arg("value"))
      .define_method("supply", &channel_supply, Rice::Arg("value"),
                     Rice::Arg("timeout") = std::optional<double>())
      .define_method("pop", [](Channel &self) { return Rice::Object(self.pop()); })
      .define_method(
          "demand",
          [](Channel &self, std::optional<double> timeout) {
            return Rice::Object(self.demand(timeout));
          },
          Rice::Arg("timeout") = std::optional<double>())
      .define_method("peek", [](Channel &self) { return Rice::Object(self.peek()); })
      .define_method("count", &Channel::count)
      .define_method(
          "read?",
          [](Channel &self, double id) { return self.has_read(static_cast<love::uint64>(id)); },
          Rice::Arg("id"))
      .define_method("clear", &Channel::clear)
      .define_method("lock", &Channel::lock)
      .define_method("unlock", &Channel::unlock)
      .define_method("to_s", &to_s<Channel>)
      .define_method("==", &same<Channel>, Rice::Arg("other"))
      .define_method("hash", &identity<Channel>);

  define_engine_class<Thread>(thread_module, "Thread")
      .define_method("name", &Thread::name)
      .define_method("code", &Thread::code)
      .define_method("begin", &Thread::begin)
      .define_method(
          "finish", [](Thread &self, std::optional<std::string> error) { self.finish(error); },
          Rice::Arg("error") = std::optional<std::string>())
      .define_method("wait", &Thread::wait)
      .define_method("running?", &Thread::running)
      .define_method("error", &Thread::error)
      .define_method("to_s", &to_s<Thread>)
      .define_method("==", &same<Thread>, Rice::Arg("other"))
      .define_method("hash", &identity<Thread>);
}

} // namespace lota::native
