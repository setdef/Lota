# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# The checks .github/workflows/windows.yml runs on Windows, in
# RubyInstaller's Ruby, each a command:
#
# [notices BUILD SOURCE] Every file of SOURCE that ninja compiled in BUILD,
#   with each notice of copyright and each license its first lines state,
#   for ext/lota/licenses.rb.
# [werror COMPILE_COMMANDS] Compiles a file of Lota's with an array read
#   out of bounds, with the extension's own command, and passes only if
#   that fails as an error while the same file without the read compiles.
# [closure FILE...] Every DLL each FILE loads, and those load, and passes
#   only if each is Windows', Ruby's, or one of lib/lota/libraries.
# [load MODE DECOY] Loads Lota and reports where Windows found each DLL.
#   MODE preload requires "lota", as a game does, after a decoy
#   OpenAL32.dll's directory DECOY and the runner's MSYS2 are added to
#   the DLL search, and passes only if OpenAL32.dll is the one in
#   lib/lota/libraries and nothing loads from DECOY or MSYS2. MODE bare
#   requires "lota/native" without the preloader, with only DECOY added,
#   and exits 3 when the decoy answered, as a control.
# [restart] Runs <tt>lota run</tt> on test/games/restart, which restarts
#   twice and then quits with status 3, and passes only if each run read
#   the value the run before it chose and the last run's status is the
#   first process's. Ruby's exec on Windows starts the command as a new
#   process, waits for it, and exits with its status (win32/win32.c,
#   child_result, with P_OVERLAY), so each run has a process id of its
#   own, which it reports.

require "json"
require "open3"
require "rbconfig"
require "tmpdir"

# The checks, one method each.
module WindowsChecks
  ROOT = File.expand_path("..", __dir__)
  LIBRARIES = File.join(ROOT, "lib/lota/libraries")
  # Words that name or quote a license, for which #notices reports a file.
  LICENSE_WORDS = [
    "GNU Library General Public",
    "GNU Lesser General Public",
    "GNU General Public",
    "MIT",
    "BSD",
    "Apache",
    "public domain",
    "Permission is hereby",
    "Redistribution and use",
  ].freeze

  extend self

  def notices(build, source)
    deps, status = Open3.capture2("ninja", "-C", build, "-t", "deps")
    abort "ninja -t deps failed in #{build}" unless status.success?
    prefix = normal(source)
    files = deps.lines.map(&:strip).select { |line| normal(line).start_with?(prefix) }.uniq.sort
    puts "#{files.size} files of #{source} compiled"
    by_notice = Hash.new { |hash, key| hash[key] = [] }
    files.each do |file|
      text = File.binread(file).force_encoding(Encoding::UTF_8).scrub
      notices = text.scan(/^.*copyright.*$/i).map { |line| line.gsub(%r{\A[\s/*#;-]+|[\s*/]+\z}, "") }
      licenses = LICENSE_WORDS.select { |word| text.include?(word) }
      by_notice[[notices.sort, licenses]] << file.delete_prefix(prefix)
    end
    by_notice.sort_by { |key, _| key.inspect }.each do |(notices, licenses), paths|
      puts "--- #{licenses.join(', ')}: #{notices.join(' | ')}"
      puts paths.map { |path| "    #{path}" }
    end
  end

  def werror(commands)
    entry = JSON.parse(File.read(commands)).find { |item| item.fetch("file").end_with?("native/math.cpp") }
    abort "no compile command for native/math.cpp in #{commands}" unless entry
    command = entry.fetch("command")
    abort "the extension compiles without -Werror: #{command}" unless command.include?("-Werror")
    abort "the extension turns an error off: #{command}" if command.match?(/-Wno-error/)

    probe = File.join(ROOT, "tmp", "werror_probe.cpp")
    clean = compile(command, entry.fetch("file"), probe, "int lota_probe(int i) { int a[2] = {i, i + 1}; return a[1]; }")
    abort "the probe without the read did not compile:\n#{clean.last}" unless clean.first

    passed, output = compile(command, entry.fetch("file"), probe,
      "int lota_probe(int i) { int a[2] = {i, i + 1}; return a[3]; }")
    abort "an array read out of bounds compiled:\n#{output}" if passed
    abort "the probe failed for another reason:\n#{output}" unless output.match?(/-Werror[=,]-?W?array-bounds/)

    puts "Lota's code still fails on a warning (-Warray-bounds among them):"
    puts output.lines.grep(/error/).first(3)
  end

  # Compiles +body+ after binding.hpp, as +file+ is compiled by +command+.
  def compile(command, _file, probe, body)
    File.binwrite(probe, "#include \"native/binding.hpp\"\n#{body}\n")
    # The source, however the command spells its path, but not the object
    # or dependency files named after it.
    source = %r{(?<=\s)\S*native[\\/]math\.cpp(?=\s|\z)}
    abort "no source in the compile command: #{command}" unless command.match?(source)

    probe_command = command.gsub(source, probe.tr("\\", "/")).sub(/-o \S+/, "-o #{probe}.obj")
    output, status = Open3.capture2e(probe_command)
    [status.success?, "#{probe_command}\n#{output}"]
  end

  def closure(*files)
    objdump = %w[objdump llvm-objdump].find { |tool| system(tool, "--version", out: File::NULL, err: File::NULL) }
    problems = []
    seen = {}
    queue = files.map { |file| File.expand_path(file) }
    done = []
    until queue.empty?
      file = queue.shift
      next if done.include?(file.downcase)

      done << file.downcase
      puts "#{file.delete_prefix("#{ROOT}/")}: #{File.size(file)} bytes"
      imports, = Open3.capture2(objdump, "-p", file)
      imports.scan(/DLL Name: (\S+)/).flatten.each do |dll|
        next if seen[dll.downcase]

        seen[dll.downcase] = true
        where = provider(dll)
        queue << File.join(LIBRARIES, dll) if where == "lib/lota/libraries"
        problems << dll unless where
        puts "  #{dll} (#{where || "neither Windows', Ruby's, nor Lota's"}), needed by #{File.basename(file)}"
      end
    end
    abort "DLLs from elsewhere: #{problems.join(', ')}" unless problems.empty?
    puts "The DLLs that are not Windows' or Ruby's: #{Dir.children(LIBRARIES).sort.join(', ')}"
  end

  # Whose +dll+ is: Lota's, Ruby's, Windows', or nil for anyone else's.
  def provider(dll)
    if File.exist?(File.join(LIBRARIES, dll)) then "lib/lota/libraries"
    elsif File.exist?(File.join(RbConfig::CONFIG["bindir"], dll)) then "Ruby's"
    elsif dll.start_with?("api-ms-win-") || File.exist?(File.join("C:/Windows/System32", dll)) then "Windows'"
    end
  end

  def load(mode, decoy)
    puts "#{RUBY_DESCRIPTION}, PATH #{ENV.fetch('PATH', '')}"
    report_dll_directories
    $LOAD_PATH.unshift(File.join(ROOT, "lib"))
    (mode == "bare") ? load_bare(decoy) : load_preloaded(decoy)
  end

  # How RubyInstaller adds a DLL directory: by its own extension (:cext),
  # Fiddle, or PATH.
  def report_dll_directories
    mechanism = RubyInstaller::Runtime::DllDirectory.class_variable_get(:@@dll_directory_mechanism)
    puts "RubyInstaller adds DLL directories by #{mechanism.inspect} " \
      "(#{$LOADED_FEATURES.grep(/dll_directory/).join(', ')})"
  rescue NameError => e
    puts "RubyInstaller's DllDirectory: #{e.message}"
  end

  def load_bare(decoy)
    RubyInstaller::Runtime.add_dll_directory(decoy)
    require "lota/native"
    puts "Lota's extension loaded with only the decoy to answer for OpenAL32.dll"
    exit 1
  rescue LoadError => e
    puts "LoadError: #{e.message}"
    # 127: ERROR_PROC_NOT_FOUND, Windows found an OpenAL32.dll without
    # OpenAL's functions: the decoy.
    exit((e.message.include?("127") || e.message.include?("procedure")) ? 3 : 1)
  end

  def load_preloaded(decoy)
    begin
      RubyInstaller::Runtime.enable_msys_apps
      puts "MSYS2 enabled: #{RubyInstaller::Runtime.msys2_installation.mingw_bin_path}"
    rescue => e
      puts "No MSYS2 to enable: #{e.class}: #{e.message}"
    end
    RubyInstaller::Runtime.add_dll_directory(decoy)
    # OpenAL Soft plays into a wave file, as the tests have it.
    ENV["ALSOFT_CONF"] = File.join(ROOT, "test/alsoft.conf")
    ENV["LOTA_TEST_HOME"] = Dir.mktmpdir("lota-windows-")
    require "lota"
    %i[Data Sound Audio].each { |name| Lota::Native.const_get(name).open }
    modules = loaded_modules
    puts "Loaded:", modules.map { |path| "  #{path}" }
    openal = modules.find { |path| File.basename(path).casecmp?("OpenAL32.dll") }
    expected = File.join(LIBRARIES, "OpenAL32.dll")
    abort "OpenAL32.dll is #{openal.inspect}, not #{expected}" unless openal && same?(openal, expected)
    strays = modules.select { |path| path.match?(%r{msys64|/decoy/}i) }
    abort "loaded from MSYS2 or the decoy: #{strays.join(', ')}" unless strays.empty?
    puts "OpenAL32.dll is Lota's own, #{openal}, and nothing loaded from MSYS2 or the decoy"
  end

  # The path of every module loaded in this process.
  def loaded_modules
    require "fiddle"
    kernel32 = Fiddle.dlopen("kernel32")
    process = Fiddle::Function.new(kernel32["GetCurrentProcess"], [], Fiddle::TYPE_VOIDP)
    enum = Fiddle::Function.new(kernel32["K32EnumProcessModules"],
      [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
    name = Fiddle::Function.new(kernel32["GetModuleFileNameW"],
      [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_INT)
    handles = Fiddle::Pointer.malloc(8 * 1024, Fiddle::RUBY_FREE)
    needed = Fiddle::Pointer.malloc(4, Fiddle::RUBY_FREE)
    abort "K32EnumProcessModules failed" if enum.call(process.call, handles, 8 * 1024, needed).zero?

    count = needed[0, 4].unpack1("L") / Fiddle::SIZEOF_VOIDP
    handles[0, count * Fiddle::SIZEOF_VOIDP].unpack("Q*").map do |handle|
      buffer = Fiddle::Pointer.malloc(2 * 1024, Fiddle::RUBY_FREE)
      length = name.call(handle, buffer, 1024)
      buffer[0, length * 2].force_encoding(Encoding::UTF_16LE).encode(Encoding::UTF_8).tr("\\", "/")
    end
  end

  def restart
    log = File.join(Dir.mktmpdir("lota-restart-"), "log")
    environment = { "RUBYOPT" => "-I#{File.join(ROOT, 'lib')}", "LOTA_RESTART_LOG" => log }
    output, status = Open3.capture2e(environment, RbConfig.ruby, "-w", File.join(ROOT, "exe/lota"), "run",
      File.join(ROOT, "test/games/restart"), "chain", "string", "table")
    puts output
    abort "lota run exited #{status.exitstatus}, not 3" unless status.exitstatus == 3

    loads = File.readlines(log, chomp: true).grep(/\Aload /)
    puts loads
    values = loads.map { |line| line[/ restart=(.*) variable=/, 1] }
    expected = ["nil", '"café\nline"', '[1.0, {"name" => "ada"}]']
    abort "the runs read #{values.inspect}, not #{expected.inspect}" unless values == expected

    pids = loads.map { |line| line[/ pid=(\d+)/, 1] }
    abort "the runs shared a process id: #{pids.join(', ')}" unless pids.uniq.size == pids.size
    puts "Each restart crossed, each run in a process of its own: #{pids.join(', ')}"
  end

  def same?(path, other)
    File.expand_path(path).casecmp?(File.expand_path(other))
  end

  def normal(path)
    File.expand_path(path).tr("\\", "/").downcase
  end
end

command, *arguments = ARGV
WindowsChecks.public_send(command, *arguments)
