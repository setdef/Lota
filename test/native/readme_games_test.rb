# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require "fileutils"
require "rbconfig"
require "tmpdir"
require "zlib"

# The games the README shows, run as a reader runs them: with lota run, in a
# window, from the files the README gives. A fenced Ruby block whose first
# line names a file (# main.rb) is that file of the game its section shows;
# a section with a main.rb is a game. If a snippet stops working, or the
# README stops showing a game, this fails.
#
# The harness adds to the end of main.rb. On its second frame it calls the
# game's keypressed and mousepressed callbacks as the engine would, then
# asks to quit, so no one has to press a key. A game that raises shows the
# error screen, which QuitOnError ends.
class ReadmeGamesTest < Minitest::Test
  include NativeHelper
  extend NativeHelper

  README = File.join(ROOT, "README.md")

  # Quits a game's error screen once it is up (quit_on_error.rb).
  QUIT_ON_ERROR = File.expand_path("quit_on_error.rb", __dir__)

  # A game the README shows: the heading of its section and its files.
  Game = Data.define(:heading, :files)

  # Appended to main.rb. Prints what the game saved as its quit callback
  # returns, while the filesystem is still open.
  HARNESS = <<~RUBY

    # harness
    frames = 0
    drawn = Lota.method(:draw)
    Lota.define_singleton_method(:draw) do
      drawn.call
      frames += 1
      next unless frames == 2

      Lota::Callbacks.call(:mousepressed, 10, 10, 1, false, 1)
      Lota::Callbacks.call(:keypressed, :escape, :escape, false)
      Lota::Event.quit
    end
    quit = Lota.respond_to?(:quit) ? Lota.method(:quit) : nil
    Lota.define_singleton_method(:quit) do |*arguments|
      result = quit&.call(*arguments)
      directory = Lota::Filesystem.save_directory
      puts "saved in \#{directory}"
      Dir.glob(File.join(directory, "*")).each { |path| puts "saved \#{File.basename(path)}: \#{File.read(path)}" }
      result
    end
  RUBY

  # What each game printed and how it ended, by heading. Each game runs
  # once, for every test.
  def self.runs
    @runs ||= games.to_h do |game|
      [game.heading, Dir.mktmpdir("readme-game-") { |parent| play(game, parent) }]
    end
  end

  # Each game the README shows, in order.
  def self.games
    @games ||= File.read(README).split(/^(?=\#{2,3} )/).filter_map do |section|
      files = section.scan(/^\x60{3}ruby\n# (\w+\.rb)\n(.*?)^\x60{3}$/m).to_h
      Game.new(heading: section[/\A#+ (.*)$/, 1], files:) if files.key?("main.rb")
    end
  end

  # Runs +game+ in a folder under +parent+, named for the parent so that
  # its save folder is its own, and returns its output and Process::Status.
  def self.play(game, parent)
    folder = File.join(parent, File.basename(parent))
    write(game, folder)
    output, status = lota_run(folder)
    saved = output[/^saved in (.*)$/, 1]
    FileUtils.rm_rf(saved) if saved
    [output, status]
  end

  # Writes the game's files, the assets its snippets load, and the harness.
  def self.write(game, folder)
    FileUtils.mkdir_p(File.join(folder, "images"))
    FileUtils.mkdir_p(File.join(folder, "sounds"))
    File.binwrite(File.join(folder, "images/ship.png"), png)
    File.binwrite(File.join(folder, "sounds/laser.wav"), wav)
    game.files.each do |name, source|
      File.write(File.join(folder, name), (name == "main.rb") ? source + HARNESS : source)
    end
  end

  # A 2 by 2 white PNG.
  def self.png
    chunk = lambda do |type, data|
      [data.bytesize].pack("N") + type + data + [Zlib.crc32(type + data)].pack("N")
    end
    rows = (["\x00".b + ("\xFF".b * 8)] * 2).join
    "\x89PNG\r\n\x1A\n".b + chunk.call("IHDR".b, [2, 2, 8, 6, 0, 0, 0].pack("NNCCCCC")) +
      chunk.call("IDAT".b, Zlib::Deflate.deflate(rows)) + chunk.call("IEND".b, "".b)
  end

  # A tenth of a second of silence: 16-bit mono PCM at 8000 hertz.
  def self.wav
    samples = "\x00\x00".b * 800
    "RIFF".b + [36 + samples.bytesize].pack("V") + "WAVEfmt ".b + [16, 1, 1, 8000, 16_000, 2, 16].pack("VvvVVvv") +
      "data".b + [samples.bytesize].pack("V") + samples
  end

  # Runs <tt>lota run</tt> on +folder+ and returns its output and
  # Process::Status, as test/native/lota_run_test.rb does.
  def self.lota_run(folder)
    native = File.dirname(File.dirname(loaded("lota/native")))
    native_test = File.dirname(loaded("lota_native_test"))
    load_path = [native, File.join(ROOT, "lib"), native_test].uniq.join(File::PATH_SEPARATOR)
    capture2e({}, RbConfig.ruby, "-w", "-I#{load_path}", "-r#{QUIT_ON_ERROR}", File.join(ROOT, "exe/lota"), "run", folder)
  end

  def test_the_readme_shows_a_first_game_and_a_larger_one
    games = self.class.games

    assert_operator games.size, :>=, 2, "the README should show at least two games"
    assert_includes games.first.files.keys, "conf.rb"
  end

  def test_every_game_in_the_readme_runs_and_quits
    self.class.runs.each do |heading, (output, status)|
      assert_predicate status, :success?, "#{heading} failed:\n#{output}"
      refute_includes output, "error screen", "#{heading} raised:\n#{output}"
    end
  end

  def test_the_first_game_reports_its_window
    output, = self.class.runs.values.first

    assert_match(/^window \d+x\d+$/, output)
  end

  def test_the_larger_game_saves_the_shots_it_fired
    output, = self.class.runs.values.last

    assert_includes output, "saved shots.txt: 1", "the click should be saved:\n#{output}"
  end

  def test_a_snippet_that_raises_is_caught
    game = Game.new(heading: "planted", files: { "main.rb" => "def Lota.draw = raise('planted')\n" })
    output, status = Dir.mktmpdir("readme-game-") { |parent| self.class.play(game, parent) }

    refute_predicate status, :success?
    assert_includes output, "planted"
  end
end
