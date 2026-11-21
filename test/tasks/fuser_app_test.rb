# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../test_helper"
require_relative "../../tasks/fuser_app"
require_relative "../../tasks/release"
require "open3"
require "rbconfig"
require "tmpdir"

# What the fuser app's project holds beyond lota fuse's: the fledge.yml keys
# Fledge's guide asks of an app that builds apps, and an entry script that
# makes an app when its program is given --build and starts the window
# otherwise. Building it with the real Fledge, and making an app with it,
# is the fuser's run on a build of its own.
class FuserAppTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  # A FuserApp as #initialize leaves it, without the game it writes and
  # locks, which needs Fledge from Git.
  def fuser_app
    FuserApp.allocate.tap { |app| app.instance_variable_set(:@options, FuserApp.options("dist/fuser")) }
  end

  def test_the_fuser_carries_the_tools_fledge_build_from_takes_and_is_offered_for_a_lota
    config = fuser_app.__send__(:fledge_config, FuserApp::NAME, FuserApp::IDENTITY, FuserApp::IDENTITY)

    assert_equal "Lota Fuser", config["name"]
    assert_equal Release::APPS.fetch("fuser"), FuserApp::NAME, "a release publishes the fuser by its name"
    assert_equal "com.setdef.lota.Fuser", config["identifier"]
    assert_equal Lota::VERSION, config["version"], "the fuser carries the version of the Lota it ships"
    assert config["build_tools"]
    assert_equal [{ "name" => "Lota game", "extensions" => ["lota"] }], config["file_associations"]
  end

  def test_the_entry_script_given_build_makes_an_app_before_it_starts_the_window
    script = fuser_app.__send__(:entry_script, FuserApp::IDENTITY)

    assert_operator script.index("Lota::Fuser.main"), :<, script.index("Lota::Boot.new")
    Dir.mktmpdir do |folder|
      File.write(File.join(folder, "main.rb"), script)
      output, status = Open3.capture2e(RbConfig.ruby, "-I#{File.join(ROOT, 'lib')}", File.join(folder, "main.rb"), "--build")

      assert_equal 1, status.exitstatus, output
      assert_includes output, "lota fuser: --build needs the game in one file to make an app of"
    end
  end

  def test_a_gem_only_vendor_cache_holds_gets_its_checksum_and_no_other_gem_does
    Dir.mktmpdir do |folder|
      gem = File.join(folder, "lota-1.0.0-arm64-darwin.gem")
      File.write(gem, "a gem")
      lockfile = "GEM\n  specs:\n    lota (1.0.0-arm64-darwin)\n\nCHECKSUMS\n  fledge (0.14.0)\n  lota (1.0.0-arm64-darwin)\n  " \
        "rake (13.0.0) sha256=ab\n\nBUNDLED WITH\n  4.0.22\n"

      assert_equal lockfile.sub("  lota (1.0.0-arm64-darwin)\n  rake", "  lota (1.0.0-arm64-darwin) sha256=#{Digest::SHA256.hexdigest('a gem')}\n  rake"),
        FuserApp.with_checksum(lockfile, "lota", gem)
    end
  end

  # From Fledge v0.16.0, Fledge from Git ships no compiled file of its own
  # in an app, so the fuser names it there, at the tag Lota builds with, as
  # lota fuse's tools do.
  def test_the_fuser_ships_fledge_from_git_at_the_tag_lota_builds_with
    gemfile = fuser_app.__send__(:gemfile, FuserApp::IDENTITY, nil)

    assert_includes gemfile, %(gem "fledge", git: "#{Lota::Fuse::FLEDGE_GIT}", ref: "#{Lota::Fuse.fledge_ref}"\n)
    assert_includes gemfile, %(gem "lota", "#{Lota::VERSION}"\n)
  end

  def test_the_window_makes_an_app_of_what_is_dropped_on_it_and_of_what_its_program_is_given
    main = FuserApp::GAME.fetch("main.rb")

    assert_includes main, "SCREEN.drop(file.filename)"
    assert_includes main, "arguments.each { |path| SCREEN.drop(path) }"
    assert_includes FuserApp::GAME.fetch("conf.rb"), "t.identity = \"LotaFuser\""
    assert_includes FuserApp::GAME.fetch("conf.rb"), "t.modules.audio = false"
  end
end
