# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Checks that an app Xcode built from the iOS kit says what the kit's
# workflow asked for (kit.json, which ipad/prepare.rb wrote): its display
# name, character for character, through project.yml, XcodeGen, and
# Xcode's Info.plist processing; its identifier; one app for iPhone and
# iPad; its orientations, status bar, launch screen, input, and audio
# settings; and an icon. Plain Ruby 2.6, for a runner's /usr/bin/ruby.
#
#   ruby check_app.rb APP_BUNDLE KIT_JSON
require "json"
require "open3"

app, kit_json = ARGV
kit = JSON.parse(File.read(kit_json, encoding: "UTF-8"))
plist, status = Open3.capture2("plutil", "-convert", "json", "-o", "-", File.join(app, "Info.plist"))
abort "plutil could not read #{app}/Info.plist" unless status.success?
info = JSON.parse(plist.force_encoding("UTF-8"))
audio = { "ambient" => "ambient", "solo-ambient" => "soloAmbient", "playback" => "playback", "default" => "" }

checks = {
  "CFBundleDisplayName is #{kit['display_name'].inspect}" => info["CFBundleDisplayName"] == kit["display_name"],
  "CFBundleIdentifier is #{kit['identifier']}" => info["CFBundleIdentifier"] == kit["identifier"],
  "CFBundleExecutable is #{kit['app_name']}" => info["CFBundleExecutable"] == kit["app_name"],
  "UIDeviceFamily is [1, 2] (iPhone and iPad)" => info["UIDeviceFamily"] == [1, 2],
  "UISupportedInterfaceOrientations are the iPhone's" => info["UISupportedInterfaceOrientations"] == kit["orientations"]["iphone"],
  "UISupportedInterfaceOrientations~ipad are the iPad's" => info["UISupportedInterfaceOrientations~ipad"] == kit["orientations"]["ipad"],
  "UIStatusBarHidden is #{kit['hide_status_bar']}" => (info["UIStatusBarHidden"] == true) == kit["hide_status_bar"],
  "UIViewControllerBasedStatusBarAppearance is false when hidden" =>
    kit["hide_status_bar"] ? info["UIViewControllerBasedStatusBarAppearance"] == false : !info.key?("UIViewControllerBasedStatusBarAppearance"),
  "UILaunchScreen is there" => info["UILaunchScreen"].is_a?(Hash),
  "UIApplicationSupportsIndirectInputEvents is true" => info["UIApplicationSupportsIndirectInputEvents"] == true,
  "UIRequiresFullScreen is unset" => !info.key?("UIRequiresFullScreen"),
  "LotaAudioSessionCategory is #{audio.fetch(kit['audio_category']).inspect}" => info["LotaAudioSessionCategory"] == audio.fetch(kit["audio_category"]),
  "the app has an icon (CFBundleIcons and Assets.car)" => info.key?("CFBundleIcons") && File.file?(File.join(app, "Assets.car")),
  "the app holds the game (fledge/app)" => File.directory?(File.join(app, "fledge", "app")),
}
checks.each { |label, ok| puts "#{ok ? 'ok  ' : 'FAIL'} #{label}" }
puts "CFBundleDisplayName bytes: #{info['CFBundleDisplayName'].to_s.unpack('U*').map { |code| format('U+%04X', code) }.join(' ')}"
exit(checks.values.all? ? 0 : 1)
