# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "open3"

# Who wrote what Lota's precompiled gem carries, and under which licenses,
# as ext/lota/licenses.rb records it, written out as the REUSE
# Specification 3.3 asks.
#
# The repository is a REUSE project, and so is the precompiled gem, but
# the gem carries more: the compiled bundle, which holds LÖVE's engine,
# the libraries LÖVE bundles, and Rice's headers, and the frameworks the
# bundle loads, or on Linux its shared libraries. NativeGem gives the gem
# the repository's REUSE.toml with one more annotation for the bundle and
# one for each framework or library, which #annotations writes from the
# record.
#
# The record stays complete because the build checks it. A framework or
# library the bundle loads must have an entry (#framework_for), and so
# must every file the bundle was compiled from (#bundled), which
# LinkedFiles reads from the linker's map and ninja's dependency log.
class Licensing
  # Code the bundle compiles in, or a framework the gem ships.
  #
  # [name] What the work is called.
  # [sources] Globs of its files, relative to the repository, or to the
  #   installed +gem+; a glob ending in /** covers everything under it.
  #   A framework has none: it is matched by name.
  # [gem] The gem whose files +sources+ name (Rice), or nil.
  # [copyright] Its notices of copyright, from its own files; none only
  #   while +pending+.
  # [license] The SPDX license expressions it is under.
  # [pending] What about its licensing the maintainer has yet to decide,
  #   or nil. Its license is left out of the gem until then.
  # [source] The Source archive of a framework's code, or nil.
  # [title] What an app's notices call it, where that is not +name+, or
  #   nil: a record names the same library on several platforms apart, as
  #   "zlib (Windows)", which the notices call zlib.
  # [version] Its version, or nil where the record does not know it.
  # [credit] The words its license asks a product's documentation to
  #   carry, which an app's notices carry, or nil.
  class Work < Data.define(:name, :sources, :gem, :copyright, :license, :pending, :source, :title, :version, :credit)
    def initialize(source: nil, title: nil, version: nil, credit: nil, **)
      super
    end

    # What an app's notices call it.
    def notice_name
      title || name
    end

    # Its version, or the version of the gem it comes from.
    def notice_version
      version || (gem && Gem::Specification.find_by_name(gem).version.to_s)
    end

    # Whether +path+, absolute, is one of this work's files, in the
    # repository at +root+.
    def covers?(path, root)
      base = gem ? Gem::Specification.find_by_name(gem).full_gem_path : root
      sources.any? do |glob|
        pattern = File.join(base, glob.end_with?("/**") ? "#{glob}/*" : glob)
        File.fnmatch?(pattern, path, File::FNM_PATHNAME)
      end
    end
  end

  # The archive of the source code a framework was built from, which the
  # gem carries beside it.
  #
  # [url] Where its release is published.
  # [sha256] Its SHA-256, as hexadecimal.
  # [path] Where rake sources:fetch keeps it, relative to the repository.
  # [copyright] Its notices of copyright, every one its files hold.
  # [license] The SPDX license expressions of everything in it.
  class Source < Data.define(:url, :sha256, :path, :copyright, :license)
    # The archive's file name, which it keeps in the gem's SOURCES.
    def name
      File.basename(path)
    end
  end

  # Where a gem keeps the source archives its frameworks' licenses ask
  # for, relative to the gem.
  SOURCES = "sources"

  # Raised for an entry the record cannot hold.
  class Invalid < StandardError; end

  # Raised for a framework, or a file the bundle compiled, that no entry
  # covers.
  class Unrecorded < StandardError; end

  attr_reader :works, :frameworks

  # Reads the record at +path+.
  def self.load(path)
    new(path).tap { |licensing| licensing.instance_eval(File.read(path), path) }
  end

  # [path] Where the record is, for the messages that ask to add to it.
  def initialize(path = "ext/lota/licenses.rb")
    @path = path
    @works = []
    @frameworks = {}
  end

  # Records code the bundle compiles in.
  def work(name, sources:, copyright:, license: [], pending: nil, gem: nil, title: nil, version: nil, credit: nil)
    @works << checked(Work.new(name:, sources:, gem:, copyright:, license:, pending:, title:, version:, credit:))
  end

  # Records a framework the gem ships on macOS, by its directory's name,
  # with the archive of its source when its license asks the gem to carry
  # it.
  def framework(name, copyright:, license:, pending: nil, source: nil, title: nil, version: nil, credit: nil)
    @frameworks[name] = checked(Work.new(name:, sources: [], gem: nil, copyright:, license:, pending:,
      source: source && Source.new(**source), title:, version:, credit:))
  end

  # Records a shared library the gem ships on Linux, by the soname the
  # bundle or another library needs it by, as a framework is recorded.
  def library(name, copyright:, license:, pending: nil, source: nil, title: nil, version: nil, credit: nil)
    framework(name, copyright:, license:, pending:, source:, title:, version:, credit:)
  end

  # The entry for the framework, or on Linux the library, +name+
  # (SDL3.framework, libSDL3.so.0).
  def framework_for(name)
    @frameworks.fetch(name) do
      raise Unrecorded, "#{name} has no recorded license; record its copyright and license in #{@path}"
    end
  end

  # The works the bundle carries, in the record's order, from the files
  # it was linked from (LinkedFiles). Each file goes to the first work
  # that covers it, and every file must go to one, except files under
  # +outside+, absolute paths of what is not code the bundle carries: the
  # toolchain's and Ruby's headers, and the frameworks', whose code ships
  # in the frameworks themselves. A work is carried when an object the
  # bundle took was compiled from it, or, for a work none of whose
  # sources ninja compiled, such as a header-only library, when an object
  # the bundle took read one of its files. Raises Unrecorded otherwise.
  def bundled(linked, root:, outside:)
    files = linked.files.reject { |path| outside.any? { |prefix| path.start_with?(prefix) } }
    owners = files.to_h { |path| [path, owner(path, root)] }
    unrecorded = owners.select { |_, work| work.nil? }.keys
    if unrecorded.any?
      raise Unrecorded, "the bundle compiles files no entry in #{@path} covers; record their copyright and " \
        "license there:\n#{unrecorded.sort.map { |path| "  #{path}" }.join("\n")}"
    end

    @works.select do |work|
      next false unless owners.value?(work)

      linked.sources.any? { |path| owners[path] == work } ||
        linked.compiled.none? { |path| owner(path, root) == work }
    end
  end

  # REUSE.toml's annotations for a gem whose +bundle+ carries +works+, and
  # which ships the frameworks, or libraries, +frameworks+ names, each name
  # to the path its annotation covers (NativeFormat#annotation), all paths
  # relative to the gem. Each one's source archive gets an annotation of
  # its own, at its place in SOURCES. +companions+ are the other
  # extensions the gem carries, such as Windows' preloader, each path to
  # the works it carries.
  def annotations(bundle:, works:, frameworks:, companions: {})
    tables = [annotation(bundle, works)] + companions.map { |path, carried| annotation(path, carried) }
    tables += frameworks.map { |name, path| annotation(path, [framework_for(name)]) }
    tables += sources(frameworks.keys).map do |source|
      annotation("#{SOURCES}/#{source.name}", [
Work.new(name: source.name, sources: [], gem: nil,
  copyright: source.copyright, license: source.license, pending: nil),
])
    end
    tables.join("\n")
  end

  # The record's name for Lota's own code, which an app's notices state on
  # their own, always (Lota::Notices), so its manifest leaves it out.
  LOTA = "Lota"

  # Where a gem keeps the manifest of what it carries, relative to the
  # gem, which <tt>lota fuse</tt> writes an app's notices from.
  NOTICES = "notices.json"

  # The manifest, as a Hash for JSON, of what a gem carries, for an app's
  # notices (Lota::Notices): each work +bundle+ carries, each work each of
  # +companions+ carries (each path to its works), and each framework, or
  # library, +frameworks+ names (each name to its path in the gem), with
  # its source archive, all paths relative to the gem. Each is named by
  # Work#notice_name, with Work#notice_version, its licenses, notices of
  # copyright, and credit. Lota's own work is left out (LOTA). Raises
  # Invalid for a work whose license is pending, which the notices could
  # not name.
  #
  # A phone's app, which no gem carries Lota into, can describe the works
  # its own link takes the same way, with no frameworks.
  def notices(bundle:, works:, frameworks:, companions: {})
    carried = [[bundle, works], *companions.to_a].flat_map do |path, its|
      its.reject { |work| work.name == LOTA }.map { |work| notice(work, file: path, separate: false) }
    end
    carried += frameworks.map { |name, path| notice(framework_for(name), file: path, separate: true) }
    { "components" => carried.uniq }
  end

  private def notice(work, file:, separate:)
    raise Invalid, "#{work.name}'s license is pending, so the notices cannot name it" if work.pending

    source = work.source
    {
      "name" => work.notice_name,
      "version" => work.notice_version,
      "license" => work.license,
      "copyright" => work.copyright,
      "credit" => work.credit,
      "file" => file,
      "separate" => separate,
      "source" => source && {
"file" => File.join(SOURCES, source.name),
"url" => source.url,
"sha256" => source.sha256,
"license" => source.license,
},
    }
  end

  # The source archives of the frameworks named +frameworks+, each once.
  def sources(frameworks)
    frameworks.filter_map { |name| framework_for(name).source }.uniq
  end

  # A work must record its copyright and license, unless what it lacks is
  # pending the maintainer's decision.
  private def checked(work)
    return work if work.pending

    raise Invalid, "#{work.name} records no copyright, and nothing pending" if work.copyright.empty?
    raise Invalid, "#{work.name} records no license, and nothing pending" if work.license.empty?

    work
  end

  private def owner(path, root)
    @works.find { |work| work.covers?(path, root) }
  end

  private def annotation(path, works)
    pending = works.select(&:pending)
    lines = pending.any? ? ["# Licenses the maintainer has yet to decide, left out below (#{@path}):"] : []
    lines += pending.map { |work| "#   #{work.name}: #{work.pending}" }
    lines << "[[annotations]]"
    lines << "path = #{toml(path)}"
    lines << "SPDX-FileCopyrightText = #{toml_list(works.flat_map(&:copyright).uniq)}"
    lines << "SPDX-License-Identifier = #{toml_list(works.flat_map(&:license).uniq)}"
    "#{lines.join("\n")}\n"
  end

  private def toml_list(values)
    "[\n#{values.map { |value| "  #{toml(value)},\n" }.join}]"
  end

  # A TOML basic string.
  private def toml(value)
    %("#{value.gsub('\\', '\\\\\\\\').gsub('"', '\\"')}")
  end
end

# The files a bundle was linked from: each object file the linker's map
# lists, and what ninja's dependency log says each was compiled from. The
# map is Apple's linker's (ld -map) on macOS, GNU ld's (-Map) on Linux and
# with MinGW's GCC, whose "Archive member included" section names each
# member it took from an archive and whose LOAD lines name every other
# input, and the one link.exe's /map writes with MinGW's clang, which LLD
# writes too (lld/COFF/MapFile.cpp): each symbol with the file that
# defined it, an archive's member as the archive's name without its
# extension, a colon, and the member's name, and every other object by its
# file name alone.
#
# An object from a static archive appears in the map by its file name
# alone, as libengine.a(Data.cpp.o), so it is matched with the objects
# ninja built for that archive's target by name; where several share a
# name, all of them count, since any could be the one the linker took.
# Where the map names an archive, or an object ninja did not build, by its
# file name without a directory, as link.exe's map does, it is the first
# of that name in +libraries+, the directories the linker searched.
#
# [files] Every source and header the linked objects read, and every
#   linked object ninja did not build (a toolchain runtime's), as absolute
#   paths.
# [sources] The source each linked object was compiled from.
# [compiled] The source of every object ninja built.
class LinkedFiles < Data.define(:files, :sources, :compiled)
  # Raised when the map or the dependency log cannot be read.
  class Failure < StandardError; end

  # The files the bundle whose linker map is at +map+ was linked from, in
  # the ninja build at +build+, whose linker searched the directories
  # +libraries+.
  def self.read(map:, build:, libraries: [])
    raise Failure, "#{map} does not exist; rake compile writes it beside the bundle" unless File.file?(map)

    deps, status = Open3.capture2e("ninja", "-C", build, "-t", "deps")
    raise Failure, "ninja -t deps failed in #{build}:\n#{deps}" unless status.success?

    parse(File.binread(map), deps, build:, libraries:)
  end

  # The files from the map's text and ninja -t deps's output, in +build+,
  # whose linker searched +libraries+. Windows' \ separators read as /, and
  # its \r\n line endings, with which GNU ld writes its map there, as \n.
  def self.parse(map, deps, build:, libraries: [])
    objects = objects(deps.delete("\r").tr("\\", "/"), build)
    linked = linked(map.b.delete("\r").tr("\\", "/")).flat_map { |entry| members(entry, objects, build, libraries) }
    files = linked.flat_map { |object| objects.fetch(object, [object]) }.uniq
    new(files:, sources: linked.filter_map { |object| source(object, objects) }.uniq,
      compiled: objects.keys.filter_map { |object| source(object, objects) }.uniq)
  end

  # Each object ninja built, relative to +build+, to the absolute paths of
  # what it read.
  private_class_method def self.objects(deps, build)
    objects = {}
    current = nil
    deps.each_line do |line|
      if (object = line[/\A(\S.*?): #deps/, 1])
        current = objects[object] = []
      elsif current && (input = line[/\A\s+(\S.*)$/, 1])
        current << File.expand_path(input, build)
      end
    end
    objects
  end

  # The map's object files, as it names them.
  private_class_method def self.linked(map)
    map = map.b
    return link_linked(map) if map.match?(LINK_PUBLICS)
    return gnu_linked(map) unless map.start_with?("# Path: ")

    section = map[/^# Object files:\n(.*?)^# Sections:/m, 1] or raise Failure, "the linker map lists no object files"
    section.lines.filter_map { |line| line[/\A\[\s*\d+\]\s+(.+\.o\)?)$/, 1]&.force_encoding(Encoding::UTF_8) }
  end

  # The headings of the sections GNU ld's map has after the archive
  # members it took (ld/ldlang.c and ldmain.c in GNU binutils).
  GNU_SECTIONS = Regexp.union("Allocating common symbols", "Discarded input sections", "Memory Configuration",
    "Linker script and memory map")

  # The object files in GNU ld's map: each archive member it took, from
  # the section that says why it took it, where a member starts a line,
  # and each object it loaded whole, from the LOAD lines, which also name
  # the archives and shared libraries it searched. With MinGW, an object
  # CMake built ends in .obj, and one of GCC's own runtime in .o.
  private_class_method def self.gnu_linked(map)
    loaded = map.scan(/^LOAD (.+\.o(?:bj)?)$/).flatten
    raise Failure, "the linker map lists no object files" if loaded.empty?

    members = map[/^Archive member included to satisfy reference by file \(symbol\)\n(.*?)^#{GNU_SECTIONS}$/m, 1].to_s
    (loaded + members.scan(/^(\S+\.o(?:bj)?\))/).flatten).map { |entry| entry.force_encoding(Encoding::UTF_8) }
  end

  # The heading of the public symbols in a map in link.exe's form.
  LINK_PUBLICS = /^\s*Address\s+Publics by Value\s+Rva\+Base\s+Lib:Object$/

  # The object files in a map in link.exe's form: the file of each symbol,
  # public or static, once each, with an archive's member written as GNU
  # ld writes it, archive.a(member). A symbol the linker made has none, or
  # a name in angle brackets, as <linker-defined>.
  private_class_method def self.link_linked(map)
    files = map.scan(/^\s*\h{4}:\h{8}\s+\S+\s+\h{16}\s+(?:[fi]\s+)?([^<\s]\S*)$/).flatten.uniq
    raise Failure, "the linker map lists no object files" if files.empty?

    files.map do |file|
      archive, member = file.split(":", 2)
      (member ? "#{archive}.a(#{member})" : file).force_encoding(Encoding::UTF_8)
    end
  end

  # The objects ninja built that +entry+ names: itself, or, for an
  # archive's member, each object of the archive's target with its name.
  # An object named without a directory is each object ninja built of that
  # name. Anything else stands for itself, by absolute path (#path).
  private_class_method def self.members(entry, objects, build, libraries)
    return [entry] if objects.key?(entry)

    archive, member = entry.match(/\A(.+)\((.+)\)\z/)&.captures
    unless archive
      found = entry.include?("/") ? [] : objects.keys.select { |object| File.basename(object) == entry }
      return found.empty? ? [path(entry, build, libraries)] : found
    end

    found = objects.keys.select { |object| File.basename(object) == member && built_into?(object, archive) }
    found.empty? ? [path(archive, build, libraries)] : found
  end

  # Whether ninja built +object+ for the target whose archive is +archive+:
  # in that target's directory, beside the archive, or anywhere when the
  # map names the archive without its directory.
  private_class_method def self.built_into?(object, archive)
    target = "CMakeFiles/#{File.basename(archive, '.a').delete_prefix('lib')}.dir/"
    archive.include?("/") ? object.start_with?("#{File.dirname(archive)}/#{target}") : object.include?(target)
  end

  # The absolute path of +file+, as the map names it: in +build+, or, for a
  # name without a directory, the first file of that name in +libraries+.
  private_class_method def self.path(file, build, libraries)
    found = libraries.map { |dir| File.join(dir, file) }.find { |candidate| File.file?(candidate) } unless
      file.include?("/")
    found || File.expand_path(file, build)
  end

  # The source +object+ was compiled from: what it read whose name is its
  # own without .o, or .obj.
  private_class_method def self.source(object, objects)
    name = File.basename(object).sub(/\.o(?:bj)?\z/, "")
    objects.fetch(object, []).find { |input| File.basename(input) == name }
  end
end
