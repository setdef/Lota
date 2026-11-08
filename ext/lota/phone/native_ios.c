// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// Lota::Native's entry point on a phone, the one source mkmf compiles
// there (phone/ios.rb). CMake builds the extension itself, with its Init
// renamed lota_Init_native (cmake/LotaExtension.cmake), into a static
// archive the app links; Fledge compiles this file with Init_native
// renamed again, to the name its registration of "lota/native" calls.

void lota_Init_native(void);

void Init_native(void);

void Init_native(void) { lota_Init_native(); }
