require "logstash/devutils/rspec/spec_helper"
require "flores/pki"
require "socket"
require "logstash/outputs/http"
require "ftw/webserver"
require "flores/random"
require "flores/pki"

TLS_VERSIONS = [ 
  # "TLSv1.2", # JRuby doesn't support TLSv1.2 yet, I think.
  "TLSv1.1",
  "TLSv1", # Not recommended for production
  "SSLv3"  # Please never use SSLv3.
] 

# A webserver for testing web clients.
# Chooses a random port to bind to.
class TestingWebServer
  def initialize
    @socket, @host, @port = Flores::Random.tcp_listener

    # This is janky, maybe expose this better from FTW
    @webserver = FTW::WebServer.new(@host, @port, &method(:handle_request))
  end

  def address
    "#{@host}:#{@port}"
  end

  def run
    @running = true
    while running?
      client, _addr = @socket.accept
      handle_connection(client)
    end
  rescue
    #p :Error => e
    #p e.backtrace
    raise
  end

  def running?
    @running
  end

  def stop
    @running = false
    @webserver.stop
  end

  def on_connect(&block)
    @on_connect = block
  end

  def on_request(&block)
    @on_request = block
  end

  def on_exception(&block)
    @on_exception = block
  end

  def handle_connection(client_socket)
    connection = FTW::Connection.from_io(client_socket)
    @on_connect.call(connection) if @on_connect
    @webserver.handle_connection(connection)
  rescue => e
    if @on_exception
      @on_exception.call(e, connection)
      connection.disconnect("done")
      client_socket.close
      raise
    else
      raise
    end
  end

  def handle_request(request, response, connection)
    response.status = 200
    response.body = "Good job."
    @on_request.call(request, response, connection) if @on_request
  end
end

describe LogStash::Outputs::Http do
  let(:server) { TestingWebServer.new }
  let(:queue) { Queue.new }
  before do
    # Cabin::Channel.get(LogStash).subscribe(STDERR)
    # Cabin::Channel.get(LogStash).level = :debug
    # Cabin::Channel.get.subscribe(STDERR)
    # Cabin::Channel.get.level = :debug
    server.on_request do |request, response, _connection|
      queue << [:request, request, response, request.read_body]
    end
    server.on_exception do |exception, _connection|
      queue << [:exception, exception]
    end
    plugin.register
  end

  let(:server_thread) { Thread.new { server.run } }

  let(:http_method) { Flores::Random.item(["post", "put"]) }
  let(:message) { Flores::Random.text(1..100) }
  let(:event) { LogStash::Event.new("message" => message) }
  let(:plugin) { LogStash::Outputs::Http.new("url" => "http://#{server.address}/", "http_method" => http_method) }

  shared_examples "expected behavior" do
    before do
      server_thread
    end
    after do
      server.stop
    end
    it "should correctly send an http request" do
      plugin.receive(event)
      type, *args = queue.pop
      case type
      when :request
        request, _response, request_body = args
        received_event = LogStash::Json.load(request_body)
        expect(request.method.downcase).to eql(http_method.downcase)
        expect(received_event["message"]).to eql(message)
      when :exception
        raise args[0]
      end
    end
  end

  shared_examples "expecting failure" do
    before do
      server_thread
    end
    after do
      server.stop
    end
    it "should fail" do
      plugin.receive(event)
      type, *args = queue.pop
      case type
      when :request
        raise "Should not get here."
      when :exception
        expect(args[0]).to be_a(OpenSSL::SSL::SSLError)
      end
    end
  end

  context "comfortable plain-text http" do
    include_examples "expected behavior"
  end

  context "within the maddening spirit of TLS" do
    let(:key_bits) { 512 } # for speed, do not use in production.
    let(:key) { OpenSSL::PKey::RSA.generate(key_bits, 65_537) }
    let(:csr) { Flores::PKI::CertificateSigningRequest.new }
    let(:certificate) do
      csr.subject = "CN=#{@host}"
      csr.subject_alternates = ["IP:#{@host}"]
      csr.public_key = key.public_key
      csr.start_time = Time.now
      csr.expire_time = csr.start_time + 3600
      csr.signing_key = key
      csr.create
    end

    let(:tls_options) do
      {
        :ssl_version => tls_version,
        :key => key,
        :certificate => certificate
      }
    end

    before do
      server.on_connect do |connection|
        connection.secure(tls_options)
      end
    end

    TLS_VERSIONS.repeated_permutation(2).each do |tls, client_tls|
      context "with #{tls} server and #{client_tls} client" do
        let(:tls_version) { tls }
        let(:plugin_settings) do
          {
            "url" => "https://#{server.address}/",
            "http_method" => http_method,
            "verify_ssl" => false, # DO NOT USE IN PRODUCTION
            "ssl_version" => client_tls
          }
        end
        let(:plugin) { LogStash::Outputs::Http.new(plugin_settings) }

        if tls == client_tls
          include_examples "expected behavior"
        else
          include_examples "expecting failure"
        end
      end
    end
  end
end
