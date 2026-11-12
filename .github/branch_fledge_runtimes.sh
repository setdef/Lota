#!/bin/bash
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Branch proof only, never on trunk: Fledge's Ruby 4.1 runtimes from a CI
# run of its experiment/ruby-4.1-trunk branch, which no release holds yet.
#
# Usage: .github/branch_fledge_runtimes.sh PLATFORM...
#
# Downloads the run's runtime-PLATFORM artifact for each PLATFORM into one
# flat folder, as FLEDGE_RUNTIME_DIR wants it, and names that folder in
# GITHUB_ENV. A phone build needs the phone's runtime and the one for the
# computer it builds on. The runtimes are not checked against Fledge's
# pins, so lota fuse builds with the same commit's Fledge
# (LOTA_FLEDGE_REF), whose launcher reads only the fledge.cfg its own
# fledge build writes. GH_TOKEN must be set.
set -euo pipefail
[ $# -gt 0 ] || { echo "usage: branch_fledge_runtimes.sh PLATFORM..." >&2; exit 64; }
run=42767887631
temp=$RUNNER_TEMP
command -v cygpath > /dev/null && temp=$(cygpath -u "$RUNNER_TEMP")
dir="$temp/fledge-runtimes"
rm -rf "$dir" "$dir.download"
mkdir -p "$dir"
for platform in "$@"; do
  if command -v gh > /dev/null; then
    gh run download "$run" -R setdef/Fledge -n "runtime-$platform" -D "$dir.download"
  else
    # A container without the GitHub CLI: the artifact's zip, through the API.
    id=$(curl --fail --silent --show-error -H "Authorization: Bearer $GH_TOKEN" \
      "https://api.github.com/repos/setdef/Fledge/actions/runs/$run/artifacts?per_page=100" |
      ruby -rjson -e 'print JSON.parse($stdin.read)["artifacts"].find { |a| a["name"] == ARGV[0] }.fetch("id")' "runtime-$platform")
    mkdir -p "$dir.download"
    curl --fail --location --silent --show-error -H "Authorization: Bearer $GH_TOKEN" -o "$dir.download/a.zip" \
      "https://api.github.com/repos/setdef/Fledge/actions/artifacts/$id/zip"
    (cd "$dir.download" && unzip -q a.zip && rm a.zip)
  fi
  find "$dir.download" -type f -exec mv {} "$dir" \;
  rm -rf "$dir.download"
done
ls -l "$dir"
if command -v cygpath > /dev/null; then
  echo "FLEDGE_RUNTIME_DIR=$(cygpath -w "$dir")" >> "$GITHUB_ENV"
else
  echo "FLEDGE_RUNTIME_DIR=$dir" >> "$GITHUB_ENV"
fi
