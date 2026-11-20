# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "rubygems/package"
require_relative "tree_helper"
require_relative "../../tasks/release"

# A release publishes Lota's source gem beside its precompiled ones, built
# once its phone engines are, with their checksums pinned in it for that
# release, so a phone build from the gem alone fetches the engines the
# release published: Release#add_source_gem builds it from the working
# tree, stamped with the release's version, checks it, and lists it in
# the release's SHA256SUMS. The gemspec lists files with git ls-files and
# the gem's install runs extconf.rb, so these are integration tests.
class ReleaseSourceGemTest < Minitest::Test
  include TreeHelper

  ENGINES = Lota::PhoneEngine::TARGETS.map { |target| Lota::PhoneEngine.asset(target) }

  # A clone of the files the source gem is built from, as git tracks them:
  # the real gemspec, README.rdoc, the executable it names, extconf.rb, and
  # phone/engine.rb, and a version file and lockfile at 0.0.1.dev.
  def clone(root)
    %w[lota.gemspec README.rdoc exe/lota ext/lota/extconf.rb ext/lota/phone/engine.rb].each do |path|
      write(root, path, File.read(File.join(ROOT, path)))
    end
    write(root, "lib/lota/version.rb", "module Lota\n  VERSION = \"0.0.1.dev\"\nend\n")
    write(root, "Gemfile.lock", "PATH\n  remote: .\n  specs:\n    lota (0.0.1.dev)\n")
    git_stage(root)
    root
  end

  # The folder Release#add_engines leaves: a gem and the engines, each
  # with its line in SHA256SUMS.
  def release(root)
    names = ["lota-0.4.0-arm64-darwin.gem", *ENGINES]
    names.each { |name| write(root, "release/#{name}", name) }
    write(root, "release/SHA256SUMS", names.sort.map { |name| "#{Digest::SHA256.hexdigest(name)}  #{name}\n" }.join)
    File.join(root, "release")
  end

  def test_add_source_gem_builds_the_stamped_gem_with_the_releases_engines_pinned_and_lists_it
    in_tree do |root|
      repository = Release.new(root: clone(File.join(root, "clone")))
      repository.stamp("0.4.0")
      dir = release(root)
      before = Lota::PhoneEngine.sums(File.read(File.join(dir, "SHA256SUMS")))

      assert_equal "lota-0.4.0.gem", repository.add_source_gem(dir, "0.4.0")

      package = Gem::Package.new(File.join(dir, "lota-0.4.0.gem"))
      assert_equal ["lota", "0.4.0", "ruby"], [package.spec.name, package.spec.version.to_s, package.spec.platform.to_s]
      assert_includes package.spec.files, "ext/lota/phone/engines.txt"
      package.extract_files(File.join(root, "unpacked"))
      pin = Lota::PhoneEngine.pin(File.read(File.join(root, "unpacked/ext/lota/phone/engines.txt")))
      assert_equal "v0.4.0", pin.release
      assert_equal before.slice(*ENGINES), pin.sums
      sums = Lota::PhoneEngine.sums(File.read(File.join(dir, "SHA256SUMS")))
      assert_equal before.merge("lota-0.4.0.gem" => Digest::SHA256.file(File.join(dir, "lota-0.4.0.gem")).hexdigest), sums
    end
  end

  def test_add_source_gem_refuses_a_working_tree_not_stamped_with_the_version
    in_tree do |root|
      repository = Release.new(root: clone(File.join(root, "clone")))
      dir = release(root)

      error = assert_raises(Release::Refusal) { repository.add_source_gem(dir, "0.4.0") }

      assert_match(/0\.0\.1\.dev, not 0\.4\.0/, error.message)
      refute_path_exists File.join(dir, "lota-0.4.0.gem")
    end
  end

  def test_add_source_gem_refuses_a_gem_that_would_install_on_this_computer
    in_tree do |root|
      repository = Release.new(root: clone(File.join(root, "clone")))
      File.write(File.join(root, "clone/ext/lota/extconf.rb"), "File.write(\"Makefile\", \"all:\\ninstall:\\n\")\n")
      repository.stamp("0.4.0")
      dir = release(root)

      error = assert_raises(Release::Refusal) { repository.add_source_gem(dir, "0.4.0") }

      assert_match(/installed/, error.message)
      refute_includes File.read(File.join(dir, "SHA256SUMS")), "lota-0.4.0.gem"
    end
  end
end
