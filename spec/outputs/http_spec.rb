require "logstash/devutils/rspec/spec_helper"
require "logstash/outputs/http"
require "thread"
require "sinatra"

PORT = rand(65535-1024) + 1025

class LogStash::Outputs::Http
  attr_writer :agent
  attr_reader :request_tokens
end

# note that Sinatra startup and shutdown messages are directly logged to stderr so
# it is not really possible to disable them without reopening stderr which is not advisable.
#
# == Sinatra (v1.4.6) has taken the stage on 51572 for development with backup from WEBrick
# == Sinatra has ended his set (crowd applauds)

class TestApp < Sinatra::Base

  # disable WEBrick logging
  def self.server_settings
    { :AccessLog => [], :Logger => WEBrick::BasicLog::new(nil, WEBrick::BasicLog::FATAL) }
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

  multiroute(%w(get post put patch delete), "/good") do
    self.class.last_request = request
    [200, "YUP"]
  end

  multiroute(%w(get post put patch delete), "/bad") do
    self.class.last_request = request
    [500, "YUP"]
  end
end

RSpec.configure do |config|
  #http://stackoverflow.com/questions/6557079/start-and-call-ruby-http-server-in-the-same-script
  def sinatra_run_wait(app, opts)
    queue = Queue.new

    Thread.new(queue) do |queue|
      begin
        app.run!(opts) do |server|
          queue.push("started")
        end
      rescue
        # ignore
      end
    end

    queue.pop # blocks until the run! callback runs
  end

  config.before(:suite) do
    sinatra_run_wait(TestApp, :port => PORT, :server => 'webrick')
  end
end

describe LogStash::Outputs::Http do
  # Wait for the async request to finish in this spinlock
  # Requires pool_max to be 1
  def wait_for_request

    loop do
      sleep(0.1)
      break if subject.request_tokens.size > 0
    end
  end

  let(:port) { PORT }
  let(:event) { LogStash::Event.new("message" => "hi") }
  let(:url) { "http://localhost:#{port}/good" }
  let(:method) { "post" }

  describe "when num requests > token count" do
    let(:pool_max) { 10 }
    let(:num_reqs) { pool_max / 2 }
    let(:client) { subject.client }
    subject {
      LogStash::Outputs::Http.new("url" => url,
                                  "http_method" => method,
                                  "pool_max" => pool_max)
    }

    before do
      subject.register
    end

    it "should receive all the requests" do
      expect(client).to receive(:send).
                          with(method.to_sym, url, anything).
                          exactly(num_reqs).times.
                          and_call_original

      num_reqs.times {|t| subject.receive(event)}
    end
  end

  shared_examples("verb behavior") do |method|
    subject { LogStash::Outputs::Http.new("url" => url, "http_method" => method, "pool_max" => 1) }

    let(:expected_method) { method.clone.to_sym }
    let(:client) { subject.client }

    before do
      subject.register
      allow(client).to receive(:send).
                         with(expected_method, url, anything).
                         and_call_original
      allow(subject).to receive(:log_failure).with(any_args)
    end

    context "performing a get" do
      describe "invoking the request" do
        before do
          subject.receive(event)
        end

        it "should execute the request" do
          expect(client).to have_received(:send).
                              with(expected_method, url, anything)
        end
      end

      context "with passing requests" do
        before do
          subject.receive(event)
        end

        it "should not log a failure" do
          expect(subject).not_to have_received(:log_failure).with(any_args)
        end
      end

      context "with failing requests" do
        let(:url) { "http://localhost:#{port}/bad"}

        before do
          subject.receive(event)
          wait_for_request
        end

        it "should log a failure" do
          expect(subject).to have_received(:log_failure).with(any_args)
        end
      end
    end
  end

  LogStash::Outputs::Http::VALID_METHODS.each do |method|
    context "when using '#{method}'" do
      include_examples("verb behavior", method)
    end
  end

  shared_examples("a received event") do
    before do
      TestApp.last_request = nil
    end

    before do
      subject.receive(event)
      wait_for_request
    end

    let(:last_request) { TestApp.last_request }
    let(:body) { last_request.body.read }
    let(:content_type) { last_request.env["CONTENT_TYPE"] }

    it "should receive the request" do
      expect(last_request).to be_truthy
    end

    it "should receive the event as a hash" do
      expect(body).to eql(expected_body)
    end

    it "should have the correct content type" do
      expect(content_type).to eql(expected_content_type)
    end
  end

  describe "integration tests" do
    let(:url) { "http://localhost:#{port}/good" }
    let(:event) { LogStash::Event.new("foo" => "bar", "baz" => "bot")}

    subject { LogStash::Outputs::Http.new(config) }

    before do
      subject.register
    end

    describe "sending with the default (JSON) config" do
      let(:config) {
        {"url" => url, "http_method" => "post", "pool_max" => 1}
      }
      let(:expected_body) { LogStash::Json.dump(event) }
      let(:expected_content_type) { "application/json" }

      include_examples("a received event")
    end

    describe "sending the event as a form" do
      let(:config) {
        {"url" => url, "http_method" => "post", "pool_max" => 1, "format" => "form"}
      }
      let(:expected_body) { subject.send(:encode, event.to_hash) }
      let(:expected_content_type) { "application/x-www-form-urlencoded" }

      include_examples("a received event")
    end

    describe "sending the event as a message" do
      let(:config) {
        {"url" => url, "http_method" => "post", "pool_max" => 1, "format" => "message", "message" => "%{foo} AND %{baz}"}
      }
      let(:expected_body) { "#{event["foo"]} AND #{event["baz"]}" }
      let(:expected_content_type) { "text/plain" }

      include_examples("a received event")
    end

    describe "sending a mapped event" do
      let(:config) {
        {"url" => url, "http_method" => "post", "pool_max" => 1, "mapping" => {"blah" => "X %{foo}"}}
      }
      let(:expected_body) { LogStash::Json.dump("blah" => "X #{event["foo"]}") }
      let(:expected_content_type) { "application/json" }

      include_examples("a received event")
    end
  end
end
