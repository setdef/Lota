# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "bundler/setup"
require "open3"
require "rbconfig"

# Checks that an app made from Lota's app with fledge build --from is
# signed with the developer's own identity, as the sharing guide tells a
# developer to sign one (doc/guide/sharing.md), with an identity made for
# the run, so no check needs an account of anyone's. It is a thin check
# over Fledge's own: the identity comes from Fledge's
# .github/scripts/make-test-identity.sh or .ps1, and on macOS Apple's
# notary is the stand-in Fledge's own tests use, an xcrun first on PATH
# (Fledge's test/support/stand_in_notary.rb), from the Fledge the bundle
# names (Fledge's doc/contributors/design/signing.md, "What CI proves, and
# the stand-ins").
#
#   BUNDLE_GEMFILE=TOOLS ruby .github/signed_check.rb APP PROJECT OUT IDENTITY [NAME]
#
# TOOLS is a Gemfile that names Fledge, APP the folder of Lota's app,
# PROJECT the project to make into an app, OUT where it goes, and
# IDENTITY the identity: on macOS its name or its SHA-1 hash, with NAME
# its name when it is the hash, and on Windows its SHA-1 thumbprint on
# Windows. On macOS the build also notarizes with the stand-in, and every
# Mach-O file of the made app must verify strictly, carry the hardened
# runtime, a secure timestamp, and the identity's signature, its program
# Fledge's entitlements, its bundle the stand-in's stapled ticket, and the
# stand-in must have been asked to notarize it. On Windows every program
# and library of the made app, and its setup program, must carry a
# signature by the identity. Prints what it checked; exits 1 on the first
# check that fails.
module SignedCheck
  # The profile the build names for the stand-in notary, which holds no
  # credentials.
  PROFILE = "lota-signed-check"

  # The entitlements Fledge signs a macOS program with, for Ruby's JITs
  # (doc/contributors/design/packaging.md, "Signing on macOS").
  ENTITLEMENTS = %w[
    com.apple.security.cs.allow-unsigned-executable-memory
    com.apple.security.cs.disable-library-validation
].freeze

  extend self

  def fail!(message)
    warn "signed check: #{message}"
    exit 1
  end

  def ok(message)
    puts "ok: #{message}"
  end

  # Runs fledge build --from with +options+, through the bundle.
  def build(app, project, out, options)
    command = [RbConfig.ruby, "-S", "bundle", "exec", "fledge", "build", "--from", app, *options, "--out", out, project]
    puts command.join(" ")
    system(*command) or fail!("fledge build --from failed (#{$?})")
  end

  def macos(app, project, out, identity, name)
    fledge = Gem.loaded_specs.fetch("fledge").full_gem_path
    require File.join(fledge, "test", "support", "stand_in_notary")
    StandInNotary.with do |calls, _submitted|
      build(app, project, out, ["--sign", identity, "--notarize", PROFILE])
      submit = calls.call.find { |call| call[0, 2] == %w[notarytool submit] }
      fail!("the notary was never asked: #{calls.call.inspect}") unless submit
      fail!("notarytool submit had no --keychain-profile #{PROFILE}: #{submit.inspect}") unless submit.each_cons(2).include?(["--keychain-profile", PROFILE])
      fail!("nothing was stapled: #{calls.call.inspect}") unless calls.call.any? { |call| call[0, 2] == %w[stapler staple] }
      ok("Fledge asked the notary stand-in to notarize the app with the profile alone, and stapled it")
    end
    bundle = Dir.glob(File.join(out, "*-arm64-darwin", "*.app")).first or fail!("no .app in #{out}")
    _, status = Open3.capture2e("codesign", "--verify", "--strict", "--deep", "--verbose=2", bundle)
    fail!("#{bundle} does not verify") unless status.success?
    ok("#{File.basename(bundle)} verifies, deeply and strictly")
    files = Dir.glob(File.join(bundle, "**", "*")).select { |path| File.file?(path) && !File.symlink?(path) && macho?(path) }
    fail!("only #{files.size} Mach-O files in #{bundle}") if files.size < 10
    files.each do |file|
      shown, = Open3.capture2e("codesign", "--display", "--verbose=2", file)
      fail!("#{file} is not signed with the hardened runtime:\n#{shown}") unless shown.include?("(runtime)")
      fail!("#{file} has no secure timestamp:\n#{shown}") unless shown.match?(/^Timestamp=/)
      fail!("#{file} is not signed by #{name}:\n#{shown}") unless shown.include?("Authority=#{name}")
    end
    ok("its #{files.size} Mach-O files carry the hardened runtime, a secure timestamp, and #{name}'s signature")
    program = File.join(bundle, "Contents", "MacOS", File.basename(bundle, ".app"))
    entitlements, = Open3.capture2e("codesign", "--display", "--entitlements", "-", "--xml", program)
    missing = ENTITLEMENTS.reject { |key| entitlements.include?("<key>#{key}</key>") }
    fail!("#{program} lacks #{missing.join(', ')}") unless missing.empty?
    ok("its program carries Fledge's entitlements")
    ticket = File.join(bundle, "Contents", "CodeResources")
    fail!("#{bundle} holds no stapled ticket") unless File.file?(ticket) && File.read(ticket).include?(StandInNotary::TICKET)
    ok("its bundle holds the stand-in's stapled ticket")
  end

  def macho?(path)
    File.open(path, "rb") { |file| [0xfeedfacf, 0xcafebabe, 0xbebafeca, 0xcffaedfe].include?(file.read(4).to_s.unpack1("N")) }
  end

  def windows(app, project, out, identity)
    build(app, project, out, ["--sign", identity])
    folder = Dir.glob(File.join(out, "*-mingw-ucrt")).find { |path| File.directory?(path) } or fail!("no app folder in #{out}")
    files = Dir.glob(File.join(folder, "**", "*.{exe,dll}")) + Dir.glob(File.join(out, "*-setup.exe"))
    fail!("only #{files.size} programs and libraries in #{folder}") if files.size < 10
    list = File.join(out, "signed-files.txt")
    File.write(list, files.map { |file| File.expand_path(file).tr("/", "\\") }.join("\n"))
    script = "foreach ($f in Get-Content -LiteralPath '#{File.expand_path(list).tr('/', '\\')}') { " \
      "$s = Get-AuthenticodeSignature -LiteralPath $f; '{0}|{1}|{2}' -f $s.Status, $s.SignerCertificate.Thumbprint, $f }"
    shown, status = Open3.capture2e("powershell", "-NoProfile", "-Command", script)
    fail!("Get-AuthenticodeSignature failed:\n#{shown}") unless status.success?
    lines = shown.lines(chomp: true).grep(/\|/)
    fail!("read #{lines.size} signatures of #{files.size} files:\n#{shown}") unless lines.size == files.size
    unsigned = lines.reject { |line| line.split("|")[1].to_s.casecmp?(identity) }
    fail!("not signed by #{identity}:\n#{unsigned.join("\n")}") unless unsigned.empty?
    statuses = lines.map { |line| line.split("|").first }.tally
    ok("its #{files.size} programs and libraries, and its setup program, carry #{identity}'s signature (#{statuses})")
  end

  def call(arguments)
    app, project, out, identity, name = arguments
    fail!("usage: ruby .github/signed_check.rb APP PROJECT OUT IDENTITY") unless identity
    if RbConfig::CONFIG["host_os"].include?("darwin")
      macos(app, project, out, identity, name || identity)
    elsif Gem.win_platform?
      windows(app, project, out, identity)
    else
      fail!("Fledge signs on macOS and Windows only")
    end
  end
end

SignedCheck.call(ARGV)
