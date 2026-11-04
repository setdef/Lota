<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Releasing Lota

A game that depends on Lota installs it as a gem, and Lota's gem compiles nothing at install, so each platform gets a precompiled gem of its own (ADR 002, section 2). Building those gems by hand on five machines, and checking each one, is slow and easy to get wrong. So a release is a tag. You push it, and CI builds each platform's gem, runs the gate, installs the gem on a clean runner, runs Lövetest from it, and publishes exactly those gems as a GitHub release.

## When to cut a release

Cut one when a downstream project, such as Deckbuilder or a game, needs something on trunk that no release has yet. Tag a commit where every platform's gate and delivery passed. A release that lists a platform is a promise that its gem works there, so CI publishes nothing when any platform fails, rather than a release missing one.

## Versions before 1.0

Lota follows Semantic Versioning, and before 1.0.0 a version is `0.MINOR.PATCH`. A breaking change bumps MINOR (0.1.0 to 0.2.0). Anything else bumps PATCH (0.1.0 to 0.1.1). CHANGELOG.md marks each breaking change with **Breaking:**, so a glance at `[Unreleased]` tells you which to bump.

## Cutting a release

On a clean trunk that matches `origin/trunk`, prepare the version:

```sh
bundle exec rake release:prepare[0.1.0]
```

It refuses a tree with changes of its own, a branch other than trunk, a version that is not newer, and an empty `[Unreleased]`. Otherwise it makes three edits and nothing else:

- In CHANGELOG.md, `[Unreleased]`'s changes move under `## [0.1.0] - YYYY-MM-DD`, dated today, with a fresh, empty `## [Unreleased]` above. Released sections are never edited again.
- `Lota::VERSION` in lib/lota/version.rb becomes `"0.1.0"`.
- Gemfile.lock records `lota (0.1.0)`, so CI's frozen bundle still installs.

Review the diff, run the gate, and commit the three files as `chore: release 0.1.0`, with the trailers AGENTS.md asks for:

```sh
PAGER=cat git diff
bundle exec rake
```

Then tag that commit and push trunk before the tag:

```sh
git tag --annotate v0.1.0 --message "Lota 0.1.0"
git push origin trunk
git push origin v0.1.0
```

The tag is annotated and unsigned, since no signing key is configured here. Once one is, use `git tag --sign` instead.

## What CI does with the tag

A tag matching `v[0-9]*` runs the whole of `.github/workflows/ci.yml` on its commit. Each platform's gate builds a gem and records its SHA-256, and its delivery job checks that SHA-256, installs the gem into an empty `GEM_HOME`, runs Lövetest from it, checks the SHA-256 again, and uploads the gem it verified.

Windows works the same way with less. Its build job builds the engine with MinGW, runs the Windows checks and the tests that open no window, and builds the gem, but it does not run the gate. Its delivery job installs the gem on a runner without MSYS2 and runs a game that opens no window and plays a sound through the gem's `OpenAL32.dll`, because GitHub's Windows runners have no GPU and no OpenGL that LÖVE can draw with. So CI proves that a Windows gem installs, loads only its own DLLs and Windows', and runs a game. Only a Windows PC proves that it draws, takes input, and plays through a real audio device.

The release job then runs only if every one of those jobs passed. It refuses, before publishing anything, when:

- the tag's commit is not on trunk,
- the tag is not `v` and the version lib/lota/version.rb gives,
- CHANGELOG.md has no dated section for that version, or the section is empty,
- there is not exactly one verified gem for each platform, or a gem's name, specification, or SHA-256 disagrees with the one its delivery job verified.

It then creates the GitHub release for the tag, titled "Lota 0.1.0", with the CHANGELOG section as its notes, one gem for each platform, and SHA256SUMS:

```
lota-0.1.0-arm64-darwin.gem
lota-0.1.0-x86_64-linux-gnu.gem
lota-0.1.0-aarch64-linux-gnu.gem
lota-0.1.0-x64-mingw-ucrt.gem
lota-0.1.0-aarch64-mingw-ucrt.gem
SHA256SUMS
```

The release job's token may write the repository's contents, which a release is, and nothing else; no other job's token may write. CI never publishes to RubyGems. That is the maintainer's alone, and is never part of this procedure. Bundler's `rake release` task would push to RubyGems, so the Rakefile makes it refuse, along with the tasks it runs.

If a platform fails on the tag, nothing is published. Rerun the failed jobs if the failure was the runner's. Otherwise fix trunk and release the next PATCH version; never move a tag that has been pushed.

## Trying the release job

Run CI by hand on a branch (Actions, CI, "Run workflow", or `gh workflow run ci.yml --ref <branch>`). The release job then does everything but publish: it checks the tag lib/lota/version.rb's version would have, assembles the gems, and keeps them, SHA256SUMS, and the notes as the artifact `release-dry-run-v<version>`. The input `ignore_gate_failures` lets a dry run go on past a failing gate, to try the release job while a platform is red. It is for testing only, and is refused on a tag.

## Installing a release

No gem server carries Lota's gems yet. Download your platform's gem from the release and check it:

```sh
gh release download v0.1.0 --repo setdef/Lota --pattern 'lota-0.1.0-arm64-darwin.gem' --pattern SHA256SUMS
shasum -a 256 --check --ignore-missing SHA256SUMS
gem install --local lota-0.1.0-arm64-darwin.gem
```

On Windows, with RubyInstaller's Ruby, take `x64-mingw-ucrt` or `aarch64-mingw-ucrt`, whichever `ruby -e 'puts Gem::Platform.local'` prints, and compare PowerShell's `Get-FileHash` of the gem with its line in SHA256SUMS.

A project with a Gemfile vendors the gems instead. Put the gem for each platform the project runs on in its `vendor/cache`, ask for the version, and install from there. Bundler locks every platform it finds a gem for in `vendor/cache`.

```ruby
# Gemfile
gem "lota", "0.1.0"
```

```sh
bundle install --local
```
