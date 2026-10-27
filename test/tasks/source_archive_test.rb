# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/licensing"
require_relative "../../tasks/source_archive"
require "digest"
require "socket"

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
end
