# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# For tests that define a game's callbacks, which are methods on Lota
# (ADR 003, section 2), and so outlive the test that defines them.
#
# Before each test it takes away the callbacks a game defined, such as the
# Lota.conf that test/lovetest/conf.rb defines once EngineHelper boots,
# and after each test it puts Lota's singleton methods back as they were,
# Lota's own Lota.run among them.
module CallbackHelper
  LIB = File.expand_path("../lib", __dir__)

  def setup
    super
    @lota_methods = Lota.singleton_methods(false).to_h { |name| [name, Lota.singleton_class.instance_method(name)] }
    @lota_methods.each { |name, method| Lota.singleton_class.remove_method(name) unless lota_own?(method) }
  end

  def teardown
    Lota.singleton_methods(false).each do |name|
      Lota.singleton_class.remove_method(name) unless Lota.singleton_class.instance_method(name) == @lota_methods[name]
    end
    @lota_methods.each do |name, method|
      Lota.singleton_class.define_method(name, method) unless Lota.singleton_methods(false).include?(name)
    end
    super
  end

  # Defines the callback +name+ on Lota, as <tt>def Lota.name</tt> does,
  # replacing one Lota defines itself without a warning.
  def define_callback(name, &body)
    Lota.singleton_class.remove_method(name) if Lota.singleton_methods(false).include?(name)
    Lota.define_singleton_method(name, &body)
  end

  private def lota_own?(method)
    method.source_location&.first&.start_with?(LIB)
  end
end
