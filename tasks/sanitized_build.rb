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
# On macOS, ASan's runtime is a dynamic library that must be in the process
# before anything it instruments, or it aborts with "Interceptors are not
# working". Ruby is not instrumented and loads the extensions with dlopen,
# so the runtime goes in with DYLD_INSERT_LIBRARIES (Clang's
# AddressSanitizer documentation, "Usage" on Darwin). dyld drops DYLD_
# variables when it starts a protected binary such as /bin/sh or
# /usr/bin/env, so the tests must start Ruby directly, never through a
# shell or a binstub.
class SanitizedBuild
  # Raised when the tree cannot say which runtime its compiler links.
  class Failure < StandardError; end

  # ASan's runtime on macOS, which also carries UBSan's.
  RUNTIME = "libclang_rt.asan_osx_dynamic.dylib"

  # [build] The CMake build tree, configured with LOTA_SANITIZE on.
  def initialize(build:)
    @build = File.expand_path(build)
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
  # Clang prints the bare name back when it has no such file.
  def runtime
    path, status = Open3.capture2(compiler, "-print-file-name=#{RUNTIME}")
    path = path.strip
    raise Failure, "#{compiler} has no #{RUNTIME}" unless status.success? && File.absolute_path?(path) && File.exist?(path)

    path
  end

  # ASan's options for Ruby. Ruby gives each thread an alternate signal
  # stack it allocates with malloc (signal.c, rb_allocate_sigaltstack and
  # rb_register_sigaltstack). ASan installs its own on each thread and, when
  # the thread ends, unmaps whatever stack is current, which by then is
  # Ruby's malloc'd one: munmap fails and ASan aborts ("failed to deallocate
  # ... error code: 22"). use_sigaltstack=0 leaves the stacks to Ruby.
  #
  # On macOS, ASan also removes itself from DYLD_INSERT_LIBRARIES once
  # loaded, so child processes run without it. The sanitizer tests start
  # child Rubies that must load it too, so strip_env=0 keeps it.
  OPTIONS = "use_sigaltstack=0:strip_env=0"

  # The environment that loads the runtime into Ruby.
  def environment
    { "DYLD_INSERT_LIBRARIES" => runtime, "ASAN_OPTIONS" => OPTIONS }
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
