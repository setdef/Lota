# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Restarts once, as LÖVE's fused game restarts, with its process id as
# the value, and says each run's process id and value, then says whether
# it runs fused, with YJIT, and where it saves, saves a file, plays a
# tenth of a second of silence through the gem's OpenAL Soft, draws the
# screen Lövetest's captureScreenshot test captures, saves a screenshot
# of it, and quits with status 3, so an exit status of 0 cannot pass by
# accident.
module FuseCheck
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
  # SPDX-License-Identifier: Zlib
  #
  # Translated to Ruby from what Lövetest's love.load makes for its screen
  # (vendor/love/testing/main.lua:46-57) and from its captureScreenshot
  # test (tests/graphics.lua:1648-1673), which sets TextCommand while the
  # screen is captured, and whose TextRun Lövetest's TestSuite sets to the
  # test's name (classes/TestSuite.lua:79). setDefaultFilter becomes a
  # writer of several values (rule 6), newImage, newQuad, and newFont
  # Image.new, Quad.new, and Font.new (rule 2), and captureScreenshot
  # capture_screenshot (rule 13).
  def self.load
    Lota::Graphics.default_filter = :nearest, :nearest
    Lota::Graphics.line_style = :rough
    Lota::Graphics.line_width = 1
    @texture = Lota::Graphics::Image.new("resources/love.png")
    @img = Lota::Graphics::Quad.new(0, 0, 64, 64, @texture)
    @font = Lota::Graphics::Font.new("resources/font.ttf", 8, :normal)
    @text_command = "Capturing screenshot"
    @text_run = "love.graphics.captureScreenshot"
    Lota::Graphics.capture_screenshot("screenshot.png")
  end

  # Translated to Ruby from Lövetest's love.draw (main.lua:179-188).
  # setFont becomes a writer (rule 5).
  def self.draw
    return unless @font

    lw = (Lota::Graphics.width - 128) / 2.0
    lh = (Lota::Graphics.height - 128) / 2.0
    Lota::Graphics.draw(@texture, @img, lw, lh, 0, 2, 2)
    Lota::Graphics.font = @font
    Lota::Graphics.print(@text_command, 4, 12, 0, 2, 2)
    Lota::Graphics.print(@text_run, 4, 32, 0, 2, 2)
  end
  # SPDX-SnippetEnd
end

def Lota.load(_arguments)
  puts "run: #{Process.pid} #{Lota.restart.inspect}"
  return Lota::Event.restart(Process.pid) if Lota.restart.nil?

  puts "fused: #{Lota::Filesystem.fused?}"
  puts "yjit: #{defined?(RubyVM::YJIT) ? RubyVM::YJIT.enabled? : 'absent'}"
  puts "identity: #{Lota::Filesystem.identity}"
  puts "saved: #{Lota::Filesystem.write('check.txt', 'saved').first}"
  puts "save directory: #{Lota::Filesystem.save_directory}"
  Lota::Filesystem.remove("screenshot.png")
  Lota::Audio::Source.new(Lota::Sound::SoundData.new(4410, 44_100, 16, 1)).play
  puts "#{Lota::System.os}: #{Lota::Audio.active_source_count} source playing"
  puts "renderer: #{Lota::Graphics.renderer_info.join(' / ')}"
  FuseCheck.load
end

def Lota.draw = FuseCheck.draw

# The screenshot is written as the first frame is shown, so the second
# frame's update finds it and quits.
def Lota.update(_dt)
  return unless Lota::Filesystem.exists("screenshot.png")

  puts "screenshot: #{File.join(Lota::Filesystem.save_directory, 'screenshot.png')}"
  Lota::Event.quit(3)
end
