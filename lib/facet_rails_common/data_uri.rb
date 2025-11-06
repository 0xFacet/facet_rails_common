require "base64"
require "json"

class ::DataUri
  REGEXP = %r{
    \Adata:
    (?<mediatype>
      (?<mimetype> .+? / .+? )?
      (?<parameters> (?: ; .+? = .+? )* )
    )?
    (?<extension>;base64)?
    ,
    (?<data>.*)
  }x.freeze

  attr_reader :mimetype, :parameters, :extension, :data, :uri

  def initialize(uri)
    @uri = uri
    @match = REGEXP.match(uri)
    raise ArgumentError, 'invalid data URI' unless @match

    header_end = @match.begin(:data)
    header = header_end.nil? ? '' : uri[0...header_end]
    @header_contains_base64 = !!(header.match?(/base64/i))

    if uri.start_with?('data:,')
      @match = nil
      @mimetype = 'text/plain'
      @parameters = []
      @extension = nil
      @data = uri.split(',', 2).last || ''
    else
      @mimetype = String(@match[:mimetype]).empty? ? 'text/plain' : @match[:mimetype]
      @parameters = String(@match[:parameters]).split(';').reject(&:empty?)
      @extension = @match[:extension]
      @data = @match[:data]
      validate_base64_content
    end
  end

  def self.valid?(uri)
    begin
      DataUri.new(uri)
      true
    rescue ArgumentError
      false
    end
  end

  def self.esip6?(uri)
    begin
      parameters = DataUri.new(uri).parameters

      parameters.include?("rule=esip6")
    rescue ArgumentError
      false
    end
  end

  def validate_base64_content
    return unless claims_to_be_base64?

    raise ArgumentError, 'malformed base64 content' unless data_valid_base64?
  end

  def mediatype
    "#{mimetype}#{parameters}"
  end

  def base64?
    @header_contains_base64 && data_valid_base64?
  end
  
  def decoded_data
    base64? ? base64_decoded_data : data
  end
  
  def claims_to_be_base64?
    !String(extension).empty?
  end

  def data_valid_base64?
    !base64_decoded_data.nil?
  end
  
  def json?
    return @_json if instance_variable_defined?(:@_json)
    
    @_json = mimetype.include?('json') || decoded_data.lstrip.start_with?('{', '[')
  end
  
  def parse_json(symbolize_names: false, max_nesting: 100)
    raise ArgumentError, 'not JSON' unless json?
    JSON.parse(decoded_data, symbolize_names: symbolize_names, max_nesting: max_nesting)
  end

  private

  def base64_decoded_data
    return @base64_decoded_data if instance_variable_defined?(:@base64_decoded_data)

    @base64_decoded_data = begin
      Base64.strict_decode64(data)
    rescue ArgumentError
      nil
    end
  end
end
