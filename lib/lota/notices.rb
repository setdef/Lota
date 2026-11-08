# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "json"
require_relative "version"

module Lota
  # The notices file an app built with <tt>lota fuse</tt> carries (ADR
  # 002, Consequences).
  #
  # A fused game ships Lota and the libraries Lota's gem carries: LÖVE's
  # engine and what it bundles, compiled into Lota's extension, and the
  # libraries the extension loads, among them FreeType, whose license asks
  # for a credit in a product's documentation, and OpenAL Soft, under the
  # LGPL, which ships as a library of its own with its source. A player who
  # opens the app's folder should find what it holds and under which
  # licenses without reading a gem's REUSE.toml.
  #
  # Notices writes that file, as text, from facts alone: Lota's own license
  # statement, which every notices file opens with; then each component of
  # the gem's manifest (Component), with its version where it is known, its
  # licenses, its notices of copyright, and where in the app it is; and the
  # text of each license it names. NativeGem writes the manifest into each
  # platform's gem, from ext/lota/licenses.rb, with only what that gem
  # carries (Licensing#notices), so each platform's notices name what its
  # app holds. A phone's app, which links Lota from no gem, can hand
  # Notices the components its own build carries.
  #
  # Use it through Lota::Fuse, which writes FILE into the project Fledge
  # builds.
  #
  # === Example
  #
  #   notices = Lota::Notices.read("unpacked/lota-0.2.0-arm64-darwin", platform: "arm64-darwin",
  #     gem_folder: "lib/ruby/gems/4.0.0/gems/lota-0.2.0-arm64-darwin")
  #   File.write("NOTICES.txt", notices.text)
  class Notices
    # The error Notices raises when a gem lacks what its notices need.
    class Error < StandardError; end

    # The file Notices writes, at the top of the project, which Fledge puts
    # in the app's +app+ folder.
    FILE = "NOTICES.txt"

    # The gem's manifest of what it carries (Licensing#notices).
    MANIFEST = "notices.json"

    # Where the gem keeps the text of each license, as REUSE asks.
    LICENSES = "LICENSES"

    # Lota's own license, which LICENSE and the gemspec give.
    LICENSE = "AGPL-3.0-or-later"

    # The license's name, as its text gives it.
    LICENSE_NAME = "the GNU Affero General Public License, version 3 or any later version"

    # Lota's notice of copyright, as its files give it.
    COPYRIGHT = "2026 setdef <kerrick@setdef.com>"

    # Where Lota's source code is published.
    SOURCE = "https://github.com/setdef/lota"

    # One component the gem carries, as its manifest names it.
    #
    # [name] What it is called.
    # [version] Its version, or +nil+ where it is not known.
    # [license] The SPDX license expressions it is under.
    # [copyright] Its notices of copyright.
    # [credit] The words its license asks a product's documentation to
    #   carry, or +nil+.
    # [file] The file of the app that holds it, relative to the folder that
    #   holds the app's +app+ folder. A manifest gives it relative to the
    #   gem, which #within places in the app.
    # [separate] Whether that file is a library of its own, rather than
    #   Lota's extension, which compiles it in.
    # [source] The Source of its code the app carries, or +nil+.
    class Component < ::Data.define(:name, :version, :license, :copyright, :credit, :file, :separate, :source)
      # Its name, then its version when known.
      #
      # === Example
      #
      #   component.title # => "OpenAL Soft 1.24.3"
      def title
        [name, version].compact.join(" ")
      end

      # This component of a gem at +folder+ in the app: its file and its
      # source's, which a manifest gives relative to the gem, relative to the
      # folder that holds the app's +app+ folder, as +folder+ is.
      #
      # === Example
      #
      #   component.within("lib/ruby/gems/4.0.0/gems/lota-0.2.0").file
      #   # => "lib/ruby/gems/4.0.0/gems/lota-0.2.0/lib/lota/native.bundle"
      def within(folder)
        archive = source
        with(file: File.join(folder, file), source: archive && archive.with(file: File.join(folder, archive.file)))
      end

      # The Component a manifest's entry describes, a Hash from JSON.
      def self.from(entry)
        source = entry["source"]
        new(name: entry.fetch("name"), version: entry["version"], license: entry.fetch("license"),
          copyright: entry.fetch("copyright"), credit: entry["credit"], file: entry.fetch("file"),
          separate: entry.fetch("separate") == true, source: source && Source.new(file: source.fetch("file"),
            url: source.fetch("url"), sha256: source.fetch("sha256"), license: source.fetch("license")))
      end
    end

    # The archive of a component's source code the app carries.
    #
    # [file] The archive, relative to the folder that holds the app's +app+
    #   folder, or in a manifest relative to the gem.
    # [url] Where it was published.
    # [sha256] Its SHA-256, in hexadecimal.
    # [license] The SPDX license expressions of everything in it.
    class Source < ::Data.define(:file, :url, :sha256, :license)
    end

    # The Notices of the gem unpacked in +dir+, from its MANIFEST and the
    # license texts in its LICENSES. Raises Error when it has no manifest.
    #
    # [platform] The String platform the app is built for.
    # [gem_folder] Where the gem is in the app, relative to the folder that
    #   holds the app's +app+ folder.
    def self.read(dir, platform:, gem_folder:)
      manifest = File.join(dir, MANIFEST)
      raise Error, "the gem has no #{MANIFEST}" unless File.file?(manifest)

      components = JSON.parse(File.read(manifest, encoding: Encoding::UTF_8)).fetch("components").map do |entry|
        Component.from(entry).within(gem_folder)
      end
      texts = Dir.glob("*.txt", base: File.join(dir, LICENSES)).to_h do |name|
        [File.basename(name, ".txt"), File.read(File.join(dir, LICENSES, name), encoding: Encoding::UTF_8)]
      end
      new(components:, texts:, platform:, gem_folder:)
    end

    # The components the notices name, in the manifest's order.
    attr_reader :components

    # [components] Each Component the app holds, where it is in the app
    #   (Component#within).
    # [texts] Each license's text, by its SPDX identifier.
    # [platform] The String platform the app is built for.
    # [gem_folder] Where the gem is in the app, relative to the folder that
    #   holds the app's +app+ folder, with / between its folders.
    def initialize(components:, texts:, platform:, gem_folder:)
      @components = components
      @texts = texts
      @platform = platform
      @gem_folder = gem_folder
    end

    # Each license the notices name, by its SPDX identifier, once, in the
    # order they first name it: LICENSE, then each component's, then its
    # source's. An expression's choices (OR, AND) and exceptions (WITH)
    # count each on its own.
    def licenses
      expressions = @components.flat_map { |component| component.license + (component.source&.license || []) }
      [LICENSE, *expressions.flat_map { |expression| identifiers(expression) }].uniq
    end

    # The notices, as text. Raises Error when a license they name has no
    # text.
    def text
      texts = licenses.map do |id|
        text = @texts.fetch(id) { raise Error, "the gem has no text of #{id} in its #{LICENSES} folder, which the notices name" }
        "==== #{id} ====\n\n#{text.end_with?("\n") ? text : "#{text}\n"}"
      end
      [introduction, lota, *groups, "License texts\n", *texts].join("\n")
    end

    private def introduction
      "Notices for Lota #{VERSION} and the libraries it ships\n\n" \
        "lota fuse wrote this file as it built this app for #{@platform}. It names Lota and the libraries Lota's " \
        "gem for #{@platform} carries, with the version of each where it is known, its licenses, and its notices " \
        "of copyright, and ends with the text of every license it names. Each path is relative to the folder that " \
        "holds this file's folder. Fledge's notices#{separator}NOTICES.txt, in that folder, names Ruby and the rest " \
        "of the runtime the app runs on.\n"
    end

    private def lota
      <<~TEXT
        Lota #{VERSION}
          Copyright #{COPYRIGHT}
          License: #{LICENSE}, #{LICENSE_NAME}
          Source code: #{SOURCE}
          In this app: #{path(@gem_folder)}
          The REUSE.toml file and the #{LICENSES} folder there give the license of each of the gem's files.
      TEXT
    end

    # Each file of the gem that holds components, with them: Lota's
    # extension, then each library of its own.
    private def groups
      @components.group_by(&:file).map do |file, components|
        where = components.first&.separate ? "A library of its own" : "Compiled into Lota's extension"
        "#{where}, #{path(file)}:\n\n#{components.map { |component| entry(component) }.join("\n")}"
      end
    end

    private def entry(component)
      lines = [component.title, "  License: #{component.license.join(', ')}"]
      lines += component.copyright.map { |notice| "  Copyright #{notice}" }
      lines << "  #{component.credit}" if component.credit
      if component.separate
        lines << "  Lota's extension loads this library from its own file, so the file can be replaced with another " \
          "build of the library."
      end
      lines += source(component.source) if component.source
      "#{lines.join("\n")}\n"
    end

    private def source(source)
      [
        "  Source: #{path(source.file)}",
        "  The source code of this library, as its authors released it, published at #{source.url}, SHA-256 " \
          "#{source.sha256}, with code under #{source.license.join(', ')}.",
      ]
    end

    private def identifiers(expression)
      expression.delete("()").split(/\s+(?:OR|AND|WITH)\s+/).map(&:strip)
    end

    private def windows?
      @platform.include?("mingw")
    end

    private def separator
      windows? ? "\\" : "/"
    end

    private def path(relative)
      windows? ? relative.tr("/", "\\") : relative
    end
  end
end
