<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Releasing Lota

A game that depends on Lota installs it as a gem, and Lota's gem compiles nothing at install, so each platform gets a precompiled gem of its own ([packaging.md](design/packaging.md)). Building those gems by hand on five machines, and checking each one, is slow and easy to get wrong. So a release is a tag on a commit CI has proven. CI builds each platform's gem, runs the gate, installs the gem on a clean runner, runs Lövetest from it, and publishes exactly those gems as a GitHub release, with LÖVE's engine and Lota's extension prebuilt for each phone target beside them, and Lota's app and the fuser for each desktop.

A release that waits for someone to remember it waits too long, and one that waits for trunk to stand still never comes, since agents push to trunk all day. So CI releases on its own, and a release is a pick, not a build-up: when a full run passes on trunk, its commit is released, however far trunk has moved on since, and nothing is written to trunk first. The bookkeeping, the dated section in CHANGELOG.md, follows on top of trunk afterward, and nothing waits for it.

## Who releases

Before 1.0.0, a release is a GitHub release and nothing more, and it may be cut by the automatic job, or by the maintainer or an agent tagging a commit and running CI on the tag. Whoever cuts it, the release is a tag on a trunk commit where every platform's gate and delivery passed, because the release job publishes nothing otherwise. From 1.0.0 on, agents never tag or release (AGENTS.md).

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

CI releases nothing at 1.0.0 or later on its own; those versions are tagged by hand. Nor does any release of 1.0.0 or later go out while mise.toml pins a Ruby that is not a release, such as `4.1.0-preview1` or a release candidate. 1.0.0 freezes Lota's API, so it ships only on the Ruby it will live on, Ruby 4.1.0, and on Fledge's runtimes built on it, as the maintainer decided on 2026-11-09 ([packaging.md](design/packaging.md), "Platform gems").

1.0.0 does not wait for LÖVE 12.0. `vendor/love` pins a commit of LÖVE's `main` branch, where 12.0 is developed, and 12.0 has no release date, so the maintainer decided on 2026-11-12 that 1.0.0 ships on the pinned commit. A move of the pin after that is a change like any other: the API check above marks what LÖVE renamed or removed as breaking, so it ships in a major release, and what LÖVE added ships in a minor one.

## What a release carries

**The notes** are the entries the commit's `[Unreleased]` adds since the release before it: those that the previous release tag's `[Unreleased]` did not already list. A commit CI picks may come before the last release's dated section reached trunk, so its `[Unreleased]` can still list that release's entries, and comparing with the previous tag leaves them out. `rake "release:notes[SHA,FILE]"` writes a commit's notes.

**The version** is stamped into the gems as CI builds them, never committed. In the repository, `Lota::VERSION` is `0.0.1.dev`, and so is any gem built from a clone, which sorts before every release, so `gem build`, `rake package:native`, `lota fuse`, and `bundle exec` all work in a clone with no tags fetched. In CI, the version job decides the commit's version before anything is built, and each job that builds a gem, or fuses with one, writes that version into lib/lota/version.rb and Gemfile.lock first (`.github/actions/version`, `rake "release:stamp[0.4.0]"`). The gems a release publishes are then the gems that run built and verified, and `Lota::VERSION` in them is the release's. A phone app has no published gem to install, so it is built from a clone, and the clone's tag is what knows its version: `rake phone:gem`, which lays out the gem a phone project names, stamps the version of a release tag on the clone's commit the same way, and puts the clone's files back afterward (doc/guide/phones.md).

**The phone engines** are LÖVE's engine and its libraries, built for each iOS slice and Android ABI by `.github/workflows/phone-engine.yml` from the commit being released, with its version, so a phone build can fetch them instead of compiling LÖVE ([the phone guide](../guide/phones.md), "Prebuilt engines"). A phone build fetches only the bytes `ext/lota/phone/engines.txt` pins, by release and checksum, and those checksums exist only once the engines are built, after the commit is picked. So the release never pins its own engines in its commit or its precompiled gems, which would mean writing to trunk first, or holding every gem's build until the engines are built. Two things carry the pin instead. **The source gem**, `lota-0.4.0.gem`, is built by the release job itself, once the engines exist, with the version stamped in and `ext/lota/phone/engines.txt` written into the working tree for this release, uncommitted, as the version is (`rake "release:source[DIR,0.4.0]"`). On a desktop its install stops and names the precompiled gems, as it always has; a phone build, which takes a gem's plain `ruby` build, fetches this release's engines from it, with no clone of Lota. And the bookkeeping pins them on trunk afterward (below), so a clone of trunk fetches the newest release's engines.

**The phone extensions** are Lota's extension, built by the same workflow for each iOS slice and Android ABI against those engines, inside a real `fledge build` on the phone Ruby of the Fledge Lota pins (`.github/phones/extension_build.sh`), so a phone build fetches it too and compiles only its three-line entry point. They are pinned beside the engines, in the same file and in the same two places. Each records the files it was built from and the Ruby it was built for, so a gem whose own files differ, as a clone of trunk does between releases, compiles its extension against the prebuilt engine instead, and a phone Ruby of another ABI is refused ([the phone guide](../guide/phones.md), "Prebuilt engines").

**The apps** are Lota's app, which plays a `.lota` as LÖVE's app plays a `.love`, and the fuser, which makes a `.lota` into an app of its own ([packaging.md](design/packaging.md), "A game in one file"), for each desktop, as a LÖVE release publishes LÖVE's app. Each comes as the archive a person unpacks and the installer Fledge writes beside it: a disk image on macOS, an AppImage on Linux, and a setup program on Windows. The fuse workflow builds them in the same run as `rake player` and `rake fuser` do, from the gems that run built, and runs each before the release job takes them (`rake "release:apps[DIR,FROM,PLATFORM...]"`). Each carries the release's version as its own, as LÖVE's app carries LÖVE's. GitHub stores an asset whose name has a space under another name, so the fuser's files are published with a period for the space, as `Lota.Fuser-arm64-darwin.dmg`, the name SHA256SUMS lists.

## The automatic release

Every full CI run ([ci.md](ci.md)) starts with the version job, which asks `rake release:version` what the run's commit releases as:

1. Nothing, when a release tag on that commit or a later one already holds it, as when a newer run released first.
2. Nothing, when the commit's `[Unreleased]` adds no entry since the last release, or the last release is 1.0.0 or later.
3. A refusal, for an API break with no **Breaking:** entry. It shows as the failed job "Refuse the release", but the run stays green: it stops a release, not trunk.
4. Otherwise the next PATCH, or the next MINOR for a **Breaking:** entry. Every gem the run builds carries it.

When every job of a run on trunk passes, the release job asks again, with the tags as they are now (`rake release:plan`). A release made while the run went on may hold the commit already, or have moved the version on, so that the gems carry the wrong one; then it releases nothing. Otherwise it creates the annotated tag `v0.4.0` on the run's commit, through the API, and publishes the release from the gems the run verified. It never needs the commit to be trunk's tip, and never pushes to trunk. If any job fails, there is no tag and no release, and the next green run releases what this one would have, with whatever trunk has added since.

Runs on trunk coalesce: while one runs, a newer push supersedes any that waits ([ci.md](ci.md)). That costs a release nothing, since one run proves every commit up to its own, and its commit is released like any other.

## The changelog afterward

After every full run on trunk, the changelog job writes, on top of trunk as it is then, a dated section in CHANGELOG.md for each release tag that has none: `## [0.4.0] - 2026-11-12`, dated the day of the tag, listing exactly the entries that release's commit added, moved out of `[Unreleased]`. Entries added since the tagged commit stay in `[Unreleased]`. It reads only the tags and their `[Unreleased]` sections, so it writes the same sections however often it runs (`Release#record`, and `rake changelog:record` locally).

The same job pins the phone engines. When the newest release tag's release published them and `ext/lota/phone/engines.txt` names another release, or none, it reads that release's SHA256SUMS and pins its engines, and its extensions if it published them, by their checksums there (`Release#pin_published_engines`), as `rake "phone:engine:pin[SHA256SUMS,v0.4.0]"` does by hand. A release from before the engines were published pins nothing. A release's own tag therefore pins an earlier release's engines, which a phone build at that tag fetches only if they were built from the same engine files, and otherwise asks for a build from source.

It pushes what it wrote as one ordinary commit, `chore: record v0.4.0 in the changelog`, or with `and pin v0.4.0's phone engines` when it pins them too, or `chore: pin the phone engines v0.4.0 published` when it only pins, with the trailers `Release`, `Recorded-by` (the run), `Red-before-green: none (release bookkeeping)`, and `Provenance: requested`. If trunk moves first, it rebases and tries again, three times in all; if it still cannot push, the run stays green, and the next run's changelog job writes the section and the pin then.

So `[Unreleased]` lists what has changed since the last release's tagged commit, and CI writes every released section; nobody writes or edits one by hand. A released entry is fixed by a new entry, never by editing it, since the notes compare entries word for word. `rake changelog:check` checks the file against the tags: each release has its section, CI's list exactly what their release added, and those from before CI recorded releases match their own tag's section word for word.

## Releasing by hand

Do this for a version the automatic release will not cut, such as 1.0.0, or to release a commit before its run would. Pick a trunk commit whose full run passed, ask what it releases as, tag it, and run CI on the tag:

```sh
bundle exec rake "release:version[SHA]"
git tag --annotate v0.4.0 --message "Lota 0.4.0" SHA
git push origin v0.4.0
gh workflow run ci.yml --ref v0.4.0
```

Pushing a tag starts no run, so a tag the release job makes costs no second full run; CI runs on a tag only when you ask for it. That run is a full run of its own. Its version job checks the tag (`rake "release:version[SHA,v0.4.0]"`) and refuses one that is not `v` and MAJOR.MINOR.PATCH, one not newer than the last release, a commit that adds no entry, an API break with no **Breaking:** entry, a **Breaking:** entry released without a MINOR bump (MAJOR from 1.0.0 on), and 1.0.0 or later while Ruby is a preview; a refusal fails the run, and nothing is released. When every job passes, the release job publishes the gems that run built, which carry the tag's version, and the next full run on trunk records the section.

The tag is annotated and unsigned, since no signing key is configured here. Once one is, use `git tag --sign` instead. Never move or delete a tag that has been pushed.

## What CI checks before it publishes

Each platform's gate builds a gem and records its SHA-256, and its delivery job checks that SHA-256, installs the gem into an empty `GEM_HOME`, runs Lövetest from it, checks the SHA-256 again, and uploads the gem it verified.

Windows works the same way with less. Its build job builds the engine with MinGW, runs the Windows checks, builds the gem, and then runs Lota's tests, Lövetest's among them, on Mesa's software OpenGL, as LÖVE's own Windows CI runs Lövetest, but it does not run the gate. Its delivery job installs the gem on a runner without MSYS2 and runs a game that opens no window and plays a sound through the gem's `OpenAL32.dll`. So CI proves that a Windows gem installs, loads only its own DLLs and Windows', runs a game, and draws as LÖVE does on a software renderer. Only a Windows PC proves that it draws on a GPU, takes real input, and plays through a real audio device.

The same run checks the phone route, the iOS kit, both as Lota's CI and as a game's CI call it, and `lota fuse` on every platform, with the gems the run built, and builds the four phone engines and the four phone extensions, each kind with its SHA256SUMS (the job **Phone engines**), the extensions inside a `fledge build` whose second build, from both kinds of bundle, must compile none of Lota. The phone route builds its engine from source, so nothing in the run builds a phone app from the engines it publishes; `phone-engine.yml` run by hand, with `compare_with_source`, builds them again on other runners, checks they are the same bytes, and checks that a phone build from them matches one from source. The release job then runs only if every one of those jobs passed. It refuses, before tagging or publishing anything, when:

- the commit is not on trunk,
- the tag `v` and the version already points at another commit,
- GitHub has a release of the version without its tag,
- there is not exactly one verified gem of the version for each platform, or a gem's name, specification, or SHA-256 disagrees with the one its delivery job verified,
- the phone engines are not one for each target with the SHA256SUMS their job wrote, or one is not the bytes that SHA256SUMS names (`rake "release:engines[DIR,FROM]"`), and the same for the phone extensions (`rake "release:extensions[DIR,FROM]"`),
- the source gem it builds is not lota of the version for every platform, does not carry the pin of this release's engines and extensions, or installs on the release job's runner instead of stopping with the message that names the precompiled gems,
- a platform has no artifact of Lota's app or of the fuser, or one holds anything but the archive and the installer Fledge writes for it and the lockfile it was built from, or the release already holds one of their files (`rake "release:apps[DIR,FROM,PLATFORM...]"`).

`rake release:plan` decides what the release still needs, so running the job again is safe. With no tag, it tags the commit and publishes. With the tag on the commit and no release, it publishes. With both, it does nothing.

It then creates the GitHub release for the tag, titled "Lota 0.4.0", with the notes, one gem for each platform, the phone engines and extensions, the source gem, Lota's app and the fuser for each desktop, and one SHA256SUMS for them all:

```
lota-0.4.0-arm64-darwin.gem
lota-0.4.0-x86_64-linux-gnu.gem
lota-0.4.0-aarch64-linux-gnu.gem
lota-0.4.0-x64-mingw-ucrt.gem
lota-0.4.0-aarch64-mingw-ucrt.gem
lota-0.4.0.gem
lota-engine-ios-arm64.tar.gz
lota-engine-ios-arm64-simulator.tar.gz
lota-engine-android-arm64-v8a.tar.gz
lota-engine-android-x86_64.tar.gz
lota-extension-ios-arm64.tar.gz
lota-extension-ios-arm64-simulator.tar.gz
lota-extension-android-arm64-v8a.tar.gz
lota-extension-android-x86_64.tar.gz
Lota-arm64-darwin.tar.gz
Lota-arm64-darwin.dmg
Lota-x86_64-linux.tar.gz
Lota-x86_64-linux.AppImage
Lota-aarch64-linux.tar.gz
Lota-aarch64-linux.AppImage
Lota-x64-mingw-ucrt.zip
Lota-x64-mingw-ucrt-setup.exe
Lota-aarch64-mingw-ucrt.zip
Lota-aarch64-mingw-ucrt-setup.exe
Lota.Fuser-arm64-darwin.tar.gz
Lota.Fuser-arm64-darwin.dmg
...
Lota.Fuser-aarch64-mingw-ucrt-setup.exe
SHA256SUMS
```

The fuser's files follow the app's, platform by platform. Each app's archive is about as large as a fused game's, some 58 MB on Linux, so the apps add about a gigabyte to the gems and phone bundles, which came to some 200 MB in 0.7.1 and uploaded in seven seconds. Releases up to 0.7.0 carry the gems alone, and 0.7.1 adds the phone engines and the source gem; the phone extensions and the apps come with the releases after it.

Only two jobs' tokens may write, and only the repository's contents: the release job's, for a tag and a release, and the changelog job's, to push its commit. No other job's token may write. The release job reads, tags, and publishes with the repository's `RELEASE_TOKEN` secret when there is one, in place of its own token, and gives it only to the steps that call GitHub; no other job uses a secret. A commit the changelog job pushes starts no run of its own, since GitHub's own token starts none, and no tag starts a run, whichever token makes it, since CI runs on pushes to branches alone. So nothing publishes twice, and a release costs no second full run.

## When a release stops

If a platform fails, nothing is tagged or published. Rerun the failed jobs if the failure was the runner's; the release job runs when they pass. Otherwise fix trunk, and the next green run releases the next version, over the fix. If GitHub refuses the tag, the release job fails at "Tag the commit", naming the call it refused, the tag object (`git/tags`) or its ref (`git/refs`), with what `gh` printed; that is the token's right to tag, not the commits, so the automatic revert reports it and reverts nothing ([ci.md](ci.md)). Give the job a token that may tag, as `RELEASE_TOKEN`, and rerun it.

## Rehearsing a release

Run CI by hand on a branch other than trunk (Actions, CI, "Run workflow", or `gh workflow run ci.yml --ref <branch>`). The run decides its commit's version and stamps its gems as on trunk, and its release job does everything but publish: it decides what it would do, says so, with the branch's tip beside the commit it picked, assembles the gems and the phone engines, builds the source gem, and keeps them, SHA256SUMS, and the notes as the artifact `release-dry-run-v<version>`. It tags nothing, publishes nothing, and pushes nothing. Push to the branch while the run goes on, with `[skip ci]` in the message so no run of its own supersedes this one, and the rehearsal shows a pick of a commit that is no longer the tip.

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
