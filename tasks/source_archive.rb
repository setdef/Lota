# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "digest"
require "fileutils"
require "net/http"
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

  # [source] Its Licensing::Source.
  # [root] The repository, which the source's path is relative to.
  def initialize(source, root:)
    @source = source
    @root = root
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
  # and keeps it only when its SHA-256 is the one recorded.
  def fetch
    return if File.file?(path) && Digest::SHA256.file(path).hexdigest == @source.sha256

    FileUtils.mkdir_p(File.dirname(path))
    partial = "#{path}.part"
    File.binwrite(partial, download(URI(@source.url), REDIRECTS))
    actual = Digest::SHA256.file(partial).hexdigest
    unless actual == @source.sha256
      File.delete(partial)
      raise Failure, "#{@source.url} has SHA-256 #{actual}, not the #{@source.sha256} ext/lota/licenses.rb records"
    end
    File.rename(partial, path)
  end

  private def download(uri, redirects)
    response = Net::HTTP.get_response(uri)
    case response
    when Net::HTTPSuccess then response.body
    when Net::HTTPRedirection
      raise Failure, "#{@source.url} redirects more than #{REDIRECTS} times" if redirects.zero?

      download(URI.join(uri, response.fetch("location")), redirects - 1)
    else raise Failure, "#{uri} answered #{response.code} #{response.message}"
    end
  end
end
