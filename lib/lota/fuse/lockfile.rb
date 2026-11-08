# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  class Fuse
    # What a game's Gemfile.lock records: the platforms it locks, the gems
    # its Gemfile asks for, and each gem it locks, with its version and the
    # platform of the build it locks.
    #
    # A game that has a Gemfile was made with the versions its lockfile
    # locks, so the project Fuse writes takes the lockfile with it (Fuse
    # reads it to check it first). Bundler is not loaded to read it, since
    # Bundler's parser finds a Gemfile of its own to put a lockfile's paths
    # under; the sections Fuse reads are lines of Bundler's fixed format
    # (Bundler::LockfileParser).
    #
    # === Example
    #
    #   locked = Lota::Fuse::Lockfile.read("games/sample_game/Gemfile.lock")
    #   locked.platforms                    # => ["arm64-darwin", "x86_64-linux-gnu"]
    #   locked.versions("lota")             # => ["0.1.3"]
    #   locked.covers?("x64-mingw-ucrt")    # => false
    class Lockfile < ::Data.define(:platforms, :dependencies, :specs)
      # A gem the lockfile locks: its +name+, its +version+, and the
      # +platform+ of the build it locks, or +nil+ for a gem that is the
      # same on every platform.
      class Spec < ::Data.define(:name, :version, :platform)
        # The name of the build's <tt>.gem</tt> file, as RubyGems names it.
        #
        # === Example
        #
        #   Lota::Fuse::Lockfile::Spec.new(name: "lota", version: "0.1.3", platform: "arm64-darwin").file_name
        #   # => "lota-0.1.3-arm64-darwin.gem"
        def file_name
          "#{[name, version, platform].compact.join('-')}.gem"
        end
      end

      # A locked gem's line in a GEM, GIT, or PATH section: four spaces,
      # then its name and, in parentheses, its version and, after a hyphen,
      # its build's platform, as Bundler writes it (a gem's version holds no
      # hyphen). The lines of the gems it depends on have six spaces.
      SPEC = /^ {4}(\S+) \(([^-)]*)(?:-([^)]*))?\)$/

      # The platform a lockfile names for gems that are the same on every
      # platform.
      RUBY = "ruby"

      # Reads the lockfile at +path+.
      def self.read(path)
        parse(File.read(path))
      end

      # Reads the lockfile +text+.
      #
      # === Example
      #
      #   Lota::Fuse::Lockfile.parse("PLATFORMS\n  ruby\n\nDEPENDENCIES\n  rainbow!\n").dependencies # => ["rainbow"]
      def self.parse(text)
        specs = text.scan(SPEC).map do |name, version, platform|
          Spec.new(name: name.to_s, version: version.to_s, platform:)
        end
        new(platforms: section(text, "PLATFORMS"), dependencies: section(text, "DEPENDENCIES").map { |line| line[/\A[^\s!]+/].to_s },
          specs:)
      end

      # The lines of the section +title+ of +text+, each without the spaces
      # around it.
      def self.section(text, title)
        text[/^#{title}\n((?:  .*(?:\n|\z))*)/, 1].to_s.lines.map(&:strip)
      end

      # The versions of the gem +name+ the lockfile locks, once each.
      def versions(name)
        specs.select { |spec| spec.name == name }.map(&:version).uniq
      end

      # Whether the Gemfile asks for the gem +name+ itself.
      def depends_on?(name)
        dependencies.include?(name)
      end

      # Whether the lockfile locks gems for +platform+, a platform of
      # Fuse::PLATFORMS: whether it names that platform, in any form
      # RubyGems matches to it (Fuse.platform_name), or +ruby+, as Fledge
      # takes either.
      def covers?(platform)
        platforms.any? { |name| name == RUBY || Fuse.platform_name(name) == platform }
      end

      # The platforms the lockfile names that are neither +platform+ nor
      # +ruby+.
      def other_platforms(platform)
        platforms.reject { |name| name == RUBY || Fuse.platform_name(name) == platform }
      end

      # The <tt>.gem</tt> file names of the builds the lockfile locks for
      # platforms other than +platform+.
      def other_builds(platform)
        specs.filter_map do |spec|
          build = spec.platform
          spec.file_name if build && Fuse.platform_name(build) != platform
        end
      end
    end
  end
end
