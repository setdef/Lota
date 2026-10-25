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
