# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "digest"
require "json"
require_relative "engine"

module Lota
  # Lota's extension, Lota::Native, built once for each iOS slice and
  # Android ABI against the Ruby of Fledge's phone runtime and the prebuilt
  # engine, as a static archive, so a phone build compiles none of it and
  # needs neither CMake nor Rice. It is packed, pinned, and fetched as the
  # engine is (PhoneEngine), from the same release and the same pin.
  #
  # Each target's bundle, named by #asset, holds:
  #
  # [lib/liblota_native.a] The extension, its Init function renamed
  #                        lota_Init_native, as cmake/LotaExtension.cmake
  #                        renames it for a phone.
  # [link.txt] What links it, as phone_link.txt has it: the engine's
  #            archives and flags, with the engine's folder written as
  #            ENGINE, for #link to put the fetched engine's in.
  # [manifest.json] The target, Lota's version, #digest of the files it
  #                 was built from, the tag of the Fledge whose phone Ruby
  #                 it was built against, and that Ruby, as Headers.
  #
  # Ruby's own rule says which Ruby an extension may load into. A released
  # Ruby keeps its ABI for every teeny version of its minor one, and its
  # +ruby_version+ is the minor version's, 4.1.0; a development Ruby, a
  # preview's, names its ABI in +ruby_version+ too (4.1.0+5,
  # RUBY_ABI_VERSION in include/ruby/internal/abi.h), and is the only kind
  # that defines one. So #fetch refuses a bundle built for another
  # +ruby_version+, and, for a development Ruby, whose ABI number its
  # makers bump by hand, a bundle built against other headers, unless the
  # build can compile the extension instead; and a bundle built from other
  # files than the gem's, a pin older than the gem, is compiled instead.
  #
  # === Example
  #
  #   extension = Lota::PhoneExtension.new("android-x86_64", ext: "ext/lota",
  #     headers: Lota::PhoneExtension::Headers.of(RbConfig::CONFIG))
  #   extension.fetch(cache: Lota::PhoneEngine.cache) if extension.pinned? # => the unpacked bundle's folder
  class PhoneExtension < PhoneEngine
    # The files, relative to ext/lota, whose content the extension is
    # built from: the engine's (PhoneEngine::DIGESTED), whose headers it
    # compiles against, and the extension's own.
    DIGESTED = (PhoneEngine::DIGESTED + %w[
      cmake/LotaExtension.cmake
      cmake/LotaWarnings.cmake
      native/**/*
    ]).freeze

    # What stands for the engine's folder in link.txt.
    ENGINE = "${LOTA_ENGINE}"

    # The phone Ruby an extension is built against: its +ruby_version+,
    # and the SHA-256 of its headers.
    class Headers < ::Data.define(:ruby_version, :digest)
      # The Headers of the Ruby whose configuration is +config+, an
      # RbConfig::CONFIG: of every file in its +rubyhdrdir+ and
      # +rubyarchhdrdir+, by its path there and its content.
      def self.of(config)
        folders = [config.fetch("rubyhdrdir"), config.fetch("rubyarchhdrdir")].uniq
        lines = folders.each_with_index.flat_map do |folder, index|
          Dir.glob("**/*", base: folder).sort.select { |file| File.file?(File.join(folder, file)) }.map do |file|
            "#{index}/#{file}\0#{Digest::SHA256.file(File.join(folder, file)).hexdigest}\n"
          end
        end
        new(ruby_version: config.fetch("ruby_version"), digest: Digest::SHA256.hexdigest(lines.join))
      end

      # Whether it is a development Ruby's, which names its ABI after a +.
      def development?
        ruby_version.include?("+")
      end
    end

    # The asset's name for +target+.
    def self.asset(target)
      "lota-extension-#{target}.tar.gz"
    end

    # The SHA-256 of the files under +ext+ the extension is built from.
    def self.digest(ext)
      PhoneEngine.digest(ext, DIGESTED)
    end

    # Writes the bundle for +target+ into the folder +into+, from the
    # extension's archive at +archive+, built from the files under +ext+
    # against +headers+, the Ruby of the Fledge whose tag is +fledge+, and
    # the engine unpacked at +engine+, which the lines of phone_link.txt,
    # +link+, name. Returns the bundle's path.
    def self.pack(into:, target:, archive:, link:, engine:, ext:, headers:, fledge:, version:)
      manifest = {
        "target" => target,
        "lota" => version,
        "extension_digest" => digest(ext),
        "fledge" => fledge,
        "ruby_version" => headers.ruby_version,
        "ruby_headers_digest" => headers.digest,
      }
      path = File.join(into, asset(target))
      # CMake may name the engine's folder by its real path.
      engines = [engine, (File.realpath(engine) if File.exist?(engine))].compact.uniq
      lines = link.map { |line| engines.reduce(line) { |text, folder| text.gsub(folder, ENGINE) } }
      PhoneEngine.pack(path, {
        "lib/liblota_native.a" => File.binread(archive),
        "link.txt" => lines.map { |line| "#{line}\n" }.join,
        "manifest.json" => "#{JSON.pretty_generate(manifest)}\n",
      })
      path
    end

    # The lines of link.txt in the bundle unpacked at +folder+, with the
    # engine unpacked at +engine+.
    def self.link(folder, engine)
      File.readlines(File.join(folder, "link.txt"), chomp: true).reject(&:empty?).map { |line| line.gsub(ENGINE, engine) }
    end

    # Raised inside #fetch for a bundle built from other files than the
    # gem's: a pin a gem built between releases carries, naming the last
    # release's extension.
    class Stale < Failure; end

    # Raised by #fetch for a bundle built against a Ruby whose ABI may not
    # be the phone Ruby's.
    class OtherRuby < Failure; end

    # [target] One of TARGETS.
    # [headers] The Headers of the phone Ruby the build is for.
    # [compiles] Whether this build can compile the extension itself, as
    #            it can given the rice gem's directory.
    # The rest are PhoneEngine.new's.
    def initialize(target, headers:, compiles: false, **)
      super(target, **)
      @headers = headers
      @compiles = compiles
    end

    # What the bundle holds, as messages name it.
    def noun
      "extension"
    end

    # PhoneEngine#fetch, but +nil+, saying why, when the extension is to be
    # compiled instead: when the pinned bundle was built from other files
    # than the gem's, as when a gem built between releases pins the last
    # release's, and when it was built for another Ruby and this build can
    # compile it. Otherwise raises OtherRuby for another Ruby, and Failure
    # for any other mismatch.
    def fetch(cache:)
      super
    rescue Stale => e
      compile(e)
    rescue OtherRuby => e
      raise unless @compiles

      compile(e)
    end

    private def compile(reason)
      @out.puts("#{reason.message} So Lota compiles its extension for #{@target}.")
      nil
    end

    # An extension's manifest must name this gem's files, and a Ruby whose
    # ABI is the phone Ruby's.
    private def check_manifest(folder, manifest)
      unless manifest["extension_digest"] == self.class.digest(@ext)
        raise Stale, "The extension this Lota pins for #{@target} was built from other files than #{@ext}'s " \
          "(extension digest #{manifest['extension_digest']}, not #{self.class.digest(@ext)})."
      end
      built = "The extension this Lota pins for #{@target} was built for Ruby #{manifest['ruby_version']}, the " \
        "phone Ruby of Fledge #{manifest['fledge']},"
      unless manifest["ruby_version"] == @headers.ruby_version
        raise OtherRuby, "#{built} and this phone's Ruby is #{@headers.ruby_version}, whose ABI differs. " \
          "#{next_steps(manifest)}"
      end
      if @headers.development? && manifest["ruby_headers_digest"] != @headers.digest
        raise OtherRuby, "#{built} and this phone's Ruby has other headers, which alone tell a development " \
          "Ruby's ABI. #{next_steps(manifest)}"
      end
      folder
    end

    # What a developer does about an extension built for another Ruby.
    private def next_steps(manifest)
      "Name Fledge #{manifest['fledge']} in the Gemfile, or compile the extension for this Ruby: pass " \
        "--with-rice-dir=DIR, the rice gem's directory, with CMake on PATH."
    end
  end
end
