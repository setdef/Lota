# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2025 Aliet Exposito
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from FLASH-BLIP's conf.lua
# (test/fixtures/flash_blip/game/conf.lua, lines 1-80), by the rules of
# doc/contributors/design/translation.md: love.filesystem.lines becomes
# Lota::Filesystem.lines, an Enumerator (rule 15), love.math's random seed,
# which math.randomseed sets, the writer Lota::Math.random_seed= (rule 5),
# and the full screen type a symbol (rule 9). love.conf becomes Lota.conf
# and love.errorhandler Lota.errorhandler
# (doc/contributors/design/game.md), with the settings' names unchanged.
#
# Lua's math.randomseed in love.conf runs before love.math opens, and the
# parity harness points it at love.math.setRandomSeed only once love.math
# is open, so it seeds nothing there; Lota.math is nil until Lota::Math is
# open, so the Ruby seeds only when Lua's would. os.time() is
# Time.now.to_i. Lua's arg holds the game's folder at arg[1] and the first
# argument after it at arg[2], which is ARGV[0] here. The Lua patterns
# that read product.env become regular expressions of the same meaning,
# and the table they fill a Hash, which love.conf reads as Lua's function
# reads the local it closes over, so it is the constant PRODUCT_CONFIG
# once filled. GAME_VERSION, a Lua global, is a constant.
#
# With the VS Code Lua debugger, the game starts it and rethrows every
# error rather than showing LÖVE's error screen. That debugger debugs Lua,
# and Ruby has none like it, so the branch is translated as written and
# runs only where that debugger has set its variable.

is_debug = ENV["LOCAL_LUA_DEBUGGER_VSCODE"] == "1" && ARGV[0] == "debug"
if is_debug
  require "lldebugger"
  Lldebugger.start

  def Lota.errorhandler(msg)
    raise msg
  end
end

# Read product configuration
# Shared between the game and CI
product_config = {}
Lota::Filesystem.lines("product.env").each do |line|
  # Skip comment lines and blank lines
  next if line.match?(/\A\s*#/) || line.match?(/\A\s*\z/)

  key, value = line.match(/([^=]+)=(.*)/)&.captures
  product_config[key] = value.match(/\A"?(.*?)"?\z/)[1] if key
end

PRODUCT_CONFIG = product_config.freeze

GAME_VERSION = "v#{PRODUCT_CONFIG.fetch('PRODUCT_VERSION')}"

# https://love2d.org/wiki/Config_Files
def Lota.conf(t)
  Lota::Math.random_seed = Time.now.to_i if Lota.math

  t.identity = PRODUCT_CONFIG["PRODUCT_ID"]
  t.appendidentity = false
  t.version = PRODUCT_CONFIG["LOVE_VERSION"]

  # If t.console is set to true, then the debugger won't work.
  t.console = false
  t.accelerometerjoystick = false
  t.externalstorage = false
  t.gammacorrect = false

  t.audio.mic = PRODUCT_CONFIG["AUDIO_MIC"]
  t.audio.mixwithsystem = false

  t.window.title = PRODUCT_CONFIG["PRODUCT_NAME"]
  t.window.icon = nil
  t.window.width = 360
  t.window.height = 480
  t.window.borderless = false
  t.window.resizable = false
  t.window.minwidth = 1
  t.window.minheight = 1
  t.window.fullscreen = false
  t.window.fullscreentype = :desktop
  t.window.vsync = 1
  t.window.msaa = 0
  t.window.depth = nil
  t.window.stencil = nil
  t.window.display = 1
  t.window.highdpi = true
  t.window.usedpiscale = true
  t.window.x = nil
  t.window.y = nil

  t.modules.audio = true
  t.modules.data = true
  t.modules.event = true
  t.modules.font = true
  t.modules.graphics = true
  t.modules.image = true
  t.modules.joystick = true
  t.modules.keyboard = true
  t.modules.math = true
  t.modules.mouse = true
  t.modules.physics = true
  t.modules.sound = true
  t.modules.system = true
  t.modules.thread = true
  t.modules.timer = true
  t.modules.touch = true
  t.modules.video = true
  t.modules.window = true
end
# SPDX-SnippetEnd
