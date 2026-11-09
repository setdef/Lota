# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# The checks the Windows jobs of .github/workflows/ci.yml run, in
# RubyInstaller's Ruby, each a command:
#
# [notices BUILD SOURCE] Every file of SOURCE that ninja compiled in BUILD,
#   with each notice of copyright and each license its first lines state,
#   for ext/lota/licenses.rb.
# [werror COMPILE_COMMANDS] Compiles a file of Lota's with an array read
#   out of bounds, with the extension's own command, and passes only if
#   that fails as an error while the same file without the read compiles.
# [closure FILE...] Every DLL each FILE loads, and those load, and passes
#   only if each is Windows', Ruby's, or one of lib/lota/libraries, and
#   no FILE imports from Ruby's DLL a function of Windows' kernel32.dll.
# [load MODE DECOY] Loads Lota and reports where Windows found each DLL.
#   MODE preload requires "lota", as a game does, after DECOY, a directory
#   with a decoy of each DLL in lib/lota/libraries (SDL3.dll and
#   OpenAL32.dll), and the runner's MSYS2 are added to the DLL search, and
#   passes only if each of those DLLs is the one in lib/lota/libraries and
#   nothing loads from DECOY or MSYS2. MODE bare requires "lota/native"
#   without the preloader, with only DECOY added, and exits 3 when a decoy
#   answered, as a control.
# [opengl [EXPECT]] Runs <tt>lota run</tt> on test/games/opengl, and
#   passes only if SDL made an OpenGL context for its window, which the
#   engine used or refused for its version, and its output holds EXPECT.
# [restart] Runs <tt>lota run</tt> on test/games/restart, which restarts
#   twice and then quits with status 3, and passes only if each run read
#   the value the run before it chose and the last run's status is the
#   first process's. Ruby's exec on Windows starts the command as a new
#   process, waits for it, and exits with its status (win32/win32.c,
#   child_result, with P_OVERLAY), so each run has a process id of its
#   own, which it reports.
# [package] Builds the precompiled gem into pkg/, as rake package:native
#   does, from the extension, the preloader, and the DLLs the job built,
#   after downloading the source archives the gem carries.
# [deliver GEM...] Installs the precompiled gems into an empty GEM_HOME
#   and runs lota from them, as rake package:deliver does.
# [mesa BIN [FOLDER]] Copies Mesa's OpenGL from the MSYS2 directory BIN
#   beside Ruby's own program, or into FOLDER, beside another, such as a
#   fused game's, where Windows looks first for the opengl32.dll SDL
#   loads by name, ahead of System32's, whose OpenGL 1.1 LÖVE refuses:
#   opengl32.dll, its driver libgallium_wgl.dll, and every DLL of BIN
#   either needs, but none the folder has already.
# [tests LOGS [--prepush]] Runs each file of the tests rake test runs
#   (TEST_SUITES in tasks/test.rake), but those WINDOWS_EXCLUDED leaves
#   out, in a Ruby of its own, as Minitest's task does, each within
#   TEST_BUDGET seconds, keeps what each printed in LOGS, and passes only
#   if every file passed. With --prepush each file leaves out the tests
#   the pre-push tier leaves out (PREPUSH_EXCLUDE in tasks/test.rake).
#
# package, deliver, and tests load tasks/*.rake without Bundler, whose
# Gemfile holds gems RubyInstaller's Ruby would have to compile.

require "fileutils"
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
      problems.concat(windows_functions_from_ruby(file, imports))
      imports.scan(/DLL Name: (\S+)/).flatten.each do |dll|
        next if seen[dll.downcase]

        seen[dll.downcase] = true
        where = provider(dll)
        queue << File.join(LIBRARIES, dll) if where == "lib/lota/libraries"
        problems << dll unless where
        puts "  #{dll} (#{where || "neither Windows', Ruby's, nor Lota's"}), needed by #{File.basename(file)}"
      end
    end
    abort "DLLs from elsewhere, or Windows' functions from Ruby's: #{problems.join(', ')}" unless problems.empty?
    puts "The DLLs that are not Windows' or Ruby's: #{Dir.children(LIBRARIES).sort.join(', ')}"
  end

  # Each function of kernel32.dll's that +file+ imports from Ruby's DLL,
  # by the import table objdump printed (+imports+). Ruby's DLL exports
  # Sleep, its rb_w32_Sleep, which needs a thread of Ruby's, so a binary
  # that binds Windows' Sleep to it crashes when a thread Ruby does not
  # know sleeps, as winpthreads' threads do as they start.
  def windows_functions_from_ruby(file, imports)
    ruby = RbConfig::CONFIG.fetch("LIBRUBY_SO")
    section = imports.split(/^\s*DLL Name: /).find { |part| part.lines.first.to_s.strip.casecmp?(ruby) }
    names = section.to_s.lines.drop(1).take_while { |line| !line.strip.empty? }
      .filter_map { |line| line[/\A\s+\h+\s+(?:<none>\s+)?\h+\s+([A-Za-z_]\w*)\s*\z/, 1] }
    names.select { |name| kernel32?(name) }.map { |name| "#{File.basename(file)} imports #{name} from #{ruby}" }
  end

  # Whether Windows' kernel32.dll exports a function named +name+.
  def kernel32?(name)
    require "fiddle"
    @kernel32 ||= Fiddle::Handle.new("kernel32.dll")
    @kernel32.sym(name)
    true
  rescue Fiddle::DLError
    false
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
    puts "Lota's extension loaded with only the decoys to answer for its DLLs"
    exit 1
  rescue LoadError => e
    puts "LoadError: #{e.message}"
    # 127: ERROR_PROC_NOT_FOUND, Windows found a DLL of the right name
    # without the functions the extension imports from it: a decoy.
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
    Dir.children(LIBRARIES).sort.each do |dll|
      found = modules.find { |path| File.basename(path).casecmp?(dll) }
      expected = File.join(LIBRARIES, dll)
      abort "#{dll} is #{found.inspect}, not #{expected}" unless found && same?(found, expected)
      puts "#{dll} is Lota's own, #{found}"
    end
    strays = modules.select { |path| path.match?(%r{msys64|/decoy/}i) }
    abort "loaded from MSYS2 or the decoy: #{strays.join(', ')}" unless strays.empty?
    puts "Nothing loaded from MSYS2 or the decoy"
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

  # Runs <tt>lota run</tt> on test/games/opengl, which opens a window with
  # OpenGL alone, and passes only if SDL made an OpenGL context: the game
  # reports an OpenGL renderer, or the engine refuses the context for its
  # version ("Detected OpenGL version", vendor/love/src/modules/window/sdl/
  # Window.cpp:427-430), as it refuses the OpenGL 1.1 Windows gives a
  # runner without a GPU. +expect+, if given, must also be in what it
  # printed.
  def opengl(expect = nil)
    output, status = Open3.capture2e({ "RUBYOPT" => "-I#{File.join(ROOT, 'lib')}" }, RbConfig.ruby, "-w",
      File.join(ROOT, "exe/lota"), "run", File.join(ROOT, "test/games/opengl"))
    puts output
    opened = status.success? && output.include?("renderer: OpenGL")
    refused = status.exitstatus == 1 && output.include?("Detected OpenGL version")
    abort "lota run exited #{status.exitstatus} with no OpenGL context" unless opened || refused
    abort "lota run did not print #{expect.inspect}" if expect && !output.include?(expect)

    puts opened ? "The window opened with OpenGL" : "SDL made an OpenGL context, which the engine refused"
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

  # Builds the precompiled gem into pkg/, as rake package:native does, from
  # what the job built, and the archives sources:fetch keeps.
  def package
    package_tasks
    Licensing.load(File.join(ROOT, "ext/lota/licenses.rb")).frameworks.each_value.filter_map(&:source).uniq
      .each { |source| SourceArchive.new(source, root: ROOT).fetch }
    puts "Built #{build_native_package}"
  rescue PackageCheck::Failure, SourceArchive::Failure => e
    abort "#{e.class}: #{e.message}"
  end

  # Installs the precompiled gems given into an empty GEM_HOME and runs
  # lota from them, as rake package:deliver does.
  def deliver(*gems)
    package_tasks
    deliver_packages(gems)
  end

  # tasks/package.rake's helpers, which rake package:native and
  # package:deliver call, loaded without the bundle, which RubyInstaller's
  # Ruby would have to compile gems for: rake and Ruby's own gems are all
  # they need.
  def package_tasks
    require "rake"
    TOPLEVEL_BINDING.receiver.extend(Rake::DSL)
    Dir.chdir(ROOT)
    # Kernel's load, which the load check's name hides here.
    %w[engine package].each { |name| Kernel.load(File.join(ROOT, "tasks/#{name}.rake")) }
  end

  def mesa(bin, target = RbConfig::CONFIG["bindir"])
    objdump = %w[objdump llvm-objdump].find { |tool| system(tool, "--version", out: File::NULL, err: File::NULL) }
    queue = %w[opengl32.dll libgallium_wgl.dll]
    done = []
    until queue.empty?
      dll = queue.shift
      next if done.include?(dll.downcase)

      done << dll.downcase
      source = File.join(bin, dll)
      abort "#{source} is missing" unless File.exist?(source)
      if File.exist?(File.join(target, dll))
        puts "#{dll}: already in #{target}"
        next
      end
      FileUtils.cp(source, target)
      puts "#{dll}: copied from #{bin}"
      imports, = Open3.capture2(objdump, "-p", source)
      queue.concat(imports.scan(/DLL Name: (\S+)/).flatten.select { |name| File.exist?(File.join(bin, name)) })
    end
  end

  # The tests rake test runs that Windows leaves out, a file or a folder
  # each, with why.
  WINDOWS_EXCLUDED = {
    "test/tasks/" => "it tests the gate's Rake tasks and the builds they drive, which run on macOS and Linux " \
      "with those systems' tools and paths; on Windows the build job's steps and this file build and check",
    "test/native/bundle_test.rb" => "it reads rpaths and dynamic symbols, which Windows has none of; " \
      "the closure and load checks read the extension's DLLs instead",
  }.freeze

  # How long a file of tests may run, in seconds.
  TEST_BUDGET = 900

  def tests(logs, tier = nil)
    abort "tests takes LOGS and, optionally, --prepush" unless [nil, "--prepush"].include?(tier)
    FileUtils.mkdir_p(logs)
    files = test_files
    options = tier ? ["--exclude", PREPUSH_EXCLUDE] : []
    results = files.map { |file| run_test_file(file, logs, options) }
    report(results)
    WINDOWS_EXCLUDED.each { |file, reason| puts "Not run: #{file}, #{reason}" }
    failed = results.reject { |result| result[:passed] }
    abort "#{failed.size} of #{files.size} test files failed: #{failed.map { |result| result[:file] }.join(', ')}" if failed.any?

    puts "All #{files.size} test files passed"
  end

  # TEST_SUITES' test:ruby files, from tasks/test.rake, but those
  # WINDOWS_EXCLUDED leaves out.
  def test_files
    require "rake"
    TOPLEVEL_BINDING.receiver.extend(Rake::DSL)
    Dir.chdir(ROOT)
    Kernel.load(File.join(ROOT, "tasks/test.rake"))
    Dir[*TEST_SUITES.fetch(:ruby)].sort.reject { |file| WINDOWS_EXCLUDED.keys.any? { |left| file.start_with?(left) } }
  end

  # Runs +file+ as Minitest's task does, with its tests' names and times,
  # Minitest's +options+, and its output kept in +logs+. RUBYLIB holds lib, as Bundler's setup,
  # which the gate runs under, puts the gemspec's lib on the load path of
  # every Ruby a test starts.
  def run_test_file(file, logs, options = [])
    log = File.join(logs, "#{file.delete_suffix('.rb').tr('/', '-')}.log")
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    pid = Process.spawn({ "RUBYLIB" => File.join(ROOT, "lib") }, RbConfig.ruby, "-w", "-Ilib", "-Itest", file,
      "--verbose", *options, chdir: ROOT, in: File::NULL, out: log, err: %i[child out])
    status = wait_within(pid, TEST_BUDGET)
    seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    # A Ruby on Windows writes its lines with CRLF.
    output = File.binread(log).force_encoding(Encoding::UTF_8).scrub.delete("\r")
    summary = output[/^\d+ runs, \d+ assertions, \d+ failures, \d+ errors, \d+ skips$/]
    passed = (status&.success? && summary&.match?(/ 0 failures, 0 errors/)) ? true : false
    puts "== #{file}: #{passed ? 'passed' : 'FAILED'} in #{seconds.round}s, #{summary || status&.inspect || 'out of time'}"
    puts output.lines.last(60).join unless passed
    { file:, passed:, seconds:, summary:, skips: output.scan(/^\s*\d+\) Skipped:\n(.+)\n(.+)$/).map { |pair| pair.join(" ") } }
  end

  # The Process::Status of +pid+, or nil after ending it and every process
  # it started when it runs past +seconds+.
  def wait_within(pid, seconds)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
    loop do
      _, status = Process.wait2(pid, Process::WNOHANG)
      return status if status
      break if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.5
    end
    system("taskkill", "/T", "/F", "/PID", pid.to_s, out: File::NULL, err: File::NULL)
    Process.wait(pid)
    nil
  end

  # Each file's result, in the job's summary too.
  def report(results)
    lines = ["| File | Result | Seconds | Summary |", "| --- | --- | --- | --- |"]
    results.each do |result|
      lines << "| #{result[:file]} | #{result[:passed] ? 'passed' : 'failed'} | #{result[:seconds].round} | " \
        "#{result[:summary]} |"
    end
    skips = results.flat_map { |result| result[:skips].map { |skip| "- #{result[:file]}: #{skip}" } }
    text = [*lines, "", "Skipped:", *skips].join("\n")
    puts text
    summary = ENV.fetch("GITHUB_STEP_SUMMARY", nil)
    File.write(summary, "#{text}\n", mode: "a") if summary
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
