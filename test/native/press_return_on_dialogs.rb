# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Loaded with ruby -r into lota run by test/native/lota_run_test.rb: presses
# Return on every dialog the game shows, as the parity harness does
# (LotaNativeTest.press_return_on_dialogs), and at exit prints how many
# dialogs it pressed Return on.
require "lota"
require "lota_native_test"

LotaNativeTest.press_return_on_dialogs
at_exit { puts "dialogs #{LotaNativeTest.dialogs_answered}" }
