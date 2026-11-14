# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  # The screen Lota shows when it starts with no game, as LÖVE shows its
  # "no game" screen: a balloon on a rope over drifting clouds, which
  # quits on Escape and starts the game a player drops on it.
  #
  # LÖVE's screen is a small LÖVE program, nogame.lua, which boot.lua runs
  # when it finds no game (vendor/love/src/modules/love/boot.lua:156-170).
  # It defines the game's callbacks, love.conf among them, so the rest of
  # boot.lua starts it as it would start a game. A file or folder dropped
  # on its window restarts LÖVE with that path as the game's
  # (boot.lua:51-60).
  #
  # NoGame ports nogame.lua line for line, and Lota::Boot calls it where
  # boot.lua calls love.nogame, when it is given no game. Its pictures are
  # not in Lota: they come from artwork, base64 text of PNG files, as
  # nogame.lua holds its own, keyed as nogame.lua keys them.
  class NoGame # :nodoc: all
    # The pictures the screen draws, or +nil+ until Lota has some: a Hash
    # of each group nogame.lua names (+:bg+, +:chain+, +:duckloon+) to a
    # Hash of each density (1, and 2 for a display scaled past 1) to a
    # Hash of each picture's name (+:cloud_1_png+) to base64 text of its
    # PNG file.
    @artwork = nil

    class << self
      attr_accessor :artwork
    end

    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
    # SPDX-License-Identifier: Zlib
    #
    # Translated from vendor/love/src/scripts/nogame.lua, as cited on each
    # method. 30log's classes (lines 2829-2864) are Ruby's own, and
    # nogame.lua's globals are the screen's instance variables, which its
    # classes read through the screen.

    # 20Hz physics (nogame.lua:2868).
    STEP = 1 / 20.0

    # Debug things (nogame.lua:2870-2871).
    DEBUG = false

    # The callbacks nogame.lua defines on the love table.
    CALLBACKS = %i[conf load update draw mousepressed keypressed resize filedropped directorydropped].freeze

    # Shows the screen from the next frame on, as love.nogame does
    # (nogame.lua:24-3300): decodes +artwork+ and defines Lota.conf,
    # Lota.load, and the screen's other callbacks. Raises ArgumentError
    # when there is no artwork.
    def self.call(artwork = self.artwork)
      raise ArgumentError, "the no-game screen has no artwork" unless artwork

      # LÖVE opens love.data as it starts, before boot.lua runs anything
      # (modules/love/love.cpp:643-644), so the screen opens it to decode.
      Native::Data.open
      new(artwork).define_callbacks
    end

    # The pictures, decoded with Lota::Data.decode as nogame.lua decodes
    # each with love.data.decode (lines 26-2827).
    def initialize(artwork)
      @r = artwork.transform_values do |densities|
        densities.transform_values do |pictures|
          pictures.transform_values { |text| Lota::Data.decode(:data, :base64, text) }
        end
      end
      @g_t = 0.0 # The current elapsed time.
      @g_step = 0.0 # The current physics step.
      @g_frame_count = 0
      @g_step_count = 0
    end

    # The current elapsed time, and the current physics step, which the
    # screen's objects read as nogame.lua's read its locals.
    attr_reader :g_t, :g_step

    # Each picture, as a texture, once load has made them.
    attr_reader :img_duckloon_normal, :img_duckloon_blink, :img_n, :img_o, :img_g, :img_a, :img_m, :img_e,
      :img_square, :img_cloud_1, :cloud_images

    # Defines the screen's callbacks on Lota, as nogame.lua defines its
    # functions on the love table. Each takes every argument Lota passes
    # and hands the screen's method the ones it declares, as Lua drops
    # the arguments a function does not declare.
    def define_callbacks
      screen = self
      CALLBACKS.each do |name|
        callback = screen.method(name)
        Lota.define_singleton_method(name) { |*arguments| callback.call(*arguments.first(callback.arity)) }
      end
      nil
    end

    # +a+ modulo +b+ as Lua's % finds it, <tt>a - floor(a / b) * b</tt>
    # (LuaJIT's lj_vm_modi), whose last bits can differ from Ruby's for a
    # Float.
    def self.lua_mod(a, b)
      b = b.to_f
      a - ((a / b).floor * b)
    end

    # A State maintains two x,y,angle states for some
    # body, and interpolates between those states (nogame.lua:2876-2916).
    class State
      def initialize(body)
        @t0 = 0.0
        @x0 = body.x
        @y0 = body.y
        @r0 = body.angle

        @t1 = @t0
        @x1 = @x0
        @y1 = @y0
        @r1 = @r0
      end

      # Calculate the next state for Body, at time t.
      def save(body, t)
        @t0 = @t1
        @x0 = @x1
        @y0 = @y1
        @r0 = @r1

        @t1 = t
        @x1 = body.x
        @y1 = body.y
        @r1 = body.angle
      end

      # The state at time +t+, as [x, y, angle].
      def get(t)
        t = [t, @t1].min
        t = [t, @t0].max

        p = (t - @t0) / (@t1 - @t0)

        x = @x0 + (p * (@x1 - @x0))
        y = @y0 + (p * (@y1 - @y0))
        r = @r0 + (p * (@r1 - @r0))

        [x, y, r]
      end
    end

    # Simple class for figuring out whether the eyes
    # of the Duckloon should be closed (nogame.lua:2918-2942).
    class Blink
      def initialize
        # When this hits zero, we open the eyes.
        @closed_t = 0.0

        # When this hits zero, we close the eyes.
        @next_blink_t = 5.0
      end

      # Counts both times down by +dt+, and closes the eyes when it is time.
      def update(dt)
        @next_blink_t = [0.0, @next_blink_t - dt].max
        @closed_t = [0.0, @closed_t - dt].max

        return unless @next_blink_t == 0

        @next_blink_t = 5.0 + Lota::Math.random(0, 3)
        @closed_t = 0.1
      end

      # Whether the eyes are closed.
      def closed?
        @closed_t > 0
      end
    end

    # Duckloon (TM) (nogame.lua:2944-2998).
    class Duckloon
      attr_reader :body

      def initialize(screen, world, x, y)
        @screen = screen
        @body = Lota::Physics::Body.new(world, x, y, :dynamic)
        @body.linear_damping = 0.8
        @body.angular_damping = 0.8
        @shape = Lota::Physics::PolygonShape.new(@body, -55, -60, 0, 90, 55, -60)
        @shape.restitution = 0.5
        @img_normal = screen.img_duckloon_normal
        @img_blink = screen.img_duckloon_blink
        @img = @img_normal
        @blink = Blink.new
        @pin = Lota::Physics::MouseJoint.new(@body, x, y - 80)
        @state = State.new(@body)
      end

      # Saves the state, and pushes the balloon every fifth step.
      def step
        @state.save(@body, @screen.g_step)

        return unless NoGame.lua_mod(@screen.g_step, 5).floor == 0

        @body.apply_force(Lota::Math.random(30, 50), 0)
      end

      def update(dt)
        @blink.update(dt)
      end

      def draw
        x, y, r = @state.get(@screen.g_t)

        Lota::Graphics.color = [1, 1, 1]

        img = @img_normal
        img = @img_blink if @blink.closed?

        Lota::Graphics.draw(img, x, y, r, 1, 1, img.width / 2.0, img.height / 2.0)

        return unless DEBUG

        Lota::Graphics.color = [0.8, 0.3, 0.1]
        Lota::Graphics.polygon(:fill, @body.world_points(*@shape.points))

        Lota::Graphics.color = [0, 1, 0]
        ax, ay = attachment_point
        Lota::Graphics.circle(:fill, ax, ay, 3)
      end

      # This is where to attach the Chain.
      def attachment_point
        x, y = @body.world_point(4, 90)
        [x.to_f, y.to_f]
      end
    end

    # One link of a Chain, as nogame.lua's table for it (nogame.lua:
    # 3028-3055).
    class Link
      attr_accessor :x, :y, :info, :radius, :body, :shape, :state, :joint, :join2
    end

    # How a Chain draws one character: its radius and its picture
    # (nogame.lua:3008-3017).
    class DrawInfo < ::Data.define(:r, :img)
    end

    # The chain is built from a string containing "# nogame",
    # which represents what should be "drawn" along the chain
    # (nogame.lua:3000-3100).
    class Chain
      def initialize(screen, world, x, y, str, duckloon)
        @screen = screen
        @links = [] #: Array[Link]
        @str = str

        draw_info = {
          "n" => DrawInfo.new(11, screen.img_n),
          "o" => DrawInfo.new(11, screen.img_o),
          "g" => DrawInfo.new(11, screen.img_g),
          "a" => DrawInfo.new(11, screen.img_a),
          "m" => DrawInfo.new(11, screen.img_m),
          "e" => DrawInfo.new(11, screen.img_e),
          " " => DrawInfo.new(4, nil),
          "#" => DrawInfo.new(7, screen.img_square),
        }

        str.each_char.with_index(1) do |char, i|
          prev = nil

          prev = @links[i - 2] if i >= 2

          link = Link.new
          link.x = x
          link.y = y

          link.info = draw_info.fetch(char)
          link.radius = link.info.r

          link.y = prev.y + prev.radius + link.radius unless prev.nil?

          link.body = Lota::Physics::Body.new(world, link.x, link.y, :dynamic)
          link.body.linear_damping = 0.5
          link.body.angular_damping = 0.5
          link.shape = Lota::Physics::CircleShape.new(link.body, link.radius)
          link.shape.density = 0.1 / i
          link.state = State.new(link.body)

          # Note: every link must also be attached to the Duckloon. Otherwise the
          #       chain easily goes haywire on higher speeds.

          if prev.nil?
            link.joint = Lota::Physics::RevoluteJoint.new(link.body, duckloon.body, link.x, link.y)
          else
            link.joint = Lota::Physics::RevoluteJoint.new(link.body, prev.body, link.x, link.y - (link.radius / 2.0))
            link.join2 = Lota::Physics::RopeJoint.new(link.body, duckloon.body, link.x, link.y, x, y, link.y - y)
          end

          @links << link
        end
      end

      def step
        @links.each { |link| link.state.save(link.body, @screen.g_step) }
      end

      def update(dt); end

      def draw
        rope = [] #: Array[Float]

        @links.each do |link|
          x, y = link.state.get(@screen.g_t)
          rope << x
          rope << y
        end

        Lota::Graphics.line_width = 3
        Lota::Graphics.color = [1, 1, 1, 0.7]
        Lota::Graphics.line(rope)

        @links.each do |link|
          img = link.info.img
          next if img.nil?

          x, y, r = link.state.get(@screen.g_t)
          ox, oy = img.width / 2.0, img.height / 2.0
          Lota::Graphics.color = [1, 1, 1]
          Lota::Graphics.draw(img, x, y, r, 1, 1, ox, oy)
        end

        return unless DEBUG

        @links.each do |link|
          Lota::Graphics.color = [1, 0, 1]
          Lota::Graphics.circle(:fill, link.body.x, link.body.y, link.shape.radius)
        end
      end
    end

    # Draws clouds in a repeating pattern of 1,2,3,4, but with
    # an offset on each track (nogame.lua:3102-3132).
    class CloudTrack
      # x,y: Top-left corner of cloud track.
      def initialize(screen, x, y, offset, speed, img)
        @screen = screen
        @x = x
        @y = y
        @initial_offset = offset
        @h_spacing = 50
        @img = img
        @w = @h_spacing + @img.width
        @speed = speed # px/s
        @count = Lota::Graphics.width.fdiv(@w) + 2
        @initial_img = Lota::Math.random(1, 4)
      end

      def update(dt); end

      def draw
        abs_offset = @initial_offset + (@speed * @screen.g_t)
        offset = NoGame.lua_mod(abs_offset, @w)
        Lota::Graphics.color = [1, 1, 1, 0.3]
        (1..(@count.floor)).each do |i|
          x = @x + ((i - 1) * (@img.width + @h_spacing)) + offset - @w
          y = @y
          img_no = (abs_offset / @w).floor
          Lota::Graphics.draw(@screen.cloud_images.fetch((@initial_img + i - img_no) % 4), x, y, -0.05)
        end
      end
    end

    # The tracks of clouds, one for each 100 pixels of the window's height
    # (nogame.lua:3134-3150).
    class Clouds
      def initialize(screen)
        layer_height = 100

        @tracks = [] #: Array[CloudTrack]
        max = Lota::Graphics.height.fdiv(layer_height) + 1
        (1..(max.floor)).each do |i|
          img_cloud_1 = screen.img_cloud_1
          @tracks << CloudTrack.new(screen, 0, 20 + ((i - 1) * layer_height), img_cloud_1.width / 2.0 * i, 40, img_cloud_1)
        end
      end

      def draw
        @tracks.each(&:draw)
      end
    end

    # Called on resize (nogame.lua:3152-3167).
    def create_world
      Lota::Math.random_seed = 12_345

      wx = Lota::Graphics.width
      wy = Lota::Graphics.height
      @world = Lota::Physics::World.new(0, 9.81 * 64)
      @duckloon = Duckloon.new(self, @world, wx / 2.0, (wy / 2.0) - 100)
      ax, ay = @duckloon.attachment_point
      @chain = Chain.new(self, @world, ax, ay, "  n o # g a m e # ", @duckloon)
      @clouds = Clouds.new(self)

      @g_objs = [
        @chain,
        @duckloon,
      ]
    end

    # love.load (nogame.lua:3169-3217).
    def load
      renderername = Lota::Graphics.renderer_info.first
      Lota::Window.title = "#{Lota::Window.title} - #{renderername}"

      Lota::Graphics.background_color = [43 / 255.0, 165 / 255.0, 223 / 255.0]
      Lota::Physics.meter = 64

      dpiscale = (Lota::Window.dpi_scale > 1) ? 2 : 1

      chain = @r.fetch(:chain)
      duckloon = @r.fetch(:duckloon)
      bg = @r.fetch(:bg)
      chain_pictures = chain.fetch(dpiscale)
      duckloon_pictures = duckloon.fetch(dpiscale)
      bg_pictures = bg.fetch(dpiscale)

      @img_duckloon_normal = texture(duckloon_pictures, :normal_png, dpiscale)
      @img_duckloon_blink = texture(duckloon_pictures, :blink_png, dpiscale)

      @img_n = texture(chain_pictures, :n_png, dpiscale)
      @img_o = texture(chain_pictures, :o_png, dpiscale)
      @img_g = texture(chain_pictures, :g_png, dpiscale)
      @img_a = texture(chain_pictures, :a_png, dpiscale)
      @img_m = texture(chain_pictures, :m_png, dpiscale)
      @img_e = texture(chain_pictures, :e_png, dpiscale)
      @img_square = texture(chain_pictures, :square_png, dpiscale)

      @img_cloud_1 = texture(bg_pictures, :cloud_1_png, dpiscale)
      img_cloud_2 = texture(bg_pictures, :cloud_2_png, dpiscale)
      img_cloud_3 = texture(bg_pictures, :cloud_3_png, dpiscale)
      img_cloud_4 = texture(bg_pictures, :cloud_4_png, dpiscale)

      @cloud_images = [
        @img_cloud_1,
        img_cloud_2,
        img_cloud_3,
        img_cloud_4,
      ]

      create_world
    end

    # The texture of the picture +name+ in +pictures+, at +dpiscale+, as
    # love.graphics.newTexture makes each in nogame.lua's love.load.
    private def texture(pictures, name, dpiscale)
      Lota::Graphics::Texture.new(pictures.fetch(name), dpiscale:)
    end

    # love.update (nogame.lua:3219-3234).
    def update(dt)
      @g_t += dt

      while @g_t > @g_step
        @world.update(STEP)
        @g_step += STEP
        @g_objs.each(&:step)
        @g_step_count += 1
      end

      @g_objs.each { |obj| obj.update(dt) }
    end

    # love.draw (nogame.lua:3236-3253).
    def draw
      @clouds.draw

      @g_objs.each(&:draw)

      if DEBUG
        Lota::Graphics.color = [0, 0, 0, 0.5]
        Lota::Graphics.print("FPS: #{Lota::Timer.fps}", 50, 50)
        Lota::Graphics.print("Time: #{@g_t}", 50, 65)
        Lota::Graphics.print("g_step: #{@g_step}", 50, 80)
        Lota::Graphics.print("Frame: #{@g_frame_count}", 50, 95)
        Lota::Graphics.print("Step: #{@g_step_count}", 50, 110)
      end

      @g_frame_count += 1
    end

    # love.mousepressed (nogame.lua:3255-3262).
    def mousepressed(_x, _y, _b, istouch, clicks)
      # Double-tap the screen (when using a touch screen) to exit.
      return unless istouch && clicks == 2

      Lota::Event.quit if Lota::Window.show_message_box("Exit No-Game Screen", "", %w[OK Cancel]) == 1
    end

    # love.keypressed (nogame.lua:3264-3268).
    def keypressed(key)
      Lota::Event.quit if key == :escape
    end

    # love.resize (nogame.lua:3270-3273).
    def resize
      create_world
      @g_step = @g_t
    end

    # love.conf (nogame.lua:3275-3287). The title names Lota and its
    # version where LÖVE's names LÖVE and its own, since Lota's windows
    # carry Lota's name (AGENTS.md, Trademarks).
    def conf(t)
      t.title = "Lota #{Lota::VERSION}"
      graphics = t.graphics
      graphics.gammacorrect = true if graphics
      t.modules.audio = false
      t.modules.sound = false
      t.modules.joystick = false
      window = t.window
      window.resizable = true if window
      t.highdpi = true

      window.borderless = true if window && Lota::System.os == "iOS"
    end

    # restartWithNewGame (nogame.lua:3289-3291): restarts Lota with the
    # game at +path+, which Lota::Boot then starts (boot.lua:51-60).
    def restart_with_new_game(path)
      Lota::Event.restart({ "_noGameRestartInfo" => { "gamepath" => path } })
    end

    # love.filedropped (nogame.lua:3293-3295).
    def filedropped(file)
      restart_with_new_game(file.filename)
    end

    # love.directorydropped (nogame.lua:3297-3299).
    def directorydropped(path)
      restart_with_new_game(path)
    end

    # SPDX-SnippetEnd
  end
end
