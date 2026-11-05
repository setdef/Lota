# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# One of the gate's checks (tasks/gate.rb): rake, given the tasks the gate
# prepared (comma separated) and then the tasks to run. The prepared tasks
# are cleared, since they have run, so that this process does not build or
# fix again what another check's process is also using.
#
# Its output goes out as it is written, not when a buffer fills, so that
# what the gate shows of a check that hangs is what it has done so far.
require "rake"

$stdout.sync = true
$stderr.sync = true

application = Rake.application
prepared, *tasks = ARGV
application.standard_exception_handling do
  application.init("rake", tasks)
  application.load_rakefile
  done = prepared.split(",").map { |name| Rake::Task[name] }
  (done + done.flat_map(&:all_prerequisite_tasks)).uniq.each(&:clear)
  application.top_level
end
