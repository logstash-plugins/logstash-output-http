require File.expand_path('../spec_helper.rb', File.dirname(__FILE__))

describe LogStash::Outputs::Http do
  # Wait for the async request to finish in this spinlock
  # Requires pool_max to be 1

  before(:all) do
    @server = start_app_and_wait(TestApp)
  end

  after(:all) do
    @server.shutdown # WEBrick::HTTPServer
    TestApp.stop! rescue nil
  end

  let(:port) { PORT }
  let(:event) {
    LogStash::Event.new({"message" => "hi"})
  }
  let(:url) { "http://localhost:#{port}/good" }
  let(:method) { "post" }

  describe "obsolete settings" do
    let(:config) { {"url" => url, "http_method" => "post"} }

    [{:name => 'cacert', :canonical_name => 'ssl_certificate_authorities'},
     {:name => 'client_cert', :canonical_name => 'ssl_certificate'},
     {:name => 'client_key', :canonical_name => 'ssl_key'},
     {:name => "keystore", :canonical_name => 'ssl_keystore_path'},
     {:name => 'truststore', :canonical_name => 'ssl_truststore_path'},
     {:name => "keystore_password", :canonical_name => "ssl_keystore_password"},
     {:name => 'truststore_password', :canonical_name => "ssl_truststore_password"},
     {:name => "keystore_type", :canonical_name => "ssl_keystore_type"},
     {:name => 'truststore_type', :canonical_name => 'ssl_truststore_type'}
    ].each do |settings|
      context "with option #{settings[:name]}" do
        let(:obsolete_config) { config.merge(settings[:name] => 'test_value') }

        it "emits an error about the setting `#{settings[:name]}` now being obsolete and provides guidance to use `#{settings[:canonical_name]}`" do
          error_text = /The setting `#{settings[:name]}` in plugin `http` is obsolete and is no longer available. Use `#{settings[:canonical_name]}` instead/i
          expect { LogStash::Outputs::Http.new(obsolete_config) }.to raise_error LogStash::ConfigurationError, error_text
        end

      end
    end
  end


  shared_examples("verb behavior") do |method|

    shared_examples("failure log behaviour") do
      it "logs failure" do
        expect(subject).to have_received(:log_failure).with(any_args)
      end

      it "does not log headers" do
        expect(subject).to have_received(:log_failure).with(anything, hash_not_including(:headers))
      end

      it "does not log the message body" do
        expect(subject).to have_received(:log_failure).with(anything, hash_not_including(:body))
      end

      context "with debug log level" do
        before :all do
          @current_log_level = LogStash::Logging::Logger.get_logging_context.get_root_logger.get_level.to_s.downcase
          LogStash::Logging::Logger.configure_logging "debug"
        end
        after :all do
          LogStash::Logging::Logger.configure_logging @current_log_level
        end

        it "logs a failure" do
          expect(subject).to have_received(:log_failure).with(any_args)
        end

        it "logs headers" do
          expect(subject).to have_received(:log_failure).with(anything, hash_including(:headers))
        end

        it "logs the body" do
          expect(subject).to have_received(:log_failure).with(anything, hash_including(:body))
        end
      end

    end

    let(:verb_behavior_config) { {"url" => url, "http_method" => method, "pool_max" => 1} }
    subject { LogStash::Outputs::Http.new(verb_behavior_config) }

    let(:expected_method) { method.clone.to_sym }
    let(:client) { subject.client }

    before do
      subject.register
      allow(client).to receive(:send).
                         with(expected_method, url, anything).
                         and_call_original
      allow(subject).to receive(:log_failure).with(any_args)
      allow(subject).to receive(:log_retryable_response).with(any_args)
    end

    context 'sending no events' do
      it 'should not block the pipeline' do
        subject.multi_receive([])
      end
    end

    context "performing a get" do
      describe "invoking the request" do
        before do
          subject.multi_receive([event])
        end

        it "should execute the request" do
          expect(client).to have_received(:send).
                              with(expected_method, url, anything)
        end
      end

      context "with passing requests" do
        before do
          subject.multi_receive([event])
        end

        it "should not log a failure" do
          expect(subject).not_to have_received(:log_failure).with(any_args)
        end
      end

      context "with failing requests" do
        let(:url) { "http://localhost:#{port}/bad"}

        before do
          subject.multi_receive([event])
        end

        it "should log a failure" do
          expect(subject).to have_received(:log_failure).with(any_args)
        end
      end

      context "with ignorable failing requests" do
        let(:url) { "http://localhost:#{port}/bad"}
        let(:verb_behavior_config) { super().merge("ignorable_codes" => [400]) }

        before do
          subject.multi_receive([event])
        end

        it "should log a failure" do
          expect(subject).not_to have_received(:log_failure).with(any_args)
        end
      end

      context "with retryable failing requests" do
        let(:url) { "http://localhost:#{port}/retry"}

        before do
          TestApp.retry_fail_count=2
          allow(subject).to receive(:send_event).and_call_original
          subject.multi_receive([event])
        end

        it "should log a retryable response 2 times" do
          expect(subject).to have_received(:log_retryable_response).with(any_args).twice
        end

        it "should make three total requests" do
          expect(subject).to have_received(:send_event).exactly(3).times
        end
      end
    end

    context "on retryable unknown exception" do
      before :each do
        raised = false
        original_method = subject.client.method(:send)
        allow(subject).to receive(:send_event).and_call_original
        expect(subject.client).to receive(:send) do |*args|
          unless raised
            raised = true
            raise ::Manticore::UnknownException.new("Read timed out")
          end
          original_method.call(args)
        end
        subject.multi_receive([event])
      end

      include_examples("failure log behaviour")

      it "retries" do
        expect(subject).to have_received(:send_event).exactly(2).times
      end
    end

    context "on non-retryable unknown exception" do
      before :each do
        raised = false
        original_method = subject.client.method(:send)
        allow(subject).to receive(:send_event).and_call_original
        expect(subject.client).to receive(:send) do |*args|
          unless raised
            raised = true
            raise ::Manticore::UnknownException.new("broken")
          end
          original_method.call(args)
        end
        subject.multi_receive([event])
      end

      include_examples("failure log behaviour")

      it "does not retry" do
        expect(subject).to have_received(:send_event).exactly(1).times
      end
    end

    context "on non-retryable exception" do
      before :each do
        raised = false
        original_method = subject.client.method(:send)
        allow(subject).to receive(:send_event).and_call_original
        expect(subject.client).to receive(:send) do |*args|
          unless raised
            raised = true
            raise RuntimeError.new("broken")
          end
          original_method.call(args)
        end
        subject.multi_receive([event])
      end

      include_examples("failure log behaviour")

      it "does not retry" do
        expect(subject).to have_received(:send_event).exactly(1).times
      end
    end

    context "on retryable exception" do
      before :each do
        raised = false
        original_method = subject.client.method(:send)
        allow(subject).to receive(:send_event).and_call_original
        expect(subject.client).to receive(:send) do |*args|
          unless raised
            raised = true
            raise ::Manticore::Timeout.new("broken")
          end
          original_method.call(args)
        end
        subject.multi_receive([event])
      end

      it "retries" do
        expect(subject).to have_received(:send_event).exactly(2).times
      end

      include_examples("failure log behaviour")
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

    let(:events) { [event] }

    describe "with a good code" do
      before do
        subject.multi_receive(events)
      end

      let(:last_request) { TestApp.last_request }
      let(:body) {  read_last_request_body(last_request) }
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

    describe "a retryable code" do
      let(:url) { "http://localhost:#{port}/retry" }

      before do
        TestApp.retry_fail_count=2
        allow(subject).to receive(:send_event).and_call_original
        allow(subject).to receive(:log_retryable_response)
        subject.multi_receive(events)
      end

      it "should retry" do
        expect(subject).to have_received(:log_retryable_response).with(any_args).twice
      end
    end
  end

  shared_examples "integration tests" do
    let(:base_config) { {} }
    let(:url) { "http://localhost:#{port}/good" }
    let(:event) {
      LogStash::Event.new("foo" => "bar", "baz" => "bot", "user" => "McBest")
    }

    subject { LogStash::Outputs::Http.new(config) }

    before do
      subject.register
    end

    describe "sending with the default (JSON) config" do
      let(:config) {
        base_config.merge({"url" => url, "http_method" => "post", "pool_max" => 1})
      }
      let(:expected_body) { event.to_json }
      let(:expected_content_type) { "application/json" }

      include_examples("a received event")
    end

    describe "sending the batch as JSON" do
      let(:config) do
        base_config.merge({"url" => url, "http_method" => "post", "format" => "json_batch"})
      end

      let(:expected_body) { ::LogStash::Json.dump events }
      let(:events) { [::LogStash::Event.new("a" => 1), ::LogStash::Event.new("b" => 2)]}
      let(:expected_content_type) { "application/json" }
      
      include_examples("a received event")

    end

    describe "sending the event as a form" do
      let(:config) {
        base_config.merge({"url" => url, "http_method" => "post", "pool_max" => 1, "format" => "form"})
      }
      let(:expected_body) { subject.send(:encode, event.to_hash) }
      let(:expected_content_type) { "application/x-www-form-urlencoded" }

      include_examples("a received event")
    end

    describe "sending the event as a message" do
      let(:config) {
        base_config.merge({"url" => url, "http_method" => "post", "pool_max" => 1, "format" => "message", "message" => "%{foo} AND %{baz}"})
      }
      let(:expected_body) { "#{event.get("foo")} AND #{event.get("baz")}" }
      let(:expected_content_type) { "text/plain" }

      include_examples("a received event")
    end

    describe "sending a mapped event" do
      let(:config) {
        base_config.merge({"url" => url, "http_method" => "post", "pool_max" => 1, "mapping" => {"blah" => "X %{foo}"} })
      }
      let(:expected_body) { LogStash::Json.dump("blah" => "X #{event.get("foo")}") }
      let(:expected_content_type) { "application/json" }

      include_examples("a received event")
    end

    describe "sending a mapped, nested event" do
      let(:config) {
        base_config.merge({
          "url" => url,
          "http_method" => "post",
          "pool_max" => 1,
          "mapping" => {
            "host" => "X %{foo}",
            "event" => {
              "user" => "Y %{user}"
            },
            "arrayevent" => [{
              "user" => "Z %{user}"
            }]
          }
        })
      }
      let(:expected_body) {
        LogStash::Json.dump({
          "host" => "X #{event.get("foo")}",
          "event" => {
            "user" => "Y #{event.get("user")}"
          },
          "arrayevent" => [{
            "user" => "Z #{event.get("user")}"
          }]
        })
      }
      let(:expected_content_type) { "application/json" }

      include_examples("a received event")
    end
  end

  describe "integration test without gzip compression" do
    include_examples("integration tests")
  end

  describe "integration test with gzip compression" do
    include_examples("integration tests") do
      let(:base_config) { { "http_compression" => true } }
    end
  end

  describe "retryable error in termination" do
    let(:url) { "http://localhost:#{port-1}/invalid" }
    let(:events) { [event] }
    let(:config) { {"url" => url, "http_method" => "get", "pool_max" => 1} }

    subject { LogStash::Outputs::Http.new(config) }

    before do
      subject.register
      allow(subject).to receive(:pipeline_shutdown_requested?).and_return(true)
    end

    it "raise exception to exit indefinitely retry" do
      expect { subject.multi_receive(events) }.to raise_error(LogStash::Outputs::Http::PluginInternalQueueLeftoverError)
    end
  end
end

RSpec.describe LogStash::Outputs::Http do # different block as we're starting web server with TLS

  let(:default_server_settings) { TestApp.server_settings.dup }

  before do
    TestApp.server_settings = default_server_settings.merge(webrick_config)

    TestApp.last_request = nil

    @server = start_app_and_wait(TestApp)
  end

  let(:webrick_config) do
    cert, key = WEBrick::Utils.create_self_signed_cert 2048, [["CN", ssl_cert_host]], "Logstash testing"
    {
      SSLEnable: true,
      SSLVerifyClient: OpenSSL::SSL::VERIFY_NONE,
      SSLCertificate: cert,
      SSLPrivateKey: key
    }
  end

  after do
    @server.shutdown # WEBrick::HTTPServer

    TestApp.stop! rescue nil
    TestApp.server_settings = default_server_settings
  end

  let(:ssl_cert_host) { 'localhost' }

  let(:port) { PORT }
  let(:url) { "https://localhost:#{port}/good" }
  let(:method) { "post" }

  let(:config) { { "url" => url, "http_method" => method } }

  subject { LogStash::Outputs::Http.new(config) }

  before { subject.register }
  after  { subject.close }

  let(:last_request) { TestApp.last_request }
  let(:last_request_body) { read_last_request_body(last_request) }

  let(:event) { LogStash::Event.new("message" => "hello!") }

  context 'with default (full) verification' do

    let(:config) { super() } # 'ssl_verification_mode' => 'full'

    it "does NOT process the request (due client protocol exception)" do
      # Manticore's default verification does not accept self-signed certificates!
      Thread.start do
        subject.multi_receive [ event ]
      end
      sleep 1.5

      expect(last_request).to be nil
    end

  end

  context 'with verification disabled' do

    let(:config) { super().merge 'ssl_verification_mode' => 'none' }

    it "should process the request" do
      subject.multi_receive [ event ]
      expect(last_request_body).to include '"message":"hello!"'
    end

  end

  context 'with supported_protocols set to (disabled) 1.1' do

    let(:config) { super().merge 'ssl_supported_protocols' => ['TLSv1.1'], 'ssl_verification_mode' => 'none' }

    it "keeps retrying due a protocol exception" do # TLSv1.1 not enabled by default
      expect(subject).to receive(:log_failure).
          with('Could not fetch URL', hash_including(message: 'No appropriate protocol (protocol is disabled or cipher suites are inappropriate)')).
          at_least(:once)
      Thread.start { subject.multi_receive [ event ] }
      sleep 1.0
    end

  end unless tls_version_enabled_by_default?('TLSv1.1')

  context 'with supported_protocols set to 1.2/1.3' do

    let(:config) { super().merge 'ssl_supported_protocols' => ['TLSv1.2', 'TLSv1.3'], 'ssl_verification_mode' => 'none' }

    let(:webrick_config) { super().merge SSLVersion: 'TLSv1.2' }

    it "should process the request" do
      subject.multi_receive [ event ]
      expect(last_request_body).to include '"message":"hello!"'
    end

  end

  context 'with supported_protocols set to 1.3' do

    let(:config) { super().merge 'ssl_supported_protocols' => ['TLSv1.3'], 'ssl_verification_mode' => 'none' }

    let(:webrick_config) { super().merge SSLVersion: 'TLSv1.3' }

    it "should process the request" do
      subject.multi_receive [ event ]
      expect(last_request_body).to include '"message":"hello!"'
    end

  end if tls_version_enabled_by_default?('TLSv1.3') && JOpenSSL::VERSION > '0.12' # due WEBrick uses OpenSSL

end

# Pre-emptively rewind the retrieval of `last_request.body` - for form based endpoints, the body
# is placed in params, and body is empty, requiring a `rewind` for the body to be available for comparison
def read_last_request_body(last_request)
  last_request.body.rewind
  last_request.body.read
end