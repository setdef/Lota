# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "digest"
require "fileutils"
require "json"
require "net/http"
require "openssl"
require "timeout"
require "uri"
require "zlib"

module Lota
  # LÖVE's engine and its libraries, built once for each iOS slice and
  # Android ABI by Lota's CI and published with each release, so a phone
  # build compiles only Lota's extension and needs no clone of Lota.
  #
  # Each target's bundle is a gzipped tar archive, named by #asset, that
  # holds:
  #
  # [lib/] liblota_engine.a, LÖVE's engine with Lota's patches, and every
  #        library it links for the target: on iOS static archives, SDL3
  #        among them, and on Android SDL3 and OpenAL Soft as shared
  #        libraries beside the static ones.
  # [include/] The engine's public header folders, in the order the
  #            compiler searches them.
  # [engine.cmake] An imported target, +lota_engine+, which Lota's CMake
  #                project includes in place of building the engine
  #                (ext/lota/CMakeLists.txt, LOTA_ENGINE_DIR), and which
  #                writes phone_link.txt as dependencies_ios.cmake and
  #                dependencies_android.cmake do.
  # [manifest.json] The target, Lota's version, and #digest of the engine
  #                 files it was built from.
  # [NOTICES.txt, sources/] The notices of what it holds, as
  #                         rake ios:notices and rake android:notices write
  #                         them, and, on Android, OpenAL Soft's source.
  #
  # The gem pins, in PIN, the release that published the bundles and each
  # bundle's SHA-256, which a release writes, and #fetch takes from that
  # release only the bytes PIN names. The release is named rather than
  # derived from Lota::VERSION, so a clone between releases, whose version
  # names no release, fetches what its pin names.
  #
  # === Example
  #
  #   engine = Lota::PhoneEngine.new("android-x86_64", ext: "ext/lota")
  #   engine.fetch(cache: "~/.cache/lota/phone-engine") # => the unpacked bundle's folder
  class PhoneEngine
    # Raised when the bundle cannot be had, or is not the one pinned.
    class Failure < StandardError; end

    # What the transport answers: the HTTP status as an Integer, a
    # redirect's Location, and the body.
    class Answer < ::Data.define(:status, :location, :body); end

    # The targets, as Fledge names an iOS app's slices and Android's ABIs
    # (its ADR 022), each with its system.
    TARGETS = %w[ios-arm64 ios-arm64-simulator android-arm64-v8a android-x86_64].freeze

    # The bundles this Lota fetches, beside this file: a line
    # <tt>release TAG</tt> naming the release that published them, then
    # each one's checksum, in the form sha256sum writes.
    PIN = File.join(__dir__, "engines.txt")

    # Where the assets of the release +release+, a tag such as v1.2.3, are.
    RELEASES = "https://github.com/setdef/Lota/releases/download/%<release>s/"

    # What PIN holds: the release's tag, or +nil+ when it names none, and
    # each bundle's SHA-256 by its asset's name.
    class Pin < ::Data.define(:release, :sums); end

    # The engine files, relative to ext/lota, whose content a bundle was
    # built from: what a phone's engine compiles with, and how.
    DIGESTED = %w[
      CMakeLists.txt
      cmake/Platform.cmake
      engine/CMakeLists.txt
      engine/appdata_folder.h
      engine/*.patch
      engine/dependencies_android.cmake
      engine/dependencies_ios.cmake
      engine/sources_android.cmake
      engine/sources_ios.cmake
    ].freeze

    # How many redirects a download follows: a release's asset redirects
    # to the host that stores it.
    REDIRECTS = 5

    # How long a download waits before each new try, in seconds.
    BACKOFF = [2, 5, 15].freeze

    # The errors of a connection that drops, is refused, or times out.
    NETWORK_ERRORS = [IOError, SystemCallError, SocketError, Timeout::Error, OpenSSL::SSL::SSLError].freeze

    # The asset's name for +target+.
    def self.asset(target)
      "lota-engine-#{target}.tar.gz"
    end

    # Where fetched engines are kept by default: lota/phone-engine in
    # +env+'s XDG_CACHE_HOME, or in ~/.cache. A bundle's folder there is
    # named by its SHA-256, so every version of Lota can share it.
    def self.cache(env = ENV)
      base = env["XDG_CACHE_HOME"].to_s
      base = File.join(env.fetch("HOME") { Dir.home }, ".cache") if base.empty?
      File.join(base, "lota", "phone-engine")
    end

    # The SHA-256 of the engine files under +ext+ (ext/lota), the gem's or
    # a clone's, which a bundle records and #fetch compares.
    def self.digest(ext)
      files = DIGESTED.flat_map { |pattern| Dir.glob(pattern, base: ext) }.uniq.sort
      Digest::SHA256.hexdigest(files.map { |file| "#{file}\0#{Digest::SHA256.file(File.join(ext, file)).hexdigest}\n" }.join)
    end

    # The checksums in +text+, as sha256sum writes them, by file name.
    def self.sums(text)
      text.each_line.reject { |line| line.strip.empty? }.to_h do |line|
        sha256, name = line.strip.split(/\s+\*?/, 2)
        raise Failure, "#{line.strip.inspect} is not a line of SHA256SUMS" unless sha256&.match?(/\A\h{64}\z/) && name

        [name, sha256.downcase]
      end
    end

    # The Pin in +text+, PIN's form: an optional <tt>release TAG</tt> line,
    # and checksum lines.
    def self.pin(text)
      releases, sums = text.each_line.partition { |line| line.start_with?("release ") }
      raise Failure, "#{PIN} names more than one release" if releases.size > 1

      release = releases.first&.delete_prefix("release ")&.strip
      raise Failure, "#{release.inspect} is not a release's tag, such as v1.2.3" if
        release && !release.match?(/\Av\d[\w.-]*\z/)

      Pin.new(release:, sums: self.sums(sums.join))
    end

    # The text of PIN for the bundles that the release +release+ published
    # with the checksums +sums+, a SHA256SUMS' text.
    def self.pin_text(release, sums)
      pin = pin("release #{release}\n#{sums}")
      "release #{pin.release}\n#{pin.sums.sort.map { |name, sha256| "#{sha256}  #{name}\n" }.join}"
    end

    # The answer to a GET of +uri+, over the network.
    def self.get(uri)
      return Answer.new(status: 200, location: nil, body: File.binread(uri.path)) if uri.scheme == "file"

      response = Net::HTTP.get_response(uri)
      Answer.new(status: response.code.to_i, location: response["location"], body: response.body)
    end

    # The target, one of TARGETS.
    attr_reader :target

    # [target] One of TARGETS.
    # [ext] Lota's ext/lota, whose engine files #digest reads.
    # [pin] The pin's text, in PIN's form.
    # [url] Where the release's assets are, by default the pinned
    #       release's; a folder's +file:+ URL serves a mirror.
    # [out] Where progress goes.
    # [transport] Called with a URI, answers an Answer.
    # [pause] Called with the seconds to wait before a new try.
    def initialize(target, ext:, pin: File.exist?(PIN) ? File.read(PIN) : "", url: nil, out: $stdout,
      transport: self.class.method(:get), pause: -> (seconds) { sleep(seconds) }
    )
      raise Failure, "Lota builds no phone engine for #{target}; it builds #{TARGETS.join(', ')}" unless
        TARGETS.include?(target)

      @target = target
      @ext = ext
      @pin = self.class.pin(pin)
      @url = url
      @out = out
      @transport = transport
      @pause = pause
    end

    # The bundle's asset name.
    def asset
      self.class.asset(@target)
    end

    # The SHA-256 the gem pins for the bundle. Raises Failure when it pins
    # none.
    def sha256
      @pin.sums.fetch(asset) do
        raise Failure, "This Lota pins no prebuilt engine for #{@target} (#{PIN} names no #{asset}). Build " \
          "the engine from source: pass --with-lota-source=DIR, a clone of Lota's repository with its submodules."
      end
    end

    # Downloads the bundle into +cache+, unless it is there, checks its
    # SHA-256, unpacks it, and checks that it was built from this gem's
    # engine files, then returns the unpacked folder. Raises Failure when
    # any of these fails.
    def fetch(cache:)
      folder = File.join(File.expand_path(cache), sha256)
      unpacked = File.join(folder, @target)
      unless File.file?(File.join(unpacked, "manifest.json"))
        archive = File.join(folder, asset)
        download(archive) unless File.file?(archive) && Digest::SHA256.file(archive).hexdigest == sha256
        partial = "#{unpacked}.part"
        FileUtils.rm_rf(partial)
        Zlib::GzipReader.open(archive) { |gzip| Tar.extract(gzip, partial) }
        check(partial)
        FileUtils.rm_rf(unpacked)
        File.rename(partial, unpacked)
      end
      check(unpacked)
      @out.puts("Lota's engine for #{@target}: #{unpacked}")
      unpacked
    end

    private def download(archive)
      FileUtils.mkdir_p(File.dirname(archive))
      url = @url || release_url
      uri = URI.join(url.end_with?("/") ? url : "#{url}/", asset)
      body = with_retries(uri) { get(uri, REDIRECTS) }
      actual = Digest::SHA256.hexdigest(body)
      unless actual == sha256
        raise Failure, "#{uri} has SHA-256 #{actual}, not the #{sha256} this Lota pins (#{PIN}); it is not the " \
          "engine this Lota pins"
      end

      File.binwrite("#{archive}.part", body)
      File.rename("#{archive}.part", archive)
    end

    # The pinned release's assets.
    private def release_url
      release = @pin.release or
        raise Failure, "#{PIN} names no release to fetch #{asset} from; it needs a line such as release v1.2.3"

      format(RELEASES, release:)
    end

    # The engine's manifest must name this target and this gem's engine
    # files, which a bundle for another Lota does not.
    private def check(folder)
      manifest = JSON.parse(File.read(File.join(folder, "manifest.json")))
      raise Failure, "#{folder} holds the engine for #{manifest['target']}, not #{@target}" unless
        manifest["target"] == @target

      expected = self.class.digest(@ext)
      return folder if manifest["engine_digest"] == expected

      raise Failure, "#{folder} was built from other engine files than #{@ext}'s (engine digest " \
        "#{manifest['engine_digest']}, not #{expected}). Build the engine from source: pass " \
        "--with-lota-source=DIR, a clone of Lota's repository with its submodules."
    end

    private def with_retries(uri)
      tried = []
      begin
        yield
      rescue Transient, *NETWORK_ERRORS => e
        tried << "#{e.class}: #{e.message}"
        raise Failure, "#{uri} did not download in #{tried.size} tries: #{tried.join('; ')}" if
          tried.size > BACKOFF.size

        wait = BACKOFF.fetch(tried.size - 1)
        @out.puts("Retrying #{uri} in #{wait} seconds (#{tried.size} of #{BACKOFF.size}): #{tried.last}")
        @pause.call(wait)
        retry
      end
    end

    # A failure that asking again may mend: a dropped connection or a
    # server's error.
    class Transient < StandardError; end
    private_constant :Transient

    private def get(uri, redirects)
      answer = @transport.call(uri)
      case answer.status
      when 200 then answer.body
      when 301, 302, 303, 307, 308
        raise Failure, "#{uri} redirects more than #{REDIRECTS} times" if redirects.zero?

        get(URI.join(uri, answer.location.to_s), redirects - 1)
      when 500..599 then raise Transient, "#{uri} answered #{answer.status}"
      else raise Failure, "#{uri} answered #{answer.status}"
      end
    end

    # The POSIX ustar archives a bundle is: regular files and folders only,
    # written the same way every time, so a bundle's bytes depend only on
    # what it holds.
    module Tar
      # A tar archive's unit: each header, and each file padded to it.
      BLOCK = 512

      # Writes +files+, a Hash of each path in the archive to its content,
      # to +io+: folders first, then files, each in sorted order, with
      # no owner and a fixed time and mode.
      def self.write(io, files)
        folders = files.keys.flat_map { |path| parents(path) }.uniq.sort
        folders.each { |folder| io.write(header("#{folder}/", 0, "5", 0o755)) }
        files.keys.sort.each do |path|
          content = files.fetch(path).b
          io.write(header(path, content.bytesize, "0", 0o644))
          io.write(content)
          io.write("\0" * ((BLOCK - (content.bytesize % BLOCK)) % BLOCK))
        end
        io.write("\0" * (BLOCK * 2))
      end

      # Extracts the archive read from +io+ into the folder +into+,
      # refusing any entry but a regular file or a folder, and any path
      # that would land outside +into+.
      def self.extract(io, into)
        FileUtils.mkdir_p(into)
        while (block = io.read(BLOCK)) && block.bytesize == BLOCK && block != "\0" * BLOCK
          path, size, type = parse(block)
          destination = File.join(into, path)
          case type
          when "5" then FileUtils.mkdir_p(destination)
          when "0", "\0"
            FileUtils.mkdir_p(File.dirname(destination))
            File.binwrite(destination, size.zero? ? "" : io.read(size))
            io.read((BLOCK - (size % BLOCK)) % BLOCK)
          else raise Failure, "#{path} is not a file or a folder (type #{type.inspect}); a bundle holds no other"
          end
        end
        into
      end

      def self.parents(path)
        parts = path.split("/")[0...-1]
        parts.each_index.map { |index| parts[0..index].join("/") }
      end

      def self.header(path, size, type, mode)
        prefix, name = split(path)
        fields = [
          name,
          format("%07o", mode),
          format("%07o", 0),
          format("%07o", 0),
          format("%011o", size),
          format("%011o", 1),
          " " * 8,
          type,
          "",
          "ustar",
          "00",
          "",
          "",
          format("%07o", 0),
          format("%07o", 0),
          prefix,
        ]
        block = fields.pack("a100a8a8a8a12a12a8a1a100a6a2a32a32a8a8a155").ljust(BLOCK, "\0")
        checksum = format("%06o\0 ", block.sum(0))
        block[148, 8] = checksum
        block
      end

      # ustar's 100-byte name, with up to 155 bytes more before a slash in
      # the prefix field.
      def self.split(path)
        return ["", path] if path.bytesize <= 100

        index = path.rindex("/", 155) or raise Failure, "#{path} is too long for a tar archive"
        prefix = path[0...index]
        name = path[(index + 1)..]
        raise Failure, "#{path} is too long for a tar archive" if prefix.bytesize > 155 || name.bytesize > 100

        [prefix, name]
      end

      def self.parse(block)
        name, size, type, magic, prefix = block.unpack("a100@124a12@156a1@257a6@345a155")
        raise Failure, "the archive is not a ustar archive" unless magic.start_with?("ustar")

        name = name.delete("\0")
        prefix = prefix.delete("\0")
        path = (prefix.empty? ? name : "#{prefix}/#{name}").delete_suffix("/")
        segments = path.split("/")
        if path.empty? || path.start_with?("/") || segments.any? { |segment| segment.empty? || segment == ".." }
          raise Failure, "the archive names #{path.inspect}, outside the folder it unpacks into"
        end

        [path, Integer(size.delete("\0 "), 8), type]
      end

      private_class_method :parents, :header, :split, :parse
    end
  end
end
