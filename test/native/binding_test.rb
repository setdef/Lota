# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require "json"
require "shellwords"
require "tmpdir"

# Bindings that would break the memory rule do not compile
# (ext/lota/native/binding.hpp). Each probe compiles with the flags
# Lota::Native's own sources compile with.
class BindingTest < Minitest::Test
  include NativeHelper

  parallelize_me!

  COMPILE_COMMANDS = File.join(ROOT, "tmp/engine/build/compile_commands.json")

  def compile(body)
    Dir.mktmpdir("lota-binding") do |dir|
      probe = File.join(dir, "probe.cpp")
      File.write(probe, <<~CPP)
        #include "native/binding.hpp"
        #include "math/RandomGenerator.h"
        using love::math::RandomGenerator;
        #{body}
      CPP
      capture2e(TOOL_ENV, *command_for(probe))
    end
  end

  # native.cpp's compile command, compiling +probe+ for syntax only.
  def command_for(probe)
    entry = JSON.parse(File.read(COMPILE_COMMANDS)).find { |command| command["file"].end_with?("/native/native.cpp") }
    words = Shellwords.split(entry.fetch("command"))
    output = words.index("-o")
    words.slice!(output, 2)
    words.slice!(words.index("-c"), 2)
    [*words, "-fsyntax-only", probe]
  end

  def test_a_binding_that_returns_an_engine_object_by_pointer_compiles
    output, status = compile(<<~CPP)
      RandomGenerator *same(RandomGenerator *generator) { return generator; }
      void probe() { Rice::define_class<RandomGenerator>("Probe").define_method("same", &same); }
    CPP

    assert status.success?, output
  end

  def test_a_binding_that_returns_an_engine_object_by_value_does_not_compile
    output, status = compile(<<~CPP)
      RandomGenerator copy(RandomGenerator &generator) { return generator; }
      void probe() { Rice::define_class<RandomGenerator>("Probe").define_method("copy", &copy); }
    CPP

    refute status.success?
    assert_includes output, "engine objects cross into Ruby by pointer, never by value"
  end

  def test_a_binding_that_returns_a_const_engine_object_does_not_compile
    output, status = compile(<<~CPP)
      const RandomGenerator *same(RandomGenerator *generator) { return generator; }
      void probe() { Rice::define_class<RandomGenerator>("Probe").define_method("same", &same); }
    CPP

    refute status.success?
    assert_includes output, "bind functions that return engine objects as non-const pointers"
  end
end
