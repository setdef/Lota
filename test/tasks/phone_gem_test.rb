# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/phone_gem"

# PhoneGem builds a real gem with RubyGems from a small git repository of
# Lota's shape, and lays it out as a phone project's path gem, with the
# version of a release tag on the commit stamped in.
class PhoneGemTest < Minitest::Test
  include TreeHelper

  VERSION_RB = <<~RUBY
    module Lota
      VERSION = "0.0.1.dev"
    end
  RUBY

  GEMSPEC = <<~RUBY
    require_relative "lib/lota/version"

    Gem::Specification.new do |spec|
      spec.name = "lota"
      spec.version = Lota::VERSION
      spec.summary = "A gem of Lota's shape."
      spec.authors = ["Test"]
      spec.license = "AGPL-3.0-or-later"
      spec.homepage = "https://example.com"
      spec.required_ruby_version = ">= 3.4"
      spec.files = %w[lib/lota/version.rb]
    end
  RUBY

  LOCKFILE = <<~LOCK
    PATH
      remote: .
      specs:
        lota (0.0.1.dev)

    DEPENDENCIES
      lota!
  LOCK

  GIT = %w[git -c user.name=Test -c user.email=test@example.com].freeze

  # A clone of Lota's shape, committed, with its first commit tagged v0.5.2
  # and a second commit on top.
  def repository(root)
    write(root, "lib/lota/version.rb", VERSION_RB)
    write(root, "lota.gemspec", GEMSPEC)
    write(root, "Gemfile.lock", LOCKFILE)
    run!(root, "git", "init", "--quiet", "--initial-branch=trunk")
    run!(root, "git", "config", "maintenance.auto", "false")
    run!(root, "git", "config", "gc.auto", "0")
    commit(root, "chore: the release")
    release(root, "v0.5.2")
    write(root, "lib/lota/later.rb", "")
    commit(root, "feat: later")
  end

  def commit(root, message)
    run!(root, "git", "add", "--all")
    run!(root, *GIT, "commit", "--quiet", "-m", message)
  end

  # Tags HEAD as the release job does, with an annotated tag.
  def release(root, tag)
    run!(root, *GIT, "tag", "--annotate", tag, "-m", "Lota #{tag}")
  end

  # Yields a clone of Lota's shape and a folder beside it to lay out into.
  def in_clone
    in_tree do |dir|
      root = File.join(dir, "lota")
      repository(root)
      yield root, File.join(dir, "out")
    end
  end

  def test_a_clone_at_a_release_tag_lays_out_that_release_and_leaves_its_tree_as_it_was
    in_clone do |root, out|
      release(root, "v0.5.3")
      folder = PhoneGem.new(root:, out:).build

      assert_equal File.join(out, "lota"), folder
      assert_includes File.read(File.join(folder, "lib/lota/version.rb")), 'VERSION = "0.5.3"'
      assert_equal "0.5.3", Gem::Specification.load(File.join(folder, "lota.gemspec")).version.to_s
      assert_empty run!(root, "git", "status", "--porcelain")
    end
  end

  def test_a_clone_at_any_other_commit_lays_out_0_0_1_dev
    in_clone do |root, out|
      run!(root, "git", "tag", "v0.6.0-rc1")
      run!(root, "git", "tag", "other")
      folder = PhoneGem.new(root:, out:).build

      assert_includes File.read(File.join(folder, "lib/lota/version.rb")), 'VERSION = "0.0.1.dev"'
      assert_equal "0.0.1.dev", Gem::Specification.load(File.join(folder, "lota.gemspec")).version.to_s
    end
  end

  def test_a_build_again_leaves_nothing_of_the_last_one_in_the_folder
    in_clone do |root, out|
      write(out, "lota/stale.rb", "")

      refute_path_exists File.join(PhoneGem.new(root:, out:).build, "stale.rb")
    end
  end

  def test_a_build_that_fails_says_why_and_still_leaves_the_tree_as_it_was
    in_clone do |root, out|
      write(root, "lota.gemspec", GEMSPEC.sub("%w[lib/lota/version.rb]", "%w[lib/lota/version.rb missing.rb]"))
      commit(root, "fix: package a file that is not there")
      release(root, "v0.5.3")
      error = assert_raises(PhoneGem::Failure) { PhoneGem.new(root:, out:).build }

      assert_includes error.message, "missing.rb"
      assert_empty run!(root, "git", "status", "--porcelain")
    end
  end
end
