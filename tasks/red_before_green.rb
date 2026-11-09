# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "json"
require "open3"
require "prism"
require "rbconfig"
require "tmpdir"

# Checks that each test a commit adds or changes fails against the code
# the commit started from: the commit's test/ run against its parent's
# lib/, ext/, exe/, tasks/, and bin/. A test that passes there was never
# seen failing, so nothing shows it tests what the commit changed (rake
# red_before_green, and CI's Linux gate on every trunk push).
#
# It works in the checkout it is given, which must be clean in those
# folders and test/, and puts them back as HEAD has them when it is done.
# The native extension built for HEAD stands in for the parent's when
# ext/ and tasks/ are the same in both; otherwise it is rebuilt from the
# parent's, which ccache makes cheap. A parent whose engine differs
# (ext/lota/engine, the vendor/ submodules) would rebuild LÖVE's engine,
# so its commits go unchecked, and say why.
#
# A commit that changes no behavior, such as a refactor, or tests behavior
# that was already there, says so in a trailer, which waives the check:
#
#   Red-before-green: none (refactor)
class RedBeforeGreen
  # The commit trailer that waives the check, and the form its value takes.
  TRAILER = "Red-before-green"
  WAIVER = /\Anone \(\S.*\)\z/

  # What the parent's code is taken from; test/ comes from the commit.
  IMPLEMENTATION = %w[lib ext exe tasks bin].freeze

  # What a native rebuild follows, and what makes one of LÖVE's engine.
  NATIVE = %w[ext tasks].freeze
  ENGINE = %w[ext/lota/engine vendor].freeze

  # How long a test file may run against the parent.
  BUDGET = 900

  # Loaded with ruby -r into each test file run against a parent: writes
  # each test's name, result code, and first message, one JSON object a
  # line, to the file RED_BEFORE_GREEN_RESULTS names, where what a test
  # prints cannot get in the way. It is written out for each run rather
  # than kept in tasks/, which holds the parent's files while it runs.
  REPORTER = <<~RUBY
    require "json"
    require "minitest"

    module RedBeforeGreenReporter
      def self.minitest_plugin_init(_options)
        Minitest.reporter << Results.new(ENV.fetch("RED_BEFORE_GREEN_RESULTS"))
      end

      class Results < Minitest::AbstractReporter
        def initialize(path)
          super()
          @path = path
        end

        def record(result)
          line = JSON.generate(test: "\#{result.klass}#\#{result.name}", code: result.result_code,
            message: result.failures.first&.message.to_s)
          File.open(@path, "a") { |file| file.puts(line) }
        end
      end
    end

    Minitest.register_plugin(RedBeforeGreenReporter)
  RUBY

  # A test file's run against a parent: each test's result, by name; the
  # Process::Status, or nil if it ran out of time; and the last line it
  # wrote to standard error that is not a backtrace's, such as an
  # exception's message.
  class Run < Data.define(:results, :status, :error)
  end

  # A test the commit added or changed, the file it is defined in, and the
  # test file that runs it.
  class Test < Data.define(:name, :file, :runner)
  end

  # What became of a Test against the parent: +outcome+ is :red, :never_red,
  # :skipped, or :unchecked, and +detail+ says why.
  class Verdict < Data.define(:test, :outcome, :detail)
  end

  # A commit's +verdicts+, or the reason it went unchecked as a whole
  # (+unchecked+), or the trailer's value that waived it (+waiver+).
  class Report < Data.define(:commit, :subject, :waiver, :unchecked, :verdicts)
    # Whether the commit passes: no test of it passed against its parent,
    # and a trailer, if it has one, is in the form TRAILER takes.
    def passed?
      return waiver.match?(WAIVER) if waiver

      verdicts.none? { |verdict| verdict.outcome == :never_red }
    end

    # The report as lines for a person to read.
    def lines
      head = "#{commit[0, 12]} #{subject}"
      return [head, "  waived: #{TRAILER}: #{waiver}"] if waiver&.match?(WAIVER)
      return [head, "  MALFORMED #{TRAILER} trailer: #{waiver.inspect}; write: #{TRAILER}: none (reason)"] if waiver
      return [head, "  unchecked: #{unchecked}"] if unchecked
      return [head, "  no test added or changed"] if verdicts.empty?

      [head] + verdicts.map { |verdict| "  #{label(verdict.outcome)} #{verdict.test.name} (#{verdict.test.file}): #{verdict.detail}" }
    end

    private def label(outcome)
      { red: "red      ", never_red: "NEVER RED", skipped: "skipped  ", unchecked: "unchecked" }.fetch(outcome)
    end
  end

  # The test methods +source+ defines, by their names as Minitest reports
  # them ("Outer::Inner#test_name"), each with its source text.
  def self.test_methods(source)
    methods = {}
    walk = lambda do |node, scope|
      case node
      when Prism::ClassNode, Prism::ModuleNode
        inner = scope + [node.constant_path.slice]
        node.body&.compact_child_nodes&.each { |child| walk.call(child, inner) }
        return
      when Prism::DefNode
        methods["#{scope.join('::')}##{node.name}"] = node.slice if node.name.start_with?("test_") && !node.receiver
        return
      end
      node.compact_child_nodes.each { |child| walk.call(child, scope) }
    end
    walk.call(Prism.parse(source).value, [])
    methods
  end

  # A checker of the commits of the checkout at +root+. +suites+ are the
  # globs of the test files it runs (TEST_SUITES[:ruby]); a test in any
  # other file goes unchecked. +compile+ is the command that builds the
  # native extension, run in +root+.
  def initialize(root:, suites:, compile:, out: $stdout)
    @root = root
    @suites = suites
    @compile = compile
    @out = out
    # The revision whose native extension the checkout holds built.
    @built = "HEAD"
  end

  # The commits of +range+ (as git rev-list takes it), oldest first.
  def commits(range)
    git("rev-list", "--reverse", "--no-merges", range).lines(chomp: true)
  end

  # Checks each commit of +range+, prints its report, and returns the
  # reports.
  def check_range(range)
    commits(range).map do |commit|
      check(commit).tap { |report| @out.puts(report.lines) }
    end
  end

  # Checks +commit+ and returns its Report.
  def check(commit)
    subject = git("log", "-1", "--format=%s", commit).chomp
    report = Report.new(commit:, subject:, waiver: waiver(commit), unchecked: nil, verdicts: [])
    return report if report.waiver

    parent = git("rev-parse", "#{commit}^").chomp
    tests = changed_tests(parent, commit)
    return report if tests.empty?

    reason = unchecked_reason(parent)
    return report.with(unchecked: reason) if reason

    report.with(verdicts: against(parent, commit, tests))
  end

  private def git(*arguments)
    output, status = Open3.capture2("git", *arguments, chdir: @root)
    raise "git #{arguments.join(' ')} failed" unless status.success?

    output
  end

  private def waiver(commit)
    value = git("log", "-1", "--format=%(trailers:key=#{TRAILER},valueonly,separator=%x0A)", commit).strip
    value.empty? ? nil : value
  end

  private def blob(revision, path)
    output, status = Open3.capture2("git", "show", "#{revision}:#{path}", chdir: @root, err: File::NULL)
    status.success? ? output : ""
  end

  private def changed?(from, to, paths)
    !system("git", "diff", "--quiet", from, to, "--", *paths, chdir: @root)
  end

  # Each test whose source differs from the parent's, or that the parent
  # lacks, with the suite file that runs it.
  private def changed_tests(parent, commit)
    files = git("diff", "--name-only", "--diff-filter=AMR", parent, commit, "--", "test").lines(chomp: true)
    files.grep(/\.rb\z/).flat_map do |file|
      before = self.class.test_methods(blob(parent, file))
      self.class.test_methods(blob(commit, file)).filter_map do |name, source|
        Test.new(name:, file:, runner: runner(commit, file)) unless before[name] == source
      end
    end
  end

  # The suite file that runs the tests in +file+ at +commit+: the file
  # itself, or one that loads it with require_relative, as
  # test/lovetest/system_test.rb loads test/lovetest/tests/system.rb.
  private def runner(commit, file)
    return file if suite_files.include?(file)

    suite_files.find do |candidate|
      blob(commit, candidate).scan(/require_relative\s+["']([^"']+)["']/).any? do |(path)|
        File.expand_path("#{path.delete_suffix('.rb')}.rb", File.dirname(candidate)) == File.expand_path(file)
      end
    end
  end

  private def suite_files
    @suite_files ||= Dir.glob(@suites, base: @root)
  end

  private def unchecked_reason(parent)
    return unless changed?(parent, "HEAD", ENGINE)

    "the parent's engine (#{ENGINE.join(', ')}) differs from HEAD's, and rebuilding it is not cheap"
  end

  # Runs +tests+ with the parent's code, and puts the checkout back.
  private def against(parent, commit, tests)
    dirty = git("status", "--porcelain", "--", *IMPLEMENTATION, "test")
    raise "red_before_green needs #{IMPLEMENTATION.join(', ')} and test clean:\n#{dirty}" unless dirty.empty?

    # The files the overlay brings that HEAD lacks, to remove afterwards.
    extra = files(parent, IMPLEMENTATION) + files(commit, ["test"]) - files("HEAD", IMPLEMENTATION + ["test"])
    begin
      overlay(parent, commit)
      run(tests)
    ensure
      restore(extra)
    end
  end

  # Puts the parent's code and the commit's tests in the checkout, and
  # builds the native extension if they need another.
  private def overlay(parent, commit)
    restore_from(parent, IMPLEMENTATION)
    restore_from(commit, ["test"])
    build(parent) if changed?(parent, @built, NATIVE)
  end

  private def restore(extra)
    restore_from("HEAD", IMPLEMENTATION + ["test"])
    extra.each { |file| File.delete(File.join(@root, file)) if File.file?(File.join(@root, file)) }
  end

  private def files(revision, paths)
    git("ls-tree", "-r", "--name-only", revision, "--", *paths).lines(chomp: true)
  end

  # Makes +paths+ in the checkout as +revision+ has them. git restore
  # removes the tracked files +revision+ lacks, but refuses a path
  # +revision+ has nothing in, whose files go here.
  private def restore_from(revision, paths)
    present, absent = paths.partition { |path| !files(revision, [path]).empty? }
    git("restore", "--source=#{revision}", "--worktree", "--", *present) unless present.empty?
    files("HEAD", absent).each { |file| File.delete(File.join(@root, file)) } unless absent.empty?
  end

  # Builds the native extension from the checkout, which holds
  # +revision+'s code. The next rake compile builds HEAD's again, since
  # putting HEAD's files back makes them newer.
  private def build(revision)
    @out.puts("  building #{revision[0, 12]}'s native extension: #{@compile.join(' ')}")
    @built = nil
    output, status = Open3.capture2e(*@compile, chdir: @root)
    raise "building #{revision[0, 12]} failed:\n#{output.lines.last(40).join}" unless status.success?

    @built = revision
  end

  private def run(tests)
    tests.group_by(&:runner).flat_map do |runner, group|
      next group.map { |test| Verdict.new(test:, outcome: :unchecked, detail: "no file of the suite runs it") } unless runner

      run = run_file(runner, group.map(&:name))
      group.map { |test| verdict(test, run) }
    end
  end

  # Runs the tests named +names+ in +runner+, and returns its Run.
  private def run_file(runner, names)
    Dir.mktmpdir("red-before-green-") do |directory|
      results, reporter, errors = %w[results.jsonl reporter.rb errors.log].map { |name| File.join(directory, name) }
      File.write(reporter, REPORTER)
      pattern = "/\\A(?:#{names.map { |name| Regexp.escape(name) }.join('|')})\\z/"
      pid = Process.spawn({ "RED_BEFORE_GREEN_RESULTS" => results }, RbConfig.ruby, "-w", "-Ilib", "-Itest",
        "-r", reporter, runner, "-i", pattern, chdir: @root, in: File::NULL, out: File::NULL, err: errors,
        pgroup: true)
      status = wait(pid)
      lines = File.file?(results) ? File.readlines(results, chomp: true) : []
      Run.new(results: lines.to_h { |line| JSON.parse(line).then { |result| [result.fetch("test"), result] } },
        status:, error: File.read(errors).scrub.lines.map(&:strip).reject { |line| line.empty? || line.start_with?("from ") }.last)
    end
  end

  private def wait(pid)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + BUDGET
    loop do
      _, status = Process.wait2(pid, Process::WNOHANG)
      return status if status

      if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        Process.kill("KILL", -pid)
        Process.wait(pid)
        return nil
      end
      sleep(0.2)
    end
  end

  private def verdict(test, run)
    result = run.results[test.name]
    return missing(test, run) unless result

    case result.fetch("code")
    when "." then Verdict.new(test:, outcome: :never_red, detail: "passed against the parent, so it was never seen failing")
    when "S" then Verdict.new(test:, outcome: :skipped, detail: "skipped against the parent: #{result.fetch('message')}")
    else Verdict.new(test:, outcome: :red, detail: "fails against the parent: #{result.fetch('message').lines.first&.chomp}")
    end
  end

  # A test that reported nothing: its file failed before running any test
  # against the parent, which counts as failing there; or it ran out of
  # time, or its file ran without it, which tell nothing. The detail
  # gives the last line the file wrote to standard error, to show why.
  private def missing(test, run)
    unless run.status
      return Verdict.new(test:, outcome: :unchecked, detail: "ran past #{BUDGET} seconds against the parent")
    end
    # Minitest fails a run whose filter matches no test, as when the file
    # defines the test only on another platform.
    if !run.results.empty? || run.status.success? || run.error&.start_with?("Nothing ran for filter")
      return Verdict.new(test:, outcome: :unchecked, detail: "its file ran against the parent without it")
    end

    Verdict.new(test:, outcome: :red,
      detail: "its file failed to run against the parent (exit #{run.status.exitstatus}): #{run.error}")
  end
end
