// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// LuaJIT's conversions of a Lua number, as LÖVE's FFI code in its
// wrap_*.lua files relies on them, for the bindings that port that code
// (ADR 001, section 7: where LÖVE replaces a C++ wrap function with LuaJIT
// code, Lota ports the Lua). A Lua number is a double; LuaJIT converts it
// when the FFI stores it in a C integer field and when its bit library
// takes it, each in its own way, and C++ leaves the same casts undefined
// out of range, so each is written out here.

#ifndef LOTA_NATIVE_LUAJIT_HPP
#define LOTA_NATIVE_LUAJIT_HPP

#include <bit>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <string>
#include <string_view>

namespace lota::native::luajit {

// A Lua number stored in a C integer field of 32 bits or fewer, signed,
// or narrower than 32 bits, unsigned: converted to a 32-bit integer
// first, of which a narrower type keeps the low bits (LuaJIT 2.1,
// lj_cconv.c, lj_cconv_ct_ct, CCX(I, F)). On Apple silicon the conversion
// is the processor's own (FCVTZS), which saturates a number out of range
// and makes NaN 0.
inline std::int32_t to_int32(double number) {
  if (std::isnan(number)) {
    return 0;
  }
  if (number >= static_cast<double>(std::numeric_limits<std::int32_t>::max())) {
    return std::numeric_limits<std::int32_t>::max();
  }
  if (number <= static_cast<double>(std::numeric_limits<std::int32_t>::min())) {
    return std::numeric_limits<std::int32_t>::min();
  }
  return static_cast<std::int32_t>(number);
}

// A Lua number stored in an unsigned 32-bit field: converted straight to
// an unsigned 32-bit integer (lj_cconv.c, CCX(I, F), "uint32_t u =
// (uint32_t)n"), which on Apple silicon is the processor's FCVTZU: a
// negative number, as LuaJIT's bit library returns for a word whose top
// bit is set, becomes 0, a number too large the largest value, and NaN 0.
inline std::uint32_t to_uint32(double number) {
  if (std::isnan(number) || number <= 0) {
    return 0;
  }
  if (number >= static_cast<double>(std::numeric_limits<std::uint32_t>::max())) {
    return std::numeric_limits<std::uint32_t>::max();
  }
  return static_cast<std::uint32_t>(number);
}

// A Lua number as LuaJIT's bit library takes it, as bit.tobit does
// (lj_obj.h, lj_num2bit): adding 2^52 + 2^51 rounds it to the nearest
// whole number, ties to even, in the low 32 bits of the double, which are
// the result, so it also wraps modulo 2^32.
inline std::int32_t to_bit(double number) {
  constexpr double magic = 6755399441055744.0;
  return static_cast<std::int32_t>(
      static_cast<std::uint32_t>(std::bit_cast<std::uint64_t>(number + magic)));
}

// SPDX-SnippetBegin
// SPDX-SnippetCopyrightText: 2005-2026 Mike Pall
// SPDX-License-Identifier: MIT
//
// Ported from lj_strfmt_wptr (LuaJIT 2.1, src/lj_strfmt.c:135-152, at
// commit ea9eb7ed of the v2.1 branch LÖVE's builds clone), which
// lua_pushfstring's %p writes with (lj_strfmt_pushvf, lj_strfmt.c:576).

// +value+ as LuaJIT's %p writes it: NULL for none, and otherwise 0x and
// the address in lowercase hexadecimal, at least eight digits, and on a
// 64-bit machine two more for each byte the address needs above its low
// 32 bits.
inline std::string pointer(const void *value) {
  constexpr std::size_t least_digits = 8;
  constexpr unsigned high_shift = 32;
  constexpr unsigned byte_shift = 3;
  constexpr unsigned digit_bits = 4;
  constexpr std::uintptr_t digit_mask = 0xf;
  constexpr std::string_view hex = "0123456789abcdef";

  auto address = std::bit_cast<std::uintptr_t>(value);
  if (address == 0) {
    return "NULL";
  }
  std::size_t digits = 2 * sizeof(std::uintptr_t);
  if constexpr (sizeof(std::uintptr_t) == sizeof(std::uint64_t)) {
    const auto high = static_cast<std::uint32_t>(static_cast<std::uint64_t>(address) >> high_shift);
    digits = least_digits;
    if (high != 0) {
      // lj_fls, the index of the highest bit set, is bit_width less one.
      const auto highest = static_cast<std::size_t>(std::bit_width(high)) - 1;
      digits += 2 + (2 * (highest >> byte_shift));
    }
  }
  std::string written(digits, '0');
  for (auto digit = written.rbegin(); digit != written.rend(); ++digit, address >>= digit_bits) {
    *digit = hex.at(address & digit_mask);
  }
  return "0x" + written;
}

// SPDX-SnippetEnd

} // namespace lota::native::luajit

#endif // LOTA_NATIVE_LUAJIT_HPP
