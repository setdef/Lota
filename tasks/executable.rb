# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "rbconfig"

# Where a command is on PATH, as ext/lota/extconf.rb's find_executable
# finds it.
module Executable
  # The first file named +name+ (or +name+ with Windows' .exe) on +env+'s
  # PATH that may be run, or nil.
  def self.find(name, env = ENV)
    names = [name, "#{name}#{RbConfig::CONFIG['EXEEXT']}"].uniq
    env.fetch("PATH", "").split(File::PATH_SEPARATOR).product(names).map { |dir, file| File.join(dir, file) }
      .find { |path| File.executable?(path) && !File.directory?(path) }
  end
end
