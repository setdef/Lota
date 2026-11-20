# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "lota/fuser"
require "stringio"
require "yaml"

# What the fuser writes for a game in one file, where it finds the app it
# builds from, and what its program says when it cannot start
# (doc/contributors/design/packaging.md, "A game in one file"). That it
# unpacks an archive, reads its conf.rb, and runs Fledge is
# test/native/fuser_run_test.rb's to prove, in a process of its own, and
# that the real fledge build --from makes an app from it, which starts
# without Ruby, is the fuser's run on a real build.
class FuserTest < Minitest::Test
  def test_the_project_names_the_app_and_gives_it_a_placeholder_identifier
    config = YAML.safe_load(Lota::Fuser.fledge_yml("Sample Game", "SampleGame", linux: false, squashfs: false))

    assert_equal({ "name" => "Sample Game", "kind" => "windowed", "identifier" => "com.example.SampleGame" }, config)
  end

  def test_a_linux_app_gets_its_installers_only_where_mksquashfs_can_write_its_appimage
    without = YAML.safe_load(Lota::Fuser.fledge_yml("Sample Game", "SampleGame", linux: true, squashfs: false))
    with = YAML.safe_load(Lota::Fuser.fledge_yml("Sample Game", "SampleGame", linux: true, squashfs: true))

    assert_empty without.fetch("installers")
    refute with.key?("installers")
  end

  def test_the_app_built_from_is_the_bundle_on_macos_and_the_folder_elsewhere
    # File.expand_path, as app_folder reads the path, which on Windows puts
    # the drive in front.
    assert_equal File.expand_path("/Applications/Fuser.app"), Lota::Fuser.app_folder("/Applications/Fuser.app/Contents/Resources/app")
    assert_equal File.expand_path("/home/you/Fuser-x86_64-linux"), Lota::Fuser.app_folder("/home/you/Fuser-x86_64-linux/app")
    assert_equal File.expand_path("/home/you/Resources"), Lota::Fuser.app_folder("/home/you/Resources/app")
  end

  def test_the_program_given_no_archive_says_how_to_give_one
    err = StringIO.new

    assert_equal 1, Lota::Fuser.main("/apps/Fuser-x86_64-linux/app", [], err:)
    assert_equal "lota fuser: --build needs the game in one file to make an app of: --build GAME.lota [FOLDER]\n", err.string
  end

  def test_an_archive_that_is_not_there_is_named
    Dir.mktmpdir do |folder|
      out = StringIO.new
      err = StringIO.new
      archive = File.join(folder, "Sample Game.lota")

      assert_equal 1, Lota::Fuser.main(folder, [archive], out:, err:)
      assert_empty out.string
      assert_equal "lota fuser: found no game at #{archive}.\n", err.string
    end
  end

  def test_a_fuser_without_its_notices_makes_no_app
    Dir.mktmpdir do |folder|
      archive = File.join(folder, "Sample Game.lota")
      File.write(archive, "")
      err = StringIO.new

      assert_equal 1, Lota::Fuser.main(File.join(folder, "app"), [archive], err:)
      assert_equal "lota fuser: found no notices at #{File.join(folder, 'app', 'NOTICES.txt')} to put in the app.\n", err.string
    end
  end
end
