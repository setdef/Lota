# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"

# The Ubuntu packages Lota's Linux build needs are listed once, in tasks/apt,
# and bin/setup and the CI workflow both install from those lists.
class AptPackagesTest < Minitest::Test
  include TreeHelper

  SCRIPT = File.join(ROOT, "bin/apt-packages")
  WORKFLOW = File.read(File.join(ROOT, ".github/workflows/ci.yml"))

  def test_every_list_holds_only_package_names
    Dir[File.join(ROOT, "tasks/apt/*.txt")].each do |file|
      name = File.basename(file, ".txt")
      packages, status = Open3.capture2(SCRIPT, "list", name)

      assert_predicate status, :success?
      refute_empty packages.lines, name
      packages.each_line { |line| assert_match(/\A[a-z0-9][a-z0-9+.-]+\n\z/, line, name) }
    end
  end

  def test_a_comment_is_not_a_package
    packages, = Open3.capture2(SCRIPT, "list", "runner")

    assert_equal %w[libfuse2 libstdc++-12-dev], packages.split
  end

  def test_lists_are_joined_without_repeats
    packages, = Open3.capture2(SCRIPT, "list", "build", "display")

    assert_equal packages.split.uniq, packages.split
    assert_includes packages.split, "libgl1"
    assert_includes packages.split, "libasound2-dev"
  end

  def test_an_unknown_list_fails
    _, error, status = Open3.capture3(SCRIPT, "list", "nope")

    refute_predicate status, :success?
    assert_match(/no list/, error)
  end

  def test_missing_reports_what_dpkg_query_does_not_find_installed
    in_tree do |dir|
      write(dir, "bin/dpkg-query", <<~SH)
        #!/bin/sh
        for last; do :; done
        [ "$last" = libyaml-dev ] && { printf installed; exit 0; }
        [ "$last" = xvfb ] && { printf config-files; exit 0; }
        exit 1
      SH
      File.chmod(0o755, File.join(dir, "bin/dpkg-query"))
      missing, status = Open3.capture2({ "PATH" => "#{dir}/bin:#{ENV.fetch('PATH')}" }, SCRIPT, "missing", "display")

      assert_predicate status, :success?
      assert_equal %w[libegl1 libgl1 libgl1-mesa-dri openbox xvfb], missing.split
    end
  end

  def test_missing_reports_nothing_when_all_are_installed
    in_tree do |dir|
      write(dir, "bin/dpkg-query", "#!/bin/sh\nprintf installed\n")
      File.chmod(0o755, File.join(dir, "bin/dpkg-query"))
      missing, = Open3.capture2({ "PATH" => "#{dir}/bin:#{ENV.fetch('PATH')}" }, SCRIPT, "missing", "build", "runner")

      assert_empty missing
    end
  end

  def test_ci_installs_only_from_the_lists
    installs = WORKFLOW.lines.grep(/apt-get install/)

    refute_empty installs
    installs.each { |line| assert_match(%r{bin/apt-packages list [a-z ]+ \| xargs sudo apt-get install}, line) }
    lists = WORKFLOW.scan(%r{bin/apt-packages list ([a-z ]+) \|}).flatten.flat_map(&:split).uniq

    assert_equal %w[build runner display bundle].sort, lists.sort
  end

  def test_setup_checks_the_build_list_and_never_runs_sudo
    setup = File.read(File.join(ROOT, "bin/setup"))

    assert_includes setup, "bin/apt-packages missing build"
    refute_match(/^\s*sudo /, setup)
  end
end
