# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "jobs"

# How many jobs the builds and clang-tidy each run at once (Jobs), checked
# as rake loads and given to CMake's builds, every cmake --build among
# them, the extension's Makefile's too. Nothing else asks for it before
# a task runs, so a LOTA_JOBS it cannot read stops rake here.
begin
  ENV.update(Jobs.environment(ENV, Jobs.count))
rescue Jobs::Failure => e
  abort "❌ #{e.message}"
end
