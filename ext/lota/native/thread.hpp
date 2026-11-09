// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// love.thread's Channel and Thread, for Ruby's Ractors (ADR 007). LÖVE's
// own (src/modules/thread/Channel.cpp and LuaThread.cpp) carry Lua values
// and run Lua states, so Lota leaves them out of the engine
// (doc/contributors/design/engine.md, "The source lists") and ports them
// here: a Channel carries Ruby values that Ractors share, and a Thread
// keeps the state of the Ractor that runs its code, which
// Lota::Thread::Thread starts.

#ifndef LOTA_NATIVE_THREAD_HPP
#define LOTA_NATIVE_THREAD_HPP

#include "native/binding.hpp"
#include "native/ruby.hpp"
#include "native/signal.hpp"

#include "common/int.h"

#include <deque>
#include <optional>
#include <string>

namespace lota::native {

// SPDX-SnippetBegin
// SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
// SPDX-License-Identifier: Zlib
//
// Ported from love::thread::Channel (vendor/love/src/modules/thread/
// Channel.h and Channel.cpp) and changed to hold Ruby values instead of
// love::Variants, and to wait without Ruby's GVL.

// A queue of messages between Ractors, which any of them may push to and
// pop from, and which numbers each message it is given. It holds only
// values Ractors share (Ractor.shareable?), which Lota::Thread::Channel
// makes them, so a message reaches another Ractor as it was pushed. Ruby
// sees them through Marks, so a named channel's messages live on while no
// Ruby object holds the channel.
//
// LÖVE locks one recursive mutex around each method, and performAtomic
// holds it while its function runs. Here a Ruby thread holds the channel
// instead (lock and unlock), and the mutex guards only C++ that calls no
// Ruby: a thread that held a mutex while it ran Ruby would stop another
// that waited for it with its GVL held, and with it the collector, which
// waits for every Ractor that holds its GVL.
class Channel final : public love::Object, public ruby::Marked {
public:
  // LÖVE's type "Channel", an Object (Channel.cpp:29).
  static love::Type &type;
  static constexpr bool shareable = true;

  Channel();
  Channel(const Channel &) = delete;
  Channel(Channel &&) = delete;
  Channel &operator=(const Channel &) = delete;
  Channel &operator=(Channel &&) = delete;
  ~Channel() override;

  love::uint64 push(VALUE value);
  bool supply(VALUE value, std::optional<double> timeout);
  VALUE pop();
  VALUE demand(std::optional<double> timeout);
  VALUE peek();
  int count();
  bool has_read(love::uint64 id);
  void clear();

  // What performAtomic's lockMutex and unlockMutex do, for this Ruby
  // thread: while it holds the channel, every other waits for it.
  void lock();
  void unlock();

  void mark() const override;

private:
  // Runs +step+ under the mutex once no other Ruby thread holds the
  // channel, waiting for one that does as long as it takes, as LÖVE's
  // Lock waits for its mutex. +step+ answers whether it is done; until it
  // is, it runs again after each change, and when +deadline+ passes first,
  // this answers false.
  template <typename Step>
  bool when_free(Step step, std::optional<Signal::Clock::time_point> deadline);

  love::uint64 push_locked(VALUE value);
  bool pop_locked(VALUE &value);

  mutable Signal signal_;
  std::deque<VALUE> queue_;
  love::uint64 sent_ = 0;
  love::uint64 received_ = 0;

  // The Ruby thread that holds the channel, or Qfalse, and how many times.
  VALUE owner_ = Qfalse;
  int depth_ = 0;
};

// SPDX-SnippetEnd

// SPDX-SnippetBegin
// SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
// SPDX-License-Identifier: Zlib
//
// Ported from love::thread::LuaThread (vendor/love/src/modules/thread/
// LuaThread.h and LuaThread.cpp) and the running state of love::thread::
// sdl::Thread (sdl/Thread.cpp), and changed to keep a Ractor's state
// instead of running a Lua state on an SDL thread.

// A thread's code, its name, and the state of the Ractor that runs it:
// whether it runs, and the error it ended with. Lota::Thread::Thread
// starts the Ractor and reports to it as the Ractor begins and ends.
class Thread final : public love::Object {
public:
  // LuaThread's type, "Thread", a Threadable (LuaThread.cpp:36).
  static love::Type &type;
  static constexpr bool shareable = true;

  Thread(std::string name, std::string code);

  [[nodiscard]] const std::string &name() const { return name_; }
  [[nodiscard]] const std::string &code() const { return code_; }

  // Marks it running and forgets the last error, unless it runs, as
  // LuaThread::start and Thread::start do: false when it already runs.
  bool begin();

  // Ends a run, as LuaThread::threadFunction ends and thread_runner
  // after it: keeps +error+, pushes a threaderror message when there is
  // one (LuaThread::onError), and then is no longer running.
  void finish(const std::optional<std::string> &error);

  // Waits, without the GVL, until it no longer runs.
  void wait();

  bool running();

  // The error of its last run, or nothing.
  std::optional<std::string> error();

private:
  void on_error(const std::string &error);

  const std::string name_;
  const std::string code_;
  Signal signal_;
  bool running_ = false;
  bool has_error_ = false;
  std::string error_;
};

// SPDX-SnippetEnd

// Lota::Native::Thread: the module's functions and its two classes.
void define_thread(const Rice::Module &native);

} // namespace lota::native

#endif // LOTA_NATIVE_THREAD_HPP
