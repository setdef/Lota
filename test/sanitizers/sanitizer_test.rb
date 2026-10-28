# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../native/native_helper"
require "rbconfig"

# rake test:native only (tasks/test.rake): the sanitizers are loaded, and
# they report each deliberate bug in the test-only extension. Each bug runs
# in a child Ruby, which the report ends.
class SanitizerTest < Minitest::Test
  include NativeHelper

  parallelize_me!

  def sanitized_lib
    File.dirname(loaded("lota_native_test"))
  end

  # Runs +script+ in a child Ruby that loads the sanitized extensions, as
  # this process did; it inherits DYLD_INSERT_LIBRARIES (strip_env=0,
  # tasks/sanitized_build.rb), or LD_PRELOAD on Linux. Before the script runs, C++ holds the only
  # reference to a Counted: the wrapper that made it was on a finished
  # thread's stack, and has been collected.
  def run_bug(script)
    capture2e({}, RbConfig.ruby, "-I#{sanitized_lib}", "-e", <<~RUBY)
      require "lota_native_test"
      Thread.new { LotaNativeTest.hold(LotaNativeTest::Counted.new) }.join
      GC.start
      abort "C++ does not hold the only reference" unless LotaNativeTest.held_reference_count == 1
      #{script}
      puts "the bug went unreported"
    RUBY
  end

  def test_the_extensions_are_the_sanitized_build
    assert LotaNativeTest.sanitized?, "lota_native_test was built without the sanitizers"
    assert_equal sanitized_lib, File.dirname(File.dirname(loaded("lota/native")))
    variable, runtime = TestHome::LINUX ? %w[LD_PRELOAD libasan] : %w[DYLD_INSERT_LIBRARIES libclang_rt.asan]
    assert_includes ENV.fetch(variable, ""), runtime
  end

  def test_asan_reports_a_read_after_free
    output, status = run_bug("LotaNativeTest.use_after_free")

    refute status.success?
    assert_includes output, "ERROR: AddressSanitizer: heap-use-after-free"
    assert_includes output, "use_after_free"
    refute_includes output, "the bug went unreported"
  end

  # A binding that adopts a reference it was never given: collecting its
  # wrapper frees the object while C++ still holds it, so C++'s own release
  # touches freed memory, inside love::Object::release.
  def test_asan_reports_a_release_after_the_last_reference_is_gone
    output, status = run_bug(<<~RUBY)
      Thread.new { LotaNativeTest.mistakenly_adopted }.join
      GC.start
      LotaNativeTest.drop
    RUBY

    refute status.success?
    assert_includes output, "ERROR: AddressSanitizer: heap-use-after-free"
    assert_includes output, "love::Object::release()"
    refute_includes output, "the bug went unreported"
  end

  def test_ubsan_reports_signed_overflow
    output, status = run_bug("LotaNativeTest.add_one(2**31 - 1)")

    refute status.success?
    assert_includes output, "runtime error: signed integer overflow: 2147483647 + 1"
    refute_includes output, "the bug went unreported"
  end
end
