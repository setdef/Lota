# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "error_message/names"

module Lota
  # LÖVE's error messages, with their Lua names translated (ADR 001,
  # section 7: "Error messages follow the same rules"). :nodoc:
  #
  # LÖVE's C++ throws love::Exception, whose message sometimes names a Lua
  # module ("love.image must be loaded in order to decode an ImageData.",
  # vendor/love/src/modules/image/ImageData.cpp:116), a module function
  # ("love.window.setMode cannot be called while a render target is active
  # in love.graphics.", vendor/love/src/modules/window/sdl/Window.cpp:477),
  # or a method ("ImageData:getPixel does not currently support the %s
  # pixel format.", ImageData.cpp:549). A Lota developer should never meet
  # a <tt>love.</tt> name, so every such message comes here before Ruby
  # raises it: Rice turns each C++ exception into a Ruby one in one place,
  # cpp_protect, after calling the handler ext/lota/native/errors.hpp
  # installs, and that handler hands a love::Exception's message to
  # ErrorMessage.translate and raises what it returns. It runs only when
  # the engine raises, so a call that succeeds never comes here.
  #
  # The names come from the binding generator's table (NAMES, in
  # error_message/names.rb), so a message names a function exactly as Lota
  # does. NAMES is deeply frozen, and translate keeps no state, so a
  # message raised in any Ractor translates there.
  module ErrorMessage
    # A module ("love.image"), a module function ("love.window.setMode"),
    # or a method ("ImageData:getPixel") in LÖVE's notation, where it
    # starts a word: after no letter, digit, or underscore, so "glove.x"
    # is left alone. A module is lowercase letters; a function after it
    # starts with a letter, so the full stop that ends a sentence ("active
    # in love.graphics.") is not taken for one; a type starts with a
    # capital and its method with a lowercase letter. Every class is ASCII,
    # matched byte by byte.
    NAME = /(?<![A-Za-z0-9_])(?:love\.([a-z]+)(?:\.([A-Za-z][A-Za-z0-9_]*))?|([A-Z][A-Za-z0-9_]*:[a-z][A-Za-z0-9_]*))/n

    # +message+ with every Lua name of LÖVE's API translated by ADR 001's
    # rules, and nothing else changed, in +message+'s encoding. A module,
    # "love.image", becomes "Lota::Image" (rule 1). A function,
    # "love.graphics.readbackTexture" or "ImageData:getPixel", becomes the
    # exact Ruby name the rules give it, "Lota::Graphics.readback_texture"
    # or "Lota::Image::ImageData#pixel", looked up in NAMES rather than
    # respelled here. A module function NAMES does not know keeps its
    # module's Ruby name and LÖVE's spelling after it, and a method it does
    # not know stays as LÖVE wrote it.
    #
    # The message is read as bytes, as the engine wrote them, so a file
    # name in it that is not valid UTF-8 passes through unchanged.
    def self.translate(message)
      message.b.gsub(NAME) { |name| translation(name) }.force_encoding(message.encoding)
    end

    # The Ruby name for +name+, a LÖVE name NAME matched.
    private_class_method def self.translation(name)
      return NAMES.fetch(name, name) if name.include?(":")

      _love, mod, function = name.split(".", 3)
      constant = "Lota::#{mod.to_s.capitalize}"
      return constant unless function

      NAMES.fetch(name) { "#{constant}.#{function}" }
    end
  end
end
