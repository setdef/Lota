# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Appends what each run sees to the file named by LOTA_RESTART_LOG. The
# first run restarts with the value its first argument names, and the
# second quits with status 3, so the log tells what crossed. An argument of
# "never" quits at once, and "extra" restarts with several values, of
# which only the first crosses. A first argument of "chain" restarts once
# for each argument after it, the Nth run with the value the Nth names,
# and the run after the last quits with status 3, so one lota run carries
# every value across a restart of its own. With LOTA_RESTART_WINDOW set
# it also logs whether the window is open and when Lota closes it. A run
# given no arguments takes its first from LOTA_RESTART_ARGUMENT, so that a
# program that starts the game with none can restart it too.
LOG = ENV.fetch("LOTA_RESTART_LOG")

def log(line)
  File.open(LOG, "a") { |file| file.puts(line) }
end

VALUES = {
  "nil" => [nil],
  "true" => [true],
  "false" => [false],
  "number" => [2.5],
  "integer" => [7],
  "string" => ["café\nline"],
  "symbol" => [:name],
  "empty" => [""],
  "binary" => ["\xff\x00".b],
  "extra" => ["first", 2, true],
  "table" => [[1, { name: :ada }]],
  "none" => [],
}.freeze

def Lota.load(arguments)
  @arguments = arguments.empty? ? [*ENV.fetch("LOTA_RESTART_ARGUMENT", nil)] : arguments
  @run = File.exist?(LOG) ? File.readlines(LOG).count { |line| line.start_with?("load ") } + 1 : 1
  log("load pid=#{Process.pid} arguments=#{arguments.inspect} restart=#{Lota.restart.inspect} " \
    "variable=#{ENV.key?('LOTA_RESTART_VALUE')} verbose=#{$VERBOSE.inspect} ruby_runs=#{ruby_runs}")
  at_exit { log("at_exit pid=#{Process.pid}") }
  log("window module=#{Lota::Native::Window.open?} shown=#{shown?}")
  Lota::Native::Window.singleton_class.prepend(LogClose) if ENV.key?("LOTA_RESTART_WINDOW")
end

# How many runs of the game this Ruby has seen, when the test loaded
# RestartMarker into it before the game (in_process_restart_test.rb): one
# for each run in the same process, and always 1 when each run is a Ruby
# of its own.
def ruby_runs
  defined?(RestartMarker) ? RestartMarker.count : "none"
end

# Logs a close of the window, which Lota::Restart makes after the exit
# procs and before the process is replaced.
module LogClose
  def close(*)
    log("close was_shown=#{shown?}")
    super.tap { log("closed shown=#{shown?}") }
  end
end

# Whether the window is open: false until it opens and after it closes.
def shown?
  Lota::Native::Window.open? && Lota::Native::Window.window_open?
end

# Not draw, which runs only with a window.
def Lota.update(_dt)
  names = (@arguments.first == "chain") ? @arguments.drop(1) : @arguments.first(1)
  if @arguments.first == "never"
    Lota::Event.quit(0)
  elsif @run > names.size
    Lota::Event.quit(3)
  else
    Lota::Event.restart(*VALUES.fetch(names.fetch(@run - 1), []))
  end
end
