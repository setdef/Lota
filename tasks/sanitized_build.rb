# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "open3"
require "rbconfig"

# The build tree rake test:native compiles with AddressSanitizer and
# UndefinedBehaviorSanitizer, and how to run Ruby against it.
#
# ASan's runtime is a dynamic library that must be in the process before
# anything it instruments, or it aborts ("Interceptors are not working" on
# macOS, "ASan runtime does not come first in initial library list" on
# Linux). Ruby is not instrumented and loads the extensions with dlopen,
# so the runtime goes in first: with DYLD_INSERT_LIBRARIES on macOS
# (Clang's AddressSanitizer documentation, "Usage" on Darwin), and with
# LD_PRELOAD on Linux, where the runtime is GCC's, which compiles LÖVE's
# Linux build (ext/lota/CMakeLists.txt). dyld drops DYLD_ variables when it
# starts a protected binary such as /bin/sh or /usr/bin/env, so the tests
# must start Ruby directly, never through a shell or a binstub.
class SanitizedBuild
  # Raised when the tree cannot say which runtime its compiler links.
  class Failure < StandardError; end

  # ASan's runtime on each platform: Clang's on macOS, which also carries
  # UBSan's, and GCC's on Linux, where UBSan's is a library of its own that
  # the extensions link.
  RUNTIMES = { "macos" => "libclang_rt.asan_osx_dynamic.dylib", "linux" => "libasan.so" }.freeze

  # What else goes in with the runtime. On Linux, ASan's interceptor of
  # C++'s __cxa_throw finds the real one as the runtime starts, before
  # Ruby, which is C, has loaded the C++ runtime for an extension, and
  # fails its check on the first exception the extension throws ("CHECK
  # failed: ... real___cxa_throw"), so the C++ runtime goes in with it.
  COMPANIONS = { "macos" => [], "linux" => %w[libstdc++.so.6] }.freeze

  # The variable that loads a library into a program first.
  PRELOADS = { "macos" => "DYLD_INSERT_LIBRARIES", "linux" => "LD_PRELOAD" }.freeze

  # ASan's options for Ruby. Ruby gives each thread an alternate signal
  # stack it allocates with malloc (signal.c, rb_allocate_sigaltstack and
  # rb_register_sigaltstack). ASan installs its own on each thread and, when
  # the thread ends, unmaps whatever stack is current, which by then is
  # Ruby's malloc'd one: munmap fails and ASan aborts ("failed to deallocate
  # ... error code: 22"). use_sigaltstack=0 leaves the stacks to Ruby.
  #
  # On macOS, ASan also removes itself from DYLD_INSERT_LIBRARIES once
  # loaded, so child processes run without it. The sanitizer tests start
  # child Rubies that must load it too, so strip_env=0 keeps it. On Linux,
  # LD_PRELOAD stays, and ASan runs LeakSanitizer at exit, which macOS's
  # ASan does not, and which reports the memory Ruby leaves for the system
  # to reclaim at exit; detect_leaks=0 checks on Linux what macOS checks.
  OPTIONS = { "macos" => "use_sigaltstack=0:strip_env=0", "linux" => "use_sigaltstack=0:detect_leaks=0" }.freeze

  # [build] The CMake build tree, configured with LOTA_SANITIZE on.
  # [platform] The platform it builds for, as EngineSources names it.
  def initialize(build:, platform: RbConfig::CONFIG["host_os"].include?("linux") ? "linux" : "macos")
    @build = File.expand_path(build)
    @platform = platform
  end

  # Where the tree writes its extensions (cmake/LotaExtension.cmake), for
  # the front of Ruby's load path.
  def lib
    File.join(@build, "lib")
  end

  # The C++ compiler CMake chose for the tree.
  def compiler
    cache = File.join(@build, "CMakeCache.txt")
    raise Failure, "#{cache} is missing; configure the sanitized build first" unless File.exist?(cache)

    File.read(cache)[/^CMAKE_CXX_COMPILER:\w+=(.+)$/, 1] or raise Failure, "#{cache} names no C++ compiler"
  end

  # The runtime that compiler links, which must be the one Ruby loads.
  # Clang and GCC print the bare name back when they have no such file.
  def runtime
    find(RUNTIMES.fetch(@platform))
  end

  # Where the tree's compiler finds the library +name+.
  private def find(name)
    path, status = Open3.capture2(compiler, "-print-file-name=#{name}")
    path = path.strip
    raise Failure, "#{compiler} has no #{name}" unless status.success? && File.absolute_path?(path) && File.exist?(path)

    path
  end

  # The libraries that load into Ruby first: the runtime, and on Linux the
  # C++ runtime (COMPANIONS), each where the tree's compiler finds it.
  def preloaded
    [runtime, *COMPANIONS.fetch(@platform).map { |name| find(name) }]
  end

  # The environment that loads the runtime into Ruby.
  def environment
    separator = (@platform == "linux") ? " " : ":"
    { PRELOADS.fetch(@platform) => preloaded.join(separator), "ASAN_OPTIONS" => OPTIONS.fetch(@platform) }
  end

  # The command, for Kernel#system or Rake's sh, that runs the Minitest
  # files +tests+ in a sanitized Ruby. The tree's lib comes first on the
  # load path, ahead of +load_path+, so require "lota/native" loads the
  # sanitized bundle.
  def command(tests, load_path: [])
    runner = ['require "minitest/autorun"', *tests.map { |test| %(require "#{File.expand_path(test)}") }]
    [environment, RbConfig.ruby, "-I#{[lib, *load_path].join(File::PATH_SEPARATOR)}", "-w", "-e", runner.join("; ")]
  end
end
