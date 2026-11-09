# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/red_before_green"
require "stringio"

# RedBeforeGreen runs each test a commit adds or changes against the
# commit's parent, in a real repository whose tests Minitest runs.
class RedBeforeGreenTest < Minitest::Test
  include TreeHelper

  # Commits as nobody in particular, since the machine may have no git
  # identity.
  IDENTITY = %w[-c user.name=Sample -c user.email=sample@example.com].freeze

  CALC = <<~RUBY
    module Calc
      def self.add(left, right)
        left + right
      end
    end
  RUBY

  CALC_TEST = <<~RUBY
    require "minitest/autorun"
    require "calc"

    class CalcTest < Minitest::Test
      def test_add
        assert_equal 3, Calc.add(1, 2)
      end
    end
  RUBY

  # A repository whose first commit holds Calc and its test, yielded with
  # a checker of it that records its builds in +builds+.
  def in_repository
    in_tree do |root|
      write(root, "lib/calc.rb", CALC)
      write(root, "test/calc_test.rb", CALC_TEST)
      git_stage(root)
      commit(root, "feat: add")
      yield root
    end
  end

  def checker(root, out = StringIO.new)
    compile = [RbConfig.ruby, "-e", "File.write('builds', File.read('lib/calc.rb'), mode: 'a')"]
    RedBeforeGreen.new(root:, suites: ["test/**/*_test.rb"], compile:, out:)
  end

  # Writes +files+ and commits them with +message+, returning the commit.
  def commit(root, message, files = {})
    files.each { |path, content| write(root, path, content) }
    run!(root, "git", "add", "--all")
    run!(root, "git", *IDENTITY, "commit", "--quiet", "--message", message)
    run!(root, "git", "rev-parse", "HEAD").chomp
  end

  def outcomes(report)
    report.verdicts.to_h { |verdict| [verdict.test.name, verdict.outcome] }
  end

  def test_a_test_that_fails_against_the_parent_was_red
    in_repository do |root|
      sha = commit(root, "feat: double",
        "lib/calc.rb" => CALC.sub("  end\nend", "  end\n\n  def self.double(value)\n    value * 2\n  end\nend"),
        "test/calc_test.rb" => CALC_TEST.sub("  end\nend",
          "  end\n\n  def test_double\n    assert_equal 4, Calc.double(2)\n  end\nend"))

      report = checker(root).check(sha)

      assert_equal({ "CalcTest#test_double" => :red }, outcomes(report))
      assert_predicate report, :passed?
    end
  end

  def test_a_test_that_passes_against_the_parent_was_never_red
    in_repository do |root|
      sha = commit(root, "test: zero",
        "test/calc_test.rb" => CALC_TEST.sub("  end\nend",
          "  end\n\n  def test_add_zero\n    assert_equal 1, Calc.add(1, 0)\n  end\nend"))

      report = checker(root).check(sha)

      assert_equal({ "CalcTest#test_add_zero" => :never_red }, outcomes(report))
      refute_predicate report, :passed?
      assert_match(%r{NEVER RED CalcTest#test_add_zero \(test/calc_test.rb\): passed against the parent},
        report.lines.join("\n"))
    end
  end

  def test_a_changed_test_is_checked_and_an_unchanged_one_is_not
    in_repository do |root|
      untouched = "  end\n\n  def test_untouched\n    assert true\n  end\nend"
      commit(root, "test: untouched", "test/calc_test.rb" => CALC_TEST.sub("  end\nend", untouched))
      sha = commit(root, "fix: add", "lib/calc.rb" => CALC.sub("left + right", "left + right + 0.0"),
        "test/calc_test.rb" => CALC_TEST.sub("  end\nend", untouched).sub("assert_equal 3,", "assert_kind_of Float,"))

      report = checker(root).check(sha)

      assert_equal({ "CalcTest#test_add" => :red }, outcomes(report))
    end
  end

  def test_a_test_file_that_cannot_load_against_the_parent_was_red
    in_repository do |root|
      sha = commit(root, "feat: sub",
        "lib/sub.rb" => "module Sub\n  def self.call(left, right) = left - right\nend\n",
        "test/sub_test.rb" => "require \"minitest/autorun\"\nrequire \"sub\"\n\n" \
          "class SubTest < Minitest::Test\n  def test_sub\n    assert_equal 1, Sub.call(2, 1)\n  " \
          "end\nend\n")

      report = checker(root).check(sha)

      assert_equal({ "SubTest#test_sub" => :red }, outcomes(report))
      assert_match(/its file failed to run against the parent \(exit 1\): .*cannot load such file -- sub \(LoadError\)/,
        report.verdicts.first.detail)
    end
  end

  # Minitest fails a run that its filter leaves empty, as when the file
  # defines the test only on another platform; that tells nothing.
  def test_a_test_its_file_does_not_define_here_goes_unchecked
    in_repository do |root|
      sha = commit(root, "test: elsewhere",
        "test/calc_test.rb" => CALC_TEST.sub("  end\nend", "  end\n\n  if false\n    def test_elsewhere\n      " \
          "assert true\n    end\n  end\nend"))

      report = checker(root).check(sha)

      assert_equal({ "CalcTest#test_elsewhere" => :unchecked }, outcomes(report))
      assert_predicate report, :passed?
    end
  end

  # A parity test that runs the reference love fails without it against
  # any parent, which tells nothing, while one beside it that needs no
  # love is checked as any other.
  def test_a_test_that_needs_the_reference_love_goes_unchecked
    in_repository do |root|
      needs = "raise \"LOTA_REFERENCE_LOVE is not set; bundle exec rake test:parity builds the reference love\""
      sha = commit(root, "feat: double",
        "lib/calc.rb" => CALC.sub("  end\nend", "  end\n\n  def self.double(value)\n    value * 2\n  end\nend"),
        "test/calc_test.rb" => CALC_TEST.sub("  end\nend", "  end\n\n  def test_double\n    assert_equal 4, " \
          "Calc.double(2)\n  end\n\n  def test_against_love\n    #{needs}\n  end\nend"))

      report = checker(root).check(sha)

      assert_equal({ "CalcTest#test_double" => :red, "CalcTest#test_against_love" => :unchecked }, outcomes(report))
      assert_predicate report, :passed?
      assert_match(/unchecked CalcTest#test_against_love .*needs the reference love/, report.lines.join("\n"))
    end
  end

  # A test defined outside the suite's files is run by the suite file that
  # loads it, as test/lovetest/system_test.rb runs tests/system.rb.
  def test_a_test_in_a_loaded_file_runs_through_the_file_that_loads_it
    in_repository do |root|
      commit(root, "test: cases", "test/cases/calc.rb" => "class CasesTest < Minitest::Test\nend\n",
        "test/cases_test.rb" => "require \"minitest/autorun\"\nrequire \"calc\"\nrequire_relative \"cases/calc\"\n")
      sha = commit(root, "test: case",
        "test/cases/calc.rb" => "class CasesTest < Minitest::Test\n  def test_case\n    " \
          "assert_equal 2, Calc.add(1, 1)\n  end\nend\n")

      report = checker(root).check(sha)

      assert_equal({ "CasesTest#test_case" => :never_red }, outcomes(report))
      assert_equal "test/cases_test.rb", report.verdicts.first.test.runner
    end
  end

  def test_a_trailer_waives_the_check
    in_repository do |root|
      sha = commit(root, "refactor: rename\n\nRed-before-green: none (refactor)",
        "test/calc_test.rb" => CALC_TEST.sub("def test_add", "def test_adds"))

      report = checker(root).check(sha)

      assert_predicate report, :passed?
      assert_empty report.verdicts
      assert_includes report.lines, "  waived: Red-before-green: none (refactor)"
    end
  end

  def test_a_trailer_without_a_reason_is_malformed
    in_repository do |root|
      sha = commit(root, "refactor: rename\n\nRed-before-green: none",
        "test/calc_test.rb" => CALC_TEST.sub("def test_add", "def test_adds"))

      report = checker(root).check(sha)

      refute_predicate report, :passed?
      assert_match(/MALFORMED Red-before-green trailer/, report.lines.join)
    end
  end

  def test_a_waiver_outside_the_trailer_block_is_reported_as_such
    in_repository do |root|
      message = "refactor: rename\n\nRed-before-green: none (refactor)\nProvenance: requested\n\n" \
        "Co-Authored-By: Sample <sample@example.com>"
      sha = commit(root, message, "test/calc_test.rb" => CALC_TEST.sub("def test_add", "def test_adds"))

      report = checker(root).check(sha)

      refute_predicate report, :passed?
      assert_empty report.verdicts
      assert_match(/Red-before-green waiver is not in the trailer block/, report.lines.join)
    end
  end

  def test_a_waiver_in_the_last_paragraph_with_other_trailers_still_waives
    in_repository do |root|
      message = "refactor: rename\n\nBecause.\n\nRed-before-green: none (refactor)\nProvenance: requested\n" \
        "Co-Authored-By: Sample <sample@example.com>"
      sha = commit(root, message, "test/calc_test.rb" => CALC_TEST.sub("def test_add", "def test_adds"))

      assert_predicate checker(root).check(sha), :passed?
    end
  end

  def test_a_commit_whose_engine_differs_goes_unchecked
    in_repository do |root|
      sha = commit(root, "fix: engine", "ext/lota/engine/fix.patch" => "--- a\n+++ b\n",
        "test/calc_test.rb" => CALC_TEST.sub("def test_add", "def test_adds"))

      report = checker(root).check(sha)

      assert_predicate report, :passed?
      assert_match(/rebuilding it is not cheap/, report.unchecked)
    end
  end

  # The parent's native extension is built only when its ext/ differs from
  # what the checkout holds built, and the checkout is HEAD's again after.
  def test_the_parent_is_built_only_when_its_native_code_differs_and_the_checkout_is_put_back
    in_repository do |root|
      commit(root, "feat: ext", "ext/calc.c" => "int one;\n")
      subtracting = CALC_TEST.sub("3, Calc.add(1, 2)", "-1, Calc.add(1, 2)")
      native = commit(root, "feat: two", "ext/calc.c" => "int two;\n", "lib/calc.rb" => CALC.sub("+", "-"),
        "lib/new.rb" => "", "test/calc_test.rb" => subtracting)
      plain = commit(root, "test: again", "test/calc_test.rb" => subtracting.sub("def test_add", "def test_add_again"))
      checker = checker(root)

      assert_equal :never_red, outcomes(checker.check(plain)).fetch("CalcTest#test_add_again")
      refute_path_exists File.join(root, "builds")
      assert_equal :red, outcomes(checker.check(native)).fetch("CalcTest#test_add")
      assert_equal CALC, File.read(File.join(root, "builds"))
      assert_empty run!(root, "git", "status", "--porcelain", "--untracked-files=all").lines.grep_v(/ builds$/)
    end
  end

  # In Lota's checkout the checker's own file is in tasks/, which holds
  # the parent's files while the tests run, and lacks it in the parent of
  # the commit that adds it; nothing a run loads may live there.
  def test_the_checker_runs_from_a_checkout_whose_parent_lacks_it
    in_repository do |root|
      sha = commit(root, "test: again", "test/calc_test.rb" => CALC_TEST.sub("def test_add", "def test_add_again"))
      write(root, "tasks/red_before_green.rb", File.read(File.join(ROOT, "tasks/red_before_green.rb")))
      commit(root, "chore: checker")
      script = 'require "./tasks/red_before_green"; ' \
        'checker = RedBeforeGreen.new(root: Dir.pwd, suites: ["test/**/*_test.rb"], compile: ["true"]); ' \
        "puts checker.check(ARGV.first).lines"

      output = run!(root, RbConfig.ruby, "-e", script, sha)

      assert_match(/NEVER RED CalcTest#test_add_again/, output)
    end
  end

  def test_check_range_reports_each_commit_oldest_first
    in_repository do |root|
      first = run!(root, "git", "rev-parse", "HEAD").chomp
      commit(root, "test: zero", "test/calc_test.rb" => CALC_TEST.sub("def test_add", "def test_add_again"))
      commit(root, "docs: readme", "README" => "Calc\n")
      out = StringIO.new

      reports = checker(root, out).check_range("#{first}..HEAD")

      assert_equal ["test: zero", "docs: readme"], reports.map(&:subject)
      assert_match(/test: zero\n  NEVER RED CalcTest#test_add_again .*\n\h{12} docs: readme\n  no test added or changed\n/,
        out.string)
    end
  end

  def test_test_methods_are_named_as_minitest_names_them
    source = "module Outer\n  class InnerTest\n    def test_a = 1\n    def helper = 2\n    def self.test_b = 3\n  " \
      "end\nend\nclass Top::LevelTest\n  def test_c\n  end\nend\n"

    assert_equal ["Outer::InnerTest#test_a", "Top::LevelTest#test_c"], RedBeforeGreen.test_methods(source).keys
  end
end
