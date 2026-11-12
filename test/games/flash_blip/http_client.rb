# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2025 Aliet Exposito
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from FLASH-BLIP's http_client.lua
# (test/fixtures/flash_blip/game/http_client.lua, lines 1-252), by the
# rules of doc/contributors/design/translation.md: love.filesystem.getInfo
# is Lota::Filesystem.info and getSaveDirectory save_directory (rule 3),
# love.filesystem.lines an Enumerator (rule 15), love.filesystem.read an
# Array (rule 4), love.timer.getTime Lota::Timer.time, and
# love.thread.newThread and getChannel Threads.new_thread and
# Threads.channel (threads.rb), until Lota has its own threads.
#
# LuaSocket's http.request, in the threads and in sync_get, is Ruby's own
# Net::HTTP with the same timeout on connecting, sending, and receiving, as
# LuaSocket's http.TIMEOUT has: a request that gets an answer gives a truthy
# ok and the status as an Integer, and one that fails gives ok nil and the
# error message as the code, with LuaSocket's words for a refused
# connection and a timeout. Each thread's code is Ruby source, written as
# Lota::Thread will run it, with its arguments in ARGV where Lua has ...;
# it hands back a frozen Hash with the keys ok, code, and data where Lua
# pushes a table. The other messages the module pushes are frozen Hashes
# too, read with [:success], [:data], and [:error].
#
# A callback is anything that answers call, called with as many arguments
# as Lua passes it; a proc, like a Lua function, ignores the ones it does
# not name. The options table of get is the keyword timeout. The web
# state, each web request, and each pending native request, tables with
# fixed fields, are a WebState, a WebRequest, and a PendingRequest. The
# config from product.env, keyed at runtime, is a Hash. Lua patterns are
# regular expressions with the same meaning.

require "settings"
require "threads"
require "lua"

module HttpClient
  WebState = Struct.new(:requests, :next_id, :bridge_ready)
  WebRequest = Struct.new(:callback, :req_file, :resp_file, :deadline, :abandoned)
  PendingRequest = Struct.new(:channel_name, :callback, :thread)

  DEFAULT_TIMEOUT_SECONDS = 5
  POST_TIMEOUT_SECONDS = 15

  def self.is_success(code)
    code.is_a?(Numeric) && code >= 200 && code < 300
  end

  @http = nil
  unless Settings.is_web
    require "net/http"
    @http = Net::HTTP
    # LuaSocket's http.TIMEOUT = DEFAULT_TIMEOUT_SECONDS: sync_get passes it.
  end

  @config = { "BACKEND_IP" => "127.0.0.1", "BACKEND_PORT" => "8080" }

  if Lota::Filesystem.info("product.env")
    Lota::Filesystem.lines("product.env").each do |line|
      next if line.match?(/\A\s*#/) || line.match?(/\A\s*\z/)

      match = line.match(/([^=]+)=(.*)/m)
      next unless match

      key = match[1][/\A\s*(.*?)\s*\z/m, 1]
      value = match[2][/\A"?(.*?)"?\z/m, 1]
      value = value[/\A\s*(.*?)\s*\z/m, 1]
      @config[key] = value if %w[BACKEND_IP BACKEND_IP_HTTPS BACKEND_PORT].include?(key)
    end
  end

  # On web, itch.io forces HTTPS, so the browser requires the backend to use HTTPS too (Mixed Content policy)
  # In native builds, we use plain HTTP directly because LuaSocket doesn't support TLS without LuaSec
  @base_url = if Settings.is_web
    "https://#{@config['BACKEND_IP_HTTPS']}"
  else
    "http://#{@config['BACKEND_IP']}:#{@config['BACKEND_PORT']}"
  end

  @web = WebState.new({}, 0, false)

  def self.web_ensure_bridge_ready
    return if @web.bridge_ready

    Lota::Filesystem.write("bridge_init.dat", "1")
    @web.bridge_ready = true
  end

  def self.web_request(method, endpoint, body, headers, callback, timeout)
    web_ensure_bridge_ready

    @web.next_id += 1
    id = Lua.tostring(@web.next_id)
    req_file = "web_req_#{id}.dat"
    resp_file = "web_resp_#{id}.dat"
    has_body = !body.nil?

    Lota::Filesystem.write(req_file, body) if has_body

    req_path = has_body ? "#{Lota::Filesystem.save_directory}/#{req_file}" : ""
    resp_path = "#{Lota::Filesystem.save_directory}/#{resp_file}"
    url = @base_url + endpoint

    command = [id, method, url, req_path, resp_path].join("|")
    # Lua visits the headers, and the requests below, in pairs' order,
    # which LuaJIT changes from run to run and the parity harness makes
    # sorted (test/parity/lua/conf.lua, sorted_pairs), so they are sorted.
    headers&.sort&.each do |key, value|
      command = "#{command}|#{key}:#{value}"
    end

    @web.requests[id] = WebRequest.new(
      callback:,
      req_file: has_body ? req_file : nil,
      resp_file:,
      deadline: Lota::Timer.time + (timeout || DEFAULT_TIMEOUT_SECONDS)
    )

    puts "__LOVE_HTTP__#{command}"
  end

  def self.web_poll
    return if !Settings.is_web || @web.requests.empty?

    now = Lota::Timer.time
    @web.requests.sort.each do |_, req|
      if req.deadline && !req.abandoned && now >= req.deadline
        req.abandoned = true
        req.callback.call(false, 0, "timeout")
      end
    end

    finished_ids = []
    @web.requests.sort.each do |id, req|
      finished_ids << id if Lota::Filesystem.info(req.resp_file)
    end

    finished_ids.each do |id|
      req = @web.requests[id]
      @web.requests.delete(id)

      content, = Lota::Filesystem.read(req.resp_file)
      Lota::Filesystem.remove(req.resp_file)
      Lota::Filesystem.remove(req.req_file) if req.req_file

      next if req.abandoned

      if !content
        req.callback.call(false, 0, "Failed to read bridge response file")
      else
        newline_pos = content.byteindex("\n")
        if newline_pos
          status = Lua.tonumber(content.byteslice(0, newline_pos)) || 0
          data = content.byteslice((newline_pos + 1)..)
          req.callback.call(is_success(status), status, data)
        else
          req.callback.call(false, 0, "Invalid bridge response format")
        end
      end
    end
  end

  NATIVE_GET_THREAD_CODE = <<~RUBY
    require "net/http"
    # The channels this thread hands values back on: Lota::Thread's once
    # Lota has threads, run in a Ractor of its own; until then the inline
    # Threads', on the main thread.
    channel = Lota.const_defined?(:Thread, false) ? Lota::Thread.method(:channel) : Threads.method(:channel)
    url, channel_name, timeout = ARGV
    uri = URI(url)
    ok = nil
    code = nil
    resp_body = []
    begin
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                          open_timeout: timeout, read_timeout: timeout,
                                          write_timeout: timeout) do |http|
        response = http.request(Net::HTTP::Get.new(uri))
        resp_body << response.body.to_s
        ok = true
        code = response.code.to_i
      end
    rescue Errno::ECONNREFUSED
      code = "connection refused"
    rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, Errno::ETIMEDOUT
      code = "timeout"
    rescue StandardError => e
      code = e.message
    end
    channel.call(channel_name).push({ ok: ok, code: code, data: resp_body.join }.freeze)
  RUBY

  NATIVE_POST_THREAD_CODE = <<~RUBY
    require "net/http"
    # The channels this thread hands values back on: Lota::Thread's once
    # Lota has threads, run in a Ractor of its own; until then the inline
    # Threads', on the main thread.
    channel = Lota.const_defined?(:Thread, false) ? Lota::Thread.method(:channel) : Threads.method(:channel)
    url, channel_name, timeout, body, headers = ARGV
    uri = URI(url)
    headers = headers.merge("Content-Length" => body.bytesize.to_s)
    ok = nil
    code = nil
    resp_body = []
    begin
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                          open_timeout: timeout, read_timeout: timeout,
                                          write_timeout: timeout) do |http|
        request = Net::HTTP::Post.new(uri, headers)
        request.body = body
        response = http.request(request)
        resp_body << response.body.to_s
        ok = true
        code = response.code.to_i
      end
    rescue Errno::ECONNREFUSED
      code = "connection refused"
    rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, Errno::ETIMEDOUT
      code = "timeout"
    rescue StandardError => e
      code = e.message
    end
    channel.call(channel_name).push({ ok: ok, code: code, data: resp_body.join }.freeze)
  RUBY

  @active_threads = {}
  @pending_requests = []
  @next_channel_id = 0

  def self.post(endpoint, body, headers, callback)
    if Settings.is_web
      web_request("POST", endpoint, body, headers, callback, POST_TIMEOUT_SECONDS)
      return
    end

    headers ||= {}
    @next_channel_id += 1
    channel_name = "http_post_#{@next_channel_id}"
    thread = Threads.new_thread(NATIVE_POST_THREAD_CODE)
    @active_threads[thread] = true
    @pending_requests << PendingRequest.new(channel_name, callback, thread)
    thread.start(@base_url + endpoint, channel_name, POST_TIMEOUT_SECONDS, body, headers)
  end

  def self.get(endpoint, callback, timeout: nil)
    if Settings.is_web
      web_request("GET", endpoint, nil, nil, callback, timeout)
      return
    end

    @next_channel_id += 1
    channel_name = "http_get_#{@next_channel_id}"
    thread = Threads.new_thread(NATIVE_GET_THREAD_CODE)
    @active_threads[thread] = true
    @pending_requests << PendingRequest.new(channel_name, callback, thread)
    thread.start(@base_url + endpoint, channel_name, timeout || DEFAULT_TIMEOUT_SECONDS)
  end

  def self.get_via_channel(endpoint, channel_name)
    get(endpoint, proc do |ok, status, data|
      channel = Threads.channel(channel_name)
      if ok
        channel.push({ success: true, data: }.freeze)
      else
        reason = (status == 0) ? "offline" : Lua.tostring(status)
        channel.push({ success: false, error: "Connection failed: #{reason}" }.freeze)
      end
    end)
  end

  def self.sync_get(endpoint)
    return [false, ""] if Settings.is_web || !@http

    resp_body = []
    ok = nil
    code = nil
    uri = URI(@base_url + endpoint)
    begin
      @http.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
        open_timeout: DEFAULT_TIMEOUT_SECONDS,
        read_timeout: DEFAULT_TIMEOUT_SECONDS,
        write_timeout: DEFAULT_TIMEOUT_SECONDS) do |http|
        response = http.request(Net::HTTP::Get.new(uri))
        resp_body << response.body.to_s
        ok = true
        code = response.code.to_i
      end
    rescue
      ok = nil
    end
    [(ok && is_success(code)) || false, resp_body.join]
  end

  def self.poll_thread_results(entries)
    (entries.size - 1).downto(0) do |i|
      entry = entries[i]
      msg = Threads.channel(entry.channel_name).pop
      next unless msg

      @active_threads.delete(entry.thread)
      entries.delete_at(i)
      entry.callback.call(msg[:ok] && is_success(msg[:code]), msg[:code] || 0, msg[:data])
    end
  end

  def self.update
    web_poll
    poll_thread_results(@pending_requests)
  end
end
# SPDX-SnippetEnd
