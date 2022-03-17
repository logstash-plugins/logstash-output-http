require "logstash/devutils/rspec/spec_helper"
require "logstash/outputs/http"
require "logstash/codecs/plain"

require "thread"
require "sinatra"
require "webrick"
require "webrick/https"
require 'openssl'

require "supports/compressed_requests"

PORT = rand(65535-1024) + 1025

class LogStash::Outputs::Http
  attr_writer :agent
  attr_reader :request_tokens
end

# NOTE: extend WEBrick with support for config[:SSLVersion]
WEBrick::GenericServer.class_eval do
  alias_method :__setup_ssl_context, :setup_ssl_context

  def setup_ssl_context(config)
    ctx = __setup_ssl_context(config)
    ctx.ssl_version = config[:SSLVersion] if config[:SSLVersion]
    ctx
  end

end

# note that Sinatra startup and shutdown messages are directly logged to stderr so
# it is not really possible to disable them without reopening stderr which is not advisable.
#
# == Sinatra (v1.4.6) has taken the stage on 51572 for development with backup from WEBrick
# == Sinatra has ended his set (crowd applauds)
#
class TestApp < Sinatra::Base
  # on the fly uncompress gzip content
  use CompressedRequests

  set :environment, :production
  set :sessions, false

  @@server_settings = {
      :AccessLog => [], # disable WEBrick logging
      :Logger => WEBrick::BasicLog::new(nil, WEBrick::BasicLog::FATAL)
  }

  def self.server_settings
    @@server_settings
  end

  def self.server_settings=(settings)
    @@server_settings = settings
  end

  def self.multiroute(methods, path, &block)
    methods.each do |method|
      method.to_sym
      self.send method, path, &block
    end
  end

  def self.last_request=(request)
    @last_request = request
  end

  def self.last_request
    @last_request
  end

  def self.retry_fail_count=(count)
    @retry_fail_count = count
  end

  def self.retry_fail_count()
    @retry_fail_count || 2
  end

  multiroute(%w(get post put patch delete), "/good") do
    self.class.last_request = request
    [200, "YUP"]
  end

  multiroute(%w(get post put patch delete), "/bad") do
    self.class.last_request = request
    [400, "YUP"]
  end

  multiroute(%w(get post put patch delete), "/retry") do
    self.class.last_request = request

    if self.class.retry_fail_count > 0
      self.class.retry_fail_count -= 1
      [429, "Will succeed in #{self.class.retry_fail_count}"]
    else
      [200, "Done Retrying"]
    end
  end
end

RSpec.configure do |config|
  #http://stackoverflow.com/questions/6557079/start-and-call-ruby-http-server-in-the-same-script
  def start_app_and_wait(app, opts = {})
    queue = Queue.new

    Thread.start do
      begin
        app.start!({ server: 'WEBrick', port: PORT }.merge opts) do |server|
          yield(server) if block_given?
          queue.push(server)
        end
      rescue => e
        warn "Error starting app: #{e.inspect}" # ignore
      end
    end

    queue.pop # blocks until the start! callback runs
  end

  config.extend(Module.new do

    def tls_version_enabled_by_default?(tls_version)
      begin
        context = javax.net.ssl.SSLContext.getInstance('TLS')
        context.init nil, nil, nil
        context.getDefaultSSLParameters.getProtocols.include? tls_version.to_s
      rescue => e
        warn "#{__method__} failed : #{e.inspect}"
        nil
      end
    end

  end)
end