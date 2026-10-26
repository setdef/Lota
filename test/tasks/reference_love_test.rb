# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/reference_love"
require "shellwords"
require "stringio"
require "yaml"

# ReferenceLove builds love as LÖVE's own macOS CI job does. The real
# vendor/love's workflow gives the commands; for building, a fake LÖVE
# repository and fake xcodebuild, xcrun, and ccache on the PATH stand in,
# so the tests run in moments and record what each tool was asked to do.
class ReferenceLoveTest < Minitest::Test
  include TreeHelper

  LOVE = File.join(ROOT, "vendor/love")

  # The words of the real workflow's macOS step +name+.
  def ci_step(name)
    steps = YAML.safe_load_file(File.join(LOVE, ".github/workflows/main.yml"), permitted_classes: [Symbol])
      .dig("jobs", "macOS", "steps")
    Shellwords.split(steps.find { |step| step["name"] == name }.fetch("run"))
  end

  def test_the_build_runs_loves_own_ci_commands_with_its_settings_added
    reference = ReferenceLove.new(love: LOVE, dependencies: "vendor/love-apple-dependencies", root: "tmp/x")
    build, export = reference.commands

    assert_equal ci_step("Build"), build.first(ci_step("Build").size)
    assert_equal ci_step("Export Archive"), export
    assert_includes build, "clean"
    assert_includes build, "archive"
  end

  def test_intermediates_stay_under_the_root_and_the_target_is_one_xcode_27_builds_for
    in_tree do |dir|
      settings = ReferenceLove.new(love: LOVE, dependencies: dir, root: File.join(dir, "ref")).settings

      assert_equal ["-derivedDataPath", File.join(dir, "ref/derived")], settings.first(2)
      assert_includes settings, "MACOSX_DEPLOYMENT_TARGET=12.0"
    end
  end

  def test_the_executable_is_in_the_app_the_export_step_writes
    reference = ReferenceLove.new(love: LOVE, dependencies: "vendor/love-apple-dependencies", root: "tmp/x")

    assert_equal File.join(ROOT, "tmp/x/src/love-macos/love.app/Contents/MacOS/love"), reference.executable
  end

  # A LÖVE repository whose workflow has the real macOS steps, and a
  # dependencies repository, each committed, and fake tools in +dir+/bin.
  def fake_world(dir, fail: false)
    love = File.join(dir, "love")
    steps = %w[Build Export\ Archive].map { |name| { "name" => name, "run" => Shellwords.join(ci_step(name)) } }
    write(love, ".github/workflows/main.yml", YAML.dump("jobs" => { "macOS" => { "steps" => steps } }))
    write(love, "platform/xcode/macosx/.keep")
    write(love, "src/love.cpp", "int main() {}\n")
    commit(love)
    dependencies = File.join(dir, "deps")
    write(dependencies, "macOS/Frameworks/SDL2.framework/SDL2", "sdl2")
    write(dependencies, "shared/Frameworks/SDL3.xcframework/Info.plist", "sdl3")
    commit(dependencies)
    fake_tools(dir, fail:)
    [love, dependencies]
  end

  def commit(dir)
    git_stage(dir)
    run!(dir, "git", "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "--quiet", "-m", "x")
  end

  # xcodebuild records each call in calls.log and makes love.app for
  # -exportArchive; xcrun names a compiler in bin.
  def fake_tools(dir, fail:)
    log = File.join(dir, "calls.log")
    script(dir, "xcodebuild", <<~SH)
      if [ "$1" = "-version" ]; then echo "Xcode 99.0"; exit 0; fi
      echo "$PWD $*" >> #{Shellwords.escape(log)}
      #{fail ? 'echo "error: the build broke"; exit 65' : ''}
      case "$*" in *-exportArchive*) mkdir -p love-macos/love.app/Contents/MacOS && touch love-macos/love.app/Contents/MacOS/love;; esac
    SH
    script(dir, "xcrun", %(echo "#{dir}/bin/real-$2"))
  end

  def script(dir, name, body)
    path = write(dir, "bin/#{name}", "#!/bin/sh\n#{body}\n")
    File.chmod(0o755, path)
  end

  # Runs the block with +dir+/bin first on the PATH, and ccache on it or
  # not.
  def with_tools(dir, ccache: false)
    script(dir, "ccache", 'exec "$@"') if ccache
    path = ENV.fetch("PATH")
    ENV["PATH"] = "#{dir}/bin:/usr/bin:/bin"
    yield
  ensure
    ENV["PATH"] = path
  end

  def calls(dir)
    File.readlines(File.join(dir, "calls.log"), chomp: true)
  end

  def test_a_build_exports_the_commit_copies_the_dependencies_runs_both_steps_and_then_is_current
    in_tree do |dir|
      love, dependencies = fake_world(dir)
      write(love, "src/uncommitted.cpp")
      out = StringIO.new
      reference = ReferenceLove.new(love:, dependencies:, root: File.join(dir, "ref"), out:)

      with_tools(dir) do
        assert_equal reference.executable, reference.build
        assert_path_exists reference.executable
        assert_path_exists File.join(reference.source, "src/love.cpp")
        refute_path_exists File.join(reference.source, "src/uncommitted.cpp")
        assert_path_exists File.join(reference.source, "platform/xcode/macosx/Frameworks/SDL2.framework/SDL2")
        assert_path_exists File.join(reference.source, "platform/xcode/shared/Frameworks/SDL3.xcframework/Info.plist")
        assert_equal 2, calls(dir).size
        assert calls(dir).all? { |call| call.start_with?("#{reference.source} ") }, calls(dir).inspect
        assert_includes calls(dir).first, "clean archive -project platform/xcode/love.xcodeproj"
        assert_includes calls(dir).last, "-exportArchive"

        assert_predicate reference, :current?
        reference.build

        assert_equal 2, calls(dir).size
        assert_includes out.string, "The reference love is current"
      end
    end
  end

  def test_a_new_commit_is_built_again
    in_tree do |dir|
      love, dependencies = fake_world(dir)
      reference = ReferenceLove.new(love:, dependencies:, root: File.join(dir, "ref"), out: StringIO.new)

      with_tools(dir) do
        reference.build
        write(love, "src/new.cpp")
        commit(love)

        refute_predicate reference, :current?
        reference.build

        assert_equal 4, calls(dir).size
        assert_path_exists File.join(reference.source, "src/new.cpp")
      end
    end
  end

  def test_with_ccache_on_the_path_the_compilers_run_through_it_and_linking_does_not
    in_tree do |dir|
      love, dependencies = fake_world(dir)
      reference = ReferenceLove.new(love:, dependencies:, root: File.join(dir, "ref"), out: StringIO.new)

      with_tools(dir, ccache: true) do
        settings = reference.settings
        wrapper = File.read(File.join(dir, "ref/bin/clang++"))

        assert_includes settings, "CC=#{dir}/ref/bin/clang"
        assert_includes settings, "CXX=#{dir}/ref/bin/clang++"
        assert_includes settings, "LD=#{dir}/bin/real-clang"
        assert_includes settings, "LDPLUSPLUS=#{dir}/bin/real-clang++"
        assert_includes settings, "COMPILER_INDEX_STORE_ENABLE=NO"
        assert_includes wrapper, "CCACHE_DEPEND=1"
        assert_includes wrapper, "modules,time_macros"
        assert_includes wrapper, "exec #{dir}/bin/ccache #{dir}/bin/real-clang++ \"$@\""
      end
    end
  end

  def test_without_ccache_the_compilers_are_xcodes_own
    in_tree do |dir|
      love, dependencies = fake_world(dir)
      reference = ReferenceLove.new(love:, dependencies:, root: File.join(dir, "ref"), out: StringIO.new)

      with_tools(dir) do
        assert_empty reference.settings.grep(/\A(CC|CXX|LD|LDPLUSPLUS)=/)
      end
    end
  end

  def test_a_failing_step_raises_with_the_end_of_its_log
    in_tree do |dir|
      love, dependencies = fake_world(dir, fail: true)
      reference = ReferenceLove.new(love:, dependencies:, root: File.join(dir, "ref"), out: StringIO.new)

      with_tools(dir) do
        failure = assert_raises(ReferenceLove::Failure) { reference.build }

        assert_includes failure.message, "xcodebuild clean archive failed"
        assert_includes failure.message, "error: the build broke"
        refute_predicate reference, :current?
      end
    end
  end

  def test_a_workflow_without_the_step_raises
    in_tree do |dir|
      write(dir, ".github/workflows/main.yml", YAML.dump("jobs" => { "macOS" => { "steps" => [] } }))
      reference = ReferenceLove.new(love: dir, dependencies: dir, root: File.join(dir, "ref"))

      failure = assert_raises(ReferenceLove::Failure) { reference.commands }

      assert_equal ".github/workflows/main.yml has no Build step", failure.message
    end
  end
end
