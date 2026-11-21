# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Restart
    # What the process held before a game first ran, so that a game that
    # restarts in the same process starts as it did, as LÖVE's next run
    # starts with a fresh Lua state (src/love.cpp, main and runlove).
    #
    # Ruby cannot close what a game defined, so Lota takes it away: the
    # callbacks and instance variables the game set on Lota, the constants
    # and top-level methods its files defined, its global variables, and
    # the files it loaded, so that +require+ loads them again. Instance
    # variables the game added to Lota's other modules go too. What the
    # game changed elsewhere stays, as a change to a built-in class, a
    # constant it added inside another namespace, or a gem it loaded.
    # :nodoc:
    class Snapshot
      # Takes the snapshot, of everything restore puts back.
      def initialize
        @constants = { ::Object => ::Object.constants, Lota => Lota.constants }
        @methods = top_level_methods
        @callbacks = Lota.singleton_methods(false).to_h { |name| [name, Lota.method(name).unbind] }
        @variables = Lota.instance_variables.to_h { |name| [name, Lota.instance_variable_get(name)] }
        @module_variables = lota_modules.to_h { |mod| [mod, mod.instance_variables] }
        @globals = global_variables
      end

      # Takes away what the game in the folder +directory+ added since the
      # snapshot, and puts back what it changed of Lota's. A file's place is
      # its real path, as +require+ records it.
      def restore(directory)
        prefix = File.join(File.realpath(directory), "")
        restore_callbacks
        restore_variables
        remove_module_variables
        @constants.each { |namespace, names| remove_constants(namespace, names, prefix) }
        remove_methods(prefix)
        clear_globals
        $LOADED_FEATURES.reject! { |feature| feature.start_with?(prefix) }
        nil
      end

      private def top_level_methods
        ::Object.private_instance_methods(false) | ::Object.public_instance_methods(false)
      end

      # Lota's modules and classes, but Lota::Native's, the engine's, which
      # keeps its own state, and Restart's, which carries the restart.
      private def lota_modules
        found = [] #: Array[Module]
        queue = [Lota] #: Array[Module]
        while (mod = queue.shift)
          mod.constants(false).each do |name|
            next if mod.autoload?(name)

            value = mod.const_get(name, false)
            next unless value.is_a?(Module) && value.name&.start_with?("Lota::") && !found.include?(value)
            next if value.name&.start_with?("Lota::Native", "Lota::Restart")

            found << value
            queue << value
          end
        end
        found
      end

      private def restore_callbacks
        singleton = Lota.singleton_class
        Lota.singleton_methods(false).each do |name|
          original = @callbacks[name]
          singleton.remove_method(name) unless original && Lota.method(name).unbind == original
        end
        @callbacks.each do |name, original|
          singleton.define_method(name, original) unless Lota.singleton_methods(false).include?(name)
        end
      end

      private def restore_variables
        (Lota.instance_variables - @variables.keys).each { |name| Lota.remove_instance_variable(name) }
        @variables.each { |name, value| Lota.instance_variable_set(name, value) }
      end

      private def remove_module_variables
        @module_variables.each do |mod, names|
          (mod.instance_variables - names).each { |name| mod.remove_instance_variable(name) }
        end
      end

      private def remove_constants(namespace, names, prefix)
        (namespace.constants - names).each do |name|
          file, = namespace.const_source_location(name)
          namespace.__send__(:remove_const, name) if file&.start_with?(prefix)
        end
      end

      private def remove_methods(prefix)
        (top_level_methods - @methods).each do |name|
          file, = ::Object.instance_method(name).source_location
          ::Object.__send__(:remove_method, name) if file&.start_with?(prefix)
        end
      end

      private def clear_globals
        (global_variables - @globals).each do |name|
          TOPLEVEL_BINDING.eval("#{name} = nil") if name.match?(/\A\$[A-Za-z_]\w*\z/)
        end
      end
    end
  end
end
