#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Checks an iOS app's privacy manifest against what its executable
# imports, for .github/workflows/phones.yml. Apple requires an app to
# declare, in PrivacyInfo.xcprivacy, a reason for each category of
# "required reason" API it calls ("Describing use of required reason
# API", developer.apple.com). The executable is the Release device build,
# where SDL, the engine, and Lota are linked statically, so the imports
# of `nm -u` are the APIs the app can call. This prints every import that
# matches a listed API, by category, and exits 1 when a category is
# imported but the manifest does not declare it.
#
# Two kinds of import are known and never fail the check, though they are
# printed:
#
# - getattrlist, fgetattrlist, and getattrlistat, which Apple lists under
#   DiskSpace as well as FileTimestamp. Ruby calls them to learn a
#   volume's type, not its space (Fledge's audit of Ruby's dir.c), so
#   no DiskSpace reason is true of them, and the app declares
#   FileTimestamp for them already.
# - CFPreferences, which SDL calls to read the system's scroll direction
#   when a mouse or trackpad connects. Apple's list names no CFPreferences
#   API (only UserDefaults), so no category exists to declare.
#
# If App Store Connect ever flags either, the finding belongs in
# doc/guide/phones.md, not in a silent exception here.
#
#   privacy_imports.sh EXECUTABLE MANIFEST
#
# NM overrides the command that lists undefined symbols (default
# "xcrun nm"), as the test does.
# shellcheck disable=SC2016,SC2001 # Patterns and sed programs are literal.
set -euo pipefail
executable=$1
manifest=$2
nm_command=${NM:-xcrun nm}

# category;imports that need it declared;imports that are known
table='NSPrivacyAccessedAPICategoryFileTimestamp;^_(stat|fstat|fstatat|lstat|getattrlist|fgetattrlist|getattrlistat|getattrlistbulk|NSURLContentModificationDateKey|NSURLCreationDateKey|NSFileCreationDate|NSFileModificationDate)$;
NSPrivacyAccessedAPICategorySystemBootTime;^_mach_absolute_time$;
NSPrivacyAccessedAPICategoryDiskSpace;^_(statfs|statvfs|fstatfs|fstatvfs|NSURLVolume(AvailableCapacity|AvailableCapacityForImportantUsage|AvailableCapacityForOpportunisticUsage|TotalCapacity)Key|NSFileSystemFreeSize|NSFileSystemSize)$;^_(getattrlist|fgetattrlist|getattrlistat)$
NSPrivacyAccessedAPICategoryUserDefaults;^_OBJC_CLASS_\$_NSUserDefaults$;
NSPrivacyAccessedAPICategoryActiveKeyboards;^_OBJC_CLASS_\$_UITextInputMode$;
none: CFPreferences;;^_CFPreferences'

# shellcheck disable=SC2086 # nm_command is a command and its arguments.
imports=$($nm_command -u "$executable" | sed -E 's/^[[:space:]]+//; s/\$(INODE64|DARWIN_EXTSN|UNIX2003)$//' | sort -u)

declared=$(plutil -convert json -o - "$manifest" | grep -o 'NSPrivacyAccessedAPICategory[A-Za-z]*' | sort -u || true)
echo "declared in $manifest:"
sed 's/^/  /' <<< "${declared:-}"
[ -n "$declared" ] || echo "  (none)"

status=0
while IFS=';' read -r category needed known; do
  matched=""
  if [ -n "$needed" ]; then
    matched=$(grep -E -- "$needed" <<< "$imports" || true)
  fi
  known_matched=""
  if [ -n "$known" ]; then
    known_matched=$(grep -E -- "$known" <<< "$imports" || true)
  fi
  if [ -n "$matched" ]; then
    echo "$category: imported"
    sed 's/^/  /' <<< "$matched"
    if ! grep -qx -- "$category" <<< "$declared"; then
      echo "::error::$executable imports $(tr '\n' ' ' <<< "$matched")for $category, and $manifest does not declare it"
      status=1
    fi
  fi
  if [ -n "$known_matched" ]; then
    echo "$category: known, not checked"
    sed 's/^/  /' <<< "$known_matched"
  fi
done <<< "$table"

[ "$status" -eq 0 ] && echo "every imported category is declared"
exit "$status"
