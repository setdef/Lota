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
#include <cstdint>
#include <limits>

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

} // namespace lota::native::luajit

#endif // LOTA_NATIVE_LUAJIT_HPP
