# encoding: utf-8
#
# based on relistan's rack handler
# out of the box rack only gives use the rack deflater handler to return compressed
# response, this gist offer the inverse and should work on all rack based app like sinatra or rails.
#
# original source: https://gist.github.com/relistan/2109707
require "zlib"

class CompressedRequests
  def initialize(app)
    @app = app
  end

  def encoding_handled?(env)
    ['gzip', 'deflate'].include? env['HTTP_CONTENT_ENCODING']
  end

  def call(env)
    if encoding_handled?(env)
      extracted = decode(env['rack.input'], env['HTTP_CONTENT_ENCODING'])

      env.delete('HTTP_CONTENT_ENCODING')
      env['CONTENT_LENGTH'] = extracted.bytesize
      env['rack.input'] = StringIO.new(extracted)
    end

    status, headers, response = @app.call(env)
    return [status, headers, response]
  end

  def decode(input, content_encoding)
    case content_encoding
      when 'gzip' then Zlib::GzipReader.new(input).read
      when 'deflate' then Zlib::Inflate.inflate(input.read)
    end
  end
end
