# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/native_format"

# NativeFormat::PE reads Windows' DLLs for the precompiled gem: what each
# imports, from its import tables, and whether the gem's binaries load
# from the gem alone. Its tests write small PE images of their own, so
# they run on every platform; the Windows job checks the real ones.
class NativeFormatPETest < Minitest::Test
  include TreeHelper

  X64 = 0x8664
  ARM64 = 0xAA64

  # A PE32+ image for +machine+ that imports +imports+ through its import
  # table and +delayed+ through its delay-load import table, with the
  # sections +sections+ besides its .idata, whose long names go in a
  # string table, and +strings+ in its data.
  def image(machine: X64, imports: [], delayed: [], sections: [], strings: "")
    rva = 0x1000
    names = (imports + delayed).map { |name| "#{name}\0" }
    table = (imports.size + 1) * 20
    delay_table = (delayed.size + 1) * 32
    offsets = names.each_with_index.map { |_, index| rva + table + delay_table + names.first(index).sum(&:bytesize) }
    body = imports.each_index.map { |index| [0, 0, 0, offsets[index], 0].pack("V5") }.join + ("\0" * 20)
    body += delayed.each_index.map { |index| [1, offsets[imports.size + index], 0, 0, 0, 0, 0, 0].pack("V8") }.join
    body += ("\0" * 32) + names.join + strings
    directories = Array.new(16) { [0, 0] }
    directories[1] = [rva, table] if imports.any?
    directories[13] = [rva + table, delay_table] if delayed.any?
    optional = [0x20B].pack("v") + ("\0" * 22) + [0x180000000].pack("Q<") + ("\0" * 76) + [16].pack("V") +
      directories.flatten.pack("V*")
    string_table = sections.map { |name| "#{name}\0" }.join
    headers = ["MZ", "\0" * 58, [0x40].pack("V"), "PE\0\0"].join
    symbols = 0x200 + body.bytesize
    coff = [machine, sections.size + 1, 0, symbols, 0, optional.bytesize, 0x2022].pack("vvVVVvv")
    section_table = section(".idata", rva, body.bytesize, 0x200) +
      sections.each_with_index.map { |_, index| section("/#{4 + sections.first(index).sum { |name| name.size + 1 }}", 0, 0, 0) }.join
    header = headers + coff + optional + section_table
    (header + ("\0" * (0x200 - header.bytesize)) + body + [string_table.bytesize + 4].pack("V") + string_table).b
  end

  def section(name, rva, size, raw)
    [name].pack("a8") + [size, rva, size, raw, 0, 0].pack("V6") + [0, 0].pack("vv") + [0].pack("V")
  end

  def format(arch: "x64-mingw-ucrt", machine: [])
    NativeFormat::PE.new(arch:, ruby: "x64-ucrt-ruby400.dll", compiler: "gcc", machine:)
  end

  # A gem's lib/lota: the bundle, the preloader, and the DLLs, each file
  # name to its image.
  def gem(root, files)
    files.each { |path, data| File.binwrite(write(root, File.join("lib/lota", path)), data) }
    File.join(root, "lib/lota/native.so")
  end

  def test_windows_is_read_as_pe
    assert_instance_of NativeFormat::PE, NativeFormat.for("mingw32")
  end

  def test_it_reads_the_dlls_an_image_imports_and_delay_loads_once_each_in_order
    in_tree do |root|
      path = File.join(root, "a.dll")
      File.binwrite(path, image(imports: %w[KERNEL32.dll OpenAL32.dll], delayed: %w[dwmapi.dll KERNEL32.dll]))

      assert_equal %w[KERNEL32.dll OpenAL32.dll dwmapi.dll], format.imports(path)
      assert_equal X64, format.machine(path)
    end
  end

  def test_a_file_that_is_not_a_pe_image_fails
    in_tree do |root|
      path = write(root, "a.dll", "MZ but nothing more")

      assert_raises(NativeFormat::Failure) { format.imports(path) }
    end
  end

  # The gem platform is Ruby's own arch, as RubyGems names it for
  # RubyInstaller's Ruby, and only a UCRT one.
  def test_the_platform_is_rubys_ucrt_arch
    assert_equal "x64-mingw-ucrt", format.platform
    assert_equal "aarch64-mingw-ucrt", format(arch: "aarch64-mingw-ucrt").platform
    assert_raises(NativeFormat::Failure) { format(arch: "x64-mingw32").platform }
  end

  def test_the_preloader_ships_beside_the_bundle
    assert_equal ["preload.so"], format.companions("lib/lota/native.so")
  end

  # The bundle and the preloader import OpenAL32.dll, by names that differ
  # in case, as Windows matches them; it imports a DLL of its own beside
  # it, and Windows' and Ruby's DLLs are not the gem's.
  def test_its_dependencies_are_the_dlls_beside_it_that_the_bundle_and_preloader_import
    in_tree do |root|
      bundle = gem(root,
        "native.so" => image(imports: %w[KERNEL32.dll x64-ucrt-ruby400.dll OpenAL32.dll]),
        "preload.so" => image(imports: %w[openal32.dll]),
        "libraries/OpenAL32.dll" => image(imports: %w[KERNEL32.dll helper.dll]),
        "libraries/helper.dll" => image(imports: %w[api-ms-win-crt-heap-l1-1-0.dll]),
        "libraries/unused.dll" => image)

      assert_equal %w[libraries/OpenAL32.dll libraries/helper.dll], format.dependencies(bundle)
      assert_empty format.escapes(bundle, root)
    end
  end

  # GCC's runtime as a DLL of its own, which the gem neither carries nor
  # may rely on Windows for, escapes it, as does a DLL the gem does not
  # carry.
  def test_a_dll_that_is_neither_the_gems_nor_windows_nor_rubys_escapes_it
    in_tree do |root|
      bundle = gem(root,
        "native.so" => image(imports: %w[KERNEL32.dll libstdc++-6.dll OpenAL32.dll]),
        "preload.so" => image(imports: %w[KERNEL32.dll]))

      assert_equal [
        "libstdc++-6.dll, which native.so imports, is neither the gem's nor Windows' nor Ruby's",
        "OpenAL32.dll, which native.so imports, is neither the gem's nor Windows' nor Ruby's",
      ], format.escapes(bundle, root)
    end
  end

  def test_a_bundle_without_its_preloader_escapes_the_gem
    in_tree do |root|
      bundle = gem(root, "native.so" => image(imports: %w[KERNEL32.dll]))

      assert_equal ["native.so lacks preload.so beside it"], format.escapes(bundle, root)
    end
  end

  def test_a_binary_for_another_machine_escapes_the_gem
    in_tree do |root|
      bundle = gem(root, "native.so" => image, "preload.so" => image(machine: ARM64))

      assert_equal ["preload.so is for machine 0xaa64"], format.escapes(bundle, root)
      assert_empty format(arch: "aarch64-mingw-ucrt").escapes(gem(root, "native.so" => image(machine: ARM64)), root)
    end
  end

  # Debugging information, in a section whose long name is in the string
  # table, and a directory of the machine that built it, in either
  # separator and any case, each escape the gem.
  def test_a_binary_that_keeps_debugging_information_or_names_this_machine_escapes_the_gem
    in_tree do |root|
      bundle = gem(root,
        "native.so" => image(sections: %w[.debug_info .rdata_long_name], strings: "D:\\A\\Lota\\Lota\\tmp\\src\0"),
        "preload.so" => image(strings: "C:/msys64/ucrt64/include\0"))

      assert_equal [
        "native.so keeps its debugging information (.debug_info)",
        "native.so names D:/a/Lota/Lota, a directory of the machine that built it",
        "preload.so names C:/msys64/ucrt64, a directory of the machine that built it",
      ], format(machine: %w[D:/a/Lota/Lota C:/msys64/ucrt64 E:/elsewhere]).escapes(bundle, root)
    end
  end

  # The guard's report names each module with Windows' separators; the
  # modules of Windows and of Ruby are not the gem's.
  def test_the_modules_a_run_loaded_outside_windows_and_ruby_are_its_own
    ruby = RbConfig::CONFIG.fetch("prefix")
    output = <<~OUTPUT
      Windows: 1 source playing
      lota-package-check: mapped C:\\Windows\\System32\\KERNEL32.DLL
      lota-package-check: mapped #{ruby}/bin/x64-ucrt-ruby400.dll
      lota-package-check: mapped D:\\gems\\lota\\lib\\lota\\native.so
      lota-package-check: mapped D:\\gems\\lota\\lib\\lota\\libraries\\OpenAL32.dll
    OUTPUT

    assert_equal ["D:/gems/lota/lib/lota/native.so", "D:/gems/lota/lib/lota/libraries/OpenAL32.dll"],
      format.ours(output)
    assert_equal "Windows: 1 source playing\n", format.printed(output)
    assert_includes format.report_libraries, "Get-Process -Id"
  end
end
