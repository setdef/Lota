# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "parity_helper"

# Parity::ReferenceCache gives a LoveRun what the reference love did under
# the same inputs, and runs LÖVE again whenever any input differs or the
# entry it kept does not match what it recorded. The tests here use a cache
# folder of their own, never tmp/parity-cache.
class ReferenceCacheTest < Minitest::Test
  # A stand-in for the reference love, run as LoveRun runs it: it shows
  # LOTA_PARITY_FRAMES frames, saves a file in its home, mixes audio,
  # decodes a sound, prints a line, and ends with the status in the file
  # status beside its bundle, or 0, and counts its runs in the file runs
  # there; no input names either file.
  FAKE_LOVE = <<~SH
    #!/bin/sh
    runs="${0%/love.app/*}/runs"
    echo "x$(cat "$runs" 2>/dev/null)" > "$runs"
    i=1
    while [ "$i" -le "$LOTA_PARITY_FRAMES" ]; do
      printf 'frame %s at %s' "$i" "$LOTA_PARITY_CLOCK" > "$LOTA_PARITY_FRAMES_DIR/$(printf %04d "$i").png"
      i=$((i + 1))
    done
    mkdir -p "$LOTA_TEST_HOME/save"
    printf 'saved' > "$LOTA_TEST_HOME/save/settings.txt"
    printf 'mixed' > "$LOTA_LOOPBACK_FILE"
    printf 'decoded' > "$LOTA_PARITY_SOUNDS_DIR/1.sounddata"
    echo "Thanks for playing $LOTA_PARITY_FRAMES frames!"
    exit "$(cat "${0%/love.app/*}/status" 2>/dev/null || echo 0)"
  SH

  SCRIPT = Parity::Script.new(frames: 3, fps: 60, holds: [])

  def setup
    @dir = Dir.mktmpdir("lota-reference-cache-")
    @love = File.join(@dir, "love.app/Contents/MacOS/love")
    FileUtils.mkdir_p(File.dirname(@love))
    File.write(@love, FAKE_LOVE)
    File.chmod(0o755, @love)
    @framework = File.join(@dir, "love.app/Contents/Frameworks/SDL3.framework/SDL3")
    FileUtils.mkdir_p(File.dirname(@framework))
    File.write(@framework, "SDL")
    @game = File.join(@dir, "game")
    FileUtils.mkdir_p(File.join(@game, "assets"))
    File.write(File.join(@game, "main.lua"), "function love.draw() end")
    File.write(File.join(@game, "assets/tile.png"), "tile")
    @conf = File.join(@dir, "lua")
    FileUtils.mkdir_p(@conf)
    File.write(File.join(@conf, "conf.lua"), "-- conf")
    @named = File.join(@dir, "named.conf")
    File.write(@named, "period_size = 1024")
    @harness = File.join(@dir, "harness.rb")
    File.write(@harness, "# harness")
    @platform = "the platform"
    @cache_root = File.join(@dir, "cache")
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def key
    Parity::ReferenceCache::Key.new(harness: [@harness]) { { "platform" => @platform } }
  end

  def cache(limit: Parity::ReferenceCache::LIMIT)
    Parity::ReferenceCache.new(@cache_root, key:, limit:)
  end

  # The key for a run of @love on @conf, with +environment+ added, in a run
  # folder of its own.
  def digest(environment = {}, command: [@love, @conf])
    run = Dir.mktmpdir("run", @dir)
    env = {
"LOTA_PARITY_GAME" => @game,
"LOTA_PARITY_FRAMES_DIR" => File.join(run, "love"),
"OPENAL_CONF" => @named,
**SCRIPT.environment,
**environment,
}
    key.digest(command, env, run).first
  end

  def love_run(script = SCRIPT, cache: self.cache)
    Parity::LoveRun.new(@game, script, Dir.mktmpdir("run", @dir), love: @love, cache:)
  end

  def runs
    counter = File.join(@dir, "runs")
    File.exist?(counter) ? File.read(counter).strip.size : 0
  end

  # Everything a run wrote in its folder, by path, and what it printed and
  # how it ended.
  def result(run)
    folder = File.dirname(run.frames_dir)
    files = Parity::ReferenceCache::Key.walk(folder).to_h do |path, type|
      [path, (type == "file") ? File.binread(File.join(folder, path)) : type]
    end
    [files, run.output.text, run.output.status.success?]
  end

  def test_the_same_inputs_in_another_run_folder_give_the_same_key
    assert_equal digest, digest
  end

  # Each input the reference love's run has, changed alone, changes the
  # key, so the run misses and LÖVE runs again.
  def test_a_change_to_any_input_changes_the_key
    changes = {
      "the reference love's bytes" => -> { File.write(@love, "\n", mode: "a") },
      "a library in its bundle" => -> { File.write(@framework, "SDL 3.4.11") },
      "a new library in its bundle" => -> { File.write(File.join(File.dirname(@framework), "Info.plist"), "") },
      "a file in the game" => -> { File.write(File.join(@game, "assets/tile.png"), "tile 2") },
      "a new file in the game" => -> { File.write(File.join(@game, "untracked.lua"), "") },
      "a new folder in the game" => -> { Dir.mkdir(File.join(@game, "saves")) },
      "a link in the game" => -> { File.symlink("main.lua", File.join(@game, "linked.lua")) },
      "the game's file made executable" => -> { File.chmod(0o755, File.join(@game, "main.lua")) },
      "the harness's conf.lua" => -> { File.write(File.join(@conf, "conf.lua"), "-- conf 2") },
      "a file the environment names" => -> { File.write(@named, "period_size = 512") },
      "the harness's code" => -> { File.write(@harness, "# harness 2") },
      "the platform" => -> { @platform = "another platform" },
    }
    changes.each do |input, change|
      before = digest
      change.call

      refute_equal before, digest, input
    end
  end

  def test_a_change_to_the_script_the_environment_or_the_command_changes_the_key
    before = digest

    refute_equal before, digest({ "LOTA_PARITY_FRAMES" => "4" }), "the script"
    refute_equal before, digest({ "LOTA_PARITY_HOLD" => "79:2-3" }), "a held key"
    refute_equal before, digest({ "SDL_RENDER_DRIVER" => "software" }), "a variable added to the run's"
    refute_equal before, digest({ "MALLOC_PERTURB_" => "2" }), "the memory byte"
    refute_equal before, digest(command: [@love, @conf, "--console"]), "an argument"
    Dir.chdir(@dir) { refute_equal before, digest, "the working directory" }
  end

  # A variable of this process's never reaches the run (Parity.environment),
  # so it leaves the key, and the cache, alone: the second run hits.
  def test_a_variable_of_this_process_the_run_does_not_get_leaves_the_key_alone
    first = love_run
    ENV["LOTA_REFERENCE_CACHE_TEST"] = "1"

    assert_predicate love_run, :cached?
    refute_predicate first, :cached?
    assert_equal 1, runs
  ensure
    ENV.delete("LOTA_REFERENCE_CACHE_TEST")
  end

  # The run gets exactly the harness's variables and the few every run
  # gets, and none of this process's.
  def test_a_run_gets_exactly_the_harness_environment
    ENV["LOTA_REFERENCE_CACHE_TEST"] = "1"
    output = Parity.run({ "LOTA_PARITY_GAME" => @game }, "/usr/bin/env", side: "env") { 1 }
    names = output.text.lines.map { |line| line[/\A[^=]+/] }.sort

    assert_equal Parity.environment("LOTA_PARITY_GAME" => @game).keys.sort, names
    assert_includes output.text, "PATH=/usr/bin:/bin:/usr/sbin:/sbin\n"
  ensure
    ENV.delete("LOTA_REFERENCE_CACHE_TEST")
  end

  # Each variable every run gets is in the key, as the harness's are.
  def test_a_change_to_a_variable_every_run_gets_changes_the_key
    environment = Parity.environment({})
    before = digest(environment)

    environment.each_key do |name|
      refute_equal before, digest(environment.merge(name => "#{environment.fetch(name)}x")), name
    end
  end

  def test_a_second_run_under_the_same_inputs_is_the_first_one_restored
    first = love_run
    second = love_run

    refute_predicate first, :cached?
    assert_predicate second, :cached?
    assert_equal 1, runs
    assert_equal result(first), result(second)
    assert_equal 3, second.frames.size
    assert_equal "saved", File.read(File.join(second.home, "save/settings.txt"))
    assert_equal "mixed", File.read(second.audio)
    assert_equal ["1.sounddata"], Dir.children(second.sounds_dir)
    assert_equal "Thanks for playing 3 frames!\n", second.output.text
    assert_equal Encoding.default_external, second.output.text.encoding
    assert_equal 0, second.output.status.exitstatus
  end

  def test_a_run_under_another_script_misses_and_runs_love
    love_run
    other = love_run(Parity::Script.new(frames: 4, fps: 60, holds: []))

    refute_predicate other, :cached?
    assert_equal 2, runs
    assert_equal 4, other.frames.size
  end

  # An entry whose files, text, or manifest differ from what it recorded,
  # or are missing, is never read back: LÖVE runs again, into a folder
  # with nothing of the entry's left in it, and its run is kept in the
  # entry's place, which the next run reads.
  def test_a_corrupted_entry_runs_love_again_and_is_replaced
    entry = -> { Dir[File.join(@cache_root, "*")].first }
    corruptions = {
      "a frame's bytes" => -> { File.write(File.join(entry.call, "files/love/0002.png"), "frame 2 at 0") },
      "a frame gone" => -> { File.delete(File.join(entry.call, "files/love/0003.png")) },
      "a saved file gone" => -> { FileUtils.rm_rf(File.join(entry.call, "files/home/save")) },
      "the audio grown" => -> { File.write(File.join(entry.call, "files/love.f32"), "!", mode: "a") },
      "the text" => -> { File.write(File.join(entry.call, "output"), "Thanks for playing 4 frames!\n") },
      "the manifest cut short" => -> { File.truncate(File.join(entry.call, "manifest.json"), 40) },
      "the manifest gone" => -> { File.delete(File.join(entry.call, "manifest.json")) },
      "the manifest changed" => lambda {
        path = File.join(entry.call, "manifest.json")
        File.write(path, File.read(path).sub('"exitstatus":0', '"exitstatus":1'))
      },
    }
    expected = result(love_run)
    corruptions.each_with_index do |(corruption, corrupt), index|
      corrupt.call
      rerun = love_run

      refute_predicate rerun, :cached?, corruption
      assert_equal index + 2, runs, corruption
      assert_equal expected, result(rerun), corruption
      assert_predicate love_run, :cached?, "#{corruption}: the replaced entry"
    end
  end

  def test_a_run_that_fails_is_not_kept
    File.write(File.join(@dir, "status"), "1")
    failed = love_run
    again = love_run

    refute_predicate failed.output.status, :success?
    refute_predicate again, :cached?
    assert_equal 2, runs
    assert_empty Dir[File.join(@cache_root, "*")]
  end

  def test_without_a_cache_love_runs_every_time
    2.times { refute_predicate love_run(cache: nil), :cached? }

    assert_equal 2, runs
  end

  def test_lota_parity_cache_0_turns_the_cache_off
    ENV["LOTA_PARITY_CACHE"] = "0"

    assert_nil Parity::ReferenceCache.default
  ensure
    ENV.delete("LOTA_PARITY_CACHE")
  end

  # Past the limit, the entries read least recently go first; the newest
  # stays, however big.
  def test_entries_past_the_limit_are_removed_least_recently_read_first
    small = cache(limit: 1)
    love_run(cache: small)
    first = Dir[File.join(@cache_root, "*")]
    love_run(Parity::Script.new(frames: 2, fps: 60, holds: []), cache: small)
    second = Dir[File.join(@cache_root, "*")]

    assert_equal 1, first.size
    assert_equal 1, second.size
    refute_equal first, second
    assert_predicate love_run(Parity::Script.new(frames: 2, fps: 60, holds: []), cache: small), :cached?
  end

  # The reference love itself: a run read back from the cache is, file for
  # file and byte for byte, what running LÖVE again writes and prints.
  def test_a_cached_run_of_the_reference_love_is_what_running_it_again_gives
    game = File.join(Parity::ARKANOID, "1-01_TheBallTheBrickThePlatform")
    script = Parity::Script.new(frames: 2, fps: 60, holds: [])
    real = Parity::ReferenceCache.new(@cache_root)
    run = -> (cache) { Parity::LoveRun.new(game, script, Dir.mktmpdir("run", @dir), cache:) }
    fresh = run.call(nil)
    missed = run.call(real)
    hit = run.call(real)

    assert_predicate fresh.output.status, :success?, fresh.output.text
    refute_predicate missed, :cached?
    assert_predicate hit, :cached?
    assert_equal result(fresh), result(hit)
    assert_equal 2, hit.frames.size
  end
end
