# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/licensing"
require_relative "../../tasks/source_archive"
require "digest"
require "socket"
require "stringio"

# SourceArchive fetches a framework's source archive once, over HTTP from
# a server of the test's own, and the gem build checks it every time.
class SourceArchiveTest < Minitest::Test
  include TreeHelper

  CONTENTS = "the release's archive"

  # A server on this machine that answers +responses+, one per request,
  # each the HTTP response text, and the port it listens on.
  def serve(*responses)
    server = TCPServer.new("127.0.0.1", 0)
    thread = Thread.new do
      responses.each do |response|
        client = server.accept
        while (line = client.gets) && line != "\r\n"; end
        client.write(response)
        client.close
      end
    end
    yield server.addr[1]
  ensure
    thread&.join(5)
    server&.close
  end

  def ok(body)
    "HTTP/1.1 200 OK\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}"
  end

  def source(url, sha256: Digest::SHA256.hexdigest(CONTENTS))
    Licensing::Source.new(url:, sha256:, path: "vendor/sources/x-1.0.tar.bz2", copyright: [], license: [])
  end

  def test_fetch_downloads_the_archive_following_a_redirect_and_keeps_it_when_its_sha256_matches
    in_tree do |root|
      serve("HTTP/1.1 302 Found\r\nLocation: /mirror/x-1.0.tar.bz2\r\nContent-Length: 0\r\n\r\n", ok(CONTENTS)) do |port|
        archive = SourceArchive.new(source("http://127.0.0.1:#{port}/x-1.0.tar.bz2"), root:)
        archive.fetch

        assert_equal CONTENTS, File.read(archive.path)
        archive.verify!
      end
    end
  end

  def test_fetch_keeps_nothing_whose_sha256_is_not_the_one_recorded
    in_tree do |root|
      serve(ok("something else")) do |port|
        archive = SourceArchive.new(source("http://127.0.0.1:#{port}/x-1.0.tar.bz2"), root:)
        error = assert_raises(SourceArchive::Failure) { archive.fetch }

        assert_includes error.message, "has SHA-256 #{Digest::SHA256.hexdigest('something else')}"
        refute File.exist?(archive.path)
        assert_empty Dir.glob(File.join(root, "vendor/sources/*"))
      end
    end
  end

  def test_an_archive_already_fetched_is_not_fetched_again
    in_tree do |root|
      write(root, "vendor/sources/x-1.0.tar.bz2", CONTENTS)

      archive = SourceArchive.new(source("http://127.0.0.1:1/unreachable"), root:)
      archive.fetch

      assert_equal CONTENTS, File.read(archive.path)
    end
  end

  def test_verify_fails_on_an_archive_missing_or_not_the_one_recorded
    in_tree do |root|
      archive = SourceArchive.new(source("http://example.com/x"), root:)
      missing = assert_raises(SourceArchive::Failure) { archive.verify! }
      write(root, "vendor/sources/x-1.0.tar.bz2", "changed")
      changed = assert_raises(SourceArchive::Failure) { archive.verify! }

      assert_equal "vendor/sources/x-1.0.tar.bz2 is missing; run bundle exec rake sources:fetch", missing.message
      assert_includes changed.message, "has SHA-256 #{Digest::SHA256.hexdigest('changed')}"
    end
  end

  def recorder
    waits = []
    [waits, -> (seconds) { waits << seconds }]
  end

  def unavailable
    "HTTP/1.1 503 Service Unavailable\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
  end

  def test_fetch_tries_again_after_a_host_answers_5xx
    in_tree do |root|
      serve(unavailable, unavailable, ok(CONTENTS)) do |port|
        waits, pause = recorder
        out = StringIO.new
        archive = SourceArchive.new(source("http://127.0.0.1:#{port}/x-1.0.tar.bz2"), root:, out:, pause:)
        archive.fetch

        archive.verify!
        assert_equal SourceArchive::BACKOFF.first(2), waits
        assert_includes out.string, "Retrying http://127.0.0.1:#{port}/x-1.0.tar.bz2 in 2 seconds (1 of 3): " \
          "SourceArchive::Transient: http://127.0.0.1:#{port}/x-1.0.tar.bz2 answered 503"
      end
    end
  end

  def test_fetch_gives_up_after_the_waits_and_says_what_it_tried
    in_tree do |root|
      responses = Array.new(SourceArchive::BACKOFF.size + 1) { unavailable }
      serve(*responses) do |port|
        waits, pause = recorder
        archive = SourceArchive.new(source("http://127.0.0.1:#{port}/x-1.0.tar.bz2"), root:, out: StringIO.new, pause:)
        error = assert_raises(SourceArchive::Failure) { archive.fetch }

        assert_equal SourceArchive::BACKOFF, waits
        assert_includes error.message, "did not download in 4 tries, waiting 2, 5, 15 seconds between them"
        assert_equal 4, error.message.scan("answered 503 Service Unavailable").size
        refute File.exist?("#{archive.path}.part")
      end
    end
  end

  def test_fetch_does_not_try_again_after_a_404
    in_tree do |root|
      serve("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n") do |port|
        waits, pause = recorder
        archive = SourceArchive.new(source("http://127.0.0.1:#{port}/x-1.0.tar.bz2"), root:, out: StringIO.new, pause:)
        error = assert_raises(SourceArchive::Failure) { archive.fetch }

        assert_empty waits
        assert_includes error.message, "answered 404 Not Found"
      end
    end
  end

  def test_fetch_does_not_try_again_after_the_wrong_archive
    in_tree do |root|
      serve(ok("something else")) do |port|
        waits, pause = recorder
        archive = SourceArchive.new(source("http://127.0.0.1:#{port}/x-1.0.tar.bz2"), root:, out: StringIO.new, pause:)

        assert_raises(SourceArchive::Failure) { archive.fetch }
        assert_empty waits
      end
    end
  end

  def test_fetch_tries_again_when_the_connection_is_refused
    in_tree do |root|
      closed = TCPServer.new("127.0.0.1", 0)
      port = closed.addr[1]
      closed.close
      waits, pause = recorder
      archive = SourceArchive.new(source("http://127.0.0.1:#{port}/x-1.0.tar.bz2"), root:, out: StringIO.new, pause:)
      error = assert_raises(SourceArchive::Failure) { archive.fetch }

      assert_equal SourceArchive::BACKOFF, waits
      assert_includes error.message, "Errno::ECONNREFUSED"
    end
  end

  # The error a game's CI met: the connection to github.com timed out.
  def test_fetch_tries_again_when_the_connection_times_out_and_then_succeeds
    in_tree do |root|
      calls = 0
      transport = lambda do |uri|
        calls += 1
        raise IO::TimeoutError, "user specified timeout for github.com port 443" if calls < 3

        Net::HTTP.get_response(uri)
      end
      serve(ok(CONTENTS)) do |port|
        waits, pause = recorder
        archive = SourceArchive.new(source("http://127.0.0.1:#{port}/x-1.0.tar.bz2"), root:, out: StringIO.new,
          pause:, transport:)
        archive.fetch

        archive.verify!
        assert_equal 2, waits.size
      end
    end
  end
end
