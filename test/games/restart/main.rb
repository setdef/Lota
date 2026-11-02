# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Appends what each run sees to the file named by LOTA_RESTART_LOG. The
# first run restarts with the value its first argument names, and the
# second quits with status 3, so the log tells what crossed. An argument of
# "never" quits at once, and "extra" restarts with several values, of
# which only the first crosses.
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
  "none" => [],
}.freeze

def Lota.load(arguments)
  @arguments = arguments
  @second = File.exist?(LOG)
  log("load pid=#{Process.pid} arguments=#{arguments.inspect} restart=#{Lota.restart.inspect} " \
    "variable=#{ENV.key?('LOTA_RESTART_VALUE')} verbose=#{$VERBOSE.inspect}")
  at_exit { log("at_exit pid=#{Process.pid}") }
end

def Lota.draw
  if @arguments.first == "never"
    Lota::Event.quit(0)
  elsif @second
    Lota::Event.quit(3)
  else
    Lota::Event.restart(*VALUES.fetch(@arguments.first, []))
  end
end
