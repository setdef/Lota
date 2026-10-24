# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../test_helper"
require "fileutils"
require "open3"
require "tmpdir"

# Builds small, real file trees for the tasks' tests: CMake projects, git
# repositories, and C++ files, in a temporary directory removed afterward.
module TreeHelper
  # The repository's own root, for its real configuration files.
  ROOT = File.expand_path("../..", __dir__)

  # Yields a fresh temporary directory (its real path, since macOS links
  # /var to /private/var and CMake records real paths).
  def in_tree
    Dir.mktmpdir("lota-test") { |dir| yield File.realpath(dir) }
  end

  # Writes +content+ to +path+ under +root+, creating directories.
  def write(root, path, content = "")
    file = File.join(root, path)
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, content)
    file
  end

  # Runs a command in +dir+, failing the test if it fails.
  def run!(dir, *command)
    output, status = Open3.capture2e(*command, chdir: dir)
    assert status.success?, "#{command.join(' ')} failed:\n#{output}"
    output
  end

  # Makes +dir+ a git repository with every file in it staged.
  def git_stage(dir)
    run!(dir, "git", "init", "--quiet")
    run!(dir, "git", "add", "--all")
  end
end
