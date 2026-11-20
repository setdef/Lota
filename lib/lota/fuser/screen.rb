# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "rbconfig"
require "tmpdir"
require_relative "../fuser"

module Lota
  class Fuser
    # What the fuser's window shows and does: it asks for a game in one
    # file, and makes each one dropped on it, or given to its program, into
    # an app in a process of its own (Fuser.main), so the window keeps
    # drawing while Fledge copies the fuser. Games dropped while one is
    # made wait their turn, one app at a time. It then shows where each app
    # went, or what stood in the way, as that process printed it.
    #
    # The words it shows are in WAITING, MAKING, QUEUED, MADE, and FAILED.
    #
    # === Example
    #
    #   screen = Lota::Fuser::Screen.new("Fuser.app/Contents/Resources/app")
    #   screen.drop("Sample Game.lota")
    #   screen.update
    #   screen.text # => "Making Sample Game.lota into an app..."
    class Screen
      # What the window says before anything is dropped on it.
      WAITING = "Drop a game in one file, a .lota, here to make it into an app of its own."

      # What the window says while it makes an app of the game in the file
      # named by %s.
      MAKING = "Making %s into an app..."

      # What the window says while %d more games wait to be made into apps.
      QUEUED = "%d more to make after it."

      # What the window says once it made an app of the file named by %s,
      # before the paths of what it wrote.
      MADE = "Made %s into an app:"

      # What the window says when it could not make an app of the file
      # named by %s, before what stood in the way.
      FAILED = "Could not make %s into an app:"

      # The screen of the fuser whose entry script is in the folder
      # +entry+. +command+ is what runs the making of an app, before the
      # archive's path: by default this app's program, through its Ruby,
      # given BUILD.
      def initialize(entry, command: nil)
        @entry = entry
        @command = command
        @log = nil #: String?
        @pid = nil #: Integer?
        @name = nil #: String?
        @queue = [] #: Array[String]
        @results = [] #: Array[String]
      end

      # What the window shows now: what came of each game dropped since the
      # window was last idle, then the one being made, and how many wait.
      def text
        return WAITING if @results.empty? && !@pid

        lines = @results.dup
        lines << format(MAKING, @name) if @pid
        lines << format(QUEUED, @queue.size) unless @queue.empty?
        lines.join("\n\n")
      end

      # Makes the game in the file at +path+ into an app: at once, or after
      # the games dropped before it.
      def drop(path)
        @results = [] if idle?
        @queue << File.expand_path(path)
        start unless @pid
      end

      # Notes whether the app being made is done, and what came of it, and
      # starts on the next game waiting.
      def update
        pid = @pid
        return unless pid

        done, status = Process.wait2(pid, Process::WNOHANG)
        return unless done && status

        finish(status)
        start
      end

      # Whether no game is being made or waits to be.
      private def idle?
        @pid.nil? && @queue.empty?
      end

      # Starts making the first game waiting into an app, if one waits.
      private def start
        path = @queue.shift
        return unless path

        @name = File.basename(path)
        log = File.join(Dir.mktmpdir("lota-fuser-log-"), "output.txt")
        program, *arguments = command
        @log = log
        @pid = File.open(log, "w") do |file|
          spawn(program.to_s, *arguments, path, in: File::NULL, out: file, err: file)
        end
      end

      # Notes what the process that made the app printed, after the words
      # its +status+ calls for.
      private def finish(status)
        log = @log.to_s
        output = File.read(log).lines(chomp: true).reject(&:empty?)
        FileUtils.rm_rf(File.dirname(log))
        @pid = nil
        @results << [format(status.success? ? MADE : FAILED, @name), *output].join("\n")
      end

      # The command that makes an app, before the archive's path.
      private def command
        @command || [ruby, File.join(@entry, "main.rb"), BUILD]
      end

      # This app's Ruby, which runs the app's own program again when given
      # its entry script: on Windows its windowed Ruby, so no console opens.
      private def ruby
        windowed = File.join(RbConfig::CONFIG["bindir"], "rubyw.exe")
        (Gem.win_platform? && File.file?(windowed)) ? windowed : RbConfig.ruby
      end
    end
  end
end
