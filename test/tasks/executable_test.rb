# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/executable"

# Executable finds a command on a PATH in a real folder.
class ExecutableTest < Minitest::Test
  include TreeHelper

  def test_it_finds_a_program_on_path_and_nothing_else
    in_tree do |dir|
      ninja = write(dir, "bin/ninja#{RbConfig::CONFIG['EXEEXT']}")
      File.chmod(0o755, ninja)
      FileUtils.mkdir_p(File.join(dir, "bin/cmake"))
      env = { "PATH" => [File.join(dir, "empty"), File.join(dir, "bin")].join(File::PATH_SEPARATOR) }

      assert_equal ninja, Executable.find("ninja", env)
      assert_nil Executable.find("cmake", env)
      assert_nil Executable.find("ninja", {})
    end
  end
end
