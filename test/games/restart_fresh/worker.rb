# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Waits until the game tells it to stop, so it runs while the game does.
Lota::Thread.channel("stop").demand
