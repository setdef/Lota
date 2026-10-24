# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "open3"

# A CMake project and the build directory it builds into.
#
# Rake runs CMake in two steps so the C++ gates can share them: clang-tidy
# needs only the compile_commands.json that configuring writes, while the
# engine needs the build. Each step streams CMake's output and raises
# Failure when CMake fails, so a broken build stops the gate.
class CMakeBuild
  # Raised when CMake fails, after its output has gone to +out+.
  class Failure < StandardError; end

  # [source] The directory holding CMakeLists.txt.
  # [build] The build directory.
  # [args] Extra arguments to the configure step, such as a generator.
  # [out] Where CMake's output goes; +nil+ means wherever $stdout points
  #   at the time.
  def initialize(source:, build:, args: [], out: nil)
    @source = File.expand_path(source)
    @build = File.expand_path(build)
    @args = args
    @out = out
  end

  # Configures the build directory, or refreshes it when it exists.
  def configure
    run("cmake", "-S", @source, "-B", @build, *@args)
  end

  # Builds every target; CMake reconfigures first if a CMake file changed.
  def build
    run("cmake", "--build", @build)
  end

  # The compilation database CMake writes when configuring.
  def compile_commands
    File.join(@build, "compile_commands.json")
  end

  private def run(*command)
    Open3.popen2e(*command) do |_stdin, output, wait|
      output.each_line { |line| (@out || $stdout).print(line) }
      raise Failure, "#{command.join(' ')} failed (its output is above)" unless wait.value.success?
    end
  end
end
