# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
  # SPDX-License-Identifier: Zlib

  # What the engine says about itself, translated from the functions and
  # fields LÖVE's own module puts on its table (love.getVersion,
  # love.isVersionCompatible, love.setDeprecationOutput,
  # love.hasDeprecationOutput, and the fields love._version and its kin;
  # vendor/love/src/modules/love/love.cpp:300-352 and 499-510, and 543-614).
  #
  # A library written for one version of the engine needs to know which it
  # is running on, and a game that prints its own diagnostics may not want
  # the engine's notices about deprecated names among them.
  #
  # Lota extends itself with this module, so these are methods of Lota, as
  # the table of LÖVE's functions is love itself.
  #
  # === Examples
  #
  #   major, minor, revision, codename = Lota.version # => [12, 0, 0, "Bestest Friend"]
  #   Lota.version_compatible?(12, 0)                 # => true
  #   Lota.deprecation_output = false
  module Info
    # The engine's version, as an Array of its major, minor, and revision
    # numbers and its codename (ADR 001, rule 4), matching love.getVersion
    # (love.cpp, w_love_getVersion).
    #
    # This is the version of the engine Lota builds, not of Lota itself,
    # which is Lota::VERSION.
    #
    # === Example
    #
    #   major, minor, revision, codename = Lota.version
    def version
      [_version_major, _version_minor, _version_revision, _version_codename]
    end

    # Whether the engine can run a game made for a version, matching
    # love.isVersionCompatible (love.cpp, w_love_isVersionCompatible).
    #
    # [major] Integer, or a String such as <tt>"12.0"</tt> or
    #   <tt>"12.0.0"</tt>, which gains <tt>".0"</tt> when it has fewer than
    #   two dots.
    # [minor] Integer, required when +major+ is not a String.
    # [revision] Integer, 0 by default.
    #
    # A version is compatible when it is one of the versions the engine
    # lists as compatible (#_version_compat). Raises TypeError for a
    # missing or non-numeric minor.
    #
    # === Examples
    #
    #   Lota.version_compatible?("12.0") # => true
    #   Lota.version_compatible?(11, 4)  # => false
    def version_compatible?(major, minor = nil, revision = 0)
      version = if major.is_a?(String)
        written(major)
      else
        raise TypeError, "wrong argument type #{minor.class} (expected Integer)" unless minor.is_a?(Numeric)

        "#{Integer(major)}.#{Integer(minor)}.#{Integer(revision)}"
      end
      _version_compat.any? { |compatible| written(compatible) == version }
    end

    # Turns the notices about deprecated names on or off, matching
    # love.setDeprecationOutput (love.cpp, w_love_setDeprecationOutput).
    # They are on unless the game is fused. Turning them on prints the
    # notice of each name used once so far.
    #
    # [enable] +true+ or +false+; raises TypeError for anything else.
    #
    # === Example
    #
    #   Lota.deprecation_output = false
    def deprecation_output=(enable)
      raise TypeError, "wrong argument type #{enable.class} (expected true or false)" unless [true, false].include?(enable)

      Deprecation.output = enable
    end

    # Whether the notices about deprecated names are printed, matching
    # love.hasDeprecationOutput (love.cpp, w_love_hasDeprecationOutput).
    #
    # === Example
    #
    #   Lota.deprecation_output? # => true
    def deprecation_output?
      Deprecation.output?
    end

    # The engine's version as a String, matching love._version.
    #
    # === Example
    #
    #   Lota._version # => "12.0"
    def _version
      Native::VERSION
    end

    # The engine's major version number, an Integer, matching
    # love._version_major.
    def _version_major
      Native::VERSION_MAJOR
    end

    # The engine's minor version number, an Integer, matching
    # love._version_minor.
    def _version_minor
      Native::VERSION_MINOR
    end

    # The engine's revision number, an Integer, matching
    # love._version_revision.
    def _version_revision
      Native::VERSION_REVISION
    end

    # The engine's codename, a String, matching love._version_codename.
    def _version_codename
      Native::VERSION_CODENAME
    end

    # The versions a game may name without the engine warning that it may
    # not be compatible, an Array of Strings, matching
    # love._version_compat.
    #
    # === Example
    #
    #   Lota._version_compat # => ["12.0"]
    def _version_compat
      Native::VERSION_COMPATIBILITY
    end

    # The name of the operating system, matching love._os, which is
    # Lota::System.os.
    #
    # === Example
    #
    #   Lota._os # => "OS X"
    def _os
      Native::System.os
    end

    # +version+ with <tt>".0"</tt> appended when it has fewer than two dots
    # (love.cpp:317-319 and 339-341).
    private def written(version)
      (version.count(".") < 2) ? "#{version}.0" : version
    end
  end
  # SPDX-SnippetEnd

  extend Info
end
