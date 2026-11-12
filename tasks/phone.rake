# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "phone_engine"

# A phone's prebuilt engine (tasks/phone_engine.rb), which Lota's CI builds
# for each target and a release publishes, and the checksums the gem pins
# for phone/engine.rb to fetch them by.
namespace :phone do
  desc "Build and pack LÖVE's engine for a phone TARGET (#{Lota::PhoneEngine::TARGETS.join(', ')}) into OUT, " \
    "after rake ios:sdl3 or rake android:deps"
  task :engine, [:target, :out] do |_, args|
    target = args[:target] or abort "❌ Name the target: rake phone:engine[TARGET], one of " \
      "#{Lota::PhoneEngine::TARGETS.join(', ')}"
    out = args[:out] || "tmp/phone-engine"
    build = PhoneEngineBuild.new(target)
    build.build
    build.pack(File.join(out, Lota::PhoneEngine.asset(target)))
  rescue PhoneEngineBuild::Failure, Lota::PhoneEngine::Failure, SourceArchive::Failure, Licensing::Invalid => e
    abort "❌ #{e.message}"
  end

  namespace :engine do
    desc "Write DIR/SHA256SUMS for the phone engines in DIR, one for every target"
    task :sums, [:dir] do |_, args|
      dir = args[:dir] || "tmp/phone-engine"
      assets = Lota::PhoneEngine::TARGETS.map { |target| Lota::PhoneEngine.asset(target) }
      missing = assets.reject { |asset| File.file?(File.join(dir, asset)) }
      abort "❌ #{dir} lacks #{missing.join(', ')}" unless missing.empty?

      sums = assets.map { |asset| "#{Digest::SHA256.file(File.join(dir, asset)).hexdigest}  #{asset}\n" }.join
      File.write(File.join(dir, "SHA256SUMS"), sums)
      puts sums
    end

    desc "Pin the phone engines that the release TAG published with the checksums in SUMS, for phone builds to fetch"
    task :pin, [:sums, :tag] do |_, args|
      abort "❌ Name the checksums and the release: rake phone:engine:pin[SUMS,TAG]" unless args[:sums] && args[:tag]

      text = Lota::PhoneEngine.pin_text(args[:tag], File.read(args[:sums]))
      pinned = Lota::PhoneEngine.pin(text).sums.keys.sort
      assets = Lota::PhoneEngine::TARGETS.map { |target| Lota::PhoneEngine.asset(target) }.sort
      abort "❌ #{args[:sums]} names #{pinned.join(', ')}, not #{assets.join(', ')}" unless pinned == assets

      File.write(Lota::PhoneEngine::PIN, text)
      puts "✅ Pinned the #{assets.size} phone engines of #{args[:tag]} in #{Lota::PhoneEngine::PIN}"
    rescue Lota::PhoneEngine::Failure => e
      abort "❌ #{e.message}"
    end
  end
end
