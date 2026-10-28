# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "rake/extensiontask"
require_relative "sanitized_build"

# rake compile builds ENGINE_BUILD (tasks/engine.rake): rake-compiler runs ext/lota/extconf.rb in
# tmp/<platform>/lota/native/<ruby>, then make, then make install into
# lib/lota (Plan 001, the walking skeleton).
NATIVE = Rake::ExtensionTask.new("lota/native") do |ext|
  ext.ext_dir = "ext/lota"
  ext.config_options = ["--with-cmake-build-dir=#{File.expand_path(ENGINE_BUILD)}", "--enable-native-test"]
end
NATIVE_TMP = "#{NATIVE.tmp_dir}/#{NATIVE.platform}/#{NATIVE.name}/#{RUBY_VERSION}".freeze
NATIVE_MAKEFILE = "#{NATIVE_TMP}/Makefile".freeze

namespace :engine do
  desc "Configure the engine build through extconf.rb (writes compile_commands.json)"
  task configure: NATIVE_MAKEFILE
end

# The engine links LÖVE's Linux dependencies (tasks/engine.rake), so it is
# configured again once they are built: a file task, so that a configure
# waits for them without running again when they are current.
DEPENDENCIES = (ENGINE_PLATFORM == "linux") ? [LINUX_BUILD.dependencies_stamp] : []
file NATIVE_MAKEFILE => DEPENDENCIES

# rake-compiler rebuilds the bundle only when a file it knows of changes,
# and it knows only C files directly under ext/lota. CMake knows every
# dependency, LÖVE's sources among them, and a build with nothing to do
# takes a moment, so make always runs: a task with no file behind it is
# always newer than the bundle.
task "compile:cmake"
file "#{NATIVE_TMP}/#{NATIVE.binary(NATIVE.platform)}" => "compile:cmake"

# rake test:native's tree: everything built with ASan and UBSan.
SANITIZED = SanitizedBuild.new(build: "tmp/sanitize/build")
SANITIZED_EXT = "tmp/sanitize/ext"
directory SANITIZED_EXT
file "#{SANITIZED_EXT}/Makefile" => [SANITIZED_EXT, "ext/lota/extconf.rb", *DEPENDENCIES] do
  ruby File.expand_path("ext/lota/extconf.rb"), "--with-cmake-build-dir=#{File.expand_path('tmp/sanitize/build')}",
    "--enable-native-test", "--enable-sanitizers", chdir: SANITIZED_EXT
end

namespace :compile do
  desc "Build Lota::Native and the test-only extension with ASan and UBSan"
  task sanitized: "#{SANITIZED_EXT}/Makefile" do
    sh "make", chdir: SANITIZED_EXT
  end
end
