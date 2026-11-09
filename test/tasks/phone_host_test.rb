# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
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

  # Lota's extension looks this method up on the activity by name and JNI
  # signature (ext/lota/native/event.cpp, watch_android_pause), and skips
  # the wait for a host without it, so a rename on either side would bring
  # back the crash of a Vulkan game leaving the screen
  # (doc/contributors/upstream/017.md) with no error to show for it.
  def test_the_activity_has_the_method_the_extension_reports_a_pause_to
    looked_up = File.read(File.join(ROOT, "ext/lota/native/event.cpp"))[/GetStaticMethodID\(\w+, "(\w+)", "\(Z\)V"\)/, 1]

    assert_equal "gamePaused", looked_up
    assert_match(/^    public static void #{looked_up}\(boolean \w+\) \{/, File.read(ACTIVITY))
    assert_match(/protected SDLSurface createSDLSurface\(Context context\) \{\s*return new GameSurface/, File.read(ACTIVITY))
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
  # rest. Neither love-android's nor SDL's manifest declares density, and
  # an emulator's "Display size" change ended the game too.
  def test_the_activity_handles_the_changes_that_would_end_the_game
    activity = File.read(MANIFEST).gsub(/<!--.*?-->/m, "")[/<activity\b[^>]*>/m]
    changes = activity[/android:configChanges="([^"]*)"/, 1].split("|")
    love_android = %w[orientation screenSize smallestScreenSize screenLayout keyboard keyboardHidden navigation]

    assert_equal love_android + %w[uiMode fontScale fontWeightAdjustment locale layoutDirection assetsPaths density],
      changes
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

  # SDL 3.4.10 reads the screen's orientation from statusBarOrientation
  # alone, which iOS 27 answers with Unknown, and SDL then gives a game
  # launched in landscape a portrait window
  # (doc/contributors/upstream/019.md). SDL_RunApp passes UIApplicationMain
  # no class (SDL_uikitappdelegate.m, line 60), so the app's class is the
  # one Info.plist names. It must keep UIKit's answer, read the window
  # scene's only when UIKit's is Unknown, and, while the scene's is Unknown
  # too, answer the scene's shape, so SDL does not swap the frame.
  def test_the_ios_app_reads_the_scenes_orientation_where_uikit_reports_none
    plist = File.read(File.join(HOST, "ios/Host/Info.plist")).gsub(/<!--.*?-->/m, "")
    main = File.read(File.join(HOST, "ios/Host/main.m"))
    name = plist[%r{<key>NSPrincipalClass</key>\s*<string>(\w+)</string>}, 1]
    method = main[/^@implementation #{name}\b.*?^- \(UIInterfaceOrientation\)statusBarOrientation \{\n(.*?)^\}/m, 1]

    assert_equal "LotaApplication", name
    assert_match(/^@interface #{name} : UIApplication$/, main)
    assert_match(/\A  UIInterfaceOrientation orientation = \[super statusBarOrientation\];
  if \(orientation != UIInterfaceOrientationUnknown\)
    return orientation;\n/, method)
    assert_includes method, "[scene.session.role isEqualToString:UIWindowSceneSessionRoleApplication]"
    assert_includes method, "orientation = window_scene.effectiveGeometry.interfaceOrientation;"
    shape = method.lines.last(4).join.squeeze(" ").delete("\n")
    assert_includes shape, "window_scene ? window_scene.coordinateSpace.bounds.size : UIScreen.mainScreen.bounds.size;"
    assert_match(/ return size\.width > size\.height \? UIInterfaceOrientationLandscapeRight : UIInterfaceOrientationPortrait;\z/,
      shape)
  end
end
