# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "socket"

# rake test:unit installs this before any test loads, so a unit test that
# reaches past Ruby fails at once and says why, rather than make the tier
# slow or need a build. A unit test takes milliseconds: it loads no native
# extension, starts no process, opens no socket, and never sleeps. A test
# that needs any of them is an integration test, which rake test runs
# (UNIT_TESTS in tasks/test.rake says which files are which).
module UnitGuard
  # What a unit test did that it may not.
  class Reached < StandardError; end

  # The extensions a unit test may not load: Lota's engine and the native
  # suite's test extension.
  NATIVE = %r{(?:\A|/)(?:lota/native|lota_native_test)(?:\.\w+)?\z}

  def self.refuse(what)
    raise Reached, "a unit test may not #{what}; make it an integration test (UNIT_TESTS in tasks/test.rake)"
  end

  # Kernel's methods that load an extension, start a process, or sleep.
  module Kernel
    def require(feature)
      UnitGuard.refuse("load the native extension (#{feature})") if feature.to_s.match?(NATIVE)
      super
    end

    def system(*) = UnitGuard.refuse("start a process (system)")
    def spawn(*) = UnitGuard.refuse("start a process (spawn)")
    def exec(*) = UnitGuard.refuse("start a process (exec)")
    def fork(*) = UnitGuard.refuse("start a process (fork)")
    def `(*) = UnitGuard.refuse("start a process (`)")
    def sleep(*) = UnitGuard.refuse("sleep")
  end

  # The same, called on Process, as Open3 calls Process.spawn.
  module Process
    def spawn(*) = UnitGuard.refuse("start a process (Process.spawn)")
    def fork(*) = UnitGuard.refuse("start a process (Process.fork)")
    def exec(*) = UnitGuard.refuse("start a process (Process.exec)")
  end

  # IO.popen starts a process.
  module IO
    def popen(*) = UnitGuard.refuse("start a process (IO.popen)")
  end

  # A socket reaches the network, even one on this machine.
  module Socket
    def new(*) = UnitGuard.refuse("open a socket (#{name}.new)")
    def open(*) = UnitGuard.refuse("open a socket (#{name}.open)")
  end

  # The socket classes this Ruby has; Windows' may lack the UNIX ones.
  SOCKETS = %i[TCPSocket TCPServer UDPSocket UNIXSocket UNIXServer Socket]
    .filter_map { |name| Object.const_get(name) if Object.const_defined?(name) }.freeze

  # Puts the guard on every object in this process, for good.
  def self.install
    ::Kernel.prepend(Kernel)
    ::Kernel.singleton_class.prepend(Kernel)
    ::Process.singleton_class.prepend(Process)
    ::IO.singleton_class.prepend(IO)
    SOCKETS.each { |socket| socket.singleton_class.prepend(Socket) }
    @installed = true
  end

  def self.installed? = @installed || false
end
