# Shipping a Lota game

## For a player

`lota fuse path/to/game` turns a game folder into an app for the platform you
run it on, through [Fledge](https://github.com/setdef/Fledge): a folder and
archive, and where Fledge makes them an installer. See the README's "Sharing a
game" for what each platform needs installed and the exact options
(`--out`, `--identifier`, `--icon`, `--app-version`, `--sign`).

Things a game author should know:

- `lota fuse` ships Lota, the game's folder, and the gems the game's
  `Gemfile.lock` locks, at those versions, without the `development` and
  `test` groups. It refuses a Gemfile with no `Gemfile.lock` beside it
  (run `bundle install`), a lockfile that does not lock the platform being
  built (run `bundle lock --add-platform PLATFORM`, with that platform's
  `.gem` in `vendor/cache` for a gem only `vendor/cache` holds, such as
  Lota), and a lockfile that locks another version of Lota than the one
  running `lota fuse`. The game's Gemfile need not ask for Lota; `lota fuse`
  adds it.
- Pure-Ruby gems, gems from RubyGems.org, Git, a folder inside the game, and
  the game's `vendor/cache` all ride along. A gem with a C extension and no
  build for the platform compiles on the building computer, so that
  computer needs a C compiler: Xcode's command line tools on macOS
  (`xcode-select --install`), a C compiler and `make` on Linux
  (`build-essential`), RubyInstaller's MSYS2 tools on Windows
  (`ridk install`). Without one, `lota fuse` fails after Bundler names the
  gem and says what to install. Build each platform's app on that platform:
  an extension compiles for the computer it compiles on.
- Each gem ships whole, with the license files its package holds; honoring
  each gem's license (`bundle licenses` lists them) is the game author's
  job, and a gem whose package leaves out its license text needs it added
  to the notices the author ships.
- A game folder's `.git`, `.bundle`, `vendor/bundle`, and `vendor/cache` are
  left out of the app's copy of the game; the gems in `vendor/cache` go to
  the build, not the game folder. Settings in the game's `.bundle/config`
  (such as `build.NAME` options for an extension) do not reach the build.
- The app saves under your `t.identity`, as LÖVE's fused game does.
- The identifier is a reverse-DNS name (`com.example.Game`); the default is a
  placeholder: set your own before you ship.
- Unsigned apps trigger Windows SmartScreen and macOS Gatekeeper prompts; that
  is expected until you sign.
- A fused game does not restart yet.

## Phones and tablets

Experimental. Lota's iOS and iPadOS build has run in the Simulator on CI and an
Android build has run on an emulator; nothing is verified on a real device in
Lota's own tests. Read the current state in the contributor plan
([doc/contributors/plan/002.md](https://github.com/setdef/Lota/blob/trunk/doc/contributors/plan/002.md),
"Phones") before promising a phone build, and tell the person plainly what has
and has not run on real hardware. A phone build needs the platform's tools
(Xcode for iOS, the Android NDK for Android) on a machine you build on.

## Licence

Lota is AGPL-3.0-or-later, and a commercial licence for a proprietary game is
sold at https://www.setdef.com/lota. Its gem carries LÖVE's engine (Zlib) and
the libraries it uses under their own licences, recorded in the gem's
`REUSE.toml` and `LICENSES/`; a proprietary game must still honor those (for
example OpenAL Soft's LGPL: keep it replaceable). Whether the AGPL fits how a
game ships is a question for the game's owner and their lawyer; do not answer
it for them.
