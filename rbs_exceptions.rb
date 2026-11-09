# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Approved RBS 'untyped' and signature-parity exceptions.
# Each entry must explain WHY the exception is unavoidable.
# Review carefully before adding new entries.

# Fiddle, Ruby's FFI, is a bundled gem whose types RBS's standard library
# does not have, so sig/fiddle.rbs declares the part of Fiddle::Pointer
# that Lota::Data#pointer, #ffi_pointer, and Lota::Window.pointer return,
# for Steep and for the games that type-check against Lota's signatures.
# Fiddle defines both constants in its C extension, which Lota requires
# only inside those methods (Lota::Pointer), since a game adds the gem
# only when it wants pointers, as the maintainer decided, so the parity
# check, which loads lib/ alone, never sees them defined. Where Fiddle is
# loaded, the check still holds each declared method to Fiddle's own.
allow "Fiddle", lint: :rbs_parity,
  reason: "a bundled gem's module, defined by its C extension, which lib/ requires lazily"
allow "Fiddle::Pointer", lint: :rbs_parity,
  reason: "a bundled gem's class, defined by its C extension, which lib/ requires lazily"
