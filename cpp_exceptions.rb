# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Approved NOLINT comments in Lota's own C++ (rake cpp:no_nolint).
# Each entry must explain WHY the suppressed clang-tidy check cannot be
# satisfied, for example:
#
#   allow "ext/lota/native.cpp", line: 12, reason: "..."
#
# Review carefully before adding new entries.

# The test-only extension reads Lota::Native's RandomGenerator out of the
# other bundle, whose Rice registries it cannot see, by calling that
# wrapper's virtual get() with the object's own Ruby data type. Ruby
# declares VALUE and RTYPEDDATA_TYPE in ruby/internal/ headers, whose
# paths Ruby documents as implementation details that may move ("The name
# (path) of this header file is also an implementation detail", in
# ruby/internal/value.h and ruby/internal/core/rtypeddata.h). The public
# header, ruby.h, does not export them, so misc-include-cleaner cannot be
# satisfied without tying the build to a path Ruby says will not persist.
allow "ext/lota/native_test/native_test.cpp", line: 91,
  reason: "VALUE is declared only in ruby/internal/value.h, whose path Ruby documents as an implementation detail; " \
    "Rice passes the raw Ruby object (Arg.setValue) because it converts no Rice::Object reference."
allow "ext/lota/native_test/native_test.cpp", line: 101,
  reason: "RTYPEDDATA_TYPE returns the type as const while Rice's WrapperBase::get takes it non-const " \
    "though it only reads it (rice.hpp, Wrapper.hpp), so the const_cast cannot go; and the macro is " \
    "declared only in ruby/internal/core/rtypeddata.h, whose path Ruby documents as an implementation detail."
