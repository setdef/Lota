# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Declared lint exceptions with justifications.
#
# A line-based lint names each approved line by its text, never by its
# number, so an edit elsewhere in the file leaves the approval standing:
# +at+ is the line that matches the lint, and +covers+ the line of code
# it stands for, both stripped; that is the same line unless the lint
# says otherwise, as cpp:no_nolint does (CppGates.covered). Each approval
# covers one line, so a second copy of an approved line needs an approval
# of its own, and an approval whose line is gone, or whose code changed,
# fails the lint as an unapproved line does.
class Lint
  # One approved line: its file, its text, and the text of the line it
  # covers.
  class Approval < Data.define(:path, :at, :covers); end

  # The line a matching line covers, by default itself: given a file's
  # lines and the index of the line that matched, the index of the line
  # it stands for.
  SAME_LINE = -> (_lines, index) { index }

  def self.load(path) = new(path)

  def initialize(path)
    @path = path
    instance_eval(File.read(path))
  end

  # Records an exception. A line-based lint keys it by path, the line's
  # text +at+, and the text of the line it +covers+ (by default the same
  # line); a lint over named things (lint: :rbs_parity) keys it by name
  # alone.
  def allow(path, reason:, at: nil, covers: nil, lint: nil)
    return named(lint) << path if lint
    raise ArgumentError, "#{@path}: the exception for #{path} names no line (at:)" unless at

    list << Approval.new(path:, at: at.strip, covers: (covers || at).strip)
  end

  # The exact keys allowed for a named lint.
  def keys(lint:)
    named(lint).dup
  end

  # Enforce no violations. Aborts with message if any found, otherwise prints success.
  def enforce!(glob:, pattern:, violation_name:, reject_pattern: nil, covers: SAME_LINE)
    found = violations(glob:, pattern:, reject_pattern:, covers:)

    abort <<~ERROR if found.any?
      ❌ Unapproved #{violation_name} found:
      #{found.join("\n")}

      Add to #{File.basename(@path)} with justification if truly unavoidable,
      and remove an approval whose line is gone.
    ERROR

    puts "✅ No unapproved #{violation_name} found"
  end

  # Each line that matches +pattern+, and not +reject_pattern+, in the
  # files +glob+ finds, that no approval covers; then each approval that
  # covered no such line.
  def violations(glob:, pattern:, reject_pattern: nil, covers: SAME_LINE)
    unused = list.dup
    unapproved = Dir.glob(glob).reject { |f| f.include?("/target/") }.flat_map do |file|
      lines = File.readlines(file)
      lines.each_index.filter_map do |index|
        line = lines[index]
        next unless pattern.match?(line) && !reject_pattern&.match?(line)

        found = Approval.new(path: file, at: line.strip, covers: lines.fetch(covers.call(lines, index), "").strip)
        "  #{file}:#{index + 1}: #{line.strip}" unless take(unused, found)
      end
    end
    unapproved + unused.map { |approval| "  #{approval.path}: approved, but no such line: #{describe(approval)}" }
  end

  def to_a = list
  def list = @list ||= []

  # Removes one approval equal to +found+ from +unused+, answering whether
  # there was one.
  private def take(unused, found)
    index = unused.index(found)
    unused.delete_at(index) if index
    !index.nil?
  end

  private def describe(approval)
    (approval.at == approval.covers) ? approval.at : "#{approval.at} (over #{approval.covers})"
  end

  private def named(lint)
    (@named ||= Hash.new { |hash, name| hash[name] = [] })[lint]
  end
end
