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
# ELF shared objects on Linux (ELF), and PE DLLs on Windows (PE).
#
# Each does the same things in its own terms. The bundle finds the
# libraries LÖVE links through rpaths relative to itself, which the gem
# build points into the gem's own directory of them (on Windows, which has
# no rpath, a second extension beside it loads them first); each library is
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
    if host_os.include?("linux") then ELF.new
    elsif host_os.include?("mingw") then PE.new
    else MachO.new
    end
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
  # its install name names, thinned to arm64, with only the rpaths
  # relative to it, and signed again.
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

    # The extensions the gem carries beside the bundle: none.
    def companions(_bundle)
      []
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
    # of it or of a framework it loads that is not relative to its binary,
    # and each library it loads through @rpath that no rpath resolves
    # inside +gem_dir+. dyld looks for what a framework loads through
    # @rpath in the framework's own rpaths first, then in those of what
    # loaded it, so an rpath such as vorbis's /Library/Frameworks would let
    # an ogg.framework installed there shadow the gem's.
    def escapes(bundle, gem_dir)
      inside = File.join(File.realpath(gem_dir), "")
      binaries = [bundle] + dependencies(bundle).map { |relative| binary(File.expand_path(relative, File.dirname(bundle))) }
      absolute = binaries.flat_map do |binary|
        outside_rpaths(binary).map { |rpath| "rpath #{rpath} of #{File.basename(binary)}" }
      end.uniq
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
    # without its headers, with only its arm64 code, and without the
    # rpaths that are not relative to it (#escapes), such as the
    # /Library/Frameworks love-apple-dependencies' vorbis was built with,
    # signed again. Returns the files it staged, relative to +stage+.
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
      outside = outside_rpaths(binary)
      NativeFormat.run!("install_name_tool", *outside.flat_map { |rpath| ["-delete_rpath", rpath] }, binary) if outside.any?
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
    # DYLD_PRINT_LIBRARIES set. dyld reports a library when something first
    # loads it, such as Metal when a window fills the screen, which can be
    # while a test run is partway through a line of progress dots, so its
    # report need not start a line.
    def loaded(output)
      output.scan(/dyld\[\d+\]: <[\h-]+> (.+)$/).flatten
    end

    # +output+ without what dyld printed, wherever on a line it printed it.
    def printed(output)
      output.gsub(/dyld\[\d+\]: [^\n]*\n/, "")
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

    # The directories the linker searched, which LinkedFiles needs only for
    # a map that names a file without its directory, as Apple's never does.
    def library_directories
      []
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

    # The rpaths of +binary+ that are not relative to it: absolute ones,
    # and ones relative to the executable, which is Ruby, outside the gem.
    private def outside_rpaths(binary)
      rpaths(binary).reject { |rpath| rpath.start_with?("#{RELATIVE}/") }
    end

    # The binary of +path+, as #dependencies names it: a framework's, in
    # its version directory, or the file itself.
    private def binary(path)
      return path unless path.end_with?(".framework")

      File.join(path, VERSION, File.basename(path, ".framework"))
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

    # The libraries the gem relies on the system for rather than carries,
    # by soname: glibc's and GCC's C++ runtime, which LÖVE's AppImage
    # relies on too (its appimage-prepare step copies only what its
    # installdir built). Each is one the manylinux policy lets a binary
    # need (PEP 600, and auditwheel's policy list), which packagers such as
    # Fledge check a gem's libraries against, or the dynamic linker. glibc
    # ships libmvec too, the vector math GCC's vectorized loops call on
    # x86_64, but the policy leaves it out, so LinuxBuild keeps libvorbis
    # from needing it (LinuxBuild::OVERRIDES).
    SYSTEM = %w[
      libc.so.6
      libm.so.6
      libdl.so.2
      libpthread.so.0
      librt.so.1
      libutil.so.1
      libstdc++.so.6
      libgcc_s.so.1
      ld-linux-x86-64.so.2
      ld-linux-aarch64.so.1
    ].freeze

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

    # The extensions the gem carries beside the bundle: none.
    def companions(_bundle)
      []
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
        unresolved = (needed(binary) - SYSTEM).reject do |name|
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

    # The directories the linker searched, which LinkedFiles needs only for
    # a map that names a file without its directory, as GNU ld's never
    # does.
    def library_directories
      []
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

  # PE, on Windows, with MinGW against the UCRT, for RubyInstaller's Ruby
  # (ADR 002, section 4). Windows has no rpath: it finds a DLL a binary
  # imports by its name alone, in directories the process chooses, never
  # the extension's own. So the gem carries, beside the bundle, the
  # preloader (ext/lota/preload), which loads each DLL in
  # lib/lota/libraries by its absolute path before Ruby loads the bundle,
  # and which lib/lota.rb requires first. Each binary is staged without its
  # debugging information, which libmodplug's Autotools build compiles in
  # (-g, its default flags) and which names the directories of the machine
  # that built it, as LÖVE's AppImage strips its libraries; nothing is
  # signed. The compiler's runtime is linked into every binary
  # (cmake/LotaExtension.cmake, and OpenAL Soft's own options), so what
  # the binaries import is the gem's DLLs, Ruby's, and Windows' own
  # (SYSTEM).
  #
  # What a binary imports is read from its import tables, as objdump -p
  # lists them, in Ruby, so the delivery check needs no MSYS2 on the
  # runner that installs the gem.
  class PE
    # Where the libraries go in the gem, relative to the bundle.
    DIRECTORY = "libraries"

    # The preloader's name, which lib/lota.rb requires as lota/preload.
    PRELOAD = "preload"

    # The DLLs of Windows itself that the gem's binaries may import, in
    # lower case, as Windows matches names: what the extension, the
    # preloader, and OpenAL Soft import, read from the binaries the
    # Windows build makes (objdump -p, as the closure step of the Windows
    # job prints it), each in System32 on every Windows Lota supports. The
    # UCRT's API sets (api-ms-win-crt-*), which Windows 10 and newer
    # carry, are allowed by their prefix, and Ruby's own DLL by its name
    # (RbConfig's LIBRUBY_SO).
    SYSTEM = %w[
      advapi32.dll
      avrt.dll
      dwmapi.dll
      gdi32.dll
      imm32.dll
      kernel32.dll
      ole32.dll
      oleaut32.dll
      setupapi.dll
      shell32.dll
      user32.dll
      version.dll
      winmm.dll
    ].freeze

    # The prefix of the UCRT's API sets.
    API_SETS = "api-ms-win-"

    # The machine each gem processor's binaries are for, as a PE file's
    # COFF header names it (IMAGE_FILE_MACHINE_AMD64 and _ARM64).
    MACHINES = { "x64" => 0x8664, "aarch64" => 0xAA64 }.freeze

    # How the delivery check's guard reports each module a run loaded.
    MAPPED = /^lota-package-check: mapped (.+)$/

    # The prefix of the sections that hold debugging information.
    DEBUG = ".debug"

    # [arch] Ruby's arch, x64-mingw-ucrt or aarch64-mingw-ucrt, which the
    #   gem's platform is.
    # [ruby] The name of Ruby's DLL, which the bundle imports.
    # [compiler] The C compiler, whose MSYS2 environment is the
    #   toolchain's.
    # [machine] Directories of the machine that builds or checks the gem,
    #   which no binary in it may name: the repository and the MSYS2
    #   environment MSYS2's shell names.
    def initialize(arch: RbConfig::CONFIG.fetch("arch"), ruby: RbConfig::CONFIG.fetch("LIBRUBY_SO"),
      compiler: ENV.fetch("CC", "cc"), machine: [Dir.pwd, ENV.fetch("MINGW_PREFIX", nil)].compact
    )
      @arch = arch
      @ruby = ruby
      @compiler = compiler
      @machine = machine
    end

    # The gem platform the bundle is built for: Ruby's own, which
    # RubyGems names x64-mingw-ucrt and aarch64-mingw-ucrt for
    # RubyInstaller's Ruby on x64 and ARM64. A gem for one does not match
    # the other, nor a Ruby built against the older MSVCRT (x64-mingw32).
    def platform
      raise Failure, "#{@arch} is not a MinGW UCRT Ruby" unless @arch.end_with?("-mingw-ucrt")

      Gem::Platform.new(@arch).to_s
    end

    # Where the libraries go in the gem, relative to the bundle.
    def directory
      DIRECTORY
    end

    # The extensions the gem carries beside +bundle+: the preloader.
    def companions(bundle)
      ["#{PRELOAD}#{File.extname(bundle)}"]
    end

    # The DLLs in the libraries directory beside +bundle+ that it or its
    # preloader imports, and those import in turn, each as a path relative
    # to the bundle's directory, named as the file is.
    def dependencies(bundle)
      directory = File.dirname(bundle)
      found = []
      waiting = binaries(bundle).select { |path| File.file?(path) }.flat_map { |path| imports(path) }
      until waiting.empty?
        file = library(directory, waiting.shift) or next
        relative = File.join(DIRECTORY, file)
        next if found.include?(relative)

        found << relative
        waiting.concat(imports(File.join(directory, relative)))
      end
      found
    end

    # Why +bundle+ would not load from inside +gem_dir+ alone, on any
    # Windows of its processor: a companion it lacks, a binary for another
    # machine, each DLL a binary imports that is neither one the gem
    # carries nor Windows' or Ruby's, and each binary that keeps its
    # debugging information or names a directory of this machine.
    def escapes(bundle, gem_dir)
      directory = File.dirname(bundle)
      present, missing = binaries(bundle).partition { |path| File.file?(path) }
      paths = present + dependencies(bundle).map { |relative| File.join(directory, relative) }
      missing.map { |path| "#{File.basename(bundle)} lacks #{File.basename(path)} beside it" } +
        paths.flat_map { |path| problems(path, directory, gem_dir) }.uniq
    end

    # Strips the staged +bundle+'s debugging information, and its
    # companions', which NativeGem stages beside it. It names no directory
    # to load from, so nothing else changes.
    def stage_bundle(bundle)
      binaries(bundle).select { |path| File.file?(path) }.each { |path| strip(path) }
    end

    # Copies the DLL at +source+ into +stage+, at +relative+ (the gem's
    # library directory), without its debugging information. Returns the
    # file it staged, relative to +stage+.
    def stage_library(stage, relative, source)
      file = File.join(relative, File.basename(source))
      FileUtils.mkdir_p(File.join(stage, relative))
      FileUtils.cp(source, File.join(stage, file))
      strip(File.join(stage, file))
      [file]
    end

    # Nothing is signed on Windows; says so.
    def verify(_bundle)
      "nothing signed on Windows"
    end

    # The path REUSE.toml annotates for the DLL at +path+: the file.
    def annotation(path)
      path
    end

    # What a run is given so it reports the modules it loads: nothing,
    # since the guard reports them (report_libraries).
    def report_environment
      {}
    end

    # Ruby run as the delivery check's guard exits, beside what it reports
    # of Lota: the file of each module the process has loaded, as Windows
    # PowerShell lists the modules of a process, once each. Fiddle, with
    # which Ruby could ask Windows itself, is a bundled gem, which the
    # check's empty GEM_HOME does not hold.
    def report_libraries
      <<~RUBY
        IO.popen(["powershell.exe", "-NoProfile", "-NonInteractive", "-Command",
          "(Get-Process -Id \#{Process.pid}).Modules | ForEach-Object { $_.FileName }"], &:readlines)
          .map(&:strip).reject(&:empty?).uniq.each { |path| puts "lota-package-check: mapped \#{path}" }
      RUBY
    end

    # The modules the guard reports a run loaded, with / for separators.
    def loaded(output)
      output.scan(MAPPED).flatten.map { |path| path.tr("\\", "/") }
    end

    # +output+ without what the guard reported of the modules.
    def printed(output)
      output.lines.grep_v(MAPPED).join
    end

    # The modules a run loaded that are neither Windows' nor Ruby's own,
    # which must load from the installed gem, and the bundle, each by its
    # real path, as the installed gem's directory is named.
    def ours(output)
      windows = File.join(ENV.fetch("SystemRoot", "C:/Windows").tr("\\", "/"), "")
      ruby = File.join(RbConfig::CONFIG.fetch("prefix"), "")
      loaded(output).reject { |path| [windows, ruby].any? { |dir| path.downcase.start_with?(dir.downcase) } }
        .map { |path| File.exist?(path) ? File.realpath(path) : path }
    end

    # The toolchain's own files, which the bundle reads but does not
    # carry: the MSYS2 environment of the compiler, its headers, runtime,
    # and Windows' import libraries, and Ruby's import library.
    def toolchain
      [environment, RbConfig::CONFIG.fetch("libdir")]
    end

    # The directories the compiler's linker searches for a library named
    # without one, as the compiler lists them, and Ruby's, where its
    # import library is.
    def library_directories
      output = NativeFormat.run!(@compiler, "-print-search-dirs")
      searched = output[/^libraries: =(.*)$/, 1].to_s.split(";").reject { |dir| dir.strip.empty? }
      # clang lists its resource directory, not the directory under it
      # that holds its runtime, which it names as libgcc's.
      runtime = File.dirname(NativeFormat.run!(@compiler, "-print-libgcc-file-name").strip)
      (searched + [runtime, RbConfig::CONFIG.fetch("libdir")]).map { |dir| File.expand_path(dir.strip) }.uniq
    end

    # The DLLs +binary+ imports, by the names it imports them by, from its
    # import and delay-load import tables.
    def imports(binary)
      Image.new(binary).imports
    rescue Image::Invalid => e
      raise Failure, e.message
    end

    # The processor +binary+ is for, as its COFF header names it.
    def machine(binary)
      Image.new(binary).machine
    rescue Image::Invalid => e
      raise Failure, e.message
    end

    # The bundle and its companions.
    private def binaries(bundle)
      [bundle] + companions(bundle).map { |name| File.join(File.dirname(bundle), name) }
    end

    # The file in +directory+'s libraries that Windows would take for the
    # DLL +name+, matched as Windows matches names, without case, or nil.
    private def library(directory, name)
      libraries = File.join(directory, DIRECTORY)
      return unless File.directory?(libraries)

      Dir.children(libraries).find { |file| file.casecmp?(name) }
    end

    private def problems(path, directory, gem_dir)
      inside = File.join(File.realpath(gem_dir), "")
      name = File.basename(path)
      problems = []
      expected = MACHINES.fetch(@arch.split("-").first, nil)
      problems << "#{name} is for machine 0x#{machine(path).to_s(16)}" if expected && machine(path) != expected
      imports(path).each do |dll|
        next if system?(dll)

        file = library(directory, dll)
        next if file && File.realpath(File.join(directory, DIRECTORY, file)).start_with?(inside)

        problems << "#{dll}, which #{name} imports, is neither the gem's nor Windows' nor Ruby's"
      end
      problems + debugging(path) + named(path)
    end

    # Why +path+ keeps its debugging information: each such section.
    private def debugging(path)
      Image.new(path).sections.grep(/\A#{Regexp.escape(DEBUG)}/o).map do |section|
        "#{File.basename(path)} keeps its debugging information (#{section})"
      end
    rescue Image::Invalid => e
      raise Failure, e.message
    end

    # Each directory of this machine's that +path+ names, written with
    # either separator, in any case.
    private def named(path)
      data = File.binread(path).downcase
      @machine.select do |dir|
        [dir.tr("\\", "/"), dir.tr("/", "\\")].any? { |form| data.include?(form.downcase.b) }
      end.map { |dir| "#{File.basename(path)} names #{dir}, a directory of the machine that built it" }
    end

    # Strips +path+'s debugging information, with the toolchain's strip,
    # GNU binutils' with GCC and LLVM's with clang.
    private def strip(path)
      NativeFormat.run!("strip", "--strip-debug", path)
    end

    private def system?(dll)
      dll.downcase.start_with?(API_SETS) || SYSTEM.include?(dll.downcase) || dll.casecmp?(@ruby)
    end

    # The MSYS2 environment the compiler belongs to, such as
    # C:/msys64/ucrt64/: the directory above its bin.
    private def environment
      path = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).filter_map do |dir|
        ["", ".exe"].map { |extension| File.join(dir, "#{@compiler}#{extension}") }.find { |file| File.file?(file) }
      end.first or raise Failure, "#{@compiler} is not on PATH"
      File.join(File.dirname(File.dirname(File.expand_path(path))), "")
    end

    # A PE file's headers, read as the PE format specifies them
    # (Microsoft's "PE Format", sections "MS-DOS Stub", "COFF File
    # Header", "Optional Header Data Directories", "Section Table", "The
    # .idata Section", and "Delay-Load Import Tables").
    class Image
      # Raised for a file that is not a PE image.
      class Invalid < StandardError; end

      # The data directories of the import table and the delay-load import
      # table, and the size of each table's entries.
      IMPORT = [1, 20, 12].freeze
      DELAY_IMPORT = [13, 32, 4].freeze

      # +path+'s headers.
      def initialize(path)
        @path = path
        @data = File.binread(path)
        header = @data.byteslice(0x3C, 4)&.unpack1("V")
        raise Invalid, "#{path} is not a PE image" unless @data.start_with?("MZ") && header &&
          @data.byteslice(header, 4) == "PE\0\0"

        @coff = header + 4
      end

      # The machine the image is for (IMAGE_FILE_MACHINE_*).
      def machine
        u16(@coff)
      end

      # The DLLs the image imports, in the order its tables list them, each
      # once.
      def imports
        [IMPORT, DELAY_IMPORT].flat_map { |table| names(*table) }.uniq
      end

      # The names of the image's sections. A name longer than eight bytes,
      # as GNU ld writes .debug_info, is a / and its offset in the COFF
      # string table, which follows the symbol table.
      def sections
        table = @coff + 20 + u16(@coff + 16)
        Array.new(u16(@coff + 2)) do |i|
          name = @data.byteslice(table + (i * 40), 8).to_s.unpack1("Z8")
          name.match?(%r{\A/\d+\z}) ? string(u32(@coff + 8) + (u32(@coff + 12) * 18) + name[1..].to_i) : name
        end
      end

      private def names(index, size, name_offset)
        rva, length = directory(index)
        return [] if rva.zero? || length.zero?

        offset = offset(rva)
        names = []
        loop do
          entry = @data.byteslice(offset, size)
          break if entry.nil? || entry.bytesize < size || entry.each_byte.all?(&:zero?)

          name = entry.byteslice(name_offset, 4).unpack1("V")
          # A delay-load entry whose attributes lack bit 0 holds addresses
          # rather than RVAs, as Visual C++ 6.0 wrote them.
          name -= image_base if index == DELAY_IMPORT.first && entry.unpack1("V").nobits?(1)
          names << string(offset(name))
          offset += size
        end
        names
      end

      # The RVA and size of data directory +index+, or zeros where the
      # image has fewer.
      private def directory(index)
        optional = @coff + 20
        plus = u16(optional) == 0x20B
        count = u32(optional + (plus ? 108 : 92))
        return [0, 0] if index >= count

        at = optional + (plus ? 112 : 96) + (index * 8)
        [u32(at), u32(at + 4)]
      end

      # Where the image prefers to load, which an address is relative to.
      private def image_base
        optional = @coff + 20
        (u16(optional) == 0x20B) ? @data.byteslice(optional + 24, 8).unpack1("Q<") : u32(optional + 28)
      end

      # Where the RVA +rva+ is in the file, by the section that holds it.
      private def offset(rva)
        sections = @coff + 20 + u16(@coff + 16)
        u16(@coff + 2).times do |i|
          at = sections + (i * 40)
          virtual_size, address, raw_size, raw = @data.byteslice(at + 8, 16).unpack("V4")
          return rva - address + raw if rva >= address && rva < address + [virtual_size, raw_size].max
        end
        raise Invalid, "#{@path} has no section at RVA 0x#{rva.to_s(16)}"
      end

      private def string(offset)
        @data.byteslice(offset, 512).to_s.unpack1("Z*").force_encoding(Encoding::UTF_8)
      end

      private def u16(offset)
        @data.byteslice(offset, 2).unpack1("v")
      end

      private def u32(offset)
        @data.byteslice(offset, 4).unpack1("V")
      end
    end
  end
end
