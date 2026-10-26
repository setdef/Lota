# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Lota::Native names the binding generator would not give, decided
# before it existed, so it reproduces them (tasks/bindings/binding_list.rb).
# The generator names a binding by ADR 001's rules, except that a setter
# stays set_x and a factory new_x, for the Ruby side to translate by rules
# 2, 5, and 6; a name no rule gives goes to the maintainer instead. Each
# entry must explain WHY its name differs, and a function listed here still
# appears in `rake bindings:report` if it collides. Review carefully before
# adding new entries.

# Lota::Native keeps setters as set_x, because the Ruby side applies rules
# 5 and 6, but no Ruby class wraps RandomGenerator yet, so its setter was
# bound as the writer rule 5 gives.
native_name "RandomGenerator:setState", as: "state=",
  reason: "bound as a writer since the walking skeleton (04b6f52), with no Ruby wrapper between it and " \
    "test/native/random_generator_test.rb, which assigns state= as rule 5 spells it."

# Every Lota::Native module answers open? for whether LÖVE's module is open
# (Lota.window asks it), so love.window.isOpen, whether the window is,
# cannot take the name rule 8 gives it there. Lota::Window.open? keeps
# rule 8's name; only the native layer beneath it differs.
native_name "love.window.isOpen", as: "window_open?",
  reason: "Lota::Native::Window.open? already says whether the window module is open, as open? does on " \
    "every Lota::Native module, and boot and Lota.window ask it; Lota::Window.open? calls this one."
