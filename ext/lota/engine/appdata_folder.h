// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// The folder a game that is not fused saves in, inside the system's
// application data folder: Lota, where LÖVE adds LOVE (ADR 003, section
// 8), since lota run is Lota's counterpart of the love program; on
// Linux, where LÖVE's folder is love, lowercase like the program
// (vendor/love/src/modules/filesystem/Filesystem.h:46-47), Lota's is lota.
//
// LÖVE names the folder LOVE_APPDATA_FOLDER, which
// vendor/love/src/modules/filesystem/Filesystem.h:36-54 defines
// unconditionally, under each platform's #if, so a definition on the
// compiler's command line would be replaced by LÖVE's. The engine build
// includes this header first in the one source that reads the macro,
// src/modules/filesystem/physfs/Filesystem.cpp (getFullCommonPath, lines
// 608-612), with the compiler's -include (ext/lota/engine/CMakeLists.txt).
// It includes LÖVE's header itself, whose include guard keeps the
// source's own #include from defining the macro again, and then defines
// it as Lota's. A fused game saves without the folder, as LÖVE's does
// (line 610), so it saves exactly where LÖVE's fused game does. No file
// of LÖVE's changes (ADR 001, section 2).

#ifndef LOTA_ENGINE_APPDATA_FOLDER_H
#define LOTA_ENGINE_APPDATA_FOLDER_H

#include "filesystem/Filesystem.h"

#undef LOVE_APPDATA_FOLDER
#ifdef LOVE_LINUX
#define LOVE_APPDATA_FOLDER "lota"
#else
#define LOVE_APPDATA_FOLDER "Lota"
#endif

#endif // LOTA_ENGINE_APPDATA_FOLDER_H
