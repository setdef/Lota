// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/thread.hpp"

#include "native/binding.hpp"
#include "native/ruby.hpp"
#include "native/signal.hpp"

#include "common/Exception.h"
#include "common/Module.h"
#include "common/Object.h"
#include "common/Variant.h"
#include "common/int.h"
#include "common/types.h"
#include "event/Event.h"
#include "thread/threads.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace lota::native {

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

namespace {

love::Type &channel_type() noexcept {
  static love::Type type("Channel", &love::Object::type);
  return type;
}

love::Type &thread_type() noexcept {
  static love::Type type("Thread", &love::thread::Threadable::type);
  return type;
}

} // namespace

love::Type &Channel::type = channel_type();

Channel::Channel() { ruby::Marks::instance().add(this); }

Channel::~Channel() { ruby::Marks::instance().remove(this); }

template <typename Step>
bool Channel::when_free(Step step, std::optional<Clock::time_point> deadline) {
  const ruby::ThreadId me = ruby::current_thread();
  while (true) {
    std::uint64_t seen = 0;
    bool held_elsewhere = false;
    {
      const auto lock = signal_.lock();
      held_elsewhere = owner_ != ruby::no_thread() && owner_ != me;
      if (!held_elsewhere && step()) {
        return true;
      }
      if (!held_elsewhere && deadline.has_value() && Clock::now() >= *deadline) {
        return false;
      }
      seen = signal_.count();
    }
    signal_.wait(seen, held_elsewhere ? std::nullopt : deadline);
  }
}

love::uint64 Channel::push_locked(ruby::Value value) {
  queue_.push_back(value);
  signal_.changed();
  return ++sent_;
}

bool Channel::pop_locked(ruby::Value &value) {
  if (queue_.empty()) {
    return false;
  }
  value = queue_.front();
  queue_.pop_front();
  received_++;
  signal_.changed();
  return true;
}

love::uint64 Channel::push(ruby::Value value) {
  love::uint64 id = 0;
  when_free(
      [&] {
        id = push_locked(value);
        return true;
      },
      std::nullopt);
  return id;
}

bool Channel::supply(ruby::Value value, std::optional<double> timeout) {
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

ruby::Value Channel::pop() {
  ruby::Value value = ruby::nil().value();
  when_free(
      [&] {
        pop_locked(value);
        return true;
      },
      std::nullopt);
  return value;
}

ruby::Value Channel::demand(std::optional<double> timeout) {
  if (expired(timeout)) {
    return ruby::nil().value();
  }
  ruby::Value value = ruby::nil().value();
  when_free([&] { return pop_locked(value); }, deadline_after(timeout));
  return value;
}

ruby::Value Channel::peek() {
  ruby::Value value = ruby::nil().value();
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
  const ruby::ThreadId me = ruby::current_thread();
  when_free(
      [&] {
        owner_ = me;
        depth_++;
        return true;
      },
      std::nullopt);
}

void Channel::unlock() {
  const auto lock = signal_.lock();
  if (owner_ != ruby::current_thread() || depth_ == 0) {
    return;
  }
  if (--depth_ == 0) {
    owner_ = ruby::no_thread();
    signal_.changed();
  }
}

// SPDX-SnippetEnd

void Channel::mark() const {
  const auto lock = signal_.lock();
  for (const ruby::Value value : queue_) {
    ruby::mark(value);
  }
}

// SPDX-SnippetBegin
// SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
// SPDX-License-Identifier: Zlib
//
// Ported from love::thread::LuaThread (vendor/love/src/modules/thread/
// LuaThread.cpp:36-148) and love::thread::sdl::Thread (sdl/Thread.cpp:
// 50-105).

love::Type &Thread::type = thread_type();

namespace {

// How many threads run now, which hold the thread module open as each
// LuaThread's Lua state holds love.thread (LuaThread.cpp:75 and
// wrap_ThreadModule.cpp:115-128).
std::atomic<int> &running_threads() {
  static std::atomic<int> count{0};
  return count;
}

} // namespace

Thread::Thread(std::string name, std::string code)
    : name_(std::move(name)), code_(std::move(code)) {}

bool Thread::begin() {
  const auto lock = signal_.lock();
  if (running_) {
    return false;
  }
  error_.clear();
  has_error_ = false;
  running_ = true;
  running_threads()++;
  return true;
}

void Thread::finish(const std::optional<std::string> &error) {
  {
    const auto lock = signal_.lock();
    error_ = error.value_or("");
    has_error_ = error.has_value();
  }
  if (error.has_value()) {
    on_error(*error);
  }
  const auto lock = signal_.lock();
  if (running_) {
    running_threads()--;
  }
  running_ = false;
  signal_.changed();
}

void Thread::wait() {
  while (true) {
    std::uint64_t seen = 0;
    {
      const auto lock = signal_.lock();
      if (!running_) {
        return;
      }
      seen = signal_.count();
    }
    signal_.wait(seen, std::nullopt);
  }
}

bool Thread::running() {
  const auto lock = signal_.lock();
  return running_;
}

std::optional<std::string> Thread::error() {
  const auto lock = signal_.lock();
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

  const std::vector<love::Variant> vargs = {
      love::Variant(&Thread::type, this),
      love::Variant(error.c_str(), error.length()),
  };

  const love::StrongRef<love::event::Message> msg(new love::event::Message("threaderror", vargs),
                                                  love::Acquire::NORETAIN);
  eventmodule->push(msg);
}

// SPDX-SnippetEnd

namespace {

// Whether love.thread is open, as LÖVE's ThreadModule exists once
// luaopen_love_thread made it (wrap_ThreadModule.cpp:107-128).
std::atomic<bool> &opened() {
  static std::atomic<bool> flag{false};
  return flag;
}

void open() { opened() = true; }

bool is_open() { return opened(); }

void forget_named_channels();

// Lets go of the thread module, as lua_close lets go of the main Lua
// state's reference to love.thread (src/love.cpp:291). LÖVE's module, and
// the named channels it holds (ThreadModule.h), go once no Lua state holds
// it, and every running thread's state does, so while a thread runs they
// stay for the next run of the game, which takes the same module again
// (wrap_ThreadModule.cpp:117-123). Lota's threads are Ractors, which
// cannot hold a C++ module, so the module and its channels stay while any
// Lota thread runs, and otherwise go. Returns whether the module closed.
bool close() {
  if (!opened() || running_threads() > 0) {
    return !opened();
  }
  opened() = false;
  forget_named_channels();
  return true;
}

void require_open() {
  if (!opened()) {
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

// The named channels, which live until the module closes, as
// ThreadModule's live as long as the module.
struct NamedChannels {
  std::mutex mutex;
  std::map<std::string, love::StrongRef<Channel>> channels;
};

NamedChannels &named_channels() {
  static NamedChannels named;
  return named;
}

void forget_named_channels() {
  NamedChannels &named = named_channels();
  std::map<std::string, love::StrongRef<Channel>> channels;
  {
    const std::scoped_lock lock(named.mutex);
    channels.swap(named.channels);
  }
}

Channel *get_channel(const std::string &name) {
  require_open();
  NamedChannels &named = named_channels();
  const std::scoped_lock lock(named.mutex);

  const auto it = named.channels.find(name);
  if (it != named.channels.end()) {
    return it->second.get();
  }

  auto created = std::make_unique<Channel>();
  Channel *c = created.get();
  named.channels[name].set(created.release(), love::Acquire::NORETAIN);
  return c;
}

Channel *new_channel() {
  require_open();
  return std::make_unique<Channel>().release();
}

Thread *new_thread(const std::string &name, const std::string &code) {
  require_open();
  return std::make_unique<Thread>(name, code).release();
}

// SPDX-SnippetEnd

// The Carried of the engine object +wrapper+ wraps, which a Ractor other
// than the one that made +wrapper+ may hold. A released object raises
// LÖVE's error, as luax_checktype raises for it.
Carried *carry(ruby::Value wrapper) {
  const EngineWrapper *engine = EngineWrapper::of(wrapper);
  if (engine == nullptr) {
    ruby::raise_type_error("wrong argument type " + ruby::class_name(Rice::Object(wrapper)) +
                           " (expected Lota::Native object)");
  }
  love::Object *object = engine->object();
  if (object == nullptr) {
    throw love::Exception("Cannot use object after it has been released.");
  }
  return std::make_unique<Carried>(object, ruby::data_type(wrapper)).release();
}

// A message's value, which must be one Ractors share: Lota::Thread::Channel
// makes it one before it gets here.
ruby::Value shareable(const Rice::Object &value) {
  if (!ruby::shareable(value)) {
    ruby::raise_argument_error("a Channel carries only values Ractors share");
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

} // namespace

Carried::Carried(love::Object *object, const ruby::DataType *type)
    : reference_(object, love::Acquire::RETAIN), type_(type) {}

// An object of a main-thread module joins the release queue off the main
// thread, as its wrapper's reference does (ObjectWrapper::drop).
Carried::~Carried() {
  const auto found = rewraps().find(type_);
  if (found != rewraps().end() && found->second.released_on_main_thread && !on_main_thread()) {
    ReleaseQueue::instance().push(reference_.get());
  }
  reference_.set(nullptr);
}

ruby::Value Carried::object() const {
  const auto found = rewraps().find(type_);
  if (found == rewraps().end()) {
    ruby::raise_type_error("Lota cannot pass this object to another thread");
  }
  return found->second.wrap(reference_.get());
}

namespace {

void thread_finish(Thread &thread, std::optional<std::string> given) {
  const std::optional<std::string> error = std::move(given);
  thread.finish(error);
}

} // namespace

bool close_thread_module() { return close(); }

void define_thread(const Rice::Module &native) {
  const Rice::Module thread_module =
      Rice::define_module_under(native, "Thread")
          .define_singleton_function("open", &open)
          .define_singleton_function("open?", &is_open)
          .define_singleton_function("close", &close)
          .define_singleton_function("channel", &get_channel, Rice::Arg("name"))
          .define_singleton_function("new_channel", &new_channel, Rice::Return().takeOwnership())
          .define_singleton_function("new_thread", &new_thread, Rice::Return().takeOwnership(),
                                     Rice::Arg("name"), Rice::Arg("code"))
          .define_singleton_function("carry", &carry, Rice::Return().takeOwnership(),
                                     Rice::Arg("object").setValue());

  Rice::define_class_under<Carried>(thread_module, "Carried")
      .define_method("object", [](const Carried &self) { return Rice::Object(self.object()); });
  Rice::Data_Type<Carried>::ruby_data_type()->flags |= RUBY_TYPED_FROZEN_SHAREABLE;

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
      .define_method("unlock", &Channel::unlock);

  define_engine_class<Thread>(thread_module, "Thread")
      .define_method("name", &Thread::name)
      .define_method("code", &Thread::code)
      .define_method("begin", &Thread::begin)
      .define_method("finish", &thread_finish, Rice::Arg("error") = std::optional<std::string>())
      .define_method("wait", &Thread::wait)
      .define_method("running?", &Thread::running)
      .define_method("error", &Thread::error);
}

} // namespace lota::native
