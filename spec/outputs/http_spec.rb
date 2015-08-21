require "logstash/devutils/rspec/spec_helper"
require "logstash/outputs/http"

class LogStash::Outputs::Http
  attr_writer :agent
end

describe LogStash::Outputs::Http do
  let(:event) { LogStash::Event.new("message" => "hi") }
  let(:url) { "http://localhost:3131" }

  before :each do
    subject.register
  end

  LogStash::Outputs::Http::VALID_METHODS.each do |method|
    subject { LogStash::Outputs::Http.new("url" => url, "http_method" => method) }
    let(:expected_method) { method.clone }
    let(:client) { subject.client }

    context "performing a #{method}" do
      it "should execute the request" do
        client.stub(url, body: "", code: 200)
        expect(client).to receive(:send).
                            with(expected_method, url, anything).
                            and_call_original
        subject.receive(event)
      end
    end
  end
end
