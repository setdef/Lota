# frozen_string_literal: true

# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Lays out the project that fledge build ios turns into the iOS kit, and
# finishes the Xcode project it writes, for any Lota game in a public
# repository (.github/workflows/ios-kit.yml).
#
# A game repository holds a game folder, and Fledge builds a project: a
# Gemfile, a fledge.yml, and a program. With no program named, the kit's
# project is the one lota fuse writes (lib/lota/fuse.rb): the game folder
# copied into game/NAME and an entry script, main.rb, that boots it
# fused. With a program named, the project is the game folder itself and
# Fledge runs that program, which boots the game as it likes. Either way
# the kit adds Lota (KIT_LOTA_GEM, a path gem) and Fledge (KIT_FLEDGE_REF)
# to a Gemfile of its own, and, in .lota-ios/, the iOS host (ipad/host/ios,
# its marks filled in) and the app's icon.
#
#   ruby prepare.rb layout          # settings from the KIT_ variables below
#   ruby prepare.rb finish PROJECT  # README.txt, the results file, BUILD-INFO.txt
#
# layout writes KIT_JSON, what it resolved, which finish reads.
require "fileutils"
require "json"
require "yaml"
require_relative "icon"

module KitPrepare
  HERE = __dir__
  # The folders of a game that never reach its app, as lota fuse leaves
  # them out (Lota::Fuse::LEFT_OUT).
  LEFT_OUT = %w[.git .bundle vendor/bundle vendor/cache].freeze
  # A named program's project is the game folder, so the files that pin a
  # desktop's Ruby and gems give way to the kit's.
  REPLACED = %w[Gemfile Gemfile.lock gems.rb gems.locked fledge.yml .ruby-version mise.toml .tool-versions].freeze
  KIT_FOLDER = ".lota-ios"
  ORIENTATIONS = {
    "portrait" => %w[UIInterfaceOrientationPortrait],
    "upside-down" => %w[UIInterfaceOrientationPortraitUpsideDown],
    "landscape-left" => %w[UIInterfaceOrientationLandscapeLeft],
    "landscape-right" => %w[UIInterfaceOrientationLandscapeRight],
    "landscape" => %w[UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight],
    "all" => %w[UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown
      UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight]
  }.freeze
  DEFAULT_ORIENTATIONS = { "iphone" => "portrait landscape", "ipad" => "all" }.freeze
  AUDIO = { "ambient" => "ambient", "solo-ambient" => "soloAmbient", "playback" => "playback", "default" => "" }.freeze
  AUDIO_PROSE = {
    "ambient" => "ambient: it mixes with other apps' audio, and the silent switch mutes it",
    "solo-ambient" => "solo ambient: it stops other apps' audio, and the silent switch mutes it",
    "playback" => "playback: it stops other apps' audio and plays through the silent switch",
    "default" => "the system's default (solo ambient): it stops other apps' audio, and the silent switch mutes it"
  }.freeze

  module_function

  def env(name, default = "")
    value = ENV.fetch(name, "").strip
    value.empty? ? default : value
  end

  def fail!(message)
    warn "::error::#{message}"
    exit 1
  end

  def notice(message)
    puts "::notice::#{message}"
  end

  # An identifier-safe target name from a display name: its ASCII letters
  # and digits, each word capitalized, as "Moon Pong ’em" becomes
  # "MoonPongEm".
  def app_name_for(display)
    ascii = display.unicode_normalize(:nfkd).encode("US-ASCII", undef: :replace, invalid: :replace, replace: "")
    name = ascii.split(/[^A-Za-z0-9]+/).reject(&:empty?).map { |word| word[0].upcase + word[1..] }.join.sub(/\A\d+/, "")
    name.empty? ? "LotaGame" : name
  end

  def orientations(text)
    chosen = DEFAULT_ORIENTATIONS.dup
    text.split(";").map(&:strip).reject(&:empty?).each do |part|
      device, list = part.include?(":") ? part.split(":", 2).map(&:strip) : [nil, part]
      devices = device ? [device.downcase] : %w[iphone ipad]
      fail!("orientations: unknown device #{device.inspect}; use iphone: or ipad:") unless (devices - %w[iphone ipad]).empty?
      devices.each { |each| chosen[each] = list }
    end
    chosen.transform_values do |list|
      names = list.split(/[\s,]+/).reject(&:empty?)
      fail!("orientations: none given in #{list.inspect}") if names.empty?
      names.flat_map { |name| ORIENTATIONS.fetch(name.downcase) { fail!("orientations: unknown #{name.inspect}; use #{ORIENTATIONS.keys.join(', ')}") } }.uniq
    end
  end

  def inside?(root, path)
    File.realpath(path).start_with?(File.join(File.realpath(root), ""))
  rescue Errno::ENOENT
    false
  end

  # The PNG of 1024 pixels a side that +icon+ names in the repository at
  # +clone+ (a folder, a glob pattern, or a file), or nil, and why.
  def find_icon(clone, icon)
    return [nil, "no icon was named"] if icon.empty?

    path = File.join(clone, icon)
    candidates = if File.directory?(path) then Dir.glob(File.join(path, "*.png"))
    elsif icon.match?(/[*?\[{]/) then Dir.glob(path)
    else [path]
    end
    candidates = candidates.select { |file| File.file?(file) && inside?(clone, file) }.sort
    return [nil, "#{icon} names no PNG file in the game repository"] if candidates.empty?

    sizes = candidates.to_h { |file| [file, KitIcon.size(file)] }
    found = sizes.find { |_, size| size && size[0] == 1024 && size[1] == 1024 }
    return [found[0], nil] if found

    [nil, "#{icon} has no PNG of 1024 by 1024 pixels (found #{sizes.map { |file, size| "#{File.basename(file)} #{size ? size.first(2).join('x') : 'not a PNG'}" }.join(', ')})"]
  end

  def copy_tree(from, to, skip)
    FileUtils.mkdir_p(to)
    Dir.each_child(from) do |child|
      source = File.join(from, child)
      next if skip.any? { |path| source == path }

      target = File.join(to, child)
      if File.symlink?(source) || !File.directory?(source)
        FileUtils.cp(source, target, preserve: true) unless File.symlink?(source) && !File.exist?(source)
      else
        copy_tree(source, target, skip)
      end
    end
  end

  def entry_script(folder)
    <<~RUBY
      # frozen_string_literal: true

      # Written by the iOS kit's workflow, as lota fuse writes its entry
      # script (lib/lota/fuse.rb), and with standard output in sync mode:
      # Fledge 0.5.0's runtime leaves it buffered, so a phone's log would
      # get the game's lines in batches, late. Starts the game in
      # game/#{folder} as a fused game, as a shipped game starts.
      $stdout.sync = true
      RubyVM::YJIT.enable if defined?(RubyVM::YJIT.enable)
      require "lota"
      exit Lota::Boot.new(File.join(__dir__, "game", #{folder.inspect}), ARGV, fused: true).call
    RUBY
  end

  def plist_strings(names)
    names.map { |name| "\t\t<string>#{name}</string>\n" }.join
  end

  def fill(text, values, file)
    values.each { |mark, value| text = text.gsub("@#{mark}@") { value } }
    left = text.scan(/@[A-Z][A-Z_]+@/).uniq - text.scan(/@@[A-Z_]+@@/).map { |mark| mark[1..-2] }
    fail!("#{file} has marks no one filled: #{left.join(', ')}") unless left.empty?
    text
  end

  def layout
    clone = File.realpath(env("KIT_GAME_CLONE"))
    game_path = env("KIT_GAME_PATH", ".")
    fail!("game_path #{game_path.inspect} leads out of the repository") if game_path.split("/").include?("..") || game_path.start_with?("/")
    game = File.join(clone, game_path)
    unless File.directory?(game) && (File.realpath(game) == clone || inside?(clone, game))
      fail!("game_path #{game_path} is not a folder in #{env('KIT_GAME_REPOSITORY')}")
    end
    game = File.realpath(game)
    project = env("KIT_PROJECT")
    FileUtils.rm_rf(project)
    FileUtils.mkdir_p(project)

    display = env("KIT_DISPLAY_NAME", File.basename(env("KIT_GAME_REPOSITORY", File.basename(clone))))
    fail!("display_name has a line break") if display.match?(/[\r\n]/)
    app_name = env("KIT_APP_NAME", app_name_for(display))
    fail!("app_name #{app_name.inspect} is not a name Xcode's target takes: letters and digits, a letter first") unless app_name.match?(/\A[A-Za-z][A-Za-z0-9]*\z/)
    identifier = env("KIT_IDENTIFIER", "com.example.#{app_name}")
    fail!("identifier #{identifier.inspect} is not reverse-DNS: letters, digits, and hyphens, between dots") unless identifier.match?(/\A[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+\z/)
    chosen = orientations(env("KIT_ORIENTATIONS"))
    audio = env("KIT_AUDIO_CATEGORY", "ambient")
    fail!("audio_category #{audio.inspect} is not one of #{AUDIO.keys.join(', ')}") unless AUDIO.key?(audio)
    hide_status_bar = env("KIT_HIDE_STATUS_BAR", "true") == "true"
    program = env("KIT_PROGRAM")

    if program.empty?
      fail!("#{game_path} has no main.rb, so there is no game to boot") unless File.file?(File.join(game, "main.rb"))
      folder = File.basename(game).gsub(%r{[\x00-\x1f<>:"/\\|?*]}, "_").sub(/[. ]+\z/, "")
      folder = "lotagame" if folder.empty?
      copy_tree(game, File.join(project, "game", folder), LEFT_OUT.map { |path| File.join(game, path) })
      File.write(File.join(project, "main.rb"), entry_script(folder))
      program_path = "main.rb"
      program_note = "main.rb, written by the kit, boots game/#{folder} fused"
    else
      fail!("program #{program.inspect} leads out of the game folder") if program.split("/").include?("..") || program.start_with?("/")
      fail!("program #{program} is not a file in #{game_path}") unless File.file?(File.join(game, program))
      copy_tree(game, project, (LEFT_OUT + REPLACED).map { |path| File.join(game, path) })
      notice("the game's own #{File.join(game_path, 'Gemfile')} gives way to the kit's, which asks for Lota and Fledge alone") if File.file?(File.join(game, "Gemfile"))
      program_path = program
      program_note = "#{program}, the game's own program"
    end

    version = "1.0.0"
    config = File.join(game, "fledge.yml")
    if File.file?(config)
      found = (YAML.safe_load_file(config) || {})["version"]
      version = found.to_s if found
    end

    kit = File.join(project, KIT_FOLDER)
    host = File.join(kit, "host")
    FileUtils.mkdir_p(kit)
    FileUtils.cp_r(File.join(HERE, "host", "ios"), host)
    plist = File.join(host, "Host", "Info.plist")
    status_bar = hide_status_bar ? "\t<key>UIStatusBarHidden</key>\n\t<true/>\n\t<key>UIViewControllerBasedStatusBarAppearance</key>\n\t<false/>\n" : ""
    File.write(plist, fill(File.read(plist), {
      "KIT_STATUS_BAR" => status_bar, "KIT_AUDIO_CATEGORY" => AUDIO.fetch(audio),
      "KIT_ORIENTATIONS_IPHONE" => plist_strings(chosen.fetch("iphone")), "KIT_ORIENTATIONS_IPAD" => plist_strings(chosen.fetch("ipad"))
    }, plist))
    spec = File.join(host, "project.yml")
    File.write(spec, fill(File.read(spec), { "KIT_DISPLAY_NAME" => JSON.generate(display) }, spec))
    fail!("display_name does not survive YAML") unless YAML.safe_load("v: #{JSON.generate(display)}")["v"] == display
    system("plutil", "-lint", plist, exception: true) if system("command -v plutil > /dev/null")

    icon_input = env("KIT_ICON")
    icon, why = find_icon(clone, icon_input)
    icon_file = File.join(kit, "icon-1024.png")
    if icon
      FileUtils.cp(icon, icon_file)
      _, _, alpha = KitIcon.size(icon)
      puts "::warning::#{File.basename(icon)} has an alpha channel, which the App Store refuses in an app icon" if alpha
      icon_note = "#{icon.delete_prefix(File.join(clone, ''))} from the game repository"
    else
      KitIcon.plain(icon_file)
      puts "::warning::#{why}, so the app's icon is a plain generated one (an orange disc on blue)"
      icon_note = "a plain generated icon, an orange disc on blue, since #{why}"
    end

    lota_gem = env("KIT_LOTA_GEM")
    fledge_ref = env("KIT_FLEDGE_REF", "v0.5.0")
    File.write(File.join(project, "Gemfile"), <<~RUBY)
      # frozen_string_literal: true

      # Written by the iOS kit's workflow: Lota from the kit's checkout,
      # and Fledge, which builds the Xcode project.
      source "https://rubygems.org"

      gem "lota", path: #{lota_gem.inspect}
      gem "fledge", git: "https://github.com/setdef/Fledge", tag: #{fledge_ref.inspect}, group: :development
    RUBY
    fledge = {
      "name" => app_name, "version" => version,
      "programs" => [{ "path" => program_path, "kind" => "windowed", "identifier" => identifier, "icon" => "#{KIT_FOLDER}/icon" }],
      "ios" => { "host" => "#{KIT_FOLDER}/host" }
    }
    File.write(File.join(project, "fledge.yml"), "# Written by the iOS kit's workflow for fledge build ios.\n#{YAML.dump(fledge)}")

    settings = {
      "display_name" => display, "app_name" => app_name, "identifier" => identifier, "version" => version,
      "game_repository" => env("KIT_GAME_REPOSITORY"), "game_ref" => env("KIT_GAME_REF"), "game_sha" => env("KIT_GAME_SHA"),
      "game_path" => game_path, "program" => program_note, "icon" => icon_note, "icon_generated" => icon.nil?,
      "orientations" => chosen, "audio_category" => audio, "hide_status_bar" => hide_status_bar,
      "questions" => env("KIT_QUESTIONS"), "lota_repository" => env("KIT_LOTA_REPOSITORY"), "lota_sha" => env("KIT_LOTA_SHA"),
      "lota_ref" => env("KIT_LOTA_REF"), "fledge_ref" => fledge_ref, "run_id" => env("KIT_RUN_ID"), "run_url" => env("KIT_RUN_URL"),
      "results_file" => "#{app_name}-results.txt"
    }
    if settings["questions"] != ""
      questions = File.join(clone, settings["questions"])
      fail!("kit_questions #{settings['questions']} is not a file in the game repository") unless File.file?(questions) && inside?(clone, questions)
      settings["questions_text"], settings["question_types"] = questionnaire(File.read(questions, encoding: "UTF-8"))
    end
    File.write(env("KIT_JSON"), JSON.pretty_generate(settings))
    puts JSON.pretty_generate(settings.except("questions_text"))
  end

  # The questions of a kit_questions file as the results file asks them,
  # and the answer types it named. A file whose lines read
  # "question | answer type", with # comment lines, becomes numbered
  # questions, each with a blank for its answer and one for a note; any
  # other file is copied as it is. y/n, rating, and choice (as
  # "choice: a/b/c") say what to answer; text and any other type get a
  # plain blank.
  def questionnaire(text)
    lines = text.lines.map(&:strip).reject { |line| line.empty? || line.start_with?("#") }
    return [text, []] unless !lines.empty? && lines.all? { |line| line.include?("|") }

    types = []
    body = lines.each_with_index.map do |line, index|
      question, type = line.split("|", 2).map(&:strip)
      types << type
      hint = case type.downcase
      when %r{\A(y/n|yes/no)(\s*\+\s*text)?\z} then " (y/n)"
      when "rating" then " (1 to 5)"
      when /\Achoice:\s*(.+)\z/ then " (#{Regexp.last_match(1).split('/').map(&:strip).join(' / ')})"
      else ""
      end
      "#{index + 1}. #{question}#{hint}\n   Answer:\n   Note:\n"
    end
    puts "kit_questions: #{lines.size} questions, answer types #{types.uniq.join(', ')}"
    [body.join("\n"), types.uniq]
  end

  def orientation_prose(names)
    names.map { |name| name.delete_prefix("UIInterfaceOrientation").gsub(/(?<=[a-z])(?=[A-Z])/, " ").downcase }.join(", ")
  end

  def finish(project)
    settings = JSON.parse(File.read(env("KIT_JSON")))
    questions = settings["questions_text"] || File.read(File.join(HERE, "questions.txt"), encoding: "UTF-8")
    values = {
      "DISPLAY_NAME" => settings["display_name"], "APP_NAME" => settings["app_name"], "IDENTIFIER" => settings["identifier"],
      "VERSION" => settings["version"], "RESULTS_FILE" => settings["results_file"],
      "GAME_REPOSITORY" => settings["game_repository"], "GAME_REF" => settings["game_ref"], "GAME_SHA" => settings["game_sha"],
      "GAME_PATH" => settings["game_path"], "PROGRAM" => settings["program"], "ICON" => settings["icon"],
      "LOTA_REPOSITORY" => settings["lota_repository"], "LOTA_SHA" => settings["lota_sha"], "LOTA_REF" => settings["lota_ref"],
      "FLEDGE_REF" => settings["fledge_ref"], "RUN_ID" => settings["run_id"], "RUN_URL" => settings["run_url"],
      "XCODE" => env("KIT_XCODE", "the Xcode in BUILD-INFO.txt"),
      "IPHONE_ORIENTATIONS" => orientation_prose(settings["orientations"]["iphone"]),
      "IPAD_ORIENTATIONS" => orientation_prose(settings["orientations"]["ipad"]),
      "AUDIO" => AUDIO_PROSE.fetch(settings["audio_category"]),
      "STATUS_BAR" => settings["hide_status_bar"] ? "with no status bar" : "with the status bar showing",
      "QUESTIONS" => questions.chomp
    }
    readme = File.join(HERE, "README.txt")
    File.write(File.join(project, "README.txt"), fill(File.read(readme, encoding: "UTF-8"), values, readme))
    results = File.join(HERE, "results.txt")
    File.write(File.join(project, settings["results_file"]), fill(File.read(results, encoding: "UTF-8"), values, results))
    File.write(File.join(project, "BUILD-INFO.txt"), <<~TEXT)
      #{settings['display_name']} (#{settings['app_name']}, #{settings['identifier']}), version #{settings['version']}
      Game #{settings['game_repository']} #{settings['game_ref']}, commit #{settings['game_sha']}, folder #{settings['game_path']}
      Program #{settings['program']}
      Icon #{settings['icon']}
      Lota #{settings['lota_repository']} #{settings['lota_ref']}, commit #{settings['lota_sha']}
      Fledge #{settings['fledge_ref']}
      #{env('KIT_BUILT_WITH')}
      Workflow run #{settings['run_id']}, #{settings['run_url']}
    TEXT
    puts File.read(File.join(project, "BUILD-INFO.txt"))
  end
end

case ARGV[0]
when "layout" then KitPrepare.layout
when "finish" then KitPrepare.finish(ARGV.fetch(1))
else abort "usage: ruby prepare.rb layout | finish PROJECT"
end
