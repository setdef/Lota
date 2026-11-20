# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Restarts once, with its process id, while a sound plays, and quits with
# 3 from its second run, which saves a file and reads it back. Each run
# prints its process id, the value it restarted with, and whether this
# Ruby has loaded Shellwords, which the first run loads and nothing else
# does: a run in the same Ruby finds it, and one exec started does not.
# The second run also prints the App Sandbox container the system named
# in APP_SANDBOX_CONTAINER_ID, which Lota reads to restart in the process
# where exec cannot (Lota::Restart).
def Lota.load(_arguments)
  puts "run: #{Process.pid} #{Lota.restart.inspect} #{!defined?(Shellwords).nil?}"
  if Lota.restart.nil?
    require "shellwords"
    @source = Lota::Audio::Source.new(Lota::Sound::SoundData.new(4410, 44_100, 16, 1))
    @source.play
    return Lota::Event.restart(Process.pid)
  end

  puts "sandbox container: #{ENV.fetch('APP_SANDBOX_CONTAINER_ID', 'none')}"
  puts "fused: #{Lota::Filesystem.fused?}"
  stamp = "saved by #{Process.pid}"
  Lota::Filesystem.write("check.txt", stamp)
  directory = Lota::Filesystem.save_directory
  puts "save directory: #{directory}"
  puts "read back: #{File.read(File.join(directory, 'check.txt')) == stamp}"
  Lota::Event.quit(3)
end
