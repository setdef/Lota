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
# bundle loads. NativeGem gives the gem the repository's REUSE.toml with
# one more annotation for the bundle and one for each framework, which
# #annotations writes from the record.
#
# The record stays complete because the build checks it. A framework the
# bundle loads must have an entry (#framework_for), and so must every
# file the bundle was compiled from (#bundled), which LinkedFiles reads
# from the linker's map and ninja's dependency log.
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
  class Work < Data.define(:name, :sources, :gem, :copyright, :license, :pending)
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
  def work(name, sources:, copyright:, license: [], pending: nil, gem: nil)
    @works << checked(Work.new(name:, sources:, gem:, copyright:, license:, pending:))
  end

  # Records a framework the gem ships, by its directory's name.
  def framework(name, copyright:, license:, pending: nil)
    @frameworks[name] = checked(Work.new(name:, sources: [], gem: nil, copyright:, license:, pending:))
  end

  # The entry for the framework +name+ (SDL3.framework).
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
  # which ships the frameworks named +frameworks+ in +framework_dir+, all
  # paths relative to the gem.
  def annotations(bundle:, works:, framework_dir:, frameworks:)
    tables = [annotation(bundle, works)]
    tables += frameworks.map { |name| annotation("#{framework_dir}/#{name}/**", [framework_for(name)]) }
    tables.join("\n")
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
# (ld -map) lists, and what ninja's dependency log says each was compiled
# from.
#
# An object from a static archive appears in the map by its file name
# alone, as libengine.a(Data.cpp.o), so it is matched with the objects
# ninja built for that archive's target by name; where several share a
# name, all of them count, since any could be the one the linker took.
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
  # the ninja build at +build+.
  def self.read(map:, build:)
    raise Failure, "#{map} does not exist; rake compile writes it beside the bundle" unless File.file?(map)

    deps, status = Open3.capture2e("ninja", "-C", build, "-t", "deps")
    raise Failure, "ninja -t deps failed in #{build}:\n#{deps}" unless status.success?

    parse(File.binread(map), deps, build:)
  end

  # The files from the map's text and ninja -t deps's output, in +build+.
  def self.parse(map, deps, build:)
    objects = objects(deps, build)
    linked = linked(map).flat_map { |entry| members(entry, objects, build) }
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
    section = map.b[/^# Object files:\n(.*?)^# Sections:/m, 1] or raise Failure, "the linker map lists no object files"
    section.lines.filter_map { |line| line[/\A\[\s*\d+\]\s+(.+\.o\)?)$/, 1]&.force_encoding(Encoding::UTF_8) }
  end

  # The objects ninja built that +entry+ names: itself, or, for an
  # archive's member, each object of the archive's target with its name.
  # An object ninja did not build stands for itself, by absolute path.
  private_class_method def self.members(entry, objects, build)
    return [entry] if objects.key?(entry)

    archive, member = entry.match(/\A(.+)\((.+)\)\z/)&.captures
    return [File.expand_path(entry, build)] unless archive

    target = "#{File.dirname(archive)}/CMakeFiles/#{File.basename(archive, '.a').delete_prefix('lib')}.dir/"
    found = objects.keys.select { |object| object.start_with?(target) && File.basename(object) == member }
    found.empty? ? [File.expand_path(archive, build)] : found
  end

  # The source +object+ was compiled from: what it read whose name is its
  # own without .o.
  private_class_method def self.source(object, objects)
    objects.fetch(object, []).find { |input| File.basename(input) == File.basename(object, ".o") }
  end
end
