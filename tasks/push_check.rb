# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "open3"

# The checks the pre-push hook runs over the commits it pushes (rake
# push_check[RANGE]): those that take seconds, build nothing, and do the
# same on Linux, macOS, and Windows, so a push is checked alike wherever
# its hook runs. They show the commits broke nothing they reach; CI's
# pre-push tier (rake prepush) and the gate check the rest after the push.
#
# In order: each commit's Provenance: trailer (tasks/provenance.rb),
# RuboCop over the files the commits change (or over every file git
# knows, when they change RuboCop's settings or its gems), the unit
# tests, the licensing of every file git knows, Steep when they change
# typed code or its signatures, and red_before_green over the unit tests
# they add or change. The provenance, the unit tests, and the licensing
# always run, so a push is never let through having checked nothing.
class PushCheck
  # One check: the rake task, or RuboCop, by +name+, with the +files+
  # RuboCop inspects.
  class Step < Data.define(:name, :files)
    def self.new(name:, files: []) = super
  end

  # A change that can change what Steep finds.
  TYPED = %r{\A(?:lib/|sig/|Steepfile\z|rbs_exceptions\.rb\z|Gemfile\.lock\z)}

  # A change that can change what RuboCop finds in a file that did not
  # change: its settings, Lota's own cops, or its gems.
  LINT_SETTINGS = %r{\A(?:\.rubocop\.yml\z|lib/lota/rubocop(?:/|\.rb\z)|Gemfile\.lock\z)}

  # The paths the commits of +range+ change, and leave in place, in the
  # checkout at +root+.
  def self.changes(root, range)
    git(root, "diff", "--name-only", "-z", "--diff-filter=d", range).split("\0")
  end

  # The paths of the files git knows in the checkout at +root+, tracked
  # or staged.
  def self.known(root) = git(root, "ls-files", "-z", "--cached").split("\0")

  private_class_method def self.git(root, *args)
    output, status = Open3.capture2("git", "-c", "core.quotePath=false", *args, chdir: root)
    raise ArgumentError, "git #{args.first} failed in #{root}" unless status.success?

    output
  end

  # [range] The commits, as git rev-list takes them.
  # [changed] The paths they change and leave in place.
  # [known] The paths git knows.
  def initialize(range:, changed:, known:)
    @range = range
    @changed = changed
    @known = known
  end

  # The checks, in the order they run. RuboCop runs only when there is a
  # file for it, since given none it would inspect every file there.
  def steps
    [
      Step.new(name: "provenance[#{@range}]"),
      *(Step.new(name: "rubocop", files: linted) unless linted.empty?),
      Step.new(name: "test:unit"),
      Step.new(name: "reuse:lint"),
      *(Step.new(name: "steep") if @changed.any? { |path| path.match?(TYPED) }),
      Step.new(name: "red_before_green:unit[#{@range}]"),
    ]
  end

  # Runs each check with +perform+, which answers whether it passed, and
  # says on +out+ how long each took, stopping at the first that fails.
  # Answers whether every check passed. +clock+ answers the time in
  # seconds, with #next.
  def run(out:, clock:, &perform)
    steps.all? do |step|
      out.puts "push_check: #{step.name}#{" (#{step.files.size} files)" if step.name == 'rubocop'}"
      started = clock.next
      passed = perform.call(step)
      out.puts "push_check: #{step.name} #{passed ? 'passed' : 'failed'} in #{format('%.1f', clock.next - started)}s"
      passed
    end
  end

  # What RuboCop inspects: every file git knows when the commits change
  # its settings, else the files they change that git knows. RuboCop
  # itself, with --force-exclusion, keeps only its own targets among them.
  private def linted
    (@changed.any? { |path| path.match?(LINT_SETTINGS) }) ? @known : @changed & @known
  end
end
