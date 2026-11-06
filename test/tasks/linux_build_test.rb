# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/linux_build"
require "stringio"

# LinuxBuild runs love-appimage-source's Makefile as LÖVE's own Linux CI
# does. The real Makefile names what it downloads and what love links; for
# building, a fake Makefile with the same variables and rules, whose
# downloads and builds only write files and log what they did, stands in,
# so the tests run in moments, on macOS too.
class LinuxBuildTest < Minitest::Test
  include TreeHelper

  MAKEFILE = File.join(ROOT, "vendor/love-appimage-source/Makefile")

  # The real Makefile's rules, by the targets each names before its colon.
  def self.rules
    @rules ||= File.read(MAKEFILE).lines.filter_map { |line| line.match(/\A(\S[^=]*?):(?!=)(.*)$/)&.captures }
  end

  def test_the_downloads_are_the_makefiles_own
    build = LinuxBuild.new(makefile: MAKEFILE, sources: "/s", root: "/r")
    values = build.variables("SDL3_BRANCH", "OPENAL_BRANCH", "FT_VERSION")

    assert_includes build.downloads, "SDL3-#{values.fetch('SDL3_BRANCH')}/CMakeLists.txt"
    assert_includes build.downloads, "openal-soft-#{values.fetch('OPENAL_BRANCH')}/CMakeLists.txt"
    assert_includes build.downloads, "freetype-#{values.fetch('FT_VERSION')}.tar.gz"
    assert_includes build.downloads, "cmake_install.sh"
    assert_equal LinuxBuild::DOWNLOADS.size, build.downloads.size
  end

  # The libraries LinuxBuild builds are what the rule that configures love
  # waits for, so love builds against nothing it did not build.
  def test_the_libraries_are_what_love_is_configured_after
    love = self.class.rules.find { |targets, _| targets.include?("$(LOVE_PATH)/build/CMakeCache.txt") }
    prerequisites = love.last.split.grep(%r{\Ainstalldir/lib/})

    assert_equal prerequisites.sort, LinuxBuild::LIBRARIES.sort
  end

  # libvorbis's configure puts -ffast-math in its CFLAGS on Linux
  # (configure.ac:133-189), under which glibc's headers declare vector
  # versions of sin, cos, and acosf (bits/math-vector.h) and GCC on x86_64
  # vectorizes loops into calls to libmvec, which the gem may not rely on.
  # The make command LinuxBuild runs gives that configure, and only it,
  # CFLAGS that take back what the headers read, __FAST_MATH__; libogg's,
  # whose rule the libvorbis rule's prerequisites reach, keeps its own.
  # make runs recipes that call $(MAKE) even in a dry run, so those run as
  # true, in build directories made for them.
  def test_only_libvorbiss_configure_is_given_cflags_that_keep_libmvec_out
    in_tree do |dir|
      linux = LinuxBuild.new(makefile: MAKEFILE, sources: File.join(dir, "sources"), root: dir)
      files = linux.variables("LIBOGG_FILE", "LIBVORBIS_FILE")
      files.each_value { |name| FileUtils.mkdir_p(File.join(dir, name, "build")) }
      output, = Open3.capture2e(*linux.make_command(dir, "--dry-run", "MAKE=true", "installdir/lib/libvorbis.so"),
        chdir: dir)
      configures = output.lines.grep(%r{\Acd \S+/build && .*\.\./configure }).to_h { |line| [line[%r{\Acd ([^/]+)/}, 1], line] }

      assert_equal files.values_at("LIBOGG_FILE", "LIBVORBIS_FILE").sort, configures.keys.sort, output
      assert_includes configures.fetch(files.fetch("LIBVORBIS_FILE")), "&& CFLAGS=-U__FAST_MATH__ LDFLAGS="
      refute_includes configures.fetch(files.fetch("LIBOGG_FILE")), "CFLAGS"
    end
  end

  # A Makefile with the real one's download variables, whose rules make
  # each download and each library by writing a file, and love from
  # love2d-$(LOVE_BRANCH), logging each target to make.log.
  def fake_makefile(dir, fail: nil)
    names = LinuxBuild::DOWNLOADS.keys.to_h { |name| [name, "#{name.downcase}-1"] }
    downloads = LinuxBuild::DOWNLOADS.map { |name, rule| rule.include?("%s") ? format(rule, "$(#{name})") : rule }
    libraries = LinuxBuild::LIBRARIES.join(" ")
    write(dir, "appimage/Makefile", <<~MAKE)
      LOVE_BRANCH := main
      #{names.map { |name, value| "#{name} := #{value}" }.join("\n")}
      LOVE_PATH := love2d-$(LOVE_BRANCH)

      #{downloads.join(' ')}:
      \tmkdir -p $(dir $@) && echo downloaded > $@ && echo "$@" >> make.log
      #{(fail == :download) ? "\tfalse" : ''}

      #{libraries}:
      \tmkdir -p $(dir $@) && test -f sdl3_path-1/CMakeLists.txt && echo built > $@ && echo "$@" >> make.log
      #{(fail == :build) ? "\tfalse" : ''}

      installdir/bin/love: $(LOVE_PATH)/CMakeLists.txt
      \tmkdir -p $(dir $@) && cp $(LOVE_PATH)/CMakeLists.txt $@ && echo "$@ $(LOVE_PATH)" >> make.log
    MAKE
  end

  # A LÖVE repository with one commit.
  def fake_love(dir)
    love = File.join(dir, "love")
    write(love, "CMakeLists.txt", "project(love)\n")
    git_stage(love)
    run!(love, "git", "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "--quiet", "-m", "x")
    [love, run!(love, "git", "rev-parse", "HEAD").strip]
  end

  def build(dir, out: StringIO.new)
    LinuxBuild.new(makefile: File.join(dir, "appimage/Makefile"), sources: File.join(dir, "sources"),
      root: File.join(dir, "root"), out:)
  end

  def log(dir, where)
    File.readlines(File.join(dir, where, "make.log"), chomp: true)
  end

  def test_fetch_runs_the_downloads_alone_and_then_is_current
    in_tree do |dir|
      fake_makefile(dir)
      linux = build(dir)
      linux.fetch

      assert_equal linux.downloads, log(dir, "sources")
      assert_path_exists File.join(dir, "sources/libogg_file-1.tar.gz")
      linux.fetch
      assert_equal linux.downloads, log(dir, "sources")
    end
  end

  # What fetch downloaded is copied in, so the Makefile finds it made and
  # downloads nothing; each library is built from it, once.
  def test_the_dependencies_build_from_what_was_fetched_and_then_are_current
    in_tree do |dir|
      fake_makefile(dir)
      linux = build(dir)
      linux.fetch

      assert_equal File.join(dir, "root/installdir"), linux.dependencies
      assert_equal LinuxBuild::LIBRARIES, log(dir, "root")
      assert_path_exists linux.dependencies_stamp
      linux.dependencies
      assert_equal LinuxBuild::LIBRARIES, log(dir, "root")
    end
  end

  # A download the recipe adds is fetched though the Makefile is the same.
  def test_fetch_runs_again_when_the_downloads_change
    in_tree do |dir|
      fake_makefile(dir)
      linux = build(dir)
      linux.fetch
      File.write(File.join(dir, "sources/stamp"), "makefile and fewer downloads")
      linux.fetch

      assert_equal linux.downloads, log(dir, "sources")
    end
  end

  def test_the_dependencies_need_what_fetch_downloads
    in_tree do |dir|
      fake_makefile(dir)
      failure = assert_raises(LinuxBuild::Failure) { build(dir).dependencies }

      assert_includes failure.message, "cmake_install.sh is missing; run bundle exec rake sources:fetch"
    end
  end

  # love builds from an export of the commit, under the name the Makefile
  # gives its clone of LÖVE, and again only for another commit.
  def test_love_builds_from_the_commit_beside_the_dependencies
    in_tree do |dir|
      fake_makefile(dir)
      love, commit = fake_love(dir)
      write(love, "uncommitted.txt")
      linux = build(dir)
      linux.fetch

      assert_equal File.join(dir, "root/installdir/bin/love"), linux.love(love)
      assert_equal "project(love)\n", File.read(linux.executable)
      assert_equal "installdir/bin/love love2d-#{commit}", log(dir, "root").last
      refute_path_exists File.join(dir, "root/love2d-#{commit}/uncommitted.txt")
      linux.love(love)
      assert_equal 1, log(dir, "root").count { |line| line.start_with?("installdir/bin/love") }
    end
  end

  def test_a_failing_step_raises_with_the_end_of_its_log
    in_tree do |dir|
      fake_makefile(dir, fail: :build)
      linux = build(dir)
      linux.fetch
      failure = assert_raises(LinuxBuild::Failure) { linux.dependencies }

      assert_includes failure.message, "failed; the end of #{linux.log}"
      refute_path_exists linux.dependencies_stamp
    end
  end

  # A download that fails is tried again, from nothing, and gives up after
  # LinuxBuild::ATTEMPTS.
  def test_failed_downloads_are_retried_and_then_give_up
    in_tree do |dir|
      fake_makefile(dir, fail: :download)
      out = StringIO.new
      failure = assert_raises(LinuxBuild::Failure) { build(dir, out:).fetch }

      assert_includes failure.message, "failed; the end of"
      assert_equal LinuxBuild::ATTEMPTS - 1, out.string.scan("Retrying the downloads").size
    end
  end
end
