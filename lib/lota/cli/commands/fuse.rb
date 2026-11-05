# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../../fuse"

module Lota
  module CLI
    module Commands
      # Builds the game in a folder into an app a player runs without Ruby,
      # as a LÖVE game is fused into an executable of its own (ADR 002,
      # section 5).
      #
      # A player has no Ruby and no Lota, and should not need either. This
      # command hands the game to Fledge with Lota::Fuse, prints the paths
      # of what Fledge built, and says that it built for this computer's
      # platform only: build each platform's app on that platform.
      #
      # Use it when you want someone to play your game.
      #
      # === Example
      #
      #   lota fuse
      #   lota fuse path/to/game --identifier com.example.SampleGame
      #   lota fuse path/to/game --out builds --sign "Developer ID Application: NAME (TEAM)"
      module Fuse
        # The words Fledge reads as a phone, which Lota cannot build for
        # yet (ADR 002, section 2).
        PHONES = %w[ios android].freeze

        # The options that take a value, each with the Lota::Fuse::Options
        # member it sets.
        VALUES = {
          "--out" => :out,
          "-o" => :out,
          "--sign" => :sign,
          "--identifier" => :identifier,
          "--app-version" => :app_version,
          "--icon" => :icon,
        }.freeze

        # Runs the fuse command.
        #
        # [argv] Command-line arguments: the game's folder and the options.
        def self.call(argv)
          if argv.intersect?(["--help", "-h"])
            puts usage
            exit(0)
          end

          path, options = parse(argv)
          require "lota"
          paths = Lota::Fuse.new(path, Lota::Fuse.options(**options)).call
          puts "Built #{paths.empty? ? 'nothing' : 'the app'} for #{Lota::Fuse.platform_name(Lota::Fuse.this_platform)} only. " \
            "Run lota fuse on each platform you ship for."
        rescue Lota::Fuse::Error => e
          warn "lota fuse: #{e.message}"
          exit(1)
        end

        # The game's folder and the options +argv+ gives, as
        # <tt>--name VALUE</tt> or <tt>--name=VALUE</tt>. Raises
        # Lota::Fuse::Error for an option it does not know, one with no value,
        # a phone, or more than one folder.
        def self.parse(argv) # :nodoc:
          paths = [] #: Array[String]
          options = {} #: Hash[Symbol, String]
          arguments = argv.dup
          while (argument = arguments.shift)
            name, value = argument.split("=", 2)
            if (key = VALUES[name.to_s])
              value ||= arguments.shift
              raise Lota::Fuse::Error, "#{name} needs a value" if value.nil? || value.empty?

              options[key] = value
            elsif PHONES.include?(argument)
              raise Lota::Fuse::Error, "Lota cannot build for #{argument} yet: its engine is not built for phones (ADR 002, section 2)."
            elsif argument.start_with?("-")
              raise Lota::Fuse::Error, "unrecognized option '#{argument}'\n#{usage}"
            else
              paths << argument
            end
          end
          raise Lota::Fuse::Error, "takes one game folder, but got #{paths.join(' and ')}" if paths.size > 1

          [paths.first || ".", options]
        end

        # Returns command-specific usage.
        def self.usage # :nodoc:
          <<~USAGE
            Usage: lota fuse [path] [options]

            Builds the game in path, or in the current directory, into an
            app for this computer's platform that runs without Ruby, with
            Fledge (github.com/setdef/Fledge). Build each platform's app on
            that platform. It needs Lota's gem for this platform installed,
            Git, and the network, which fetch Fledge.

            Options:
              --out DIR, -o DIR       Write the app, and the project it is built
                                      from, to DIR (default: dist)
              --identifier ID         The reverse-DNS name the system knows the
                                      app by, such as com.example.YourGame
                                      (default: com.example.IDENTITY, a
                                      placeholder: replace it before you ship)
              --app-version VERSION   The app's version, such as 1.0.0 (default:
                                      Fledge's, 0.0.0)
              --icon PATH             The app's icon files in the game's folder,
                                      without their extension, as Fledge takes
                                      them: icons/icon for icons/icon.icns,
                                      icons/icon.ico, and icons/icon-16.png to
                                      -512.png (default: none)
              --sign IDENTITY         Sign the app with IDENTITY, as Fledge's
                                      --sign does
              --help, -h              Show this help

            #{Lota::Fuse::FLEDGE_REF_VARIABLE} names the Git tag or commit of Fledge to
            build with instead of #{Lota::Fuse::FLEDGE_REF[0, 12]}.
          USAGE
        end
      end
    end
  end
end
