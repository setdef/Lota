# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "open3"
require "rbconfig"
require "rubygems/package"
require_relative "release"

# The folder of the files Lota's gem packages, which a phone project's
# Gemfile names as its lota gem (doc/guide/phones.md). A gem named by its
# path carries its whole folder into the app, so the folder holds the
# gem's files, unpacked, and not the clone's.
#
# A release's tag holds no stamped version, since a release commits none
# (doc/contributors/releasing.md). So a clone checked out at a release's
# tag builds its gem with that release's version stamped in, as CI stamps
# a release's gems (Release#stamp), and the clone's working tree is left
# as it was; Lota::VERSION in the app is then the release's. At any other
# commit, the gem is 0.0.1.dev, as every gem built from a clone is.
class PhoneGem
  # Raised when the gem cannot be built.
  class Failure < StandardError; end

  # The specification the gem is built from.
  GEMSPEC = "lota.gemspec"

  # [root] The clone.
  # [out] The folder to build the gem in, and to unpack it in as lota/.
  def initialize(root:, out:)
    @root = root
    @out = File.expand_path(out, root)
    @release = Release.new(root:)
  end

  # The version the gem carries: that of the newest release tag on the
  # clone's HEAD, or nil to leave the clone's own.
  def version
    @release.on("HEAD").last&.delete_prefix("v")
  end

  # Builds the gem and unpacks it, with its specification, in place of
  # any earlier one, as #folder. Returns the folder.
  def build
    gem = File.join(@out, "lota.gem")
    FileUtils.mkdir_p(@out)
    stamped { package(gem) }
    package = Gem::Package.new(gem)
    FileUtils.rm_rf(folder)
    package.extract_files(folder)
    File.write(File.join(folder, GEMSPEC), package.spec.to_ruby)
    folder
  end

  # The folder the gem unpacks to, which a phone project's Gemfile names.
  def folder
    File.join(@out, "lota")
  end

  # Yields with #version stamped into the working tree, if there is one,
  # and puts back afterward the files Release#stamp writes.
  private def stamped
    number = version
    return yield unless number

    kept = [Release::VERSION_FILE, Release::LOCKFILE].to_h { |path| [path, File.binread(File.join(@root, path))] }
    begin
      @release.stamp(number)
      yield
    ensure
      kept.each { |path, bytes| File.binwrite(File.join(@root, path), bytes) }
    end
  end

  # Builds +gem+ with gem build, outside the bundle rake may run in, as a
  # developer's own gem build in the clone runs.
  private def package(gem)
    command = [RbConfig.ruby, File.join(RbConfig::CONFIG["bindir"], "gem"), "build", GEMSPEC, "--output", gem]
    output, status = unbundled { Open3.capture2e(*command, chdir: @root) }
    raise Failure, "gem build #{GEMSPEC} failed:\n#{output}" unless status.success?
  end

  private def unbundled(&)
    defined?(Bundler) ? Bundler.with_unbundled_env(&) : yield
  end
end
