# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../../fuse"

module Lota
  module CLI
    module Commands
      # Builds the game in a folder into an app a player runs without Ruby,
      # as a LÖVE game is fused into an executable of its own
      # (doc/contributors/design/packaging.md).
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
      #   lota fuse path/to/game --exclude server --exclude 'test/**' --exclude doc
      #   lota fuse path/to/game --out builds --sign "Developer ID Application: NAME (TEAM)"
      #   lota fuse path/to/game --sign "Developer ID Application: NAME (TEAM)" --notarize sample-profile
      #   lota fuse path/to/game --sign-command "signtool sign /fd sha256 /a %1"
      module Fuse
        # The words Fledge reads as a phone, which Lota cannot build for
        # yet (doc/contributors/design/packaging.md).
        PHONES = %w[ios android].freeze

        # The options that take a value, each with the Lota::Fuse::Options
        # member it sets.
        VALUES = {
          "--out" => :out,
          "-o" => :out,
          "--sign" => :sign,
          "--sign-command" => :sign_command,
          "--notarize" => :notarize,
          "--identifier" => :identifier,
          "--app-version" => :app_version,
          "--icon" => :icon,
        }.freeze

        # The options that may be given more than once, each with the
        # Lota::Fuse::Options member it collects.
        REPEATED = { "--exclude" => :exclude }.freeze

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
          options = {} #: Hash[Symbol, String | Array[String]]
          arguments = argv.dup
          while (argument = arguments.shift)
            name, value = argument.split("=", 2)
            if (key = VALUES[name.to_s])
              value ||= arguments.shift
              raise Lota::Fuse::Error, "#{name} needs a value" if value.nil? || value.empty?

              options[key] = value
            elsif (key = REPEATED[name.to_s])
              value ||= arguments.shift
              raise Lota::Fuse::Error, "#{name} needs a value" if value.nil? || value.empty?

              (options[key] ||= []) << value
            elsif PHONES.include?(argument)
              raise Lota::Fuse::Error, "Lota cannot build for #{argument} yet: its engine is not built for phones (doc/contributors/design/packaging.md)."
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
              --exclude PATTERN       Leave paths out of the app, in addition to
                                      .git, .bundle, vendor/bundle, and
                                      vendor/cache. PATTERN is a glob relative
                                      to the game's folder, as File.fnmatch
                                      reads it with FNM_PATHNAME, FNM_EXTGLOB,
                                      and FNM_DOTMATCH: * stays in a folder,
                                      **/ crosses folders, {a,b} picks, and *
                                      matches dotfiles. A match leaves out a
                                      folder whole, so server leaves out the
                                      folder server; end it with / to match
                                      folders only. Give it as often as you
                                      like (quote it from your shell); a
                                      pattern that matches nothing warns.
                                      conf.rb and main.rb can't be left out
              --sign IDENTITY         Sign the app with IDENTITY, as Fledge's
                                      --sign does
              --sign-command COMMAND  Sign a Windows app with COMMAND instead,
                                      as Fledge's --sign-command does: Fledge
                                      runs it through cmd.exe for each file,
                                      with the file's path in place of %1, or
                                      after COMMAND. Without either option,
                                      Fledge reads FLEDGE_SIGN_COMMAND.
                                      Windows only
              --notarize PROFILE      Have Apple notarize the macOS app that
                                      --sign signed with a Developer ID
                                      Application identity, with the
                                      credentials xcrun notarytool
                                      store-credentials PROFILE stored, as
                                      Fledge's --notarize does. Waits for
                                      Apple, usually minutes. macOS only
              --help, -h              Show this help

            #{Lota::Fuse::FLEDGE_REF_VARIABLE} names the Git tag or commit of Fledge to
            build with instead of #{Lota::Fuse::FLEDGE_REF[0, 12]}.
          USAGE
        end
      end
    end
  end
end
