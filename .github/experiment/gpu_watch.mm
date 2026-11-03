// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// Throwaway diagnostic for the spike/macos-frames CI experiment. Never on
// trunk. Loaded into the reference love and into Lota with
// DYLD_INSERT_LIBRARIES (Parity.loopback). It changes nothing the engines
// draw, and writes only to gpu_watch.log beside itself (no variable names
// it, since the reference cache's key hashes every file a variable
// names; and the harness
// compares the engines' output exactly, so nothing goes to stderr). Every
// line starts with [gpu_watch]. It records:
// * every nextDrawable that returns nil or takes longer than 0.25 s;
// * every command buffer that completes with a status other than
//   completed, with its error;
// * the drawable texture's framebufferOnly and usage, once per process,
//   since LÖVE blits from it for a screenshot;
// * for each screenshot: it fills the buffer LÖVE's present creates (the
//   first shared buffer of the drawable's width * height * 4 bytes after
//   each nextDrawable) with 0xA5, and after waitUntilCompleted returns
//   scans it before LÖVE reads it: uniform 165 means the blit never
//   reached the buffer, uniform black that the blit copied only the clear;
// * a summary at exit.
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <objc/runtime.h>
#include <atomic>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <fcntl.h>
#include <mutex>
#include <unistd.h>
#include <dlfcn.h>
#include <libgen.h>

static IMP original_next, original_commit, original_new_buffer, original_wait;
static std::atomic<long> drawables{0}, commits{0}, failures{0}, slow{0}, nils{0}, scans{0}, grey{0}, black{0}, partial{0};
static std::atomic<double> longest{0};
static std::atomic<size_t> screenshot_bytes{0};
static std::mutex pending_lock;
static id<MTLBuffer> pending = nil;
static long pending_drawable = 0;
static std::atomic<int> framebuffer_only{-1};
static char tag[512] = "";

static double now() {
  timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return t.tv_sec + t.tv_nsec / 1e9;
}

static char path[1024] = "";

static void say(const char *format, ...) {
  if (path[0] == '\0') return;
  char line[2048];
  timespec wall;
  clock_gettime(CLOCK_REALTIME, &wall);
  struct tm parts;
  gmtime_r(&wall.tv_sec, &parts);
  int used = snprintf(line, sizeof line, "[gpu_watch] %02d:%02d:%02d.%03ld %s ", parts.tm_hour, parts.tm_min, parts.tm_sec,
    wall.tv_nsec / 1000000, tag);
  va_list arguments;
  va_start(arguments, format);
  used += vsnprintf(line + used, sizeof line - used - 1, format, arguments);
  va_end(arguments);
  if (used > (int)sizeof line - 2) used = sizeof line - 2;
  line[used++] = '\n';
  int file = open(path, O_WRONLY | O_APPEND | O_CREAT, 0644);
  if (file < 0) return;
  write(file, line, used);
  close(file);
}

static void commit(id self, SEL selector) {
  long number = ++commits;
  long drawable = drawables.load();
  double committed = now();
  [(id<MTLCommandBuffer>)self addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
    if (buffer.status != MTLCommandBufferStatusCompleted) {
      ++failures;
      say("command buffer %ld (after drawable %ld, %ld screenshots scanned) ended with status %ld after %.3f s, GPU %.3f ms: %s",
        number, drawable, scans.load(), (long)buffer.status, now() - committed, (buffer.GPUEndTime - buffer.GPUStartTime) * 1000,
        buffer.error ? buffer.error.description.UTF8String : "no error");
    }
  }];
  ((void (*)(id, SEL))original_commit)(self, selector);
}

static void scan(id<MTLCommandBuffer> command) {
  id<MTLBuffer> buffer;
  long drawable;
  {
    std::lock_guard<std::mutex> hold(pending_lock);
    buffer = pending;
    drawable = pending_drawable;
    pending = nil;
  }
  if (buffer == nil) return;
  ++scans;
  const uint8_t *bytes = (const uint8_t *)buffer.contents;
  size_t length = buffer.length, pixels = length / 4, filled = 0, dark = 0;
  for (size_t i = 0; i < length; i += 4) {
    if (bytes[i] == 0xA5 && bytes[i + 1] == 0xA5 && bytes[i + 2] == 0xA5 && bytes[i + 3] == 0xA5) ++filled;
    if (bytes[i] == 0 && bytes[i + 1] == 0 && bytes[i + 2] == 0) ++dark;
  }
  const char *verdict = nullptr;
  if (filled == pixels) {
    verdict = "UNIFORM 165 (blit never landed)";
    ++grey;
  } else if (dark == pixels) {
    verdict = "UNIFORM BLACK (blit copied only black)";
    ++black;
  } else if (filled > 0) {
    verdict = "PARTLY 165 (blit landed in part)";
    ++partial;
  }
  if (verdict != nullptr || command.status != MTLCommandBufferStatusCompleted || command.error != nil || getenv("GPU_WATCH_VERBOSE"))
    say("screenshot %ld of drawable %ld: %s; %zu of %zu pixels 165, %zu black; command buffer status %ld, error %s, GPU %.3f ms, "
        "drawable framebufferOnly %d",
      scans.load(), drawable, verdict ? verdict : "content", filled, pixels, dark, (long)command.status,
      command.error ? command.error.description.UTF8String : "none", (command.GPUEndTime - command.GPUStartTime) * 1000,
      framebuffer_only.load());
}

static void wait_until_completed(id self, SEL selector) {
  ((void (*)(id, SEL))original_wait)(self, selector);
  scan((id<MTLCommandBuffer>)self);
}

static id new_buffer(id self, SEL selector, NSUInteger length, MTLResourceOptions options) {
  id<MTLBuffer> buffer = ((id (*)(id, SEL, NSUInteger, MTLResourceOptions))original_new_buffer)(self, selector, length, options);
  size_t expected = screenshot_bytes.load();
  if (buffer != nil && expected != 0 && length == expected && (options & MTLResourceStorageModeMask) == MTLResourceStorageModeShared
      && screenshot_bytes.compare_exchange_strong(expected, 0)) {
    memset(buffer.contents, 0xA5, length);
    std::lock_guard<std::mutex> hold(pending_lock);
    pending = buffer;
    pending_drawable = drawables.load();
  }
  return buffer;
}

static id next_drawable(id self, SEL selector) {
  static bool installed = false;
  CAMetalLayer *layer = (CAMetalLayer *)self;
  if (!installed && layer.device != nil) {
    installed = true;
    id<MTLCommandBuffer> probe = [[layer.device newCommandQueue] commandBuffer];
    Class buffers = object_getClass(probe);
    original_commit = method_setImplementation(class_getInstanceMethod(buffers, @selector(commit)), (IMP)commit);
    original_wait = method_setImplementation(class_getInstanceMethod(buffers, @selector(waitUntilCompleted)), (IMP)wait_until_completed);
    original_new_buffer = method_setImplementation(class_getInstanceMethod(object_getClass(layer.device),
      @selector(newBufferWithLength:options:)), (IMP)new_buffer);
    say("installed on %s (%s), command buffer class %s, layer framebufferOnly %d", layer.device.name.UTF8String,
      object_getClassName(layer.device), class_getName(buffers), (int)layer.framebufferOnly);
  }
  long number = ++drawables;
  double start = now();
  id<CAMetalDrawable> drawable = ((id (*)(id, SEL))original_next)(self, selector);
  double waited = now() - start;
  double seen = longest.load();
  while (waited > seen && !longest.compare_exchange_weak(seen, waited)) {}
  if (drawable == nil) ++nils;
  if (drawable == nil || waited > 0.25) {
    ++slow;
    say("nextDrawable %ld returned %s after %.3f s", number, drawable ? "a drawable" : "nil", waited);
  }
  if (drawable != nil) {
    static bool described = false;
    if (!described) {
      described = true;
      say("drawable texture %lux%lu framebufferOnly %d usage %lu storage %lu pixel format %lu", drawable.texture.width,
        drawable.texture.height, (int)drawable.texture.framebufferOnly, (unsigned long)drawable.texture.usage,
        (unsigned long)drawable.texture.storageMode, (unsigned long)drawable.texture.pixelFormat);
    }
    framebuffer_only = (int)drawable.texture.framebufferOnly;
    screenshot_bytes = drawable.texture.width * drawable.texture.height * 4;
  }
  return drawable;
}

static void summary() {
  say("exit: drawables %ld, longest nextDrawable %.3f s, slow or nil %ld (nil %ld), commits %ld, failed command buffers %ld, "
      "screenshots %ld, uniform 165 %ld, uniform black %ld, partly 165 %ld",
    drawables.load(), longest.load(), slow.load(), nils.load(), commits.load(), failures.load(), scans.load(), grey.load(),
    black.load(), partial.load());
}

__attribute__((constructor)) static void install() {
  Dl_info self;
  if (dladdr((const void *)&install, &self) && self.dli_fname) {
    char copy[1024];
    snprintf(copy, sizeof copy, "%s", self.dli_fname);
    snprintf(path, sizeof path, "%s/gpu_watch.log", dirname(copy));
  }
  const char *run = getenv("LOTA_LOOPBACK_FILE");
  const char *slash = run ? strrchr(run, '/') : nullptr;
  char directory[256] = "";
  if (run && slash) {
    const char *start = run;
    for (const char *p = run; p < slash; ++p)
      if (*p == '/') start = p + 1;
    snprintf(directory, sizeof directory, "%s", start);
  }
  snprintf(tag, sizeof tag, "pid=%d %s run=%s", getpid(), getprogname(), directory);
  original_next = method_setImplementation(class_getInstanceMethod([CAMetalLayer class], @selector(nextDrawable)), (IMP)next_drawable);
  atexit(summary);
  say("loaded");
}
