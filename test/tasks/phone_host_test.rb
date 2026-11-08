# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"

# The phone hosts in ext/lota/phone/host, which a game's Fledge project
# names under ios: host: and android: host: in fledge.yml, and which
# fledge build copies over the project it writes (Fledge's ADR 025). The
# app built from them runs only on a phone or its Simulator or emulator
# (.github/workflows/phones.yml); these tests check what can be read here:
# that the gem carries them, and that they agree with the engine Lota
# builds and the Fledge files they replace.
class PhoneHostTest < Minitest::Test
  include TreeHelper

  HOST = File.join(ROOT, "ext/lota/phone/host")
  ACTIVITY = File.join(HOST, "android/src/main/java/org/setdef/fledge/host/MainActivity.java")
  MANIFEST = File.join(HOST, "android/src/main/AndroidManifest.xml")

  # The methods LÖVE's Android code looks up that MainActivity need not
  # have, each with why: Android's own, and those Lota's engine never
  # reaches or whose absence LÖVE checks for.
  NOT_NEEDED = {
    "getAssets" => "every Activity has it",
    "list" => "AssetManager's, not the Activity's",
    "buildFileTree" => "only for a game inside the APK's assets, and Fledge unpacks the game into files",
    "getCRequirePath" => "only for Lua's C modules, through wrap_Filesystem.cpp",
    "requestRecordAudioPermission" => "LÖVE checks that it exists (android.cpp, requestRecordingPermission)",
    "showRecordingAudioPermissionMissingDialog" => "LÖVE checks that it exists (android.cpp)",
  }.freeze

  def test_the_gem_carries_each_host_file
    files = Gem::Specification.load(File.join(ROOT, "lota.gemspec")).files
    hosts = Dir.glob("**/*", base: HOST).select { |path| File.file?(File.join(HOST, path)) }

    assert_operator hosts.size, :>=, 5
    hosts.each { |path| assert_includes files, "ext/lota/phone/host/#{path}" }
  end

  # SDL's Java loads each library by name, in order, before SDL's main
  # runs (SDLActivity.getLibraries): SDL3 first, whose JNI_OnLoad
  # registers SDL's Java methods, then the shared libraries the extension
  # links, then Fledge's Ruby and the app's extensions.
  def test_the_activity_loads_sdl_first_and_every_shared_library_the_engine_links
    libraries = File.read(ACTIVITY)[/getLibraries\(\) \{\s*return new String\[\] \{(.*?)\};/m, 1].scan(/"([^"]+)"/).flatten
    linked = File.read(File.join(ROOT, "ext/lota/engine/dependencies_android.cmake")).scan(/^\s*-l(\w+)$/).flatten -
      %w[android log stdc++]

    assert_equal "SDL3", libraries.first
    assert_equal %w[SDL3 openal].sort, linked.sort
    assert_equal linked.sort, (libraries - %w[fledgeruby fledgeext]).sort
    assert_equal %w[fledgeruby fledgeext], libraries.last(2)
  end

  # LÖVE's engine calls these on the Activity through JNI without checking
  # that they exist, so an app whose Activity lacks one stops in the first
  # call that reaches it, such as love.window.setMode's setImmersiveMode.
  def test_the_activity_has_every_method_loves_android_code_calls_on_it
    called = File.read(File.join(ROOT, "vendor/love/src/common/android.cpp"))
      .scan(/GetMethodID\(\w+, "(\w+)"/).flatten.uniq
    defined = File.read(ACTIVITY).scan(/^    public \w+ (\w+)\(/).flatten

    assert_includes called, "setImmersiveMode"
    assert_empty called - NOT_NEEDED.keys - defined
  end

  # Read without an XML library: REXML defines a module method +name+ of
  # its own (REXML::Functions), which RbsParity, reading the name of every
  # module loaded in the same test process, would call and fail in.
  def test_the_manifest_replaces_fledges_and_names_its_activity
    manifest = File.read(MANIFEST).gsub(/<!--.*?-->/m, "")
    activity = manifest[/<activity\b[^>]*>/m]

    assert_includes activity, %(android:name="org.setdef.fledge.host.MainActivity")
    assert_includes activity, %(android:exported="true")
    assert_includes manifest, %(<application android:label="@string/app_name"@@ICON@@>)
    assert_includes manifest, %(<uses-feature android:glEsVersion="0x00030000" />)
    refute_includes manifest, "<meta-data", "Back closes the app by default, as in LÖVE"
  end

  # Android recreates the activity for a change of configuration the
  # manifest leaves out, and SDL then ends the game and exits the app
  # (doc/contributors/upstream/014.md). love-android's manifest
  # (app/src/main/AndroidManifest.xml at 1c89bb0b2e, line 36) declares
  # the first seven; an emulator recreated the activity for each of the
  # rest. Density stays out, as in love-android's and SDL's manifests.
  def test_the_activity_handles_the_changes_that_would_end_the_game
    activity = File.read(MANIFEST).gsub(/<!--.*?-->/m, "")[/<activity\b[^>]*>/m]
    changes = activity[/android:configChanges="([^"]*)"/, 1].split("|")
    love_android = %w[orientation screenSize smallestScreenSize screenLayout keyboard keyboardHidden navigation]

    assert_equal love_android + %w[uiMode fontScale fontWeightAdjustment locale layoutDirection assetsPaths], changes
    refute_includes changes, "density"
  end

  # Fledge fills these marks in its project.yml, and in a host's copy of
  # it (Fledge's lib/fledge/templates/ios/project.yml at v0.5.1).
  def test_the_ios_project_keeps_fledges_marks_and_sdls_scene_delegate
    project = File.read(File.join(HOST, "ios/project.yml"))
    plist = File.read(File.join(HOST, "ios/Host/Info.plist"))

    %w[NAME IDENTIFIER VERSION APP_ICON EXTENSIONS LDFLAGS].each { |mark| assert_includes project, "@@#{mark}@@" }
    assert_empty project.scan(/(?<!@)@[A-Z_]+@(?!@)/), "a mark Fledge does not fill"
    assert_match %r{<key>UISceneDelegateClassName</key>\s*<string>SDLUIKitSceneDelegate</string>}, plist
    assert_includes File.read(File.join(HOST, "ios/Host/main.m")), "SDL_RunApp(argc, argv, run_ruby, NULL)"
  end
end
