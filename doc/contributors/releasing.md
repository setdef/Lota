<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Releasing Lota

A game that depends on Lota installs it as a gem, and Lota's gem compiles nothing at install, so each platform gets a precompiled gem of its own ([packaging.md](design/packaging.md)). Building those gems by hand on five machines, and checking each one, is slow and easy to get wrong. So a release is a tag on a commit CI has proven. CI builds each platform's gem, runs the gate, installs the gem on a clean runner, runs Lövetest from it, and publishes exactly those gems as a GitHub release.

A release that waits for someone to remember it waits too long, so CI cuts one on its own whenever trunk is green and has something to release. You can still cut one by hand.

## Who releases

Before 1.0.0, a release is a GitHub release and nothing more, and it may be cut by the automatic job, by the maintainer, or by an agent. Whoever cuts it, the release is a tag on a trunk commit where every platform's gate and delivery passed, because the release job publishes nothing otherwise. From 1.0.0 on, agents never tag or release (AGENTS.md).

Publishing to RubyGems.org is the maintainer's alone, and never part of this procedure. Bundler's `rake release` task would push to RubyGems, so the Rakefile makes it refuse, along with the tasks it runs.

## Versions before 1.0

Lota follows Semantic Versioning, and before 1.0.0 a version is `0.MINOR.PATCH`. A breaking change bumps MINOR (0.1.0 to 0.2.0). Anything else bumps PATCH (0.1.0 to 0.1.1). CHANGELOG.md marks each breaking change with **Breaking:** at the start of its entry, so a glance at `[Unreleased]` tells you which to bump.

An entry is easy to write without the mark, so `rake release:next` checks for it. It compares the API that sig/ declares under `Lota`, the signatures of lib/ and of the extension, with the API at the last release's tag (`tasks/api_diff.rb`):

- **Additions only:** the bump stands.
- **A Breaking: entry:** MINOR, whatever sig/ shows.
- **Something removed or changed, and no Breaking: entry:** it refuses, and prints each method, attribute, constant, class, module, or type it found removed or changed, as it was and as it is now.

A method counts as changed when one of its old overloads has no new overload that takes every call the old one took and returns nothing it did not promise. A wider parameter, a new optional parameter, or a narrower return keeps it; so does a type alias or a subclass that covers the old type. Anything else counts as changed, so the check errs toward asking. Answer a refusal by adding the **Breaking:** entry, or by restoring the API, or its signature, if the change was not meant to break anything.

Lota 1.0.0 freezes its API, and ships only on a released Ruby, never a preview or a release candidate ([ADR 013](adr/013.md)). So while `mise.toml` pins a Ruby that is not a release, such as `4.1.0-preview1`, `release:prepare` and the release job refuse 1.0.0 and every version after it.

## The automatic release

When a full CI run passes on a push to trunk, its `prepare-release` job looks for a release to cut ([ci.md](ci.md)):

1. If trunk has moved past the run's commit, it stops. The newer commit's own full run tries again when it passes.
2. `rake release:next` decides the version. It releases nothing while the last release commit's version has no tag yet, so one release is in flight at a time, and nothing when `[Unreleased]` lists no changes. From 1.0.0 on, it releases nothing, and releases are cut by hand.
3. `rake release:prepare` moves `[Unreleased]` under the version, as below, and the job commits it as `chore: release 0.3.2`, with the trailers `Released-by` (the run), `Red-before-green: none (release)`, and `Provenance: requested`.
4. It pushes the commit to trunk, never with force. If trunk moved meanwhile, the push is refused and the job stops.
5. It starts CI on trunk with the input `release_tag` set to `v0.3.2`. A push made with GitHub's own token starts no workflow, so CI on the release commit has to be started by `workflow_dispatch`, the one event that token can start.

That run is a full run of its own, in a concurrency group of its own, so no push to trunk cancels it while it waits. When every job passes, the release job creates the annotated tag `v0.3.2` on the commit, through the API, and publishes the release from the gems that run verified. If any job fails, there is no tag and no release.

The job's own failures, such as a refusal from `release:next`, show as a failed `prepare-release` job, but the run stays green: they stop a release, not trunk.

## Cutting a release by hand

Do this when the automatic release stalled, or for a version the automatic job will not cut, such as 1.0.0. On a clean trunk that matches `origin/trunk`, prepare the version:

```sh
bundle exec rake release:next
bundle exec rake release:prepare[0.3.2]
```

`release:next` prints the version it would cut, and refuses an API break with no **Breaking:** entry. `release:prepare` refuses a tree with changes of its own, a branch other than trunk, a version that is not newer, 1.0.0 or later on a Ruby that is not a release, and an empty `[Unreleased]`. Otherwise it makes three edits and nothing else:

- In CHANGELOG.md, `[Unreleased]`'s changes move under `## [0.3.2] - YYYY-MM-DD`, dated today, with a fresh, empty `## [Unreleased]` above. Released sections are never edited again.
- `Lota::VERSION` in lib/lota/version.rb becomes `"0.3.2"`.
- Gemfile.lock records `lota (0.3.2)`, so CI's frozen bundle still installs.

Review the diff, run the gate, and commit the three files as `chore: release 0.3.2`, with the trailers AGENTS.md asks for:

```sh
PAGER=cat git diff
bundle exec rake
```

Then push trunk, and either tag the commit and push the tag:

```sh
git push origin trunk
git tag --annotate v0.3.2 --message "Lota 0.3.2"
git push origin v0.3.2
```

or start CI on the commit and let it tag the commit when every job passes:

```sh
git push origin trunk
gh workflow run ci.yml --ref trunk -f release_tag=v0.3.2
```

The tag is annotated and unsigned, since no signing key is configured here. Once one is, use `git tag --sign` instead. Never move or delete a tag that has been pushed.

## What CI does before it publishes

A tag matching `v[0-9]*`, or a run with `release_tag`, runs the whole of `.github/workflows/ci.yml` on its commit. Each platform's gate builds a gem and records its SHA-256, and its delivery job checks that SHA-256, installs the gem into an empty `GEM_HOME`, runs Lövetest from it, checks the SHA-256 again, and uploads the gem it verified.

Windows works the same way with less. Its build job builds the engine with MinGW, runs the Windows checks, builds the gem, and then runs Lota's tests, Lövetest's among them, on Mesa's software OpenGL, as LÖVE's own Windows CI runs Lövetest, but it does not run the gate. Its delivery job installs the gem on a runner with only the MSYS2 that the pinned head build of RubyInstaller loads zlib from ([windows.md](windows.md)) and runs a game that opens no window and plays a sound through the gem's `OpenAL32.dll`. So CI proves that a Windows gem installs, loads only its own DLLs and Windows', runs a game, and draws as LÖVE does on a software renderer. Only a Windows PC proves that it draws on a GPU, takes real input, and plays through a real audio device.

The same run checks the phone route, the iOS kit, and `lota fuse` on every platform, with the gems the run built. The release job then runs only if every one of those jobs passed. It refuses, before tagging or publishing anything, when:

- the commit is not on trunk,
- the tag is not `v` and the version lib/lota/version.rb gives,
- the version is 1.0.0 or later and `mise.toml` pins a Ruby that is not a release,
- CHANGELOG.md has no dated section for that version, or the section is empty,
- the tag already points at another commit,
- there is not exactly one verified gem for each platform, or a gem's name, specification, or SHA-256 disagrees with the one its delivery job verified.

`rake release:plan` decides what the release still needs, so running the job again is safe. With no tag, it tags the commit and publishes. With the tag on the commit and no release, it publishes. With both, it does nothing. A run started with `release_tag` on a commit whose `[Unreleased]` lists changes is not on a release commit, as when trunk moved before the run started; it publishes nothing and warns.

It then creates the GitHub release for the tag, titled "Lota 0.3.2", with the CHANGELOG section as its notes, one gem for each platform, and SHA256SUMS:

```
lota-0.3.2-arm64-darwin.gem
lota-0.3.2-x86_64-linux-gnu.gem
lota-0.3.2-aarch64-linux-gnu.gem
lota-0.3.2-x64-mingw-ucrt.gem
lota-0.3.2-aarch64-mingw-ucrt.gem
SHA256SUMS
```

Only two jobs' tokens may write. The release job's may write the repository's contents, which a tag and a release are, and `prepare-release`'s may write contents, to push its commit, and start workflows. No other job's token may write, and none uses another secret. A tag the release job makes through the API starts no run of its own, so nothing publishes twice.

## When a release stops

If a platform fails on the release commit, nothing is tagged or published. Rerun the failed jobs if the failure was the runner's; the release job runs when they pass. Otherwise fix trunk, and the next green run releases the next PATCH version over it.

While a release commit's version has no tag, `release:next` cuts no other release, and says so in each `prepare-release` job. If its run cannot be rerun, release the commit by hand: tag it and push the tag, as above.

## Rehearsing a release

Run CI by hand on a branch (Actions, CI, "Run workflow", or `gh workflow run ci.yml --ref <branch>`). The release job then does everything but publish: it checks the tag lib/lota/version.rb's version would have, assembles the gems, and keeps them, SHA256SUMS, and the notes as the artifact `release-dry-run-v<version>`. The input `ignore_gate_failures` lets a dry run go on past a failing gate, to try the release job while a platform is red. It is for testing only, and is refused on a tag or with `release_tag`.

To rehearse the automatic release, run CI by hand on a branch other than trunk with `rehearse_auto_release`. When that run passes, `prepare-release` commits the release to the branch, not trunk, and starts CI on the branch with `release_tag`. That run's release job decides what the release needs, says what it would have done on trunk, and keeps the artifact, but tags and publishes nothing.

## Installing a release

No gem server carries Lota's gems yet. Download your platform's gem from the release and check it:

```sh
gh release download v0.3.2 --repo setdef/Lota --pattern 'lota-0.3.2-arm64-darwin.gem' --pattern SHA256SUMS
shasum -a 256 --check --ignore-missing SHA256SUMS
gem install --local lota-0.3.2-arm64-darwin.gem
```

On Windows, with RubyInstaller's Ruby, take `x64-mingw-ucrt` or `aarch64-mingw-ucrt`, whichever `ruby -e 'puts Gem::Platform.local'` prints, and compare PowerShell's `Get-FileHash` of the gem with its line in SHA256SUMS.

A project with a Gemfile vendors the gems instead. Put the gem for each platform the project runs on in its `vendor/cache`, ask for the version, and install from there. Bundler locks every platform it finds a gem for in `vendor/cache`.

```ruby
# Gemfile
gem "lota", "0.3.2"
```

```sh
bundle install --local
```
