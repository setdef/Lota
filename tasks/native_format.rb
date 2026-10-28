# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "open3"
require "rbconfig"

# How each platform's precompiled gem holds its compiled code, and how the
# package checks read it: Mach-O bundles and frameworks on macOS (MachO),
# and ELF shared objects on Linux (ELF).
#
# Both do the same things in their own terms. The bundle finds the
# libraries LÖVE links through rpaths relative to itself, which the gem
# build points into the gem's own directory of them; each library is
# staged into that directory, changed only as its platform needs; the
# libraries a gem carries are the ones the bundle loads, and what they load
# in turn, found through those rpaths; and a run of the installed gem
# reports what it loaded, so the delivery check can tell that it loaded
# from the gem. NativeGem builds and PackageCheck checks through the host's
# format, NativeFormat.host.
module NativeFormat
  # Raised when a tool fails or a binary cannot be read.
  class Failure < StandardError; end

  # The format of the platform Ruby runs on.
  def self.host
    self.for(RbConfig::CONFIG["host_os"])
  end

  # The format of the platform Ruby's <tt>host_os</tt> +host_os+ names.
  def self.for(host_os)
    host_os.include?("linux") ? ELF.new : MachO.new
  end

  # Runs +command+, raising Failure with its output when it fails, or
  # when there is no such command.
  def self.run!(*command)
    output, status = Open3.capture2e(*command)
    raise Failure, "#{command.join(' ')} failed:\n#{output}" unless status.success?

    output
  rescue Errno::ENOENT => e
    raise Failure, "#{command.first} is not installed (#{e.message}); bin/setup installs what the build needs"
  end

  # Mach-O, on macOS: the bundle loads frameworks through @rpath, and the
  # gem carries each in lib/lota/frameworks, as the one version directory
  # its install name names, thinned to arm64 and signed again.
  class MachO
    # The platform the precompiled gem is for: Apple Silicon.
    PLATFORM = "arm64-darwin"

    # Where the frameworks go in the gem, relative to the bundle.
    DIRECTORY = "frameworks"

    # The framework version directory a @rpath install name names, the
    # directory its signature covers.
    VERSION = "Versions/A"

    # Development files in a framework's version directory.
    DEVELOPMENT = %w[Headers Resources/CMake].freeze

    # What a relative rpath starts with.
    RELATIVE = "@loader_path"

    # The gem platform the bundle is built for.
    def platform
      PLATFORM
    end

    # Where the libraries go in the gem, relative to the bundle.
    def directory
      DIRECTORY
    end

    # What the bundle loads through its relative rpaths
    # (<tt>@loader_path/...</tt>), each as a path relative to the bundle's
    # directory: the framework directory for a framework, the file itself
    # for anything else. A copy of the bundle loads only with each of these
    # at the same place relative to it. That includes what those load in
    # turn through @rpath, as libvorbis loads libogg, which dyld finds
    # through the rpaths of the bundle that loaded them. Libraries no rpath
    # resolves, such as the sanitizer runtime that DYLD_INSERT_LIBRARIES
    # loads, are left out.
    def dependencies(bundle)
      directory = File.dirname(bundle)
      rpaths = relative_rpaths(bundle)
      found = []
      waiting = rpath_libraries(bundle)
      until waiting.empty?
        name = waiting.shift
        rpath = rpaths.find { |candidate| File.exist?(File.join(directory, candidate, name)) } or next
        relative = File.join(rpath, name[%r{\A[^/]+\.framework}] || name)
        next if found.include?(relative)

        found << relative
        waiting.concat(rpath_libraries(File.join(directory, rpath, name)) - [name])
      end
      found
    end

    # Why +bundle+ would not load from inside +gem_dir+ alone: each rpath
    # that is not relative to the bundle, and each library it loads through
    # @rpath that no rpath resolves inside +gem_dir+.
    def escapes(bundle, gem_dir)
      inside = File.join(File.realpath(gem_dir), "")
      absolute = rpaths(bundle).reject { |rpath| rpath.start_with?("#{RELATIVE}/") }.map { |rpath| "rpath #{rpath}" }
      unresolved = rpath_libraries(bundle).reject do |name|
        relative_rpaths(bundle).any? do |rpath|
          path = File.join(File.dirname(bundle), rpath, name)
          File.exist?(path) && File.realpath(path).start_with?(inside)
        end
      end
      absolute + unresolved.map { |name| "@rpath/#{name} resolves outside #{gem_dir}" }
    end

    # Points the staged +bundle+'s rpaths at the gem's frameworks alone,
    # and signs it again, since the change invalidates its signature.
    def stage_bundle(bundle)
      NativeFormat.run!("install_name_tool", *rpaths(bundle).flat_map { |rpath| ["-delete_rpath", rpath] },
        "-add_rpath", "#{RELATIVE}/#{DIRECTORY}", bundle)
      sign(bundle)
    end

    # Copies the framework at +source+ into +stage+, at +relative+ (the
    # gem's framework directory) and its own name: its version directory
    # alone, without the symlinks around it, on which RubyGems warns,
    # without its headers, and with only its arm64 code, signed again.
    # Returns the files it staged, relative to +stage+.
    def stage_library(stage, relative, source)
      name = File.basename(source)
      version = File.join(relative, name, VERSION)
      target = File.join(stage, version)
      FileUtils.mkdir_p(File.dirname(target))
      FileUtils.cp_r(File.join(source, VERSION), target)
      DEVELOPMENT.each { |path| FileUtils.rm_rf(File.join(target, path)) }
      binary = File.join(target, File.basename(name, ".framework"))
      if NativeFormat.run!("lipo", "-archs", binary).split.size > 1
        NativeFormat.run!("lipo", binary, "-thin", "arm64", "-output", binary)
      end
      sign(target)
      files(stage, version, name)
    end

    # Verifies the signature of +bundle+ and of each framework it loads, as
    # Gatekeeper would, and says what it checked.
    def verify(bundle)
      signed = [bundle] + dependencies(bundle).map do |framework|
        File.join(File.expand_path(framework, File.dirname(bundle)), VERSION)
      end
      signed.each { |path| NativeFormat.run!("codesign", "--verify", "--strict", "--verbose=2", path) }
      "#{signed.size} signatures verify"
    end

    # The path REUSE.toml annotates for the framework at +path+: every file
    # in it.
    def annotation(path)
      "#{path}/**"
    end

    # What a run is given so it reports the libraries it loads.
    def report_environment
      { "DYLD_PRINT_LIBRARIES" => "1" }
    end

    # Ruby run as the delivery check's guard, beside what it reports of
    # Lota: dyld reports what it loads itself.
    def report_libraries
      ""
    end

    # The files dyld reports loading, from output printed with
    # DYLD_PRINT_LIBRARIES set.
    def loaded(output)
      output.scan(/^dyld\[\d+\]: <[\h-]+> (.+)$/).flatten
    end

    # +output+ without what dyld printed.
    def printed(output)
      output.lines.grep_v(/^dyld\[\d+\]: /).join
    end

    # The libraries a run loaded that are not macOS's own (from /System):
    # the frameworks, which must load from the installed gem, and the
    # bundle.
    def ours(output)
      loaded = loaded(output)
      loaded.grep(%r{\.framework/}).reject { |path| path.start_with?("/System/") } +
        loaded.grep(%r{/lota/native\.bundle\z})
    end

    # The toolchain's own files, which the bundle reads but does not
    # carry: Xcode's.
    def toolchain
      developer = NativeFormat.run!("xcode-select", "--print-path").strip
      [File.join(developer, "")]
    end

    # Runs otool, which macOS's command-line tools provide.
    def otool(*)
      NativeFormat.run!("otool", *)
    end

    private def sign(path)
      NativeFormat.run!("codesign", "--force", "--sign", "-", path)
      NativeFormat.run!("codesign", "--verify", "--strict", "--verbose=2", path)
    end

    private def files(stage, version, name)
      Dir.glob("**/*", File::FNM_DOTMATCH, base: File.join(stage, version)).filter_map do |path|
        full = File.join(stage, version, path)
        raise Failure, "#{name} holds a symlink, #{path}" if File.symlink?(full)

        File.join(version, path) if File.file?(full)
      end
    end

    private def rpaths(binary)
      otool("-l", binary).scan(/^\s+path (\S+) \(offset \d+\)$/).flatten
    end

    private def relative_rpaths(binary)
      rpaths(binary).filter_map { |rpath| rpath.delete_prefix("#{RELATIVE}/") if rpath.start_with?("#{RELATIVE}/") }
    end

    # The names +binary+ needs through @rpath, once each, though otool
    # lists a library once for each architecture of a universal binary. A
    # library's own install name is among them.
    private def rpath_libraries(binary)
      lines = otool("-L", binary).lines.grep(/\A\s/)
      libraries = lines.map { |line| line.split.first }.uniq
      libraries.filter_map { |library| library.delete_prefix("@rpath/") if library.start_with?("@rpath/") }
    end
  end

  # ELF, on Linux: the bundle needs LÖVE's libraries by their sonames,
  # which the dynamic linker finds through its RUNPATH, each library its own
  # dependencies through its own (ld.so(8)), and the gem carries each in
  # lib/lota/libraries, under its soname, with its RUNPATH pointed at its
  # own directory and its debugging information stripped, as LÖVE's
  # AppImage carries them (love-appimage-source's Makefile, appimage-prepare,
  # and separate_debug.sh).
  class ELF
    # Where the libraries go in the gem, relative to the bundle.
    DIRECTORY = "libraries"

    # What a relative rpath starts with.
    RELATIVE = "$ORIGIN"

    # The libraries every glibc system has, which the gem relies on rather
    # than carries: glibc's own, libmvec among them, the vector math GCC's
    # vectorized loops call on x86_64, and GCC's C++ runtime, which LÖVE's
    # AppImage relies on too (its appimage-prepare step copies only what its
    # installdir built).
    SYSTEM = /\A(?:(?:libc|libm|libmvec|libdl|libpthread|librt|libutil|libstdc\+\+|libgcc_s)\.so\.\d+|ld-linux-[\w-]+\.so\.\d+)\z/

    # Where the system's libraries are, which a run may load from.
    SYSTEM_DIRECTORIES = %w[/lib/ /lib64/ /usr/lib/ /usr/lib64/ /usr/local/lib/].freeze

    # How the delivery check's guard reports each library a run mapped.
    MAPPED = /^lota-package-check: mapped (.+)$/

    # The gem platform the bundle is built for: this machine's processor,
    # on Linux with glibc. RubyGems matches a plain <tt>x86_64-linux</tt>
    # gem on musl too (Gem::Platform#===), where a library built against
    # glibc does not load, so the platform names glibc ("gnu").
    def platform
      "#{RbConfig::CONFIG.fetch('host_cpu')}-linux-gnu"
    end

    # Where the libraries go in the gem, relative to the bundle.
    def directory
      DIRECTORY
    end

    # What the bundle loads through relative rpaths, and what those load in
    # turn through theirs, each as a path relative to the bundle's
    # directory, under the soname it is needed by. The system's libraries,
    # and any no relative rpath resolves, such as the sanitizer runtime that
    # LD_PRELOAD loads, are left out.
    def dependencies(bundle)
      directory = File.dirname(bundle)
      found = []
      waiting = needed(bundle).map { |name| [bundle, name] }
      until waiting.empty?
        binary, name = waiting.shift
        path = resolve(binary, name) or next
        relative = Pathname.new(File.join(File.dirname(path), name)).relative_path_from(directory).to_s
        next if found.include?(relative)

        found << relative
        waiting.concat(needed(path).map { |library| [path, library] })
      end
      found
    end

    # Why +bundle+ would not load from inside +gem_dir+ alone: each rpath
    # of it or a library it loads that is not relative to its file, and
    # each library none of them resolves inside +gem_dir+ that is not the
    # system's.
    def escapes(bundle, gem_dir)
      inside = File.join(File.realpath(gem_dir), "")
      binaries = [bundle] + dependencies(bundle).map { |relative| File.expand_path(relative, File.dirname(bundle)) }
      binaries.flat_map do |binary|
        absolute = runpath(binary).reject { |rpath| rpath.start_with?(RELATIVE) }
          .map { |rpath| "rpath #{rpath} of #{File.basename(binary)}" }
        unresolved = needed(binary).reject { |name| SYSTEM.match?(name) }.reject do |name|
          path = resolve(binary, name)
          path && File.realpath(path).start_with?(inside)
        end
        absolute + unresolved.map { |name| "#{name} resolves outside #{gem_dir}" }
      end.uniq
    end

    # Points the staged +bundle+'s rpath at the gem's libraries alone.
    def stage_bundle(bundle)
      NativeFormat.run!("patchelf", "--set-rpath", "#{RELATIVE}/#{DIRECTORY}", bundle)
    end

    # Copies the library at +source+, a path ending in the soname it is
    # needed by, into +stage+, at +relative+ (the gem's library directory),
    # as a file of that name rather than the symlink a build installs it
    # as, on which RubyGems warns, without its debugging information, and
    # with its rpath pointed at its own directory, where the libraries it
    # needs are. Returns the file it staged, relative to +stage+.
    def stage_library(stage, relative, source)
      file = File.join(relative, File.basename(source))
      target = File.join(stage, file)
      FileUtils.mkdir_p(File.dirname(target))
      FileUtils.cp(File.realpath(source), target)
      File.chmod(0o755, target)
      NativeFormat.run!("strip", "--strip-debug", target)
      NativeFormat.run!("patchelf", "--set-rpath", RELATIVE, target)
      [file]
    end

    # Nothing is signed on Linux; says so.
    def verify(_bundle)
      "nothing signed on Linux"
    end

    # The path REUSE.toml annotates for the library at +path+: the file.
    def annotation(path)
      path
    end

    # What a run is given so it reports the libraries it loads: nothing,
    # since the guard reports them (report_libraries).
    def report_environment
      {}
    end

    # Ruby run as the delivery check's guard exits, beside what it reports
    # of Lota: each shared object the process has mapped, as Linux lists
    # them in /proc/self/maps, once each.
    def report_libraries
      <<~RUBY
        File.foreach("/proc/self/maps").filter_map { |line| line[%r{ (/\\S+\\.so(?:\\.[\\d.]+)?)$}, 1] }.uniq
          .each { |path| puts "lota-package-check: mapped \#{path}" }
      RUBY
    end

    # The shared objects the guard reports a run mapped.
    def loaded(output)
      output.scan(MAPPED).flatten
    end

    # +output+ without what the guard reported of the libraries.
    def printed(output)
      output.lines.grep_v(MAPPED).join
    end

    # The libraries a run mapped that are neither the system's nor Ruby's
    # own, which must load from the installed gem, and the bundle.
    def ours(output)
      ruby = [RbConfig::CONFIG.fetch("libdir"), RbConfig::CONFIG.fetch("rubyarchdir")].map { |dir| File.join(dir, "") }
      loaded(output).reject { |path| path.start_with?(*SYSTEM_DIRECTORIES, *ruby) }
    end

    # The toolchain's own files, which the bundle reads but does not
    # carry: the system's compiler, its runtime, and glibc's headers and
    # start files, all under /usr.
    def toolchain
      ["/usr/"]
    end

    # The sonames +binary+ needs.
    def needed(binary)
      dynamic(binary).scan(/\(NEEDED\)\s+Shared library: \[(.+)\]$/).flatten
    end

    # The directories +binary+'s RUNPATH, or its older RPATH, names.
    def runpath(binary)
      dynamic(binary).scan(/\((?:RUNPATH|RPATH)\)\s+Library r(?:un)?path: \[(.*)\]$/).flatten
        .flat_map { |paths| paths.split(":") }
    end

    # Where +binary+'s relative rpaths find the library +name+, or nil.
    private def resolve(binary, name)
      runpath(binary).select { |rpath| rpath.start_with?(RELATIVE) }
        .map { |rpath| File.join(rpath.sub(RELATIVE, File.dirname(binary)), name) }
        .find { |path| File.exist?(path) }
    end

    private def dynamic(binary)
      NativeFormat.run!("readelf", "--dynamic", binary)
    end
  end
end
