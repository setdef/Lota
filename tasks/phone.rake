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

    desc "Pin the phone engines SUMS names (a release's SHA256SUMS) in the gem, for phone builds to fetch"
    task :pin, [:sums] do |_, args|
      sums = File.read(args[:sums] || abort("❌ Name the checksums: rake phone:engine:pin[SUMS]"))
      pinned = Lota::PhoneEngine.sums(sums)
      assets = Lota::PhoneEngine::TARGETS.map { |target| Lota::PhoneEngine.asset(target) }
      abort "❌ #{args[:sums]} names #{pinned.keys.sort.join(', ')}, not #{assets.join(', ')}" unless
        pinned.keys.sort == assets.sort

      File.write(Lota::PhoneEngine::SUMS, assets.map { |asset| "#{pinned.fetch(asset)}  #{asset}\n" }.join)
      puts "✅ Pinned #{assets.size} phone engines in #{Lota::PhoneEngine::SUMS}"
    rescue Lota::PhoneEngine::Failure => e
      abort "❌ #{e.message}"
    end
  end
end
