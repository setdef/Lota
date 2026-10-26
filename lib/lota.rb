# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "lota/version"

# Make 2D games in Ruby.
#
# Lota is an independent project, not made, endorsed, or supported by the
# LÖVE Development Team.
#
# LÖVE is a mature 2D game engine with a decade of tutorials behind it. Its
# games are written in Lua, so a Rubyist who wants that engine has to
# leave Ruby to use it, and a Lua tutorial teaches them nothing about their
# own language.
#
# Lota builds a modified version of LÖVE's C++ engine and hands control to
# Ruby instead of Lua. The modules keep LÖVE's names, so a LÖVE tutorial
# still reads true: love.graphics becomes Lota::Graphics, love.audio
# becomes Lota::Audio, and newSpriteBatch becomes SpriteBatch.new.
#
# Lota::Native is the engine itself: LÖVE's C++ classes, bound to Ruby by
# a compiled extension (ext/lota).
module Lota
end

require "lota/native"

# Ruby runs exit procs on the main thread, after the game and before it
# frees what is left. Releases the collector queued on other threads happen
# here, so none is lost (ADR 001, section 5); Ruby itself then frees the
# remaining wrappers on the main thread.
at_exit { Lota::Native.drain_release_queue }

require_relative "lota/filesystem"
require_relative "lota/image"
require_relative "lota/graphics"
require_relative "lota/timer"
require_relative "lota/keyboard"
require_relative "lota/mouse"
require_relative "lota/math"
require_relative "lota/event"
require_relative "lota/window"
require_relative "lota/settings"
require_relative "lota/callbacks"
require_relative "lota/boot"

# The lowercase spelling of each module, so that a LÖVE tutorial's
# love.graphics becomes lota.graphics and nothing else changes (ADR 003,
# section 4). Lota::Graphics remains the idiomatic spelling.
#
# Each accessor returns +nil+ until its module is open, and for good when
# the settings turn the module off (<tt>t.modules.timer = false</tt>), as
# love.timer is nil until boot.lua requires it and stays nil when it does
# not (vendor/love/src/modules/love/boot.lua:347-372). So
# <tt>if lota.timer</tt> asks what LÖVE's <tt>if love.timer then</tt>
# asks. The constant stays defined, as LÖVE keeps the module's code: only
# the accessor tells whether the module was loaded. love.filesystem is
# always loaded (boot.lua:46), and so is Lota.filesystem.
module Lota
  # Lota::Filesystem, as love.filesystem.
  #
  # === Example
  #
  #   lota.filesystem # => Lota::Filesystem
  def self.filesystem
    Filesystem
  end

  # Lota::Image, as love.image, or +nil+ when the module is not open.
  #
  # === Example
  #
  #   lota.image # => Lota::Image
  def self.image
    Image if Native::Image.open?
  end

  # Lota::Graphics, as love.graphics, or +nil+ when the module is not open.
  #
  # === Example
  #
  #   lota.graphics.clear(0, 0, 0)
  def self.graphics
    Graphics if Native::Graphics.open?
  end

  # Lota::Timer, as love.timer, or +nil+ when the module is not open.
  #
  # === Example
  #
  #   dt = lota.timer.step
  def self.timer
    Timer if Native::Timer.open?
  end

  # Lota::Event, as love.event, or +nil+ when the module is not open.
  #
  # === Example
  #
  #   lota.event.quit
  def self.event
    Event if Native::Event.open?
  end

  # Lota::Keyboard, as love.keyboard, or +nil+ when the module is not open.
  #
  # === Example
  #
  #   lota.keyboard.down?(:space)
  def self.keyboard
    Keyboard if Native::Keyboard.open?
  end

  # Lota::Mouse, as love.mouse, or +nil+ when the module is not open.
  #
  # === Example
  #
  #   lota.mouse.x
  def self.mouse
    Mouse if Native::Mouse.open?
  end

  # Lota::Math, as love.math, or +nil+ when the module is not open.
  #
  # === Example
  #
  #   lota.math.random(6)
  def self.math
    Math if Native::Math.open?
  end

  # Lota::Window, as love.window, or +nil+ when the module is not open.
  #
  # === Example
  #
  #   lota.window.title = "Asteroids"
  def self.window
    Window if Native::Window.open?
  end
end

# Ruby's Kernel, to which Lota adds one private method, +lota+.
module Kernel
  # Lota, from anywhere, as LÖVE's love table is everywhere in a LÖVE
  # game (ADR 003, section 4).
  #
  # It is private, as +puts+ and +require+ are, so it adds no method to
  # any object's public interface.
  #
  # === Examples
  #
  #   def lota.update(dt)
  #     @x += 100 * dt
  #   end
  #
  #   lota.graphics.clear(0, 0, 0)
  private def lota
    Lota
  end
end
