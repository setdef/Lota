# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "json"
require "lota/notices"

# Lota::Notices writes the notices file lota fuse puts in an app (ADR 002,
# Consequences): Lota's own license statement, always, then each
# component the gem's manifest names, and the text of every license. The
# components here are the shapes NativeGem writes into each platform's
# gem (Licensing#notices), and the license texts are the repository's
# own, so a test reads what a player would.
class NoticesTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  # Every license text the repository holds, by its SPDX identifier, as
  # the gem's LICENSES folder holds them.
  TEXTS = Dir[File.join(ROOT, "{LICENSES,ext/lota/licenses}/*.txt")].to_h do |path|
    [File.basename(path, ".txt").delete_prefix("LICENSE-"), File.read(path)]
  end.freeze

  OPENAL_SOURCE = {
    "file" => "sources/openal-soft-1.24.3.tar.bz2",
    "url" => "https://openal-soft.org/openal-releases/openal-soft-1.24.3.tar.bz2",
    "sha256" => "cb5e6197a1c0da0edcf2a81024953cc8fa8545c3b9474e48c852af709d587892",
    "license" => ["LGPL-2.0-or-later", "GPL-2.0-or-later", "Python-2.0"],
  }.freeze

  FREETYPE_CREDIT = "Portions of this software are copyright © 2021 The FreeType Project (www.freetype.org). " \
    "All rights reserved. This software is based in part of the work of the FreeType Team."

  def component(name, file:, version: nil, license: ["Zlib"], copyright: ["2026 #{name}"], credit: nil,
    separate: false, source: nil
  )
    {
"name" => name,
"version" => version,
"license" => license,
"copyright" => copyright,
"credit" => credit,
"file" => file,
"separate" => separate,
"source" => source,
}
  end

  # What the macOS gem's manifest names: works in the bundle, and each
  # framework, OpenAL Soft's with its source archive.
  def macos
    [
      component("LÖVE", version: "12.0", file: "lib/lota/native.bundle", copyright: ["2006-2026 LOVE Development Team"]),
      component("stb_image", file: "lib/lota/native.bundle", license: ["MIT OR Unlicense"]),
      component("FreeType", version: "2.11.1", file: "lib/lota/frameworks/freetype.framework", separate: true,
        license: ["FTL", "MIT", "MIT-open-group"], credit: FREETYPE_CREDIT),
      component("OpenAL Soft", version: "1.24.3", file: "lib/lota/frameworks/OpenAL-Soft.framework", separate: true,
        license: ["LGPL-2.0-or-later", "BSD-3-Clause", "MIT", "LicenseRef-PFFFT"], source: OPENAL_SOURCE),
    ]
  end

  # What the Windows gem's manifest names: every library but OpenAL Soft
  # compiled into the bundle, FreeType's credit with it.
  def windows
    [
      component("FreeType", version: "2.13.3", file: "lib/lota/native.so", license: ["FTL", "MIT"],
        credit: FREETYPE_CREDIT.sub("2021", "2024")),
      component("OpenAL Soft", version: "1.24.3", file: "lib/lota/libraries/OpenAL32.dll", separate: true,
        license: ["LGPL-2.0-or-later", "MIT"], source: OPENAL_SOURCE),
    ]
  end

  # What a phone's app would name: Apple's OpenAL, so no LGPL library and
  # no source to carry, and FreeType compiled into the app.
  def ios
    [component("FreeType", version: "2.11.1", file: "Lota", license: ["FTL"], credit: FREETYPE_CREDIT)]
  end

  def notices(components, platform: "arm64-darwin", gem_folder: "lib/ruby/gems/4.0.0/gems/lota-#{Lota::VERSION}-arm64-darwin")
    Lota::Notices.new(components: components.map { |hash| Lota::Notices::Component.from(hash).within(gem_folder) }, texts: TEXTS,
      platform:, gem_folder:)
  end

  # Lota's own statement opens every notices file, whatever the gem
  # carries, with the license the repository's LICENSE and gemspec give,
  # and that license's whole text.
  def test_lotas_own_license_statement_is_always_there
    gemspec = Gem::Specification.load(File.join(ROOT, "lota.gemspec"))

    [[], macos, windows, ios].each do |components|
      text = notices(components).text

      assert_includes text, "Lota #{Lota::VERSION}\n  Copyright 2026 setdef <kerrick@setdef.com>\n" \
        "  License: AGPL-3.0-or-later, the GNU Affero General Public License, version 3 or any later version\n"
      assert_includes text, "  Source code: #{gemspec.metadata.fetch('source_code_uri')}\n"
      assert_includes text, "\n==== AGPL-3.0-or-later ====\n\n#{File.read(File.join(ROOT, 'LICENSES/AGPL-3.0-or-later.txt'))}"
      assert_equal "AGPL-3.0-or-later", notices(components).licenses.first
    end
    assert_equal gemspec.license, Lota::Notices::LICENSE
    assert_includes File.read(File.join(ROOT, "LICENSE")), "GNU AFFERO GENERAL PUBLIC LICENSE\n                       Version 3"
  end

  # The statement is Lota's own: a gem's manifest cannot replace it, even
  # one that names a component Lota.
  def test_no_component_replaces_lotas_statement
    text = notices([component("Lota", file: "lib/lota/native.bundle", license: ["MIT"], copyright: ["2026 Someone"])]).text

    assert_includes text, "Lota #{Lota::VERSION}\n  Copyright 2026 setdef <kerrick@setdef.com>\n  License: AGPL-3.0-or-later"
  end

  def test_the_app_holds_the_gem_and_each_component_where_the_notices_say
    text = notices(macos).text
    gem = "lib/ruby/gems/4.0.0/gems/lota-#{Lota::VERSION}-arm64-darwin"

    assert_includes text, "  In this app: #{gem}\n"
    assert_includes text, "\nCompiled into Lota's extension, #{gem}/lib/lota/native.bundle:\n\nLÖVE 12.0\n  License: Zlib\n" \
      "  Copyright 2006-2026 LOVE Development Team\n"
    assert_includes text, "\nA library of its own, #{gem}/lib/lota/frameworks/freetype.framework:\n\nFreeType 2.11.1\n"
    assert_includes text, "\nstb_image\n  License: MIT OR Unlicense\n"
  end

  # On Windows the paths are written as Windows writes them, under the
  # runtime's ruby folder.
  def test_windows_paths_use_backslashes
    gem = "ruby/lib/ruby/gems/4.0.0/gems/lota-#{Lota::VERSION}-x64-mingw-ucrt"
    text = notices(windows, platform: "x64-mingw-ucrt", gem_folder: gem).text

    assert_includes text, "  In this app: #{gem.tr('/', '\\')}\n"
    assert_includes text, "Compiled into Lota's extension, #{gem.tr('/', '\\')}\\lib\\lota\\native.so:"
    assert_includes text, "  Source: #{gem.tr('/', '\\')}\\sources\\openal-soft-1.24.3.tar.bz2\n"
    assert_includes text, "the libraries Lota's gem for x64-mingw-ucrt carries"
  end

  # FreeType's license asks a binary's documentation to credit it
  # (ext/lota/licenses/LICENSE-FTL.txt, lines 35-56 and 116-120), in the
  # words it gives, wherever FreeType is.
  def test_freetype_is_credited_in_its_licenses_words
    ftl = File.read(File.join(ROOT, "ext/lota/licenses/LICENSE-FTL.txt"))

    assert_includes ftl.gsub(/\s+/, " "), "Portions of this software are copyright © <year> The FreeType Project (www.freetype.org). All rights reserved."
    assert_includes ftl.gsub(/\s+/, " "), "the software is based in part of the work of the FreeType Team"
    [macos, ios].each { |components| assert_includes notices(components).text, "  #{FREETYPE_CREDIT}\n" }
    assert_includes notices(windows).text, "copyright © 2024 The FreeType Project"
    refute_includes notices([]).text, "FreeType"
  end

  # OpenAL Soft's license asks for its source with its object code, and
  # for the library to be one a player can replace (LGPL-2.0-or-later,
  # sections 4 and 6): the notices say where its source archive is in the
  # app, where it was published, and that the library is a file of its
  # own. A gem without it says neither.
  def test_openal_softs_source_and_replacement_are_stated_only_where_it_ships
    gem = "lib/ruby/gems/4.0.0/gems/lota-#{Lota::VERSION}-arm64-darwin"
    text = notices(macos).text

    assert_includes text, "\nOpenAL Soft 1.24.3\n  License: LGPL-2.0-or-later, BSD-3-Clause, MIT, LicenseRef-PFFFT\n"
    assert_includes text, "  Source: #{gem}/sources/openal-soft-1.24.3.tar.bz2\n" \
      "  The source code of this library, as its authors released it, published at " \
      "https://openal-soft.org/openal-releases/openal-soft-1.24.3.tar.bz2, SHA-256 " \
      "cb5e6197a1c0da0edcf2a81024953cc8fa8545c3b9474e48c852af709d587892, with code under " \
      "LGPL-2.0-or-later, GPL-2.0-or-later, Python-2.0.\n"
    assert_includes text, "  Lota's extension loads this library from its own file, so the file can be replaced " \
      "with another build of the library.\n"
    %w[LGPL-2.0-or-later GPL-2.0-or-later Python-2.0].each { |id| assert_includes text, "\n==== #{id} ====\n" }

    [[], ios].each do |components|
      text = notices(components).text

      refute_includes text, "OpenAL"
      refute_includes text, "  Source: "
      refute_includes text, "LGPL"
      refute_includes text, "can be replaced"
    end
  end

  # Each license an expression names has its text once, in the order the
  # notices first name it: an OR names each choice, a WITH its exception.
  def test_each_license_named_has_its_text_once
    components = macos + [
component("glslang", file: "lib/lota/native.bundle",
  license: ["GPL-3.0-or-later WITH Bison-exception-2.2", "BSD-3-Clause"]),
]

    assert_equal %w[
      AGPL-3.0-or-later
      Zlib
      MIT
      Unlicense
      FTL
      MIT-open-group
      LGPL-2.0-or-later
      BSD-3-Clause
      LicenseRef-PFFFT
      GPL-2.0-or-later
      Python-2.0
      GPL-3.0-or-later
      Bison-exception-2.2
], notices(components).licenses
    assert_equal 1, notices(components).text.scan("\n==== MIT ====\n").size
  end

  def test_a_license_without_its_text_is_an_error
    error = assert_raises(Lota::Notices::Error) do
      Lota::Notices.new(components: [Lota::Notices::Component.from(component("X", file: "x", license: ["Zlib"]))],
        texts: TEXTS.except("Zlib"), platform: "arm64-darwin", gem_folder: "gems/lota").text
    end

    assert_equal "the gem has no text of Zlib in its LICENSES folder, which the notices name", error.message
  end

  # Notices.read takes the manifest and LICENSES folder a gem unpacks to.
  def test_it_reads_a_gems_manifest_and_license_texts
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "LICENSES"))
      %w[AGPL-3.0-or-later Zlib MIT Unlicense].each do |id|
        File.write(File.join(dir, "LICENSES", "#{id}.txt"), TEXTS.fetch(id))
      end
      File.write(File.join(dir, "notices.json"), JSON.generate("components" => macos.take(2)))

      read = Lota::Notices.read(dir, platform: "arm64-darwin", gem_folder: "gems/lota")

      assert_equal ["LÖVE", "stb_image"], read.components.map(&:name)
      assert_equal ["gems/lota/lib/lota/native.bundle"], read.components.map(&:file).uniq
      assert_includes read.text, "\n==== Unlicense ====\n"
      File.delete(File.join(dir, "notices.json"))
      error = assert_raises(Lota::Notices::Error) { Lota::Notices.read(dir, platform: "arm64-darwin", gem_folder: "gems/lota") }
      assert_equal "the gem has no notices.json", error.message
    end
  end
end
