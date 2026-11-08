# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Temporary diagnostics for the sanitized suite on CI.
module DiagRss
  @count = 0

  class << self
    attr_accessor :count
  end

  def after_teardown
    super
    DiagRss.count += 1
    rss = `ps -o rss= -p #{Process.pid}`.strip
    swap = (DiagRss.count % 25).zero? ? `sysctl -n vm.swapusage 2>/dev/null`.strip : ""
    warn "DIAG #{DiagRss.count} #{Time.now.strftime('%H:%M:%S')} rss=#{rss} #{self.class}##{name} #{swap}"
  end
end

Minitest::Test.prepend(DiagRss)
