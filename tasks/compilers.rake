# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "compiler_stamp"

# Before any task runs: on Linux, tmp/ builds from scratch, once, when the
# compilers that built it changed (CompilerStamp).
if RUBY_PLATFORM.include?("linux")
  which = lambda do |name|
    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |dir| File.join(dir, name) }
      .find { |path| File.executable?(path) && !File.directory?(path) }
  end
  CompilerStamp.new(
    tmp: File.expand_path("../tmp", __dir__),
    compilers: CompilerStamp.describe(ENV, which:, version: CompilerStamp.method(:version))
  ).refresh
end
