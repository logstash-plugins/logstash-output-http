require "logstash/devutils/rspec/spec_helper"
require "logstash/outputs/http"
require "ftw"


class LogStash::Outputs::Http
  attr_writer :agent
end

describe LogStash::Outputs::Http do
  let(:agent) { FTW::Agent.new }
  let(:event) { LogStash::Event.new("message" => "hi") }
  let(:url) { "http://localhost:3131" }
  let(:method) { "post" }
  subject { LogStash::Outputs::Http.new("url" => url, "http_method" => method) }

  before :each do
    subject.register
    subject.agent = agent
  end

  it "should execute a request" do
    expect(agent).to receive(:execute).with(FTW::Request)
    subject.receive(event)
  end

  context "http_method = post" do
    it "should execute a POST to a url" do
      expect(agent).to receive(:post).with(url).and_call_original
      subject.receive(event)
    end
  end

  context "http_method = put" do
    let(:method) { "put" }
    it "should execute a PUT to a url" do
      expect(agent).to receive(:put).with(url).and_call_original
      subject.receive(event)
    end
  end
end
