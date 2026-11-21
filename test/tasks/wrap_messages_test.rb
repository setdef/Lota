# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/bindings/binding_list"
require_relative "../../tasks/bindings/catalog"
require_relative "../../lib/lota/error_message"

# Every literal error message a function of LÖVE's wrap_*.cpp files
# raises is in Lota, or ext/lota/bindings.rb says, with the function's
# entry, why Lota never raises it (unraised:). LÖVE's behavior is matched
# "with what defaults and error messages" (AGENTS.md), and a message in
# LÖVE with none like it in Lota is a sign of a form Lota left out or of
# an error it raises in other words.
#
# The messages are read from vendor/love at the pinned commit: in each
# wrap function's body, with comments blanked, and in the bodies of the
# functions of its own file it calls, every luaL_error, luaL_argerror,
# luax_typerror, luaL_typerror, and luax_enumerror, and every throw of
# love::Exception, whose message is a string literal (adjacent literals
# joined). A message built at run time is not read. A function whose
# C++ LÖVE replaces with Lua (bound_from_lua) raises the Lua's messages,
# not its C++'s, so its C++ is not read.
#
# A message is in Lota when each of its pieces is somewhere in Lota's C++
# (ext/lota/native) or Ruby (lib), with a literal split across lines
# joined. Its pieces are the text between its printf conversions (%s,
# %d, %.2f), so "Shader uniform '%s' does not exist." is found as
# "Shader uniform '" and "' does not exist.", whatever Lota puts between
# them; a piece of fewer than two letters is not looked for. A piece may
# be spelled as LÖVE wrote it, or as Lota translates it: with a bare
# name of a function of its module in LÖVE's full notation (newSource,
# in love.audio, as love.audio.newSource), which ErrorMessage then
# translates to Lota's name (rule 23 of
# doc/contributors/design/translation.md); with LÖVE's type names as
# Lota's classes (SoundData as Lota::Sound::SoundData) and Lua's string
# as String; and either way as a double-quoted literal writes it, with
# \n for a newline. A message LÖVE ends with " expected" ("string or Data
# expected") is looked for without that word, since Ruby's TypeError
# puts it first ("expected String or Lota::Data"). The check is cheap and
# not exact: a piece found anywhere counts, so it catches a message Lota
# lacks, not one it raises in the wrong place.
class WrapMessagesTest < Minitest::Test
  LOVE = File.join(TreeHelper::ROOT, "vendor/love")

  # Messages known to be missing from Lota, by function and message, with
  # why each is still open. The check fails for a message named here
  # that Lota has since gained, so the list shrinks as each is settled.
  OPEN = {
    ["Source:queue", "SoundData or lightuserdata"] =>
      "Lota binds the SoundData form only; the translation rules do not say what Ruby passes for a light userdata",
  }.freeze

  # A LÖVE error call or throw whose message is a string literal, the
  # literal in :message.
  STRING = /"(?:[^"\\\n]|\\.)*"/
  ERROR = /
    \b(?:luaL_error\s*\(\s*L\s*,|luax_enumerror\s*\(\s*L\s*,|luaL_argerror\s*\(\s*L\s*,[^,;]+,|
    lua[xL]_typerror\s*\(\s*L\s*,[^,;]+,|throw\s+(?:love::)?Exception\s*\()\s*(?<message>(?:#{STRING}\s*)+)[,)]
  /x
  CALLED = /\b([A-Za-z_]\w*)\s*\(/
  CONVERSION = /%[-+ #0]*\d*(?:\.\d+)?(?:hh|h|ll|l|z|j|t|L)?[diouxXeEfgGcsp%]/

  # A message of +love_name+'s, at +location+ in LÖVE.
  class Message < Data.define(:love_name, :module_name, :text, :location)
  end

  def self.catalog
    @catalog ||= Bindings::Catalog.load(LOVE)
  end

  def self.list
    @list ||= Bindings::BindingList.load(File.join(TreeHelper::ROOT, "ext/lota/bindings.rb"))
  end

  # Every literal message a wrap function raises, but those of functions
  # LÖVE replaces with Lua.
  def self.messages
    @messages ||= begin
      lua = list.from_lua.to_set(&:love_name)
      catalog.functions.reject { |function| function.definition.nil? || lua.include?(function.love_name) }
        .flat_map { |function| messages_of(function) }.uniq
    end
  end

  def self.messages_of(function)
    file = function.wrap
    by_name = file.functions.to_h { |sibling| [sibling.name, sibling] }
    seen = {}
    queue = [function.definition]
    found = []
    while (body = queue.shift)
      next if seen[body.name]

      seen[body.name] = true
      body.body.to_enum(:scan, ERROR).each do
        match = Regexp.last_match
        text = match[:message].scan(STRING).map(&:undump).join
        line = file.source.line_of(body.body_offset + match.begin(0))
        found << Message.new(love_name: function.love_name, module_name: function.module_name, text:,
          location: "#{file.path}:#{line}")
      end
      body.body.scan(CALLED) { |(name)| queue << by_name[name] if by_name.key?(name) }
    end
    found
  end

  # Lota's C++ and Ruby, each literal split over lines joined.
  def self.lota
    @lota ||= Dir[File.join(TreeHelper::ROOT, "{ext/lota/native/**/*.{cpp,hpp,mm},lib/**/*.rb}")]
      .map { |path| File.read(path) }.join("\n").gsub(/"[ \t]*\\?[ \t]*\n\s*"/, "")
  end

  # LÖVE's type names and Lua's, each to the Ruby classes Lota may name
  # for it: a type to its class, from the names ErrorMessage gives LÖVE's
  # methods, by its name or that name in lowercase ("data" in File:write's
  # "string or data expected"); Lua's string to String; and Lua's number
  # to Integer, Float, or Numeric, by what the engine reads (rule 14).
  def self.classes
    @classes ||= Lota::ErrorMessage::NAMES.each_with_object({}) do |(love, ruby), classes|
      next unless love.include?(":") && ruby.include?("#")

      type = love.split(":").first
      classes[type] = classes[type.downcase] = [ruby.split("#").first]
    end.merge("string" => ["String"], "number" => %w[Integer Float Numeric])
  end

  # The module functions' names, by module.
  def self.module_functions
    @module_functions ||= catalog.functions.reject(&:type_name).group_by(&:module_name)
      .transform_values { |functions| functions.to_set(&:lua_name) }
  end

  # Whether every piece of +message+ is in Lota.
  def self.in_lota?(message)
    text = message.text.delete_suffix(" expected")
    text.split(CONVERSION).select { |piece| piece.scan(/[A-Za-z]/).size >= 2 }.all? do |piece|
      lota.include?(piece) || spellings(piece, message.module_name).any? { |spelling| lota.include?(spelling) }
    end
  end

  # The ways Lota may write +piece+ of a message of a function in +mod+.
  def self.spellings(piece, mod)
    names = module_functions.fetch(mod, Set.new)
    full = piece.gsub(/(?<![\w.:])[a-z]\w*(?![\w:]|\.\w)/) { |word| names.include?(word) ? "love.#{mod}.#{word}" : word }
    [piece, full].uniq.flat_map do |text|
      translated = Lota::ErrorMessage.translate(text)
      [text, translated, *Array.new(3) { |choice| classes_in(translated, choice) }]
    end.uniq.flat_map { |text| [text, text.inspect[1..-2]] }
  end

  # +text+ with each type name in it as the +choice+th class it may
  # become.
  def self.classes_in(text, choice)
    text.gsub(/(?<![\w:.])[A-Za-z]\w*(?![\w:])/) do |word|
      classes.fetch(word, [word]).then { |names| names[choice] || names.last }
    end
  end

  def self.unmatched
    @unmatched ||= messages.reject { |message| in_lota?(message) }
  end

  def test_every_message_a_wrap_function_raises_is_in_lota_or_excused
    missing = self.class.unmatched.reject do |message|
      self.class.list.unraised(message.love_name).key?(message.text) || OPEN.key?([message.love_name, message.text])
    end

    assert_empty missing.map { |message| "#{message.love_name}: #{message.text.inspect} (#{message.location})" },
      "LÖVE raises these messages, Lota has none like them, and ext/lota/bindings.rb excuses none of them"
  end

  def test_a_message_named_open_is_still_missing_from_lota
    missing = self.class.unmatched.map { |message| [message.love_name, message.text] }

    assert_empty OPEN.keys - missing, "Lota now has these messages, so OPEN need not name them"
  end

  def test_an_excused_message_is_one_its_function_raises_and_lota_lacks
    excused = self.class.list.love_names.uniq.flat_map do |love_name|
      self.class.list.unraised(love_name).keys.map { |text| [love_name, text] }
    end
    missing = self.class.unmatched.map { |message| [message.love_name, message.text] }

    assert_empty excused - missing, "ext/lota/bindings.rb excuses these, which LÖVE does not raise or Lota has"
  end

  def test_the_check_reads_lovees_messages_as_lovee_writes_them
    queue = self.class.messages.find { |message| message.love_name == "love.audio.newSource" && message.text.start_with?("Cannot") }

    assert_equal "Cannot create queueable sources using newSource. Use newQueueableSource instead.", queue.text
    assert_equal "src/modules/audio/wrap_Audio.cpp:60", queue.location
    assert_operator self.class.messages.size, :>, 500
  end
end
