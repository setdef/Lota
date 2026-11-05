# Shipping a Lota game

## For a player

`lota fuse path/to/game` turns a game folder into an app for the platform you
run it on, through [Fledge](https://github.com/setdef/Fledge): a folder and
archive, and where Fledge makes them an installer. See the README's "Sharing a
game" for what each platform needs installed and the exact options
(`--out`, `--identifier`, `--icon`, `--app-version`, `--sign`).

Things a game author should know:

- `lota fuse` ships Lota and the game's folder, and does not yet honor the
  game's own Gemfile: pure-Ruby code a game needs can be vendored into the
  game folder, but a gem with a native extension cannot be carried by
  `lota fuse` today (LÖVE lets a game ship native libraries beside it; this
  is a gap). A project of your own built with Fledge can carry such gems.
  `lota fuse` warns when a Gemfile has other gems.
- A game folder's `.git`, `.bundle`, `vendor/bundle`, and `vendor/cache` are
  left out of the app.
- The app saves under your `t.identity`, as LÖVE's fused game does.
- The identifier is a reverse-DNS name (`com.example.Game`, with a domain of yours in place of `example.com`); the default is a
  placeholder: set your own before you ship.
- Unsigned apps trigger Windows SmartScreen and macOS Gatekeeper prompts; that
  is expected until you sign.
- A fused game does not restart yet.

## Phones and tablets

Experimental. Lota's iOS and iPadOS build has run in the Simulator on CI and an
Android build has run on an emulator; nothing is verified on a real device in
Lota's own tests. `lota fuse` builds no phone app: follow the phone guide
([doc/guide/phones.md](https://github.com/setdef/Lota/blob/trunk/doc/guide/phones.md)),
which builds one with Fledge from a clone of Lota, and tell the person plainly
what has and has not run on real hardware (its last section). A phone build
needs the platform's tools (Xcode and XcodeGen for iOS; a JDK, the Android SDK,
and the NDK for Android) on a machine you build on.

## Licence

Lota is AGPL-3.0-or-later, and a commercial licence for a proprietary game is
sold at https://www.setdef.com/lota. Its gem carries LÖVE's engine (Zlib) and
the libraries it uses under their own licences, recorded in the gem's
`REUSE.toml` and `LICENSES/`; a proprietary game must still honor those (for
example OpenAL Soft's LGPL: keep it replaceable). Whether the AGPL fits how a
game ships is a question for the game's owner and their lawyer; do not answer
it for them.
