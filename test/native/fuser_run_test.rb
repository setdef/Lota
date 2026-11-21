# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../zip_writer"
require "json"
require "tmpdir"
require "yaml"
require "lota/fuse"

# The fuser makes a game in one file into an app: it unpacks the archive
# through the engine's filesystem, reads its conf.rb, writes the project
# lota fuse would write for its folder, and runs fledge build --from on it
# (doc/contributors/design/packaging.md, "A game in one file"). Each test
# runs Lota::Fuser in a Ruby of its own, since the filesystem takes one
# source in a process. A fuser is an app Fledge built, and Fledge builds
# for minutes, so a fake fledge stands in for it here: it records its
# arguments, the variables Fledge's guide asks a framework to set, and
# every file of the project as written, and prints a path, as Fledge
# prints each file it writes. The real build is the fuser's run on a
# build of its own.
class FuserRunTest < Minitest::Test
  include NativeHelper

  # A game whose conf.rb names it and sets its identity, with a file in a
  # folder of its own.
  GAME = {
    "conf.rb" => "def Lota.conf(t)\n  t.window.title = \"Sample Game: Deluxe\"\n  t.identity = \"SampleGame\"\nend\n",
    "main.rb" => "require_relative \"lib/helper\"\n",
    "lib" => :directory,
    "lib/helper.rb" => "HELPER = true\n",
  }.freeze

  # The fake fledge: records what it was given in the file FUSER_RECORD
  # names and prints the path of an archive in its --out folder, or exits
  # with FUSER_FAIL's status.
  FAKE_FLEDGE = <<~RUBY
    require "json"
    project = ARGV.last
    files = Dir.glob("**/*", File::FNM_DOTMATCH, base: project).reject { |path| File.directory?(File.join(project, path)) }
    File.write(ENV.fetch("FUSER_RECORD"), JSON.dump("arguments" => ARGV, "rubyopt" => ENV["RUBYOPT"], "rubylib" => ENV["RUBYLIB"],
      "files" => files.sort.to_h { |path| [path, File.read(File.join(project, path))] }))
    warn "fledge build: what Fledge says"
    exit Integer(ENV["FUSER_FAIL"]) if ENV["FUSER_FAIL"]
    puts File.join(ARGV[ARGV.index("--out") + 1], "Sample Game-x86_64-linux.tar.gz")
  RUBY

  # Runs Lota::Fuser on an archive of +entries+, named +name+, in a Ruby of
  # its own, with the fake fledge, and returns what that Ruby printed, its
  # status, what the fake recorded (or nil), and the folders it used. The
  # fuser runs Fledge in its app's bundle, so that Ruby has a bundle of its
  # own, of no gems: one that sets up on a computer that has not installed
  # this repository's, as when these tests run without Bundler. It names
  # its lockfile too, since Bundler hands a child this repository's, and
  # its settings: a run that froze this repository's bundle, as CI's does,
  # would refuse to lock an empty one.
  def fuse(entries, name: "Sample Game.lota", environment: {})
    Dir.mktmpdir("lota-fuser-run") do |folder|
      archive = File.join(folder, name)
      entries.is_a?(String) ? File.write(archive, entries) : ZipWriter.write(archive, entries)
      notices = File.join(folder, "Fuser-x86_64-linux", "app", "NOTICES.txt")
      FileUtils.mkdir_p(File.dirname(notices))
      File.write(notices, "Lota's notices\n")
      fake = File.join(folder, "fledge")
      File.write(fake, FAKE_FLEDGE)
      record = File.join(folder, "record.json")
      out = File.join(folder, "out")
      gemfile = File.join(folder, "Gemfile")
      File.write(gemfile, "")
      script = <<~RUBY
        require "lota"
        require "lota/fuser"
        fuser = Lota::Fuser.new(#{archive.dump}, app: #{File.dirname(notices, 2).dump}, notices: #{notices.dump}, out: #{out.dump},
          fledge: [RbConfig.ruby, #{fake.dump}])
        begin
          puts fuser.call
          puts "lota fuser: \#{fuser.warning}" if fuser.warning
        rescue Lota::Fuser::Error => e
          puts "Error: \#{e.message}"
        end
      RUBY
      # A person's RUBYLIB and RUBYOPT, which must not reach Fledge.
      person = { "RUBYLIB" => "elsewhere", "RUBYOPT" => "#{ENV.fetch('RUBYOPT', '')} -rset".strip }
      bundle = { "BUNDLE_GEMFILE" => gemfile, "BUNDLE_LOCKFILE" => "#{gemfile}.lock", "BUNDLE_APP_CONFIG" => folder, "BUNDLE_FROZEN" => "false" }
      output, status = ruby_of_its_own("-e", script, environment: { "FUSER_RECORD" => record, **person, **bundle, **environment })
      yield output, status, File.file?(record) ? JSON.parse(File.read(record)) : nil, folder
    end
  end

  def test_the_project_holds_the_game_named_for_its_identity_and_what_starts_it
    fuse(GAME) do |output, status, record, folder|
      assert_predicate status, :success?, output
      refute_nil record, output
      files = record.fetch("files")

      game = %w[conf.rb lib/helper.rb main.rb].map { |path| "game/SampleGame/#{path}" }

      assert_equal ["NOTICES.txt", "fledge.yml", *game, "main.rb"], files.keys
      assert_equal GAME["conf.rb"], files["game/SampleGame/conf.rb"]
      assert_equal GAME["lib/helper.rb"], files["game/SampleGame/lib/helper.rb"]
      assert_equal Lota::Fuse.entry_script("SampleGame"), files["main.rb"]
      assert_equal "Lota's notices\n", files["NOTICES.txt"]
      config = YAML.safe_load(files["fledge.yml"])

      assert_equal "Sample Game: Deluxe", config["name"]
      assert_equal "com.example.SampleGame", config["identifier"]
      assert_equal "windowed", config["kind"]
      assert_includes output, "#{File.join(folder, 'out', 'Sample Game-x86_64-linux.tar.gz')}\n"
    end
  end

  def test_fledge_builds_from_the_fuser_into_the_out_folder_as_its_guide_asks_a_framework_to_run_it
    fuse(GAME) do |output, _status, record, folder|
      refute_nil record, output
      arguments = record.fetch("arguments")

      assert_equal ["build", "--from", File.join(folder, "Fuser-x86_64-linux"), "--out", File.join(folder, "out")], arguments[0, 5]
      assert_equal "project", File.basename(arguments.last)
      # Bundler's setup puts its own path before what it was given.
      rubyopt = record["rubyopt"].split

      assert_includes rubyopt, "-rbundler/setup"
      assert_empty rubyopt.grep_v(%r{bundler/setup\z}), "the person's RUBYOPT reaches Fledge"
      # Bundler's setup puts its own folder in RUBYLIB, for the Rubies its
      # program starts.
      refute_includes record["rubylib"].to_s.split(File::PATH_SEPARATOR), "elsewhere", "the person's RUBYLIB reaches Fledge"
      assert_includes output, "fledge build: what Fledge says"
    end
  end

  def test_a_game_that_names_nothing_is_named_for_its_archive
    fuse({ "main.rb" => "\n" }) do |output, _status, record, _folder|
      refute_nil record, output
      files = record.fetch("files")

      assert_equal ["NOTICES.txt", "fledge.yml", "game/Sample Game/main.rb", "main.rb"], files.keys, output
      config = YAML.safe_load(files["fledge.yml"])

      assert_equal "Sample Game", config["name"]
      assert_equal "com.example.Sample-Game", config["identifier"]
    end
  end

  def test_an_archive_lota_refuses_makes_no_app
    fuse(GAME.merge("lib/native.so" => "ELF")) do |output, status, record, folder|
      assert_predicate status, :success?, output
      assert_nil record
      assert_includes output, "Error: Cannot play the game in '#{File.join(folder, 'Sample Game.lota')}': its entry \"lib/native.so\" is " \
        "native code"
    end
  end

  def test_a_file_that_is_no_zip_makes_no_app
    fuse("not a zip") do |output, _status, record, folder|
      assert_nil record
      assert_includes output, "Error: #{File.join(folder, 'Sample Game.lota')} is not a game in one file: it cannot be read as a zip."
    end
  end

  # Fusing a LÖVE game runs none of its code, and a conf.lua that raises
  # shows its error when the game starts, before love.init names the save
  # folder from t.identity (boot.lua:244-247, 394-396, and 440-442). So a
  # conf.rb that raises, such as one that requires a gem the fuser does not
  # ship, makes the app all the same, named for its archive, which then
  # shows that error, and the fuser says so.
  def test_a_conf_that_raises_makes_the_app_named_for_its_archive_and_says_what_it_raised
    conf = "def Lota.conf(t)\n  t.identity = \"SampleGame\"\n  require \"no_such_gem\"\nend\n"
    fuse(GAME.merge("conf.rb" => conf)) do |output, status, record, _folder|
      assert_predicate status, :success?, output
      refute_nil record, output
      files = record.fetch("files")

      assert_equal conf, files["game/Sample Game/conf.rb"]
      config = YAML.safe_load(files["fledge.yml"])

      assert_equal "Sample Game", config["name"]
      assert_equal "com.example.Sample-Game", config["identifier"]
      assert_includes output, "lota fuser: the game's conf.rb raised LoadError: cannot load such file -- no_such_gem. " \
        "The app shows that error when it starts, as a fused LÖVE game shows an error in its conf.lua.\n"
    end
  end

  # LÖVE's require finds a file of the game's own from conf.lua, so the
  # fuser reads a conf.rb that requires one.
  def test_a_conf_that_requires_a_file_of_its_game_names_the_app
    conf = "require \"lib/settings\"\ndef Lota.conf(t) = (t.identity = IDENTITY)\n"
    fuse(GAME.merge("conf.rb" => conf, "lib/settings.rb" => "IDENTITY = \"Settled\"\n")) do |output, _status, record, _folder|
      refute_nil record, output
      config = YAML.safe_load(record.fetch("files")["fledge.yml"])

      assert_equal "com.example.Settled", config["identifier"]
      refute_includes output, "raised"
    end
  end

  def test_a_failed_build_says_so_after_what_fledge_said
    fuse(GAME, environment: { "FUSER_FAIL" => "3" }) do |output, _status, _record, _folder|
      assert_includes output, "fledge build: what Fledge says"
      assert_operator output.index("fledge build: what Fledge says"), :<, output.index("Error: fledge build --from failed (exit status 3)")
    end
  end
end
