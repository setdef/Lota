# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require_relative "licensing"
require_relative "source_archive"
require_relative "../lib/lota/notices"

# The notices of a phone's app (rake ios:notices, rake android:notices),
# which lota fuse cannot write, since a phone's app links Lota from no
# gem's manifest: Fledge links the extension into the app's executable on
# iOS and into libfledgeext.so on Android (doc/guide/phones.md).
#
# It writes NOTICES.txt at the top of the phone project, which Fledge puts
# in the app's +app+ folder beside the runtime's +notices+, as lota fuse
# writes a desktop app's. Its components are the works ext/lota/licenses.rb
# records for the phone (Licensing#phone_works), through Licensing#notices,
# and Lota::Notices writes the text, with the license texts of LICENSES and
# ext/lota/licenses. A library whose license asks for its source, OpenAL
# Soft on Android, has its release's archive copied into the project's
# +sources+ folder, after its SHA-256 is checked, so the app carries it.
#
# === Example
#
#   PhoneNotices.new(licensing: Licensing.load("ext/lota/licenses.rb"), phone: "Android", root: ".")
#     .write("../MyGame-phone")
class PhoneNotices
  # Where the project keeps the source archives, which the app holds in
  # its +app+ folder.
  SOURCES = Licensing::SOURCES

  # Where Fledge puts the lota gem the guide names by its path, relative
  # to the folder that holds the app's +app+ folder: the project's
  # vendor/cache/lota (Fledge's PathPackage#installed_path).
  GEM_FOLDER = "app/vendor/cache/lota"

  # Where each phone's app holds its native libraries, as its notices say.
  LIBRARIES = {
    "iOS" => "Lota's extension and the libraries it names are linked into the app's executable.",
    "Android" => "Lota's extension, libfledgeext.so, and each library of its own are in the app's lib folder " \
      "for each of its ABIs, arm64-v8a and x86_64.",
  }.freeze

  # [licensing] The Licensing record.
  # [phone] The phone's name in the record, "iOS" or "Android".
  # [root] The repository, which the record's paths are relative to.
  def initialize(licensing:, phone:, root:)
    @licensing = licensing
    @phone = licensing.phones.fetch(phone) { raise Licensing::Unrecorded, "the record names no phone #{phone}" }
    @root = root
  end

  # The components the app holds, where it holds them.
  def components
    manifest = @licensing.notices(bundle: @phone.extension, works: @licensing.phone_works(@phone.name),
      frameworks: @phone.libraries.to_h { |library| [library, library] })
    manifest.fetch("components").map do |entry|
      component = Lota::Notices::Component.from(entry)
      source = component.source
      source ? component.with(source: source.with(file: File.join("app", source.file))) : component
    end
  end

  # The notices, as text.
  def text
    Text.new(components:, texts:, platform: @phone.name, gem_folder: GEM_FOLDER, task:,
      libraries: LIBRARIES.fetch(@phone.name)).text
  end

  # Downloads each source archive #write copies, unless it is there.
  def fetch
    archives.each(&:fetch)
  end

  # Writes the notices into the phone project at +project+, and the source
  # archive of each library that asks for its source. Raises
  # SourceArchive::Failure when an archive is missing or is not the one
  # recorded.
  def write(project)
    archives.each(&:verify!)
    File.write(File.join(project, Lota::Notices::FILE), text)
    return if archives.empty?

    FileUtils.mkdir_p(File.join(project, SOURCES))
    archives.each { |archive| FileUtils.cp(archive.path, File.join(project, SOURCES)) }
  end

  # The rake task that writes this phone's notices.
  def task
    "rake #{@phone.name.downcase}:notices"
  end

  private def archives
    @licensing.sources(@phone.libraries).map { |source| SourceArchive.new(source, root: @root) }
  end

  private def texts
    paths = Dir[File.join(@root, "LICENSES", "*.txt")] + Dir[File.join(@root, "ext/lota/licenses", "LICENSE-*.txt")]
    paths.to_h do |path|
      [File.basename(path, ".txt").delete_prefix("LICENSE-"), File.read(path, encoding: Encoding::UTF_8)]
    end
  end

  # Lota::Notices, introduced as a phone project's notices rather than
  # those lota fuse writes.
  class Text < Lota::Notices
    # [task] The rake task that writes them.
    # [libraries] Where the app holds its native libraries.
    def initialize(task:, libraries:, **)
      super(**)
      @task = task
      @libraries = libraries
    end

    private def introduction
      "Notices for Lota #{Lota::VERSION} and the libraries it ships\n\n" \
        "#{@task} wrote this file into this app's project from Lota's record of what Lota's build for " \
        "#{@platform} links. It names Lota and those libraries, with the version of each where it is known, " \
        "its licenses, and its notices of copyright, and ends with the text of every license it names. " \
        "#{@libraries} Every other path is relative to the folder that holds this file's folder. Fledge's " \
        "notices/NOTICES.txt, in that folder, names Ruby and the rest of the runtime the app runs on.\n"
    end
  end
end
