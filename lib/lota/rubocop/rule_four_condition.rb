# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module RuboCop
  # RuboCop's cops, and Lota's among them.
  module Cop
    module Lota
      # Flags a call of a module function that rule 4 of
      # doc/contributors/design/translation.md makes return an Array,
      # used directly as a condition.
      #
      # Lua tests a function's first result: <tt>if love.mouse.getPosition()</tt>.
      # Where a function returns several values, the Ruby method returns an
      # Array of all of them, and an Array is always true, even
      # <tt>[nil, message]</tt>, so the same condition in Ruby never fails.
      # Take the first result instead, with +.first+ or by destructuring.
      #
      # The cop knows the module functions (RULE_FOUR_METHODS, generated
      # from the translation rules, which lib/lota/rubocop/rule_four_methods.rb
      # says) called on a Lota module, <tt>Lota::Mouse.position</tt>, or
      # through +lota+, <tt>lota.mouse.position</tt>. It cannot know the
      # type of any other receiver, so it never flags an instance method,
      # such as <tt>file.write(data)</tt> on a File, nor a module function
      # called through a variable.
      #
      # A condition is the test of +if+, +unless+, +while+, +until+, or the
      # ternary, an operand of +&&+ or +||+ that decides one (the left
      # operand always), and the operand of +!+.
      #
      # === Examples
      #
      #   # bad
      #   if Lota::Mouse.position
      #   puts "moved" unless lota.mouse.position
      #
      #   # good
      #   if Lota::Mouse.position.first
      #   x, y = Lota::Mouse.position
      class RuleFourCondition < Base
        # The offense's message, with the call it names.
        MSG = "%<call>s returns an Array, which is always true; test its first result."
        # The node types of loops, whose condition is a test.
        LOOPS = %i[while until while_post until_post].freeze
        # The scope of each accessor of +lota+: "mouse" for "Lota::Mouse".
        ACCESSORS = RULE_FOUR_METHODS.keys.to_h do |scope|
          [scope.delete_prefix("Lota::").gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase, scope]
        end.freeze

        # Flags +node+ when it calls a listed module function as a condition.
        def on_send(node)
          name = node.children[1].to_s
          scope = scope_of(node.receiver)
          return unless scope && RULE_FOUR_METHODS.fetch(scope, []).include?(name)
          return unless condition?(node)

          add_offense(node, message: format(MSG, call: "#{scope}.#{name}"))
        end

        # The Lota module a receiver names, or nil.
        private def scope_of(receiver)
          return unless receiver

          if receiver.const_type?
            name = receiver.const_name.delete_prefix("::")
            name if RULE_FOUR_METHODS.key?(name)
          elsif receiver.send_type? && lota?(receiver.receiver)
            ACCESSORS[receiver.children[1].to_s]
          end
        end

        private def lota?(node)
          return false unless node

          if node.const_type?
            node.const_name.delete_prefix("::") == "Lota"
          else
            node.send_type? && node.receiver.nil? && node.children[1] == :lota
          end
        end

        private def condition?(node)
          outermost = node
          while (outer = outermost.parent) && outer.begin_type? && outer.children.one?
            outermost = outer
          end
          parent = outermost.parent
          return false unless parent

          case parent.type
          when :if, *LOOPS then parent.children.first.equal?(outermost)
          when :and, :or then parent.children.first.equal?(outermost) || condition?(parent)
          when :send then parent.children[1] == :! && parent.children.first.equal?(outermost)
          else false
          end
        end
      end
    end
  end
end
