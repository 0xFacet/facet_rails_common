require "base64"

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

  attr_reader :uri, :match

  def initialize(uri)
    match = REGEXP.match(uri)
    raise ArgumentError, 'invalid data URI' unless match

    @uri = uri
    @match = match
    
    validate_base64_content
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

  def is_base64?
    metadata_contains_base64? && data_valid_base64?
  end
  
  def decoded_data
    is_base64? ? base64_decoded_data : data
  end
  
  def claims_to_be_base64?
    !String(extension).empty?
  end

  def mimetype
    if String(match[:mimetype]).empty? || uri.starts_with?("data:,")
      return 'text/plain'
    end
    
    match[:mimetype]
  end
  
  def data
    match[:data]
  end

  def data_valid_base64?
    !base64_decoded_data.nil?
  end

  def parameters
    return [] if String(match[:mimetype]).empty? && String(match[:parameters]).empty?

    match[:parameters].split(";").reject(&:empty?)
  end  
  
  def extension
    match[:extension]
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

  def metadata_contains_base64?
    header_end = match.begin(:data)
    return false if header_end.nil?

    uri[0...header_end].match?(/base64/i)
  end
end
