# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"

# bin/setup, run in a copy of itself with the tools it calls recording
# what they were asked, since the real ones install things.
class SetupTest < Minitest::Test
  include TreeHelper

  TOOLS = {
    "mise" => <<~SH,
      echo "mise $*" >> "$SETUP_LOG"
      if [ "$1" = x ]; then shift 2; exec "$@"; fi
    SH
    "bundle" => %(echo "bundle $*" >> "$SETUP_LOG"\n),
    "pre-commit" => %(echo "pre-commit $*" >> "$SETUP_LOG"\n),
    "git" => <<~SH,
      echo "git $*" >> "$SETUP_LOG"
      case "$*" in *--git-common-dir*) echo "$SETUP_TREE/.git" ;; esac
    SH
  }.freeze

  # The commands bin/setup ran, one a line, in +env+.
  def setup_commands(env)
    in_tree do |dir|
      write(dir, "bin/setup", File.read(File.join(ROOT, "bin/setup")))
      write(dir, "bin/apt-packages", "#!/bin/sh\n")
      TOOLS.each { |name, body| write(dir, "tools/#{name}", "#!/bin/sh\n#{body}") }
      FileUtils.chmod(0o755, Dir[File.join(dir, "{bin,tools}/*")])
      log = File.join(dir, "setup.log")
      environment = env.merge("PATH" => "#{dir}/tools:#{ENV.fetch('PATH')}", "SETUP_LOG" => log, "SETUP_TREE" => dir)
      output, status = Open3.capture2e(environment, File.join(dir, "bin/setup"), chdir: dir)

      assert_predicate status, :success?, output
      File.readlines(log, chomp: true)
    end
  end

  # A CI runner or a build machine runs the checks, never commits, and reads
  # no documentation, so it gets the tools, the gems, and the sources alone.
  def test_on_ci_setup_leaves_out_pre_commits_hook_and_the_rdoc
    contributor = setup_commands("CI" => nil)
    ci = setup_commands("CI" => "true")

    assert_includes ci, "mise install"
    assert_includes ci, "bundle install"
    assert_includes ci, "bundle exec rake sources:fetch"
    assert_equal ["pre-commit install", "bundle exec rake rdoc"], contributor - ci
  end
end
