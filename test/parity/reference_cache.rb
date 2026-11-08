# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "digest"
require "etc"
require "fileutils"
require "json"
require "open3"
require "securerandom"

module Parity
  # What the reference love did the last time it ran a game under a script,
  # kept so that the next identical run need not happen.
  #
  # Every parity test runs a game in the reference love, then its
  # translation in Lota, and compares the two. LÖVE's side does the same
  # thing every time it gets the same inputs: a fixed dt, a fixed clock and
  # seed, scripted keys and mouse, audio mixed on game time, and, on Linux,
  # malloc's bytes fixed by MALLOC_PERTURB_. Running it again proves only
  # that it still does, and costs as long as Lota's side. So the first run
  # under a set of inputs is kept here, in tmp/parity-cache, and a later run
  # under the same inputs is given its frames, saved files, mixed audio,
  # decoded sounds, printed text, and exit status instead. Lota is still
  # run, and compared with all of it, every time.
  #
  # A cache that missed an input would compare Lota with what LÖVE did
  # under other inputs, and pass or fail for the wrong reason, silently. So
  # the key (Key) is over-broad: the reference love and every file in its
  # bundle, every file and folder the run names in its arguments or its
  # environment, the whole environment the run gets, the harness code that
  # starts it, and the platform. Anything that changes any of them misses,
  # and LÖVE runs again. An entry is read back only after every file in it
  # matches the hash its manifest recorded, and the manifest its own; an
  # entry that does not is removed, and LÖVE runs again. Only a run that
  # ended with status 0 is kept, since a failed or stopped one says more
  # about the machine than about the game.
  #
  # LOTA_PARITY_CACHE=0 turns it off: every run is LÖVE's own, and nothing
  # is kept. CI turns it off, since each run starts from a clean checkout
  # and a reference love built anew (.github/workflows/ci.yml).
  class ReferenceCache
    # Where entries are kept, one folder each, named by its key.
    ROOT_DIR = File.expand_path("../../tmp/parity-cache", __dir__)

    # The most bytes entries may take, together. Once a new entry takes
    # them past it, the entries read least recently are removed until they
    # are under it again. One gate's entries take about 190 MB, so the
    # limit holds two sets of them, as a change and its undoing make.
    LIMIT = 512 * 1024 * 1024

    # The layout of an entry, which a change to this file's way of writing
    # one changes; this file's own hash is part of the key too.
    FORMAT = 1

    # The cache LoveRun uses: the one in ROOT_DIR, or +nil+ when
    # LOTA_PARITY_CACHE is 0.
    def self.default
      return if ENV.fetch("LOTA_PARITY_CACHE", "1") == "0"

      @default ||= new(ROOT_DIR)
    end

    # [root] The folder to keep entries in.
    # [key] The Key that names a run's entry.
    # [limit] The most bytes the entries may take, together.
    def initialize(root, key: Key.new, limit: LIMIT)
      @root = root
      @key = key
      @limit = limit
    end

    # The Output of the reference love's +command+, run with exactly
    # +environment+ (Parity.environment) and its files written in
    # +directory+: the
    # cached one, with the files it wrote restored into +directory+, and
    # +true+; or, when there is none, the one the block returns, having run
    # it, and +false+. +directory+ holds only empty folders before the run.
    def fetch(command, environment, directory)
      begin
        key, inputs = @key.digest(command, environment, directory)
      rescue SystemCallError
        # A file the key names went away while it was hashed: no key can be
        # trusted, so LÖVE runs, and nothing is kept.
        return [yield, false]
      end
      restored = restore(key, directory)
      return [restored, true] if restored

      output = yield
      store(key, inputs, directory, output) if output.status.success?
      [output, false]
    end

    # The entry for +key+'s folder.
    def entry(key)
      File.join(@root, key)
    end

    # How a cached run ended: always with an exit status, which is 0 for
    # every run kept.
    class Status < Data.define(:exitstatus)
      def success?
        exitstatus.zero?
      end

      # A cached run was never stopped by a signal.
      def termsig
        nil
      end
    end

    # Restores the entry for +key+ into +directory+ and returns its Output,
    # or returns +nil+, with +directory+ as it was, when there is no entry
    # or any part of it does not match its manifest. An entry that does not
    # match is removed.
    private def restore(key, directory)
      manifest = read_manifest(key) or return
      before = Dir.children(directory)
      begin
        manifest.fetch("files").each { |file| restore_file(key, directory, file) }
        text = verified(File.join(entry(key), "output"), manifest.fetch("output")).force_encoding(Encoding.default_external)
      rescue Corrupt, KeyError, NoMethodError, TypeError, SystemCallError
        Dir.children(directory).each { |name| FileUtils.rm_rf(File.join(directory, name)) unless before.include?(name) }
        before.each { |name| clear(File.join(directory, name)) }
        FileUtils.rm_rf(entry(key))
        return
      end
      File.utime(nil, nil, File.join(entry(key), "manifest.json"))
      Output.new(text, Status.new(manifest.fetch("exitstatus")))
    end

    # Raised for an entry whose files do not match its manifest.
    class Corrupt < StandardError; end

    # The manifest of the entry for +key+, if it is whole and its own; an
    # entry that has one but not that one is removed.
    private def read_manifest(key)
      path = File.join(entry(key), "manifest.json")
      return unless File.file?(path)

      manifest = JSON.parse(File.read(path))
      raise Corrupt unless manifest.is_a?(Hash)

      digest = manifest.delete("digest")
      raise Corrupt unless digest == Digest::SHA256.hexdigest(JSON.generate(manifest))
      raise Corrupt unless manifest["format"] == FORMAT && manifest["key"] == key && manifest.fetch("exitstatus").zero?

      manifest
    rescue Corrupt, JSON::ParserError, KeyError, NoMethodError, SystemCallError
      FileUtils.rm_rf(entry(key))
      nil
    end

    private def restore_file(key, directory, file)
      path = File.join(directory, safe(file.fetch("path")))
      case file.fetch("type")
      when "directory" then FileUtils.mkdir_p(path)
      when "file"
        FileUtils.mkdir_p(File.dirname(path))
        File.binwrite(path, verified(File.join(entry(key), "files", safe(file.fetch("path"))), file))
      else raise Corrupt
      end
    end

    # The bytes of +path+, if they are the bytes +record+ names.
    private def verified(path, record)
      raise Corrupt unless File.file?(path) && !File.symlink?(path)

      bytes = File.binread(path)
      raise Corrupt unless bytes.bytesize == record.fetch("bytes") && Digest::SHA256.hexdigest(bytes) == record.fetch("sha256")

      bytes
    end

    # +path+, relative, if it stays inside the folder it is relative to.
    private def safe(path)
      raise Corrupt if path.start_with?("/") || path.split("/").include?("..")

      path
    end

    # Empties the folder +path+, or removes it if it is not one.
    private def clear(path)
      return FileUtils.rm_rf(path) unless File.directory?(path) && !File.symlink?(path)

      Dir.children(path).each { |name| FileUtils.rm_rf(File.join(path, name)) }
    end

    # Keeps what the run left in +directory+ and +output+ as the entry for
    # +key+, written beside it and then renamed into place, so no reader
    # sees half an entry, then removes old entries past the limit. A run
    # that left anything but files and folders is not kept.
    private def store(key, inputs, directory, output)
      files = Key.walk(directory)
      return unless files.all? { |_, type| %w[file directory].include?(type) }

      FileUtils.mkdir_p(@root)
      partial = File.join(@root, ".partial-#{Process.pid}-#{SecureRandom.hex(4)}")
      records = files.map { |path, type| copy(directory, partial, path, type) }
      File.binwrite(File.join(partial, "output"), output.text)
      manifest = {
"format" => FORMAT,
"key" => key,
"files" => records,
"output" => record(output.text.b),
"exitstatus" => output.status.exitstatus,
"inputs" => inputs,
}
      File.write(File.join(partial, "manifest.json"),
        JSON.generate(manifest.merge("digest" => Digest::SHA256.hexdigest(JSON.generate(manifest)))))
      FileUtils.rm_rf(entry(key))
      File.rename(partial, entry(key))
      evict(key)
    rescue SystemCallError
      FileUtils.rm_rf(partial) if partial
    end

    private def copy(directory, partial, path, type)
      target = File.join(partial, "files", path)
      if type == "directory"
        FileUtils.mkdir_p(target)
        return { "path" => path, "type" => type }
      end

      FileUtils.mkdir_p(File.dirname(target))
      bytes = File.binread(File.join(directory, path))
      File.binwrite(target, bytes)
      { "path" => path, "type" => type, **record(bytes) }
    end

    private def record(bytes)
      { "bytes" => bytes.bytesize, "sha256" => Digest::SHA256.hexdigest(bytes) }
    end

    # Removes the entries read least recently, other than +kept+'s, until
    # the rest take no more than the limit, and any partial entry an
    # interrupted run left over an hour ago.
    private def evict(kept)
      Dir.glob(File.join(@root, ".partial-*")).each do |partial|
        FileUtils.rm_rf(partial) if File.mtime(partial) < Time.now - 3600
      end
      entries = Dir.children(@root).reject { |name| name.start_with?(".") }.map do |name|
        manifest = File.join(@root, name, "manifest.json")
        [name, File.exist?(manifest) ? File.mtime(manifest) : Time.at(0), size(File.join(@root, name))]
      end
      total = entries.sum(&:last)
      entries.sort_by { |_, read, _| read }.each do |name, _, bytes|
        break if total <= @limit
        next if name == kept

        FileUtils.rm_rf(File.join(@root, name))
        total -= bytes
      end
    end

    # The bytes the files in the folder +path+ take.
    private def size(path)
      Dir.glob(File.join(path, "**/*"), File::FNM_DOTMATCH).sum { |file| File.file?(file) ? File.size(file) : 0 }
    end

    # What names the reference love's run of a game: the SHA-256 of
    # everything that could make it do anything other than what it did, and
    # those inputs themselves, which an entry keeps, so that a miss can be
    # explained by comparing them.
    #
    # - The command and the working directory it runs in.
    # - The whole environment the run gets, which is the harness's alone
    #   (Parity.environment): no variable of this process's reaches the
    #   run, so none can change what it does, and none is in the key.
    # - The bytes of every file the command or the environment names by an
    #   absolute path, each word of each value taken alone: the reference
    #   love itself, the libraries preloaded into it, OpenAL Soft's
    #   settings, the sounds it decodes.
    # - Every file under every folder the command names, and the game's
    #   folder: the harness's conf.lua, and the game, committed or not.
    # - Every file in the reference love's bundle, the libraries it loads
    #   from beside itself (Key.libraries).
    # - The harness's code that sets up the run (HARNESS).
    # - The platform: the system and its version, which on macOS fixes
    #   every system library and the Metal driver, the hardware and its
    #   displays, the time zone, and on Linux the installed packages, Mesa
    #   among them (Key.platform).
    #
    # The run's own folder is the one thing the run names that differs
    # every time: it appears in the key as <run>. The inputs an entry keeps
    # hold each variable's value as its hash, since the environment can
    # hold secrets, such as a token, that do not belong in tmp.
    class Key
      # The files that decide how the harness starts the reference love.
      HARNESS = [
        "test/parity/parity_helper.rb",
        "test/parity/reference_cache.rb",
        "test/native/native_helper.rb",
        "test/test_home.rb",
        "test/test_helper.rb",
      ].map { |path| File.expand_path("../../#{path}", __dir__) }.freeze

      # [harness] The files that decide how the harness starts a run.
      # [platform] A block that answers the platform's description.
      def initialize(harness: HARNESS, &platform)
        @harness = harness
        @platform = platform || -> { Key.platform }
      end

      # The key and the inputs it is the hash of, for the reference love's
      # +command+, run with exactly +environment+, in the run folder
      # +directory+.
      def digest(command, environment, directory)
        variables = environment.compact.sort.to_h
        inside = -> (path) { path == directory || path.start_with?("#{directory}/") }
        words = (command + variables.values).flat_map { |value| value.split(/[\s:,;=]/) }
          .select { |word| word.start_with?("/") && !inside.call(word) }.uniq.sort
        folders = (command.drop(1) + [variables["LOTA_PARITY_GAME"]].compact)
          .select { |path| File.directory?(path) && !inside.call(path) }.uniq.sort
        inputs = {
          "format" => FORMAT,
          "command" => command.map { |word| word.gsub(directory, "<run>") },
          "working directory" => Dir.pwd,
          "environment" => variables.transform_values { |value| Digest::SHA256.hexdigest(value.gsub(directory, "<run>")) },
          "files" => words.select { |word| File.file?(word) }.to_h { |word| [word, Key.file(word)] },
          "folders" => folders.to_h { |folder| [folder, Key.tree(folder)] },
          "libraries" => Key.libraries(command.first).to_h { |path| [path, Key.tree(path)] },
          "harness" => @harness.to_h { |path| [path, Key.file(path)] },
          "platform" => (@memo ||= @platform.call),
        }
        [Digest::SHA256.hexdigest(JSON.generate(inputs)), inputs]
      end

      # The SHA-256 of the file +path+'s bytes, or "missing".
      def self.file(path)
        File.file?(path) ? Digest::SHA256.file(path).hexdigest : "missing"
      end

      # The SHA-256 of the folder or file +path+: of every file and folder
      # under it, by relative path, and each file's bytes and whether it is
      # executable, and the target of each symbolic link, and what it
      # points to, followed.
      def self.tree(path, seen = [])
        return file(path) unless File.directory?(path)
        return "cycle" if seen.include?(File.realpath(path))

        seen += [File.realpath(path)]
        entries = walk(path).map do |relative, type|
          full = File.join(path, relative)
          case type
          when "file" then [relative, type, File.executable?(full), file(full)]
          when "link" then [relative, type, File.readlink(full), File.exist?(full) ? tree(full, seen) : "dangling"]
          else [relative, type]
          end
        end
        Digest::SHA256.hexdigest(JSON.generate(entries))
      end

      # Every path under the folder +path+, relative to it, sorted, with
      # its type: "file", "directory", "link", or "other". Links are not
      # followed.
      def self.walk(path, relative = nil)
        here = relative ? File.join(path, relative) : path
        Dir.children(here).sort.flat_map do |name|
          child = relative ? File.join(relative, name) : name
          full = File.join(path, child)
          type = if File.symlink?(full) then "link"
          elsif File.directory?(full) then "directory"
          elsif File.file?(full) then "file"
          else "other"
          end
          (type == "directory") ? [[child, type], *walk(path, child)] : [[child, type]]
        end
      end

      # The files the reference love at +executable+ loads from beside
      # itself: on macOS, its whole app bundle, frameworks and all; on
      # Linux, the folder it is in, the lib folder beside a bin folder, and
      # every library ldd says it links. System libraries are the
      # platform's (Key.platform).
      def self.libraries(executable)
        app = executable.split("/").each_index.map { |index| executable.split("/")[0..index].join("/") }
          .find { |path| path.end_with?(".app") }
        return [app] if app

        folder = File.dirname(executable)
        lib = File.join(File.dirname(folder), "lib")
        [folder, *(lib if File.basename(folder) == "bin" && File.directory?(lib)), *linked(executable)].uniq
      end

      # On Linux, every library ldd says +executable+ links, by path; none
      # elsewhere. Raises if ldd cannot run, as the key cannot be trusted.
      def self.linked(executable)
        return [] unless TestHome::LINUX

        output, status = Open3.capture2e("ldd", executable)
        raise Errno::ENOENT, "ldd #{executable}" unless status.success?

        output.scan(%r{=> (/\S+)}).flatten
      end

      # What the platform the reference love runs on is: Ruby's platform,
      # uname, the time zone, and on macOS the system's build, the
      # hardware, and the displays, whose density decides a frame's size;
      # on Linux the distribution and the package database, which names
      # every system library's version.
      def self.platform
        uname = Etc.uname
        {
          "ruby" => RUBY_DESCRIPTION,
          "uname" => uname.values_at(:sysname, :nodename, :release, :version, :machine).join(" "),
          "time zone" => File.exist?("/etc/localtime") ? File.realpath("/etc/localtime") : "none",
          **(TestHome::LINUX ? linux : macos),
        }
      end

      def self.macos
        {
          "system" => capture("sw_vers"),
          "hardware" => capture("sysctl", "-n", "hw.model", "machdep.cpu.brand_string"),
          "displays" => capture("system_profiler", "SPDisplaysDataType"),
        }
      end

      def self.linux
        packages = %w[/var/lib/dpkg/status /var/lib/rpm/rpmdb.sqlite /lib/apk/db/installed].find { |path| File.file?(path) }
        {
          "release" => File.exist?("/etc/os-release") ? File.read("/etc/os-release") : "none",
          "packages" => packages ? file(packages) : "unknown: #{SecureRandom.hex(8)}",
        }
      end

      # What +command+ prints, or, if it cannot run, a value no other run
      # shares, so that a platform this cannot describe never hits.
      def self.capture(*command)
        output, status = Open3.capture2e(*command)
        status.success? ? output : "unknown: #{SecureRandom.hex(8)}"
      rescue SystemCallError
        "unknown: #{SecureRandom.hex(8)}"
      end
    end
  end
end
