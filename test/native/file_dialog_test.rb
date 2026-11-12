# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"
require "json"
require "tmpdir"

# Lota::Window.show_file_dialog, love.window.showFileDialog
# (src/modules/window/wrap_Window.cpp:655-757). LÖVE hands the request to
# SDL's file dialog and returns at once. SDL calls back from whichever
# thread answered the dialog; LÖVE copies the answer into an event of its
# own, and calls the game's function when the event pump reaches it, on
# the main thread (src/modules/window/sdl/Window.cpp:1498-1558,
# src/modules/event/sdl/Event.cpp:273-280).
#
# Every platform's SDL checks the filters before it shows anything, and
# answers a pattern it refuses with an error, through the same callback
# (SDL 3.4.10, src/dialog/SDL_dialog.c, SDL_ShowFileDialogWithProperties),
# so a refused pattern reaches the game's block through the whole path
# with no dialog shown. On Linux SDL shows the dialog with zenity when
# SDL_FILE_DIALOG_DRIVER says so (src/dialog/unix/SDL_unixdialog.c), and a
# program that answers as zenity does, test/native/zenity/zenity, stands
# in for the person choosing (FakeZenity below).
class FileDialogTest < Minitest::Test
  include NativeHelper

  # SDL's message for a pattern with a character it refuses
  # (src/dialog/SDL_dialog_utils.c, validate_list), after the words
  # SDL_ShowFileDialogWithProperties puts in front.
  REFUSED_PATTERN = "Invalid dialog file filters: Invalid character in pattern " \
    "(Only [a-zA-Z0-9_.-] allowed, or a single *)"

  def setup
    EngineHelper.open_window
    Lota::Event.pump
    Lota::Event.clear
  end

  def teardown
    Lota::Event.clear
  end

  # The answer waits for the event pump, as LÖVE's callback does, and
  # brings no files, no filter, and SDL's error.
  def test_the_answer_reaches_the_block_when_the_events_are_pumped
    answers = []
    result = Lota::Window.show_file_dialog(:openfile, filters: { "Images" => "*.png" }) do |files, filter, error|
      answers << [files, filter, error]
    end

    assert_nil result
    assert_empty answers
    Lota::Event.pump

    assert_equal [[[], nil, REFUSED_PATTERN]], answers
  end

  # Rule 31 of doc/contributors/design/translation.md: a function LÖVE keeps
  # to call later can be anything that answers call, which receives as many
  # of the answer's three values as it declares (doc/contributors/design/
  # game.md).
  def test_any_callable_takes_the_answer_and_as_many_values_as_it_declares
    files_only = []
    Lota::Window.show_file_dialog(:savefile, -> (files) { files_only << files }, filters: { "Text" => "t?t" })
    everything = []
    Lota::Window.show_file_dialog(:openfolder, -> (*answer) { everything << answer }, filters: { "A" => "a;" })
    Lota::Event.pump

    assert_equal [[]], files_only
    assert_equal [[[], nil, "Invalid dialog file filters: Empty pattern not allowed"]], everything
  end

  # fileDialogCallback (wrap_Window.cpp:655-686) turns an error in the
  # game's function into one that comes out of the pump.
  def test_an_error_in_the_block_comes_out_of_the_pump
    Lota::Window.show_file_dialog(:openfile, filters: { "Images" => "*.png" }) { raise "no thanks" }

    error = assert_raises(RuntimeError) { Lota::Event.pump }
    assert_match(/\AError in file dialog callback: .*no thanks/, error.message)
  end

  # The callable is held until the answer comes, though Ruby holds it no
  # longer.
  def test_the_callable_outlives_every_reference_ruby_had_to_it
    answers = []
    on_a_finished_fiber do
      Lota::Window.show_file_dialog(:openfile, -> (_files, _filter, error) { answers << error }, filters: { "X" => "*" * 2 })
    end
    collect_garbage
    Lota::Event.pump

    assert_equal [REFUSED_PATTERN], answers
  end

  # w_showFileDialog checks the type, then the function, then each option
  # as it reads it (wrap_Window.cpp:688-757).
  def test_the_arguments_are_checked_in_loves_order_before_anything_is_shown
    error = assert_raises(ArgumentError) { Lota::Window.show_file_dialog(:openfiles) }
    assert_equal "Invalid file dialog type 'openfiles', expected one of: 'openfile', 'openfolder', 'savefile'",
      error.message

    assert_raises(TypeError) { Lota::Window.show_file_dialog(:openfile) }
    assert_raises(TypeError) { Lota::Window.show_file_dialog(:openfile, "file.txt") }
    assert_raises(ArgumentError) { Lota::Window.show_file_dialog(:openfile, -> {}) { nil } }
    assert_raises(TypeError) { Lota::Window.show_file_dialog(:openfile, title: 1) { nil } }
    assert_raises(TypeError) { Lota::Window.show_file_dialog(:openfile, filters: [%w[Text txt]]) { nil } }
    assert_raises(TypeError) { Lota::Window.show_file_dialog(:openfile, filters: { text: "txt" }) { nil } }
    assert_raises(TypeError) { Lota::Window.show_file_dialog(:openfile, multiselect: 1) { nil } }
    assert_raises(TypeError) { Lota::Window.show_file_dialog(:openfile, attachtowindow: "yes") { nil } }
    Lota::Event.pump
  end

  # Each option reaches zenity's command line as SDL writes it
  # (src/dialog/unix/SDL_zenitydialog.c, create_zenity_args), and what
  # zenity prints is what the block receives. LÖVE attaches the dialog to
  # the window only when asked (FileDialogData starts zeroed,
  # wrap_Window.cpp:690). zenity names no filter, so the filter is nil.
  def test_on_linux_each_option_reaches_zenity_and_its_answer_reaches_the_block
    skip "SDL shows its own dialogs on #{RUBY_PLATFORM}, which no program of the tests answers" unless TestHome::LINUX

    saved = "/tmp/Sample Game/save 1.txt"
    answers, calls = FakeZenity.answer(self, picks: %w[/srv/a.png /srv/b.png], dialogs: [
      [
        "savefile",
        {
        title: "Save",
        acceptlabel: "Keep",
        cancellabel: "Back",
        defaultname: saved,
        filters: { "Text" => "txt;md", "All files" => "*" },
        attachtowindow: true,
},
],
      ["openfile", { multiselect: true }],
    ])

    assert_equal [[[saved], nil, nil], [%w[/srv/a.png /srv/b.png], nil, nil]], answers
    save, open = calls
    window = save[save.index("--attach") + 1]

    assert_match(/\A0x\h+\z/, window)
    assert_equal [
      "--file-selection",
      "--separator=\n",
      "--save",
      "--confirm-overwrite",
      "--filename",
      saved,
      "--modal",
      "--attach",
      window,
      "--title",
      "Save",
      "--ok-label",
      "Keep",
      "--cancel-label",
      "Back",
      "--file-filter=Text | *.[tT][xX][tT] *.[mM][dD]",
      "--file-filter=All files | *.*",
], save
    assert_equal ["--file-selection", "--separator=\n", "--multiple"], open
  end

  # A person who cancels zenity makes it print nothing and exit with 1,
  # which SDL reads as a list of one empty name, and LÖVE passes on; Lota
  # leaves the empty name out, so a cancelled dialog chose no files, as
  # SDL documents (doc/contributors/upstream/027.md).
  def test_on_linux_cancelling_zenity_chooses_no_files
    skip "SDL shows its own dialogs on #{RUBY_PLATFORM}, which no program of the tests answers" unless TestHome::LINUX

    answers, calls = FakeZenity.answer(self, picks: [], dialogs: [["openfolder", {}]])

    assert_equal [[[], nil, nil]], answers
    assert_equal [["--file-selection", "--separator=\n", "--directory"]], calls
  end

  # Runs show_file_dialogs.rb in a Ruby of its own, whose SDL shows its
  # file dialogs with test/native/zenity/zenity, which answers each with
  # +picks+, or cancels it when +picks+ is empty, and returns what each
  # dialog's block received and each command line zenity was given, less
  # the program's name.
  module FakeZenity
    FOLDER = File.expand_path("zenity", __dir__)
    SCRIPT = File.expand_path("show_file_dialogs.rb", __dir__)

    def self.answer(test, picks:, dialogs:)
      Dir.mktmpdir do |directory|
        log = File.join(directory, "zenity.log")
        output, status = test.ruby_of_its_own(SCRIPT, JSON.generate(dialogs), timeout: 60, environment: {
          "PATH" => [FOLDER, ENV.fetch("PATH")].join(File::PATH_SEPARATOR),
          "SDL_FILE_DIALOG_DRIVER" => "zenity",
          "LOTA_ZENITY_LOG" => log,
          "LOTA_ZENITY_PICKS" => picks.map { |pick| "#{pick}\n" }.join,
        })
        test.assert_predicate status, :success?, output
        answers = output.lines.grep(/\A\[/).map { |line| JSON.parse(line) }
        [answers, File.binread(log).force_encoding(Encoding::UTF_8).split("\x1E").map { |call| call.split("\0") }]
      end
    end
  end
end
