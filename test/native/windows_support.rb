# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# What the native suite does on Windows alone, where native_helper.rb
# loads this file.
module WindowsSupport
  # Starts +command+ as NativeHelper.spawn does. Ruby starts a process on
  # Windows with CreateProcess (win32/win32.c, CreateChild), never a fork,
  # and waits only for a process it started itself, so Process.spawn
  # starts it. The program goes as a pair of itself and its name, as
  # posix_spawnp takes it, so that Ruby never hands a command of one word,
  # such as a path with a space in it, to a shell to split.
  def self.spawn(command, output, variables)
    environment = variables.to_h { |variable| variable.split("=", 2) }
    program, *arguments = command
    Process.spawn(environment, [program, program], *arguments, unsetenv_others: true, in: File::NULL, out: output,
      err: output)
  end
end
