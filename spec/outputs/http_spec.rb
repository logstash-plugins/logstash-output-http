require "logstash/devutils/rspec/spec_helper"
require "logstash/outputs/http"
require "thread"
require "sinatra"

PORT = rand(65535-1024) + 1025

class LogStash::Outputs::Http
  attr_writer :agent
  attr_reader :request_tokens
end

RSpec.configure do |config|
  class TestApp < Sinatra::Base
    def self.multiroute(methods, path, &block)
      methods.each do |method|
        method.to_sym
        self.send method, path, &block
      end
    end



    multiroute(%w(get post put patch delete), "/good") do
      [200, "YUP"]
    end

    multiroute(%w(get post put patch delete), "/bad") do
      [500, "YUP"]
    end
  end

  #http://stackoverflow.com/questions/6557079/start-and-call-ruby-http-server-in-the-same-script
  def sinatra_run_wait(app, opts)
    queue = Queue.new
    thread = Thread.new do
      Thread.abort_on_exception = true
      app.run!(opts) do |server|
        queue.push("started")
      end
    end
    queue.pop # blocks until the run! callback runs
  end


  config.before(:suite) do
    sinatra_run_wait(TestApp, :port => PORT, :server => 'webrick')
  end
end

describe LogStash::Outputs::Http do
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
          loop do
            break if subject.request_tokens.size > 0
          end
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
end
