module FacetRailsCommon::NumbersToStrings
  private
  
  def numbers_to_strings(result)
    result = result.as_json

    case result
    when String
      format_decimal_or_string(result)
    when Numeric
      result.to_s
    when Hash
      result.deep_transform_values { |value| numbers_to_strings(value) }
    when Array
      result.map { |value| numbers_to_strings(value) }
    else
      result
    end
  end
  
  def format_decimal_or_string(str)
    dec = BigDecimal(str)
    
    return str unless dec.to_s == str
    
    (dec.frac.zero? ? dec.to_i : dec).to_s
  rescue ArgumentError
    str
  end
end