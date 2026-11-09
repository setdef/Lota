<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# AGENTS.md

## Project

Lota (the `lota` gem) drives a modified build of LÖVE's C++ engine from Ruby (>= 4.0.1) instead of Lua. Rice (in `ext/`) is a thin binding over LÖVE's engine; Ruby owns the game loop and every API decision (ADR 001). The plan of record is `doc/contributors/plan/001.md`.

Pre-1.0, zero external users. Prefer good design over backward compatibility; record every breaking change in CHANGELOG.md.

## Design precedence

1. **Ruby the language.** What Ruby can and cannot express. Lua constructs with no Ruby meaning (tables as objects, metatables, `:` calls, multiple returns padded with `nil`) are translated, not ported.
2. **LÖVE fidelity.** Behavior MUST match LÖVE's source at the pinned commit: what happens, in what order, with what defaults and error messages. Nouns and primary verbs keep LÖVE's names.
3. **The translation rules.** ADR 001, section 7, is the only sanctioned way a Lota name differs from LÖVE's (`SpriteBatch.new` is `newSpriteBatch`, `title=` is `setTitle`, `down?` is `isDown`, symbols are strings, blocks are paired calls). Do not invent other "more Ruby-like" APIs. Read the rules from Ruby, as a Ruby developer does: each Lota name comes from a LÖVE name by these rules, or is Ruby's own. Earlier changes are not precedent; a case the rules do not settle goes to the maintainer as a new rule.
4. **Ruby culture.** Idioms yield to 1, 2, and 3.

The authority is the pinned submodule `vendor/love` (`git submodule update --init` if empty). For a function's arity, overloads, defaults, and errors, read its `wrap_*.cpp` file; for its behavior, read the C++ it calls. The LÖVE wiki and `love2d-community/love-api` mostly describe LÖVE 11; where they disagree with `vendor/love`, the source wins. For Rice, read its source at the version in `Gemfile.lock`. Never guess at a reference's contents. Cite the file and lines you ported, and add an SPDX snippet (`Zlib`) around any code or prose derived from LÖVE.

## Trademarks

Use "LÖVE", "LOVE", "Love2D", and LÖVE's heart logo only in ways that need no permission from their owner. Use the name only as plain text, and only where it is needed to say what Lota builds on, works with, or translates from ("builds a modified version of LÖVE's engine", "matching love.graphics.push"). Never put it in Lota's own names (project, gem, module, command, repository, domain, or product), except an identifier that must match LÖVE's API so that LÖVE code runs unchanged, such as the `love` method that `lota/compat` defines; such identifiers live only in opt-in compatibility code. Never use the logo or LÖVE's stylized artwork, and never word anything so it suggests the LÖVE Development Team made, endorses, or supports Lota. The README carries the statement that Lota is independent.

## Reporting upstream

LÖVE does not accept pull requests, bug reports, or other contributions made with LLM or generative AI tools (its README, in Contributing), and SDL asks that generative AI not be used in any way when contributing (its AGENTS.md), so an agent files nothing at LÖVE or SDL, and the maintainer does not report in an agent's place. What an agent finds wrong in LÖVE's engine or tests goes into a numbered file of its own, `doc/contributors/upstream/NNN.md` (the next number after the last), written as the report the agent would file if it could: what is wrong, where in LÖVE's source, how to reproduce it, and what Lota does about it. Lota works around a finding in its own code whenever it can. Only when it cannot may an agent consider a patch file (ADR 001, section 2) and say why nothing else works. A fork of LÖVE needs the maintainer's permission first. Read any other project's contribution policy before putting anything in its tracker.

## How to work

- Research before designing: read the LÖVE source and the relevant ADR in `doc/contributors/adr/` first.
- Root-cause every fix. If you cannot explain why a change fixed the symptom, it is not a fix.
- Write tests first. A test must fail if the code it covers is deleted or mutated, and must exercise real collaborators, not stubs that hide missing behavior. Where LÖVE's behavior is the contract, the story's acceptance test (Plan 001) is the test: a fixture someone else wrote, behaving as it does in LÖVE.
- Lota is a dependency of games, so the dependency points one way: nothing on trunk (code, tests, docs, comments, examples, CI) names or depends on a game that uses Lota. Examples use Lota's own sample names, such as "Sample Game". Temporary material, such as the Windows kit and experiment branches, is exempt, and history may mention a game. Likewise nothing on trunk refers to a particular agent; agents are ephemeral.
- Never edit `vendor/love`. Engine changes go in patch files in this repository (ADR 001, section 2), and every patch needs a reason it cannot be avoided.
- Design in the spirit of Kent Beck (small steps, Implementation Patterns), Freeman & Pryce (tests drive interfaces), Sandi Metz (duplication over the wrong abstraction), Rebecca Wirfs-Brock (responsibility-driven roles), Martin Fowler (refactor in behavior-preserving steps), and Matz (programmer happiness). Write prose in the style of `doc/contributors/documentation_style.md`.

## Ruby, RBS, and docs

- `Data.define` for value objects (`class Foo < Data.define(...)`), `class` for entities. Value types that games pass between Ractors must be frozen `Data` (ADR 001, section 6).
- Every Ruby method has an RBS signature in `sig/` mirroring `lib/`. No `untyped`, no comments in `.rbs`. For `Data.define` classes, declare `self.new` instead of `initialize` (Steep mis-checks `initialize` there); plain classes declare `initialize` as usual.
- RDoc (never YARD) in `.rb` files only. Wrap SPDX headers in `#--` / `#++`.
- Architectural decisions get an ADR; plans live in `doc/contributors/plan/`.
- Editing README.md or README.rdoc requires reading both files in full first, then rewriting for coherence, not appending.

## Commands

- Run Ruby with `bundle exec ruby`. Run tests with `bundle exec rake test`. Never `ruby -Ilib:test`.
- `bundle exec rake` is the gate: tests, RuboCop, RubyCritic, Steep, signature parity, RDoc coverage, REUSE, and the package check. It must pass with zero errors and zero warnings. Run `bundle exec rake rubocop:autocorrect_all` first to save time.
- Approved exceptions live in `rbs_exceptions.rb`; adding one needs a justification that it is impossible otherwise.
- Rake tasks use `git ls-files`: new or deleted files must be staged before they count.
- Always `PAGER=cat` for git.

## Provenance

The maintainer uses three words for how work comes to exist. *Written* means typed by hand, with nothing generated. *Wrought* means an agent generated it while the maintainer iterated with it and reviewed every change before committing it. *Requested* means an agent built it with little or no review.

Provenance belongs to each change, not to a kind of file, so one file can hold wrought and requested changes, and each commit's trailer says which it holds.

- **Wrought:** changes to ADRs and this file. The maintainer approves each one as a diff before it is committed.
- **Requested:** every other change, including changes to plans, which are made without the maintainer's review, and all code (`lib/`, `sig/`, `ext/`, `tasks/`, `test/`), patch files, the binding generator and everything it generates, the README, and the user guide. Because no one reviews this work line by line, the gates review it: sanitizers, clang-tidy, the memory test, the package check, and the parity harness. Never weaken a gate to make requested work pass.
- **Decisions** that belong to the maintainer as product owner go to the maintainer as questions, never as decisions: the public Ruby API, how a game is laid out and started, rule collisions, licensing, and anything that publishes outside this repository.
- **Tests:** the Lua side of every parity test comes from LÖVE's own Lövetest or from published LÖVE games, never from an agent, so a test checks Lota against something an agent did not write.
- **Generated code** is marked as generated in its header and is never edited by hand; change the rules or the generator instead.

A commit holds work of one provenance and says which in a `Provenance:` trailer (`written`, `wrought`, or `requested`). Work of both kinds goes in separate commits.

## Committing

- Work on `trunk`, never on a branch. Your working copy holds only commits you have not pushed yet, for minutes, not hours: sync with `origin/trunk`, make one small, complete change that keeps the build green, run the gate, sync again, and push. If the push is rejected, rebase onto `origin/trunk`, run the gate again, and push.
- Take other agents' work only from `trunk`, never from their working copies.
- Before changing what other agents are likely changing too, such as the binding generator, `ext/lota/bindings.rb`, or a test that counts Lövetest's tests, say so first.
- Work too big for one commit lands as small commits behind a feature flag or by branch by abstraction.
- A red build on `trunk` stops all other work until it is fixed or the commit that broke it is reverted.
- Never tag or release.
- Include any plan or ADR change in the commit whose work it describes.
- Conventional Commits, plain text, wrapped at 72. The body explains why this approach over alternatives, in prose (no lists, no markdown, no file inventories). Types: `lib/ext/sig` feat/fix/refactor/perf; `bin/tasks`/CI chore; `examples/` and `doc/` docs; `test/` test. End with the `Provenance:` trailer, then the AI footer shown by `git log -n1`.

## Changelog

Keep a Changelog + SemVer. Only changes downstream game or library developers can observe: public APIs, behavior, breaking changes, deprecations, dependency changes (including the pinned LÖVE commit). Not tests, docs, internal refactors, or tooling. Terse one-line entries under `## [Unreleased]`, which means "since the last tag": a change undone before the next tag removes its entry instead of adding a "Fixed" line. Never edit released sections.

## Definition of done

1. Every item in the plan is done, or explicitly deferred with a reason.
2. Behavior matches the cited LÖVE source; deviations are justified by the precedence above and documented.
3. `bundle exec rake` passes from a clean build (`rm -rf tmp`), zero errors, zero warnings.
4. RDoc, RBS, `doc/`, README, and CHANGELOG updated where behavior changed.
5. A commit message is written (and the commit made, per Committing).
