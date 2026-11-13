// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "native/deprecation.hpp"

#include "native/binding.hpp"

#include "common/Exception.h"
#include "common/deprecation.h"

#include <cstdlib>
#include <string>
#include <utility>
#include <vector>

namespace lota::native {

namespace {

// The engine's record (common/deprecation.cpp) lives between
// initDeprecation and deinitDeprecation, which every Module's constructor
// and destructor call (common/Module.cpp:69, 96). Lota marks names before
// any module is open, as conf.rb's settings are read, so this keeps one
// count of its own from the first mark until the process ends.
void keep_record() {
  static const bool kept = [] {
    love::initDeprecation();
    std::atexit(love::deinitDeprecation);
    return true;
  }();
  (void)kept;
}

// SPDX-SnippetBegin
// SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
// SPDX-License-Identifier: Zlib
//
// Ported from luax_markdeprecated (vendor/love/src/common/runtime.cpp:
// 1074-1091), which marks the name and, on its first use, keeps where in
// the game's files it was used. The engine's own draw of the notices
// (graphics/Deprecations.cpp:41-130) reads what this records.
//
// Lota::Deprecation prints the notice itself, with Lota's name, and the
// engine would print one, with LÖVE's name, when a name's first use is
// marked while its output is on (deprecation.cpp:183-186) and when its
// output is turned on while a name has been used once (deprecation.cpp:
// 75-90). So the name is marked twice, the first time with the engine's
// output off: a name used twice is never printed by the engine, and what
// Lota's record keeps stays the engine's to draw, not to print.
// The fields arrive as a Ruby Array of Strings, the name, the kind of API,
// how it was deprecated, what replaced it, and where it was used: a
// std::vector parameter would make Rice define a Ruby class for it, which
// the test extension defines again. Rice converts an Array only by value,
// which this function then owns.
void record(Rice::Array fields_given) {
  const Rice::Array fields = std::move(fields_given);
  std::vector<std::string> texts;
  for (const auto item : fields) {
    texts.push_back(Rice::String(item.value()).str());
  }
  const std::string &name = texts.at(0);
  const std::string &api = texts.at(1);
  const std::string &type = texts.at(2);
  const std::string &replacement = texts.at(3);
  const std::string &where = texts.at(4);
  love::APIType api_type = love::API_MAX_ENUM;
  love::DeprecationType deprecation_type = love::DEPRECATED_MAX_ENUM;
  if (!love::getConstant(api.c_str(), api_type)) {
    throw love::Exception("Invalid API type '%s'", api.c_str());
  }
  if (!love::getConstant(type.c_str(), deprecation_type)) {
    throw love::Exception("Invalid deprecation type '%s'", type.c_str());
  }

  keep_record();
  const bool printing = love::isDeprecationOutputEnabled();
  love::setDeprecationOutputEnabled(false);
  {
    const love::MarkDeprecated first(name.c_str(), api_type, deprecation_type, replacement.c_str());
    if (first.info != nullptr && first.info->uses == 1) {
      first.info->where = where;
    }
  }
  {
    const love::MarkDeprecated second(name.c_str(), api_type, deprecation_type,
                                      replacement.c_str());
  }
  love::setDeprecationOutputEnabled(printing);
}

// SPDX-SnippetEnd

// w_love_setDeprecationOutput (vendor/love/src/modules/love/love.cpp:
// 499-504), whose flag the engine's draw of the notices asks first
// (Deprecations.cpp:43-44).
void output(bool enable) {
  keep_record();
  love::setDeprecationOutputEnabled(enable);
}

} // namespace

void define_deprecation(const Rice::Module &native) {
  Rice::define_module_under(native, "Deprecation")
      .define_singleton_function("record", &record, Rice::Arg("fields"))
      .define_singleton_function("output=", &output, Rice::Arg("enable"));
}

} // namespace lota::native
