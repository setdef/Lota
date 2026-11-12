# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/licensing"

# The licensing record read against the bundle rake compile built, as the
# linker and ninja report it, so it needs the build, and runs as an
# integration test; LicensingTest reads made-up maps and reports.
class LicensingBundleTest < Minitest::Test
  include TreeHelper

  BUILD = File.join(ROOT, "tmp/engine/build")

  # rake compile's bundle carries the libraries its graphics, images, and
  # filesystem need, and none it only declares.
  def test_the_real_bundle_carries_what_its_objects_were_compiled_from
    linked = LinkedFiles.read(map: File.join(BUILD, "lib/lota/native.map"), build: BUILD)
    linux = RUBY_PLATFORM.include?("linux")
    outside = [
      linux ? "/usr" : `xcode-select --print-path`.strip,
      RbConfig::CONFIG["rubyhdrdir"],
      File.join(ROOT, linux ? "tmp/dependencies/installdir" : "vendor/love-apple-dependencies"),
].map { |dir| File.join(dir, "") }
    names = Licensing.load(File.join(ROOT, "ext/lota/licenses.rb")).bundled(linked, root: ROOT, outside:).map(&:name)

    [
      "Lota",
      "Rice",
      "LodePNG",
      "LZ4",
      "LÖVE's patched LZ4",
      "glslang",
      "SPIRV-Cross",
      "PhysicsFS",
      "PhysicsFS's miniz",
      "PhysicsFS's LZMA SDK",
      "Noise1234",
      "Noto Sans",
      "LÖVE",
].each { |name| assert_includes names, name }
  end
end
