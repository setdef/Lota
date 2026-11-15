# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "json"
require "open3"
require "tmpdir"

# The REUSE tool's check of the files git knows, tracked or staged, as
# every rake task sees files (AGENTS.md), for rake reuse:lint and
# reuse:fix.
#
# reuse lint run in the checkout also reads every file git does not know
# and does not ignore, so a stray file another program left there, such
# as one run's output in a build machine's workspace, failed the check of
# commits that did not hold it. So the check runs in a copy of exactly
# the files git knows, as the working tree has them, where the REUSE tool
# sees what a commit of them would hold. A file git knows that lacks a
# header still fails, and so does every check the tool makes of the
# project as a whole, such as a license no file uses.
class ReuseLint
  # Raised when the REUSE tool gives no report, or one of no file.
  class Failure < StandardError; end

  # What the REUSE tool found: its JSON report, parsed, on the copy at
  # +root+, whose paths it gives in full.
  class Report < Data.define(:report, :root)
    # Whether every file complies.
    def compliant? = report.dig("summary", "compliant") == true

    # How many files the tool checked.
    def files = report.dig("summary", "files_total").to_i

    # Each kind of problem the tool found, as "kind: what, what".
    def problems
      report.fetch("non_compliant", {}).filter_map do |kind, found|
        names = found.is_a?(Hash) ? found.keys : Array(found)
        "#{kind}: #{names.map { |name| relative(name) }.join(', ')}" unless names.empty?
      end
    end

    # The files that lack copyright or licensing information.
    def missing
      found = report.fetch("non_compliant", {})
      (found.fetch("missing_copyright_info", []) | found.fetch("missing_licensing_info", [])).map { |path| relative(path) }.sort
    end

    private def relative(path) = path.delete_prefix("#{root}/")
  end

  # [root] The checkout.
  # [reuse] The command that runs the REUSE tool.
  def initialize(root, reuse: %w[reuse])
    @root = root
    @reuse = reuse
  end

  # The paths of the files git knows, tracked or staged, that the working
  # tree holds: not a submodule, which the REUSE tool leaves out, nor a
  # symbolic link, which the REUSE specification leaves out.
  def known
    output, status = Open3.capture2("git", "ls-files", "-z", "--cached", "--stage", chdir: @root)
    raise Failure, "git ls-files failed in #{@root}" unless status.success?

    output.split("\0").filter_map do |entry|
      mode, path = entry.match(/\A(\d+) \h+ \d+\t(.*)\z/m)&.captures
      next if mode.nil? || %w[160000 120000].include?(mode)

      path if File.file?(File.join(@root, path)) && !File.symlink?(File.join(@root, path))
    end.uniq
  end

  # Runs the REUSE tool over a copy of the known files, and returns its
  # Report.
  def check
    Dir.mktmpdir("lota-reuse-") do |dir|
      copy = File.join(dir, "tree")
      paths = known
      paths.each do |path|
        FileUtils.mkdir_p(File.join(copy, File.dirname(path)))
        FileUtils.cp(File.join(@root, path), File.join(copy, path))
      end
      report(copy, paths.size)
    end
  end

  # The REUSE tool's report on +copy+, which holds +count+ files. git
  # stops looking for a repository at +copy+'s folder, so a copy made
  # inside another checkout is never read through that checkout's ignores.
  private def report(copy, count)
    env = { "GIT_CEILING_DIRECTORIES" => File.dirname(copy) }
    output, error, = Open3.capture3(env, *@reuse, "lint", "--json", chdir: copy)
    found = Report.new(report: JSON.parse(output), root: File.realpath(copy))
    raise Failure, "reuse lint checked no file of the #{count} git knows" if count.positive? && found.files.zero?

    found
  rescue JSON::ParserError, Errno::ENOENT => e
    raise Failure, "reuse lint gave no report (#{e.message}#{"; #{error.strip}" unless error.to_s.strip.empty?}); " \
      "bin/setup installs reuse"
  end
end
