# encoding: utf-8
require "logstash/outputs/base"
require "logstash/namespace"
require "logstash/json"

# This output lets you `PUT` or `POST` events to a
# generic HTTP(S) endpoint
#
# Additionally, you are given the option to customize
# the headers sent as well as basic customization of the
# event json itself.
class LogStash::Outputs::Http < LogStash::Outputs::Base

  config_name "http"

  # URL to use
  config :url, :validate => :string, :required => :true

  # If TLS/SSL is used (because the `url` is "https://...", then this
  # setting will determine if certificate validation is done.
  #
  # Note: If you set this to false, you will be destroying the security
  # features provided by TLS. Setting this to false is never recommended,
  # especially never in production.
  config :verify_ssl, :validate => :boolean, :default => true

  # If TLS/SSL is used (because `url` is "https://..."), then this setting
  # will determine which version of the SSL/TLS protocol is used.
  #
  # TLSv1.1 is recommended. SSLv3 is heavily discouraged and should not be used
  # but is available for legacy systems.
  config :ssl_version, :validate => [ "TLSv1", "TLSv1.1", "SSLv3" ], :default => "TLSv1.1"

  # What http request method to use. Only put and post are supported for now.
  config :http_method, :validate => ["put", "post"], :required => :true

  # Custom headers to use
  # format is `headers => ["X-My-Header", "%{host}"]`
  config :headers, :validate => :hash


  # Content type
  #
  # If not specified, this defaults to the following:
  #
  # * if format is "json", "application/json"
  # * if format is "form", "application/x-www-form-urlencoded"
  config :content_type, :validate => :string

  # This lets you choose the structure and parts of the event that are sent.
  #
  #
  # For example:
  # [source,ruby]
  #    mapping => ["foo", "%{host}", "bar", "%{type}"]
  config :mapping, :validate => :hash

  # Set the format of the http body.
  #
  # If form, then the body will be the mapping (or whole event) converted
  # into a query parameter string, e.g. `foo=bar&baz=fizz...`
  #
  # If message, then the body will be the result of formatting the event according to message
  #
  # Otherwise, the event is sent as json.
  config :format, :validate => ["json", "form", "message"], :default => "json"

  config :message, :validate => :string

  public
  def register
    require "ftw"
    require "uri"
    @agent = FTW::Agent.new
    # TODO(sissel): SSL verify mode?

    if @content_type.nil?
      case @format
        when "form" ; @content_type = "application/x-www-form-urlencoded"
        when "json" ; @content_type = "application/json"
      end
    end
    if @format == "message"
      if @message.nil?
        raise "message must be set if message format is used"
      end
      if @content_type.nil?
        raise "content_type must be set if message format is used"
      end
      unless @mapping.nil?
        @logger.warn "mapping is not supported and will be ignored if message format is used"
      end
    end

    if !@verify_ssl
      # User requests that SSL certificates are not validated, so let's
      # override the certificate verification
      class << @agent
        def certificate_verify(host, port, verified, context)
          return true
        end
      end
    end

    @agent.configuration[FTW::Agent::SSL_VERSION] = @ssl_version
  end # def register

  public
  def receive(event)
    return unless output?(event)

    if @mapping
      evt = Hash.new
      @mapping.each do |k,v|
        evt[k] = event.sprintf(v)
      end
    else
      evt = event.to_hash
    end

    case @http_method
    when "put"
      request = @agent.put(event.sprintf(@url))
    when "post"
      request = @agent.post(event.sprintf(@url))
    else
      @logger.error("Unknown verb:", :verb => @http_method)
    end

    if @headers
      @headers.each do |k,v|
        request.headers[k] = event.sprintf(v)
      end
    end

    request["Content-Type"] = @content_type

    begin
      if @format == "json"
        request.body = LogStash::Json.dump(evt)
      elsif @format == "message"
        request.body = event.sprintf(@message)
      else
        request.body = encode(evt)
      end
      #puts "#{request.port} / #{request.protocol}"
      #puts request
      #puts
      #puts request.body
      response = @agent.execute(request)

      # Consume body to let this connection be reused
      rbody = ""
      response.read_body { |c| rbody << c }
      #puts rbody
    rescue Exception => e
      @logger.warn("Unhandled exception", :request => request, :response => response, :exception => e, :stacktrace => e.backtrace)
    end
  end # def receive

  def encode(hash)
    return hash.collect do |key, value|
      CGI.escape(key) + "=" + CGI.escape(value)
    end.join("&")
  end # def encode
end
