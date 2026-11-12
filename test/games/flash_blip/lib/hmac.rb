# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2025 Aliet Exposito
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from FLASH-BLIP's lib/hmac.lua
# (test/fixtures/flash_blip/game/lib/hmac.lua, lines 1-74), by the rules of
# doc/contributors/design/translation.md: love.data.hash is
# Lota::Data.hash, its hash function a symbol (rules 9 and 40). The Lua
# picks an XOR by the Lua version it runs on; Ruby has one, Integer#^, as
# Lua 5.3's ~ is, so the choice has no Ruby meaning and _xor is ^, while
# xor_byte, the pure fallback, stays for the reader. The key and the
# message are bytes, as Lua strings are, so the code works on binary
# Strings (String#b), and key:byte(i) is getbyte(i - 1).

# lib/hmac.lua
# HMAC-SHA256 en Lua puro

module Hmac
  # XOR byte a byte compatible con todas las versiones de Lua
  def self.xor_byte(a, b)
    # Lua 5.3+ tiene el operador ~ nativo
    # LuaJIT y Lua 5.1 no lo tienen, usamos tabla de verdad
    result = 0
    bit_val = 1
    8.times do
      a_bit = a % 2
      b_bit = b % 2
      result += bit_val if a_bit != b_bit
      a = a.fdiv(2).floor
      b = b.fdiv(2).floor
      bit_val *= 2
    end
    result
  end

  # Detecta si podemos usar operadores nativos más rápidos
  # Operador nativo, como en Lua 5.3+
  XOR = -> (a, b) { a ^ b }

  def self.sha256(msg, key)
    block_size = 64
    key = key.b

    # Si la clave es más larga que el bloque, la hashea primero
    key = Lota::Data.hash(:sha256, key).b if key.bytesize > block_size
    # Padding a block_size bytes
    key += ("\0" * (block_size - key.bytesize)).b if key.bytesize < block_size

    # Construye ipad y opad
    ipad = []
    opad = []
    (1..block_size).each do |i|
      k = key.getbyte(i - 1)
      ipad[i - 1] = XOR.call(k, 0x36).chr
      opad[i - 1] = XOR.call(k, 0x5c).chr
    end
    ipad_str = ipad.join.b
    opad_str = opad.join.b

    # HMAC = SHA256(opad || SHA256(ipad || msg))
    inner = Lota::Data.hash(:sha256, ipad_str + msg.b)
    outer = Lota::Data.hash(:sha256, opad_str + inner.b).b

    # Convierte a hex
    hex = []
    (1..(outer.bytesize)).each do |i|
      hex[i - 1] = format("%02x", outer.getbyte(i - 1))
    end
    hex.join
  end
end
# SPDX-SnippetEnd
