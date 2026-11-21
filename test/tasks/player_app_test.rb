# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../test_helper"
require "tmpdir"
require "yaml"
require_relative "../../tasks/player_app"

# PlayerApp (rake player) writes the project of Lota's app, which plays a
# .lota, as lota fuse writes a game's, with what LÖVE's app opens and an
# entry script that starts the game it is given or the no-game screen.
# Building it with the real Fledge, and starting the app, is a run of its
# own on a computer that can build one.
class PlayerAppTest < Minitest::Test
  def setup
    super
    @out = Dir.mktmpdir("lota-player-app-test")
  end

  def teardown
    FileUtils.remove_entry(@out)
    super
  end

  def app(platform = "x86_64-linux-gnu")
    PlayerApp.new(File.join(@out, "lota.gem"), @out, platform:)
  end

  def config(platform = "x86_64-linux-gnu")
    YAML.safe_load(app(platform).__send__(:fledge_yml, PlayerApp::NAME, PlayerApp::IDENTITY, PlayerApp::IDENTITY))
  end

  # LÖVE's app is named for the engine, and known as org.love2d.love.
  def test_the_app_is_named_lota_and_holds_no_game
    player = app
    folder = File.join(@out, "player")

    assert_includes File.read(File.join(folder, "conf.rb")), %(t.title = "Lota")
    assert_equal folder, player.instance_variable_get(:@directory)
    assert_equal File.join(@out, "fuse-project"), player.project
    assert_equal({ "name" => "Lota", "kind" => "windowed", "identifier" => "org.setdef.lota" },
      config.slice("name", "kind", "identifier"))
  end

  # LÖVE's app carries LÖVE's version (platform/xcode/love.xcodeproj,
  # MARKETING_VERSION, and extra/windows/love.rc, FILEVERSION), so Lota's
  # carries Lota's, the version of the gem it ships.
  def test_the_app_carries_the_version_of_lota
    assert_equal Lota::VERSION, config["version"]
  end

  # LÖVE's app opens a .love on every system (platform/unix/love.desktop.in
  # names application/x-love-game) and a folder on macOS
  # (platform/xcode/macosx/love-macosx.plist, CFBundleDocumentTypes).
  def test_the_app_opens_a_lota_everywhere_and_a_folder_on_macos
    lota, = config.fetch("file_associations")

    assert_equal ["lota"], lota.fetch("extensions")
    assert_equal ["application/x-lota-game"], lota.fetch("mime_types")
    assert_equal 1, config.fetch("file_associations").size, "a Linux desktop entry names the game's MIME type alone"
    assert_equal 1, config("x64-mingw-ucrt").fetch("file_associations").size
    _, folder = config("arm64-darwin").fetch("file_associations")

    assert folder.fetch("folders")
  end

  # fledge build --from takes Windows' launchers, rcedit, and NSIS, and
  # Linux's AppImage runtime, from the app it copies (Fledge's
  # doc/building_from_an_app.md).
  def test_the_app_carries_the_tools_a_copy_of_it_is_built_with
    assert config.fetch("build_tools")
  end

  # The entry script starts the game it is given, unfused, or the no-game
  # screen, and remembers how it started so that it can restart.
  def test_the_entry_script_starts_the_game_it_is_given_or_the_no_game_screen
    script = app.__send__(:entry_script, PlayerApp::IDENTITY)
    RubyVM::InstructionSequence.compile(script)

    assert_includes script, "Lota::Restart.__send__(:remember, argv)"
    assert_includes script, "dropped = Lota::Native.check_drop_events"
    assert_includes script, "exit Lota::Boot.new(nil, argv).call"
    refute_includes script, "fused: true"
  end
end
