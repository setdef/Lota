# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "open3"
require_relative "../engine_sources"
require_relative "binding_list"
require_relative "cpp_types"
require_relative "port"
require_relative "rules"
require_relative "survey"

module Bindings
  # Writes Lota::Native's generated bindings: the C++ and the RBS.
  #
  # Hand-written bindings drift from LÖVE in small ways: a default
  # forgotten, an argument read as an Integer where LÖVE reads a float, a
  # check made after the engine call instead of before. The generator
  # writes each listed function from its wrap function instead (Port), one
  # C++ file per LÖVE module under ext/lota/native/generated, a header that
  # defines them all, a CMake list of the files, and their signatures in
  # sig/lota/native/generated.rbs, and the Ruby name the rules give every
  # function of LÖVE's API, for the engine's error messages
  # (lib/lota/error_message.rb). #problems compares the result with the
  # committed files, so a change to the generator, the lists, or LÖVE that
  # changes a binding fails the build until it is regenerated and
  # reviewed, as the engine's source list does (tasks/engine_sources.rb).
  class Generator
    CPP_DIR = "ext/lota/native/generated"
    RBS = "sig/lota/native/generated.rbs"
    HEADER = "#{CPP_DIR}/bindings.hpp".freeze
    SOURCES = "#{CPP_DIR}/sources.cmake".freeze
    NAMES = "lib/lota/error_message/names.rb"
    THREAD_FILE = "src/modules/thread/LuaThread.cpp"

    # Raised when the lists name a function the generator cannot bind.
    class Failure < StandardError; end

    # [root] The repository.
    # [love] The LÖVE checkout, relative to +root+.
    # [list] The BindingList.
    # [exceptions] The BindingExceptions.
    # [style] The .clang-format file the C++ is laid out by.
    # [label] Names the LÖVE commit in the generated headers.
    def initialize(root:, love:, list:, exceptions:, style:, label:)
      @root = File.expand_path(root)
      @love = File.join(@root, love)
      @list = list
      @exceptions = exceptions
      @style = File.join(@root, style)
      @label = label
    end

    # Every generated file, by path relative to the repository.
    def files
      @files ||= begin
        modules = ports.group_by { |port| port.function.module_name }.sort.to_h
        cpp = modules.to_h { |name, list| ["#{CPP_DIR}/#{name}.cpp", format(module_file(name, list))] }
        cpp.merge(HEADER => format(header(modules.keys)), SOURCES => sources(modules.keys), RBS => rbs(modules),
          NAMES => names)
      end
    end

    # Writes every generated file, and removes generated files no longer
    # generated.
    def write
      stale.each { |path| File.delete(File.join(@root, path)) }
      files.each do |path, content|
        target = File.join(@root, path)
        FileUtils.mkdir_p(File.dirname(target))
        File.write(target, content)
      end
    end

    # How the committed files differ from what the generator writes, as
    # lines for a person to read; empty when they match.
    def problems
      found = stale.map { |path| "#{path} is no longer generated; remove it" }
      files.each do |path, content|
        target = File.join(@root, path)
        next found << "#{path} does not exist; generate it" unless File.exist?(target)

        committed = File.read(target)
        next if committed == content

        found << "#{path} differs from what the generator writes:"
        found.concat(EngineSources.difference(committed, content).map { |line| "  #{line}" })
      end
      found
    end

    # The survey of LÖVE's API the bindings come from.
    def survey
      @survey ||= Survey.load(@love)
    end

    # Each listed function, ported.
    def ports
      @ports ||= begin
        check_lua
        @list.generated.map { |binding| port(binding) }
      end
    end

    # Where LÖVE replaces a C++ wrap function with Lua, a game runs the
    # Lua, so Lota ports the Lua by hand and the generator never ports the
    # C++ (ADR 001, section 7): each such function must be listed with
    # bound_from_lua, and only such a function may be.
    private def check_lua
      @list.generated.each do |binding|
        lua = survey.replaced_by_lua(binding.love_name) or next
        raise Failure, "#{binding.love_name}: #{replaced(lua)}, so Lota ports the Lua, which the generator does " \
          "not read; list it with bound_from_lua"
      end
      @list.hand_written.each do |binding|
        lua = survey.replaced_by_lua(binding.love_name) or next
        raise Failure, "#{binding.love_name}: #{replaced(lua)}; list it with bound_from_lua, which says so"
      end
      @list.from_lua.each do |binding|
        next if survey.replaced_by_lua(binding.love_name)

        raise Failure, "#{binding.love_name}: no wrap_*.lua file replaces its C++; list it with generate or " \
          "bound_by_hand"
      end
    end

    # What LÖVE runs for a function whose C++ +lua+ replaces.
    def replaced(lua)
      "LÖVE runs #{lua.location} in place of its C++ #{lua.condition}"
    end

    # The Lota::Native name of a translated function: the rules' name,
    # except that a writer stays set_x and a factory new_x, because the
    # Ruby side applies rules 2, 5, and 6 (a Rice writer cannot take
    # several values), and except where binding_exceptions.rb names it.
    def native_name(entry)
      exception = @exceptions.native_for(entry.function.love_name)
      return exception.native if exception

      translation = entry.translation
      name = translation.name or raise Failure, "no rule names #{entry.function.love_name}; " \
        "settle it by a rule, or record it in binding_exceptions.rb"
      return "set_#{name.delete_suffix('=')}" if translation.rules.intersect?([5, 6])
      return "new_#{Rules.snake_case(name.delete_suffix('.new'))}" if translation.rules.include?(2)

      name
    end

    # The modules LÖVE keeps on its main thread, as its thread module
    # forbids them on every other (LuaThread.cpp, luax_module_threaderror).
    def main_thread_modules
      @main_thread_modules ||= File.read(File.join(@love, THREAD_FILE))
        .scan(/luax_preload\(L,\s*luax_module_threaderror,\s*"love\.(\w+)"\)/).flatten
    end

    private def stale
      Dir.glob("*", base: File.join(@root, CPP_DIR)).map { |name| "#{CPP_DIR}/#{name}" } - files.keys
    end

    private def port(binding)
      entry = survey[binding.love_name]
      wrap = entry.function.wrap
      main = main_thread_modules.include?(entry.function.module_name) ? Rules.module_constant(entry.function.module_name) : nil
      Port.new(entry, binding, native_name: native_name(entry), types:, module_class: wrap.instance_class,
        helpers: survey.catalog.helpers, main_thread: main, checks: survey.catalog.checks, guards: survey.catalog.guards)
    rescue Port::Unsupported => e
      raise Failure, "#{binding.love_name}: #{e.message}"
    end

    private def types
      @types ||= CppTypes.load(@love)
    end

    private def banner(comment)
      <<~TEXT.gsub(/^/, "#{comment} ").gsub(/ +$/, "")
        GENERATED by `rake bindings:generate` (tasks/bindings) from
        #{@label}. Do not edit: change ext/lota/bindings.rb,
        binding_exceptions.rb, or the generator, and regenerate.

        SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
        SPDX-License-Identifier: AGPL-3.0-or-later
      TEXT
    end

    private def module_file(name, ports)
      wrap = ports.first.function.wrap
      main = main_thread_modules.include?(name)
      <<~CPP
        #{banner('//')}
        #include "native/generated/bindings.hpp"

        #{includes(name, ports).join("\n")}

        namespace lota::native {

        namespace {

        // The names LÖVE's own code uses, unqualified, as its wrap file
        // does inside namespace #{namespace_of(wrap)}.
        using namespace love;
        using namespace #{namespace_of(wrap)};

        #{module_constant(name, ports)}#{accessor(name, instance_wrap(ports), main) if instance?(ports)}
        // SPDX-SnippetBegin
        // SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
        // SPDX-License-Identifier: Zlib
        //
        // Ported by the generator from the wrap functions cited below
        // (vendor/love/src/modules/#{name}), with each read of the Lua
        // stack made a parameter and each push the result.

        #{ports.sort_by { |port| [port.function.wrap.path, port.function.definition.line] }.map(&:definition).join("\n")}
        // SPDX-SnippetEnd

        } // namespace

        void define_generated_#{name}(const Rice::Module &native) {
        #{registrations(name, ports)}
        }

        } // namespace lota::native
      CPP
    end

    # The wrap file whose instance() macro the ports reach the module
    # through: the module's own (wrap_Sound.cpp), which a method's file
    # (wrap_Decoder.cpp) includes the same macro from.
    private def instance_wrap(ports)
      wraps = ports.map { |port| port.function.wrap }.uniq
      wraps.find { |wrap| wrap.source.raw.include?("#define instance()") } || wraps.first
    end

    private def instance?(ports)
      ports.any? { |port| port.definition.include?("instance()") }
    end

    # The Lota module's name, for errors, when the file names it.
    private def module_constant(name, ports)
      return "" unless instance?(ports) || ports.any? { |port| port.definition.include?("MODULE") }

      %(constexpr const char *MODULE = "#{Rules.module_constant(name)}";\n)
    end

    private def accessor(name, wrap, main)
      type = wrap.instance_class
      constant = wrap.source.raw[/Module::getInstance<\s*\w+\s*>\(\s*Module::(M_\w+)\s*\)/, 1]
      define = wrap.source.raw.lines.index { |line| line.include?("#define instance()") } + 1
      <<~CPP

        // The #{name} module, as LÖVE's instance() macro reaches it
        // (#{File.basename(wrap.path)}:#{define}), #{main ? 'on the main thread only (ADR 001, section 6)' : 'on any thread'}.
        #{type} *instance() {#{main ? "\n  require_main_thread(MODULE);" : ''}
          auto *instance = love::Module::getInstance<#{type}>(love::Module::#{constant});
          if (instance == nullptr) {
            throw love::Exception("%s is not open.", MODULE);
          }
          return instance;
        }
      CPP
    end

    private def registrations(name, ports)
      singleton, methods = ports.partition(&:singleton?)
      lines = []
      if singleton.any?
        lines << %(Rice::define_module_under(native, "#{name.capitalize}")#{singleton.map(&:registration).join}; )
      end
      methods.group_by { |port| port.function.type_name }.sort.each do |type, list|
        lines << %(Rice::define_class_under<#{type}>(native, "#{type}")#{list.map(&:registration).join};)
      end
      lines.join("\n")
    end

    # The headers a module's file includes: Lota's, then LÖVE's, then the
    # standard library's, each for a name the file uses.
    private def includes(name, ports)
      code = ports.map(&:definition).join("\n")
      lota = ['"native/binding.hpp"']
      lota << '"native/errors.hpp"' if code.include?("raise_enum_error")
      love = []
      love << '"common/Exception.h"' if code.include?("love::Exception") || code.include?("instance()")
      love << '"common/Module.h"' if code.include?("instance()")
      love << '"common/Color.h"' if code.match?(/\bColor[fD]?\b|\bColorT\b/)
      love << '"common/int.h"' if code.match?(/\bLOVE_U?INT\d+_(?:MAX|MIN)\b|\bu?int(?:8|16|32|64)\b/)
      love << '"common/math.h"' if code.match?(/\bF?Rect\b/)
      love.concat(declaring_headers(name, code))
      # The module's class only where a port reaches it through instance().
      classes = ports.filter_map do |port|
        type = port.function.wrap.instance_class
        type if port.definition.include?("instance()") || (type && port.definition.match?(/\b#{type}::/))
      end +
        ports.filter_map { |port| port.self_parameter&.fetch(:type) } +
        ports.flat_map { |port| port.parameters.compact.filter_map(&:object) } +
        ports.flat_map(&:result_classes)
      wrap_dir = File.dirname(ports.first.function.wrap.path)
      classes.uniq.each { |type| love << %("#{header_of(name, type, wrap_dir)}") }
      std = []
      std << "<algorithm>" if code.match?(/\bstd::(?:min|max)\b/)
      std << "<array>" if code.include?("std::array")
      std << "<cstddef>" if code.match?(/\bsize_t\b/)
      std << "<limits>" if code.include?("std::numeric_limits")
      std << "<optional>" if code.include?("std::optional")
      std << "<string>" if code.include?("std::string")
      [lota.sort, love.uniq.sort, std.sort].reject(&:empty?).map { |group| group.map { |file| "#include #{file}" }.join("\n") }
        .join("\n\n").lines(chomp: true)
    end

    # The headers of module +name+'s own folder that declare a type or an
    # enumerator +code+ names unqualified, outside any class: w_setBlendMode's
    # BlendMode and BLENDALPHA_MULTIPLY (graphics/renderstate.h), and
    # w_setMeshCullMode's CullMode (graphics/vertex.h), whose getConstant
    # overloads are declared beside them, as clang-tidy's
    # misc-include-cleaner asks.
    private def declaring_headers(name, code)
      names = code.gsub(/\w+::\w+/, "").scan(/\b[A-Z]\w*\b/).uniq
      Dir.glob("src/modules/#{name}/*.h", base: @love).sort.filter_map do |path|
        declared = top_level_declarations(path)
        %("#{path.delete_prefix('src/modules/')}") if names.intersect?(declared)
      end
    end

    # The enums and structs +path+ declares in its namespace, not inside a
    # class, and their enumerators.
    private def top_level_declarations(path)
      @top_level_declarations ||= {}
      @top_level_declarations[path] ||= begin
        text = File.read(File.join(@love, path))
        names = []
        depth = 0
        text.scan(/\b(?:enum(?:\s+class)?|struct|class)\s+(\w+)[^;{]*\{|[{}]/m) do
          token = Regexp.last_match(0)
          if token == "}"
            depth -= 1
          else
            outside = depth.zero? || namespaces_only?(text, Regexp.last_match.begin(0), depth)
            if (type = Regexp.last_match(1)) && outside && !token.start_with?("class")
              names << type
              names.concat(enumerators(text, Regexp.last_match.end(0))) if token.start_with?("enum")
            end
            depth += 1
          end
        end
        names
      end
    end

    # Whether every brace open at +offset+ in +text+ is a namespace's.
    private def namespaces_only?(text, offset, depth)
      text[0...offset].scan(/\bnamespace\s+\w+\s*\{/).size >= depth
    end

    # The enumerators of the enum whose body starts at +offset+.
    private def enumerators(text, offset)
      body = text[offset...(text.index("}", offset))]
      body.gsub(%r{//[^\n]*|/\*.*?\*/}m, "").split(",").filter_map { |entry| entry[/\A\s*(\w+)/, 1] }
    end

    # The header that declares +type+ for module +name+'s wrap files in
    # +wrap_dir+: the one beside them (physics/box2d/Body.h, not the base
    # class's physics/Body.h), one of the module's own, or, for a class
    # every module shares, as
    # love::Data is, one in src/common, which LÖVE's sources include as
    # common/ (common/Data.h).
    private def header_of(name, type, wrap_dir)
      own = File.join(wrap_dir, "#{type}.h")
      header = "#{type}.h"
      path = (named?(own, header) ? own : nil) ||
        Dir.glob("src/modules/#{name}/**/#{header}", base: @love).select { |file| named?(file, header) }.min_by(&:length) ||
        Dir.glob("src/common/#{header}", base: @love).find { |file| named?(file, header) } ||
        declaring_header(name, type) or
        raise Failure, "no header declares #{type} in love.#{name}"
      path.delete_prefix("src/modules/").delete_prefix("src/")
    end

    # Whether +path+ exists and is named exactly +header+, which a file
    # system that ignores case does not tell apart: there, a glob for
    # common/Math.h finds common/math.h.
    private def named?(path, header)
      full = File.join(@love, path)
      File.basename(path) == header && File.exist?(full) && Dir.children(File.dirname(full)).include?(header)
    end

    # The header of love.+name+ that declares class +type+, where no
    # header is named for it, as MathModule.h declares Math.
    private def declaring_header(name, type)
      Dir.glob("src/modules/#{name}/**/*.h", base: @love).sort.find do |file|
        File.read(File.join(@love, file)).match?(/^\s*class\s+#{type}\b(?!\s*;)/)
      end
    end

    # The namespace a wrap file's code is in, by its folder: love::physics::box2d
    # for src/modules/physics/box2d, as LÖVE nests its namespaces.
    private def namespace_of(wrap)
      "love::#{File.dirname(wrap.path).delete_prefix('src/modules/').split('/').join('::')}"
    end

    private def header(modules)
      <<~CPP
        #{banner('//')}
        // Defines every generated binding (ext/lota/native/generated/*.cpp)
        // on Lota::Native. native.cpp calls define_generated after the
        // hand-written bindings, so the classes those define already exist.

        #ifndef LOTA_NATIVE_GENERATED_BINDINGS_HPP
        #define LOTA_NATIVE_GENERATED_BINDINGS_HPP

        #include "native/binding.hpp"

        namespace lota::native {

        #{modules.map { |name| "void define_generated_#{name}(const Rice::Module &native);" }.join("\n")}

        inline void define_generated(const Rice::Module &native) {
        #{modules.map { |name| "define_generated_#{name}(native);" }.join("\n")}
        }

        } // namespace lota::native

        #endif // LOTA_NATIVE_GENERATED_BINDINGS_HPP
      CPP
    end

    # The name table: each function of LÖVE's API that the rules name, in
    # LÖVE's notation, with its Ruby name, sorted by LÖVE's name, which
    # Lota::ErrorMessage looks up when a message LÖVE's C++ raises names
    # one (ADR 001, section 7). A name LÖVE defines twice, in C++ and again
    # in Lua, takes the translation Survey#[] gives it.
    def name_table
      survey.entries.group_by { |entry| entry.function.love_name }.transform_values(&:first)
        .select { |_, entry| entry.translation.name }.sort.to_h { |love_name, entry| [love_name, entry.translation.ruby_name] }
    end

    # The name table as a Ruby Hash literal, which the magic comment makes
    # deeply frozen, so every Ractor can read it (ADR 001, section 6). It is
    # assigned by its full name, outside the modules' bodies, so that the
    # table is data rather than a module 1,100 lines long. Its header is
    # laid out as rake lint:normalize_ruby lays out every Ruby file's.
    private def names
      rows = name_table.map { |love_name, ruby_name| %(  #{love_name.dump} => #{ruby_name.dump},) }
      spdx, notice = banner("#").lines.partition { |line| line.include?("SPDX-") }
      <<~RUBY
        # frozen_string_literal: true

        #--
        #{spdx.join}#++

        # shareable_constant_value: literal

        #{notice.join.delete_suffix("#\n")}
        module Lota
          module ErrorMessage
          end
        end

        # Every function of LÖVE's Lua API that ADR 001's rules name, in
        # LÖVE's notation (love.window.setMode, ImageData:getPixel), with
        # the Ruby name the rules give it (Lota::Window.set_mode,
        # Lota::Image::ImageData#pixel), from tasks/bindings/rules.rb, sorted
        # by LÖVE's name. Lota::ErrorMessage.translate looks up each function
        # a message from LÖVE's C++ names here, so the message names it as
        # Lota does.
        Lota::ErrorMessage::NAMES = {
        #{rows.join("\n")}
        }
      RUBY
    end

    private def sources(modules)
      <<~CMAKE
        #{banner('#')}
        # The generated bindings, for ext/lota/native/CMakeLists.txt.
        set(LOTA_GENERATED_SOURCES
        #{modules.map { |name| "\tgenerated/#{name}.cpp" }.join("\n")}
        )
      CMAKE
    end

    private def rbs(modules)
      body = modules.map do |name, ports|
        singleton, methods = ports.partition(&:singleton?)
        blocks = []
        blocks << rbs_block("module #{name.capitalize}", singleton) if singleton.any?
        methods.group_by { |port| port.function.type_name }.sort.each do |type, list|
          blocks << rbs_block("class #{type}", list)
        end
        blocks
      end.flatten
      "#{banner('#')}\nmodule Lota\n  module Native\n#{body.join("\n\n")}\n  end\nend\n"
    end

    private def rbs_block(opening, ports)
      "    #{opening}\n#{ports.map { |port| "      #{port.rbs}" }.join("\n\n")}\n    end"
    end

    private def format(code)
      output, error, status = Open3.capture3("clang-format", "--style=file:#{@style}", "--assume-filename=generated.cpp",
        stdin_data: code)
      raise Failure, "clang-format failed: #{error}" unless status.success?

      output
    end
  end
end
