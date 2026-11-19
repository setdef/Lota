// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// Lota::Native's entry point in an Android app, the one source mkmf
// compiles there (phone/android.rb), as native_ios.c is on iOS. CMake
// builds the extension itself, with its Init renamed lota_Init_native
// (cmake/LotaExtension.cmake), into a static archive that mkmf links with
// this file into libfledgeext.lota.native.so, whose Init_native Ruby
// calls when it loads the library at require "lota/native".

void lota_Init_native(void);

void Init_native(void);

void Init_native(void) { lota_Init_native(); }
