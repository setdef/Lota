// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// liblota_metal_watch: the parity harness's Metal watch (native_test/
// CMakeLists.txt). The harness loads it into both engines' processes on
// macOS, the reference love's and Lota's, with DYLD_INSERT_LIBRARIES, beside
// liblota_loopback, and it changes nothing they draw: it only reports, on
// standard error, each Metal command buffer that ended other than
// completed, with its status and error, and at exit how many command
// buffers there were and how many failed.
//
// LÖVE presents a frame it takes a screenshot of by copying the drawable
// into a buffer, committing the command buffer, waiting for it, and reading
// the buffer back, and never reads how the command buffer ended
// (vendor/love/src/modules/graphics/metal/Graphics.mm:1683-1745). A command
// buffer the GPU did not run leaves that buffer as it was made, all zeros,
// which LÖVE hands back as an opaque black frame. This tells such a frame
// from one the GPU drew.
//
// LÖVE gets its device from MTLCreateSystemDefaultDevice, or from
// MTLCopyAllDevices when it prefers a low-power GPU (Graphics.mm:293-309).
// This library interposes both (dyld's __interpose section), and on each
// device they return, the first time it sees one of its class, makes a
// command queue and a command buffer it never commits, to learn the class
// of the command buffers the device makes, which Metal's driver defines
// and names privately. On that class it wraps commit, which adds a
// completed handler that reports the buffer if it failed, and
// waitUntilCompleted, which reports the buffer it waited for if, when the
// wait ends, it has not completed or has an error.

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <objc/runtime.h>

#include <atomic>
#include <cstdlib>
#include <mutex>
#include <string>
#include <string_view>

#include <unistd.h>

// The methods wrapped, under the names this library gives each class's own
// implementation, so that a wrapper calls it with a message, not a cast.
@interface NSObject (LotaMetalWatch)
- (void)lotaMetalWatchCommit;
- (void)lotaMetalWatchWaitUntilCompleted;
@end

namespace {

// What starts every line this library prints, which the harness matches
// to keep the lines apart from the engine's (test/parity/parity_helper.rb,
// Parity::DIAGNOSTIC).
constexpr std::string_view prefix = "lota-metal-watch: ";

// The most bytes one write puts in the pipe. A write to a pipe of no more
// than PIPE_BUF bytes, 512 on macOS, is never interleaved with another
// process's or thread's, so each line of a report is written whole.
constexpr std::size_t line_bytes = 500;

struct Counts {
  std::atomic<long> committed{0};
  std::atomic<long> completed{0};
  std::atomic<long> failed{0};
  std::atomic<long> waited{0};
  std::atomic<long> waited_failed{0};
};

Counts &counts() {
  static Counts counted;
  return counted;
}

// Writes +text+ to standard error as lines of at most line_bytes, each with
// the prefix and a newline, and with any newline of its own made a space,
// as an NSError's description has.
void print(std::string text) {
  for (char &character : text) {
    if (character == '\n') {
      character = ' ';
    }
  }
  const std::size_t room = line_bytes - prefix.size() - 1;
  for (std::size_t start = 0; start == 0 || start < text.size(); start += room) {
    std::string line(prefix);
    line.append(text, start, room);
    line.push_back('\n');
    static_cast<void>(write(STDERR_FILENO, line.data(), line.size()));
  }
}

// The name of a command buffer's status (MTLCommandBuffer.h).
std::string_view status_name(MTLCommandBufferStatus status) {
  switch (status) {
  case MTLCommandBufferStatusNotEnqueued:
    return "not enqueued";
  case MTLCommandBufferStatusEnqueued:
    return "enqueued";
  case MTLCommandBufferStatusCommitted:
    return "committed";
  case MTLCommandBufferStatusScheduled:
    return "scheduled";
  case MTLCommandBufferStatusCompleted:
    return "completed";
  case MTLCommandBufferStatusError:
    return "error";
  }
  return "unknown";
}

// Counts a command buffer that ended with +status+ and +error+, which
// commit's completed handler saw when +waited+ is false and the end of a
// wait for it when true, and reports it unless it completed without an
// error.
void check(bool waited, MTLCommandBufferStatus status, NSError *error) {
  const bool completed = status == MTLCommandBufferStatusCompleted && error == nil;
  if (waited) {
    ++counts().waited;
    if (!completed) {
      ++counts().waited_failed;
    }
  } else {
    ++(completed ? counts().completed : counts().failed);
  }
  if (completed) {
    return;
  }
  @autoreleasepool {
    std::string report(waited ? "a command buffer waited on" : "a committed command buffer");
    report.append(" ended with status ")
        .append(std::to_string(static_cast<long>(status)))
        .append(" (")
        .append(status_name(status))
        .append("), error: ");
    const char *const description = error == nil ? "none" : [[error description] UTF8String];
    report.append(description == nullptr ? "(no description)" : description);
    print(report);
  }
}

// The one line printed at exit.
void summarize() {
  print(std::to_string(counts().committed.load()) + " command buffers committed, " +
        std::to_string(counts().completed.load()) + " completed, " +
        std::to_string(counts().failed.load()) + " failed; " +
        std::to_string(counts().waited.load()) + " waited on, " +
        std::to_string(counts().waited_failed.load()) + " of them not completed");
}

// Wraps the method +selector+ of +type+ with +wrapper+, keeping the
// implementation +type+ had, its own or inherited, under +original+.
void wrap(Class type, SEL selector, SEL original, id wrapper) {
  objc_method *const method = class_getInstanceMethod(type, selector);
  if (method == nullptr) {
    return;
  }
  const char *const types = method_getTypeEncoding(method);
  class_addMethod(type, original, method_getImplementation(method), types);
  const IMP replacement = imp_implementationWithBlock(wrapper);
  if (!class_addMethod(type, selector, replacement, types)) {
    method_setImplementation(method, replacement);
  }
}

// Wraps commit and waitUntilCompleted on +type+, a class of command
// buffer, unless it, or a class it inherits from, already is.
void watch_buffers(Class type) {
  if (class_getInstanceMethod(type, @selector(lotaMetalWatchCommit)) != nullptr) {
    return;
  }
  wrap(type, @selector(commit), @selector(lotaMetalWatchCommit), ^(id<MTLCommandBuffer> buffer) {
    ++counts().committed;
    [buffer addCompletedHandler:^(id<MTLCommandBuffer> done) {
      check(false, [done status], [done error]);
    }];
    [static_cast<NSObject *>(buffer) lotaMetalWatchCommit];
  });
  wrap(type, @selector(waitUntilCompleted), @selector(lotaMetalWatchWaitUntilCompleted),
       ^(id<MTLCommandBuffer> buffer) {
         [static_cast<NSObject *>(buffer) lotaMetalWatchWaitUntilCompleted];
         check(true, [buffer status], [buffer error]);
       });
}

// Watches the command buffers +device+ makes, the first time a device of
// its class is seen; returns +device+.
id<MTLDevice> watch(id<MTLDevice> device) {
  if (device == nil) {
    return device;
  }
  static std::mutex lock;
  static NSMutableSet *const seen = [[NSMutableSet alloc] init];
  const std::scoped_lock held(lock);
  Class const type = [static_cast<NSObject *>(device) class];
  if ([seen containsObject:type]) {
    return device;
  }
  [seen addObject:type];
  @autoreleasepool {
    id<MTLCommandQueue> const queue = [device newCommandQueue];
    id<MTLCommandBuffer> const probe = [queue commandBuffer];
    if (probe != nil) {
      watch_buffers([static_cast<NSObject *>(probe) class]);
    }
    [queue release];
  }
  return device;
}

// MTLCreateSystemDefaultDevice, interposed. dyld interposes calls from every
// image but this one, so this library reaches Metal's own by name.
id<MTLDevice> default_device() noexcept { return watch(MTLCreateSystemDefaultDevice()); }

// MTLCopyAllDevices, interposed.
NSArray<id<MTLDevice>> *all_devices() noexcept {
  NSArray<id<MTLDevice>> *const devices = MTLCopyAllDevices();
  for (id<MTLDevice> device in devices) {
    watch(device);
  }
  return devices;
}

// One of dyld's interpose tuples (mach-o/dyld-interposing.h): where calls
// to the second function go instead.
template <typename Function> struct Interpose {
  Function *replacement;
  Function *replacee;
};

[[gnu::used,
  gnu::section("__DATA,__interpose")]] const Interpose<decltype(MTLCreateSystemDefaultDevice)>
    interpose_default{
        .replacement = &default_device,
        .replacee = &MTLCreateSystemDefaultDevice,
};
[[gnu::used,
  gnu::section("__DATA,__interpose")]] const Interpose<decltype(MTLCopyAllDevices)> interpose_all{
    .replacement = &all_devices,
    .replacee = &MTLCopyAllDevices,
};

// Prints the counts when the process exits, as the engine returns from
// main or Ruby exits.
[[gnu::constructor]] void install() { std::atexit(&summarize); }

} // namespace

// Counts and reports a command buffer that ended with the status +status+
// and, unless +code+ is 0, an error of Metal's domain with that code, as
// commit's completed handler does when +waited+ is 0 and the end of a wait
// when it is not. The tests call it through LotaNativeTest, since no
// program can make Metal fail a command buffer on purpose.
extern "C" __attribute__((visibility("default"))) void
lota_metal_watch_check(int waited, MTLCommandBufferStatus status, long code) {
  @autoreleasepool {
    NSError *const error =
        code == 0
            ? nil
            : [NSError
                  errorWithDomain:MTLCommandBufferErrorDomain
                             code:code
                         userInfo:@{NSLocalizedDescriptionKey : @"a failure the test reported"}];
    check(waited != 0, status, error);
  }
}
