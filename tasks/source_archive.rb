# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "digest"
require "fileutils"
require "net/http"
require "openssl"
require "timeout"
require "uri"

# The source archive of a framework the precompiled gem carries, as
# ext/lota/licenses.rb records it (Licensing::Source): fetched once from
# its release into the repository, where git ignores it, and checked by
# its SHA-256 every time the gem is built, so the build never needs the
# network and never ships an archive other than the one recorded.
class SourceArchive
  # Raised when the archive is missing, or is not the one recorded.
  class Failure < StandardError; end

  # How many redirects a download follows, as a release's link may lead
  # to a mirror.
  REDIRECTS = 5

  # How long a download waits before each new try, in seconds. Its length
  # is how many times a download is tried again: hosts drop a connection
  # now and then, and a release's host is back within seconds.
  BACKOFF = [2, 5, 15].freeze

  # What a download that fails for the network's sake raises, which is
  # worth trying again. A host that answers 404 is not.
  class Transient < StandardError; end
  private_constant :Transient

  # The errors a dropped, refused, reset, or timed-out connection raises.
  NETWORK_ERRORS = [
    IOError,
    SystemCallError,
    SocketError,
    OpenSSL::SSL::SSLError,
    Timeout::Error,
    Net::OpenTimeout,
    Net::ReadTimeout,
].freeze

  # [source] Its Licensing::Source.
  # [root] The repository, which the source's path is relative to.
  # [out] Where a retry is reported.
  # [pause] Called with the seconds to wait before a new try; tests pass
  #         a recorder.
  # [transport] Called with a URI, answers its Net::HTTPResponse; tests
  #             pass one that fails as a network does.
  def initialize(source, root:, out: $stdout, pause: -> (seconds) { sleep(seconds) },
    transport: Net::HTTP.method(:get_response)
  )
    @source = source
    @root = root
    @out = out
    @pause = pause
    @transport = transport
  end

  # The archive's path in the repository.
  def path
    File.join(@root, @source.path)
  end

  # Raises Failure unless the archive is there with the recorded SHA-256.
  def verify!
    raise Failure, "#{@source.path} is missing; run bundle exec rake sources:fetch" unless File.file?(path)

    actual = Digest::SHA256.file(path).hexdigest
    return if actual == @source.sha256

    raise Failure, "#{@source.path} has SHA-256 #{actual}, not the #{@source.sha256} ext/lota/licenses.rb " \
      "records; delete it and run bundle exec rake sources:fetch"
  end

  # Downloads the archive from its release, unless it is already there,
  # and keeps it only when its SHA-256 is the one recorded. A connection
  # that fails, or a host that answers 5xx, is tried again after each of
  # BACKOFF's waits; an archive other than the one recorded, or an answer
  # such as 404, is not, since asking again will not change it.
  def fetch
    return if File.file?(path) && Digest::SHA256.file(path).hexdigest == @source.sha256

    FileUtils.mkdir_p(File.dirname(path))
    partial = "#{path}.part"
    File.binwrite(partial, download_with_retries)
    actual = Digest::SHA256.file(partial).hexdigest
    unless actual == @source.sha256
      File.delete(partial)
      raise Failure, "#{@source.url} has SHA-256 #{actual}, not the #{@source.sha256} ext/lota/licenses.rb records"
    end
    File.rename(partial, path)
  end

  private def download_with_retries
    tried = []
    begin
      download(URI(@source.url), REDIRECTS)
    rescue Transient, *NETWORK_ERRORS => e
      tried << "#{e.class}: #{e.message}"
      if tried.size > BACKOFF.size
        raise Failure, "#{@source.url} did not download in #{tried.size} tries, waiting #{BACKOFF.join(', ')} " \
          "seconds between them: #{tried.join('; ')}"
      end

      wait = BACKOFF.fetch(tried.size - 1)
      @out.puts("Retrying #{@source.url} in #{wait} seconds (#{tried.size} of #{BACKOFF.size}): #{tried.last}")
      @pause.call(wait)
      retry
    end
  end

  private def download(uri, redirects)
    response = @transport.call(uri)
    case response
    when Net::HTTPSuccess then response.body
    when Net::HTTPRedirection
      raise Failure, "#{@source.url} redirects more than #{REDIRECTS} times" if redirects.zero?

      download(URI.join(uri, response.fetch("location")), redirects - 1)
    when Net::HTTPServerError then raise Transient, "#{uri} answered #{response.code} #{response.message}"
    else raise Failure, "#{uri} answered #{response.code} #{response.message}"
    end
  end
end
