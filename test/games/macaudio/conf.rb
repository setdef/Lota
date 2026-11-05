# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# A fused macOS app with audio on, as a player double-clicks it. With
# MACAUDIO_WINDOW=0 in its environment it opens no window, for runs where
# no window may open; audio stays on either way.
$stdout.sync = true
$stderr.puts "conf: reached, pid #{Process.pid}"

def Lota.conf(t)
  t.title = "Mac Audio Check"
  t.identity = "MacAudioCheck"
  t.highdpi = true
  return unless ENV["MACAUDIO_WINDOW"] == "0"

  %i[window graphics image font keyboard mouse].each { |name| t.modules.public_send(:"#{name}=", false) }
end
