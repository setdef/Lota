<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Releasing Lota

A game that depends on Lota installs it as a gem, and Lota's gem compiles nothing at install, so each platform gets a precompiled gem of its own ([packaging.md](design/packaging.md)). Building those gems by hand on five machines, and checking each one, is slow and easy to get wrong. So a release is a tag on a commit CI has proven. CI builds each platform's gem, runs the gate, installs the gem on a clean runner, runs Lövetest from it, and publishes exactly those gems as a GitHub release.

A release that waits for someone to remember it waits too long, and one that waits for trunk to stand still never comes, since agents push to trunk all day. So CI releases on its own, and a release is a pick, not a build-up: when a full run passes on trunk, its commit is released, however far trunk has moved on since, and nothing is written to trunk first. The bookkeeping, the dated section in CHANGELOG.md, follows on top of trunk afterward, and nothing waits for it.

## Who releases

Before 1.0.0, a release is a GitHub release and nothing more, and it may be cut by the automatic job, by the maintainer, or by an agent pushing a tag. Whoever cuts it, the release is a tag on a trunk commit where every platform's gate and delivery passed, because the release job publishes nothing otherwise. From 1.0.0 on, agents never tag or release (AGENTS.md).

Publishing to RubyGems.org is the maintainer's alone, and never part of this procedure. Bundler's `rake release` task would push to RubyGems, so the Rakefile makes it refuse, along with the tasks it runs.

## Versions before 1.0

Lota follows Semantic Versioning, and before 1.0.0 a version is `0.MINOR.PATCH`. A breaking change bumps MINOR (0.1.0 to 0.2.0). Anything else bumps PATCH (0.1.0 to 0.1.1). CHANGELOG.md marks each breaking change with **Breaking:** at the start of its entry, so a glance at `[Unreleased]` tells you which to bump.

The version is decided at the commit being released, from two things git holds: the newest release tag before that commit, and the entries the commit's `[Unreleased]` adds since that tag (below). `rake release:version` prints it for HEAD, or for any commit you name:

```sh
bundle exec rake release:version
bundle exec rake "release:version[3e4f000]"
```

An entry is easy to write without the mark, so the decision checks for it. It compares the API that sig/ declares under `Lota`, the signatures of lib/ and of the extension, at the commit with the API at the last release's tag (`tasks/api_diff.rb`):

- **Additions only:** the bump stands.
- **A Breaking: entry:** MINOR, whatever sig/ shows.
- **Something removed or changed, and no Breaking: entry:** it refuses, and prints each method, attribute, constant, class, module, or type it found removed or changed, as it was and as it is now.

A method counts as changed when one of its old overloads has no new overload that takes every call the old one took and returns nothing it did not promise. A wider parameter, a new optional parameter, or a narrower return keeps it; so does a type alias or a subclass that covers the old type. Anything else counts as changed, so the check errs toward asking. Answer a refusal by adding the **Breaking:** entry, or by restoring the API, or its signature, if the change was not meant to break anything.

CI releases nothing at 1.0.0 or later on its own; those versions are tagged by hand. Nor does any release of 1.0.0 or later go out while mise.toml pins a preview of Ruby: a 1.0 is a promise about the Ruby it runs on.

## What a release carries

**The notes** are the entries the commit's `[Unreleased]` adds since the release before it: those that the previous release tag's `[Unreleased]` did not already list. A commit CI picks may come before the last release's dated section reached trunk, so its `[Unreleased]` can still list that release's entries, and comparing with the previous tag leaves them out. `rake "release:notes[SHA,FILE]"` writes a commit's notes.

**The version** is stamped into the gems as CI builds them, never committed. In the repository, `Lota::VERSION` is `0.0.1.dev`, and so is any gem built from a clone, which sorts before every release, so `gem build`, `rake package:native`, `lota fuse`, and `bundle exec` all work in a clone with no tags fetched. In CI, the version job decides the commit's version before anything is built, and each job that builds a gem, or fuses with one, writes that version into lib/lota/version.rb and Gemfile.lock first (`.github/actions/version`, `rake "release:stamp[0.4.0]"`). The gems a release publishes are then the gems that run built and verified, and `Lota::VERSION` in them is the release's.

## The automatic release

Every full CI run ([ci.md](ci.md)) starts with the version job, which asks `rake release:version` what the run's commit releases as:

1. Nothing, when a release tag on that commit or a later one already holds it, as when a newer run released first.
2. Nothing, when the commit's `[Unreleased]` adds no entry since the last release, or the last release is 1.0.0 or later.
3. A refusal, for an API break with no **Breaking:** entry. It shows as the failed job "Refuse the release", but the run stays green: it stops a release, not trunk.
4. Otherwise the next PATCH, or the next MINOR for a **Breaking:** entry. Every gem the run builds carries it.

When every job of a run on trunk passes, the release job asks again, with the tags as they are now (`rake release:plan`). A release made while the run went on may hold the commit already, or have moved the version on, so that the gems carry the wrong one; then it releases nothing. Otherwise it creates the annotated tag `v0.4.0` on the run's commit, through the API, and publishes the release from the gems the run verified. It never needs the commit to be trunk's tip, and never pushes to trunk. If any job fails, there is no tag and no release, and the next green run releases what this one would have, with whatever trunk has added since.

Runs on trunk coalesce: while one runs, a newer push supersedes any that waits ([ci.md](ci.md)). That costs a release nothing, since one run proves every commit up to its own, and its commit is released like any other.

Until the workflow's `LOTA_RELEASE_TRUNK` is `"true"`, a green run on trunk only says what it would release, as a rehearsal does below, and a tag pushed by hand still releases.

## The changelog afterward

After every full run on trunk, the changelog job writes, on top of trunk as it is then, a dated section in CHANGELOG.md for each release tag that has none: `## [0.4.0] - 2026-11-12`, dated the day of the tag, listing exactly the entries that release's commit added, moved out of `[Unreleased]`. Entries added since the tagged commit stay in `[Unreleased]`. It pushes an ordinary commit, `chore: record v0.4.0 in the changelog`, with the trailers `Release`, `Recorded-by` (the run), `Red-before-green: none (release bookkeeping)`, and `Provenance: requested`. If trunk moves first, it rebases and tries again, three times in all; if it still cannot push, the run stays green, and the next run's changelog job writes the section then. It reads only the tags and their `[Unreleased]` sections, so it writes the same sections however often it runs (`Release#record`, and `rake changelog:record` locally).

So `[Unreleased]` lists what has changed since the last release's tagged commit, and CI writes every released section; nobody writes or edits one by hand. A released entry is fixed by a new entry, never by editing it, since the notes compare entries word for word. `rake changelog:check` checks the file against the tags: each release has its section, CI's list exactly what their release added, and those from before CI recorded releases match their own tag's section word for word.

## Releasing by hand

Do this for a version the automatic release will not cut, such as 1.0.0, or to release a commit before its run would. Pick a trunk commit whose full run passed, ask what it releases as, and tag it:

```sh
bundle exec rake "release:version[SHA]"
git tag --annotate v0.4.0 --message "Lota 0.4.0" SHA
git push origin v0.4.0
```

The tag's run is a full run of its own. Its version job checks the tag (`rake "release:version[SHA,v0.4.0]"`) and refuses one that is not `v` and MAJOR.MINOR.PATCH, one not newer than the last release, a commit that adds no entry, an API break with no **Breaking:** entry, a **Breaking:** entry released without a MINOR bump (MAJOR from 1.0.0 on), and 1.0.0 or later while Ruby is a preview; a refusal fails the run, and nothing is released. When every job passes, the release job publishes the gems that run built, which carry the tag's version, and the next full run on trunk records the section.

The tag is annotated and unsigned, since no signing key is configured here. Once one is, use `git tag --sign` instead. Never move or delete a tag that has been pushed.

## What CI checks before it publishes

Each platform's gate builds a gem and records its SHA-256, and its delivery job checks that SHA-256, installs the gem into an empty `GEM_HOME`, runs Lövetest from it, checks the SHA-256 again, and uploads the gem it verified.

Windows works the same way with less. Its build job builds the engine with MinGW, runs the Windows checks, builds the gem, and then runs Lota's tests, Lövetest's among them, on Mesa's software OpenGL, as LÖVE's own Windows CI runs Lövetest, but it does not run the gate. Its delivery job installs the gem on a runner without MSYS2 and runs a game that opens no window and plays a sound through the gem's `OpenAL32.dll`. So CI proves that a Windows gem installs, loads only its own DLLs and Windows', runs a game, and draws as LÖVE does on a software renderer. Only a Windows PC proves that it draws on a GPU, takes real input, and plays through a real audio device.

The same run checks the phone route, the iOS kit, both as Lota's CI and as a game's CI call it, and `lota fuse` on every platform, with the gems the run built. The release job then runs only if every one of those jobs passed. It refuses, before tagging or publishing anything, when:

- the commit is not on trunk,
- the tag `v` and the version already points at another commit,
- GitHub has a release of the version without its tag,
- there is not exactly one verified gem of the version for each platform, or a gem's name, specification, or SHA-256 disagrees with the one its delivery job verified.

`rake release:plan` decides what the release still needs, so running the job again is safe. With no tag, it tags the commit and publishes. With the tag on the commit and no release, it publishes. With both, it does nothing.

It then creates the GitHub release for the tag, titled "Lota 0.4.0", with the notes, one gem for each platform, and SHA256SUMS:

```
lota-0.4.0-arm64-darwin.gem
lota-0.4.0-x86_64-linux-gnu.gem
lota-0.4.0-aarch64-linux-gnu.gem
lota-0.4.0-x64-mingw-ucrt.gem
lota-0.4.0-aarch64-mingw-ucrt.gem
SHA256SUMS
```

Only two jobs' tokens may write, and only the repository's contents: the release job's, for a tag and a release, and the changelog job's, to push its commit. No other job's token may write, and none uses another secret. A tag the release job makes through the API, and a commit the changelog job pushes, start no run of their own, so nothing publishes twice.

## When a release stops

If a platform fails, nothing is tagged or published. Rerun the failed jobs if the failure was the runner's; the release job runs when they pass. Otherwise fix trunk, and the next green run releases the next version, over the fix.

## Rehearsing a release

Run CI by hand on a branch other than trunk (Actions, CI, "Run workflow", or `gh workflow run ci.yml --ref <branch>`). The run decides its commit's version and stamps its gems as on trunk, and its release job does everything but publish: it decides what it would do, says so, with the branch's tip beside the commit it picked, assembles the gems, and keeps them, SHA256SUMS, and the notes as the artifact `release-dry-run-v<version>`. It tags nothing, publishes nothing, and pushes nothing. Push to the branch while the run goes on, with `[skip ci]` in the message so no run of its own supersedes this one, and the rehearsal shows a pick of a commit that is no longer the tip.

The input `ignore_gate_failures` lets a dry run go on past a failing gate, to try the release job while a platform is red. It is for testing only, and is refused wherever the run would publish.

## Installing a release

No gem server carries Lota's gems yet. Download your platform's gem from the release and check it:

```sh
gh release download v0.4.0 --repo setdef/Lota --pattern 'lota-0.4.0-arm64-darwin.gem' --pattern SHA256SUMS
shasum -a 256 --check --ignore-missing SHA256SUMS
gem install --local lota-0.4.0-arm64-darwin.gem
```

On Windows, with RubyInstaller's Ruby, take `x64-mingw-ucrt` or `aarch64-mingw-ucrt`, whichever `ruby -e 'puts Gem::Platform.local'` prints, and compare PowerShell's `Get-FileHash` of the gem with its line in SHA256SUMS.

A project with a Gemfile vendors the gems instead. Put the gem for each platform the project runs on in its `vendor/cache`, ask for the version, and install from there. Bundler locks every platform it finds a gem for in `vendor/cache`.

```ruby
# Gemfile
gem "lota", "0.4.0"
```

```sh
bundle install --local
```
