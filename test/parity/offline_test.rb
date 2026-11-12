# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "parity_helper"
require "socket"

# No run of either engine reaches a network. A game may ask one, as
# FLASH-BLIP asks a server on the local network for a newer version at
# every start, so every run loads the harness's libraries
# (Parity.loopback), whose liblota_offline refuses each connection to an
# Internet address, at once, as a server that is there and refuses it
# would (ext/lota/native_test/offline.cpp): LuaSocket in the reference
# love and Net::HTTP in Lota then both say the connection was refused,
# whatever the network the machine is on, and nothing leaves the process.
class OfflineTest < Minitest::Test
  # A program, run as each engine is run, that connects to +port+ on the
  # loopback address, where this test listens, and to a name the network
  # would look up, and prints what each did.
  def run_connecting(port)
    script = <<~RUBY
      require "socket"
      [["127.0.0.1", #{port}], ["example.com", 80]].each do |host, port|
        TCPSocket.new(host, port).close
        puts "\#{host} connected"
      rescue SystemCallError, SocketError => e
        puts "\#{host} \#{e.class}"
      end
    RUBY
    Dir.mktmpdir("lota-offline-") do |dir|
      environment = Parity.loopback(File.join(dir, "audio.f32"))
      Parity.run(environment, RbConfig.ruby, "-e", script, side: "Lota") { 1 }
    end
  end

  def test_a_run_reaches_no_network
    server = TCPServer.new("127.0.0.1", 0)
    output = run_connecting(server.addr[1])

    assert_predicate output.status, :success?, output.text
    assert_equal "127.0.0.1 Errno::ECONNREFUSED\nexample.com Socket::ResolutionError\n", output.text
    assert_equal :wait_readable, server.accept_nonblock(exception: false), "the run connected"
  ensure
    server&.close
  end
end
