# frozen_string_literal: true

require "minitest/autorun"
require "facet_rails_common/data_uri"

class DataUriTest < Minitest::Test
  def test_decoded_data_with_base64_extension
    uri = "data:text/plain;base64,SGVsbG8="

    assert_equal "Hello", DataUri.new(uri).decoded_data
  end
  
  def test_implicit_data_uri_defaults_and_decoding
    uri = "data:,Hello"
    du = DataUri.new(uri)
    assert_equal "text/plain", du.mimetype
    assert_equal [], du.parameters
    assert_nil du.extension
    assert_equal "Hello", du.data
    refute du.base64?
    assert_equal "Hello", du.decoded_data
  end

  def test_decoded_data_when_metadata_mentions_base64
    uri = "data:text/plain;foo=base64,SGVsbG8="

    assert_equal "Hello", DataUri.new(uri).decoded_data
  end

  def test_decoded_data_when_metadata_mentions_base64_in_mime_type
    uri = "data:application/Base64Something,SGVsbG8="

    assert_equal "Hello", DataUri.new(uri).decoded_data
  end

  def test_returns_original_data_when_metadata_mentions_base64_but_data_invalid
    uri = "data:text/plain;foo=base64,@@@"
    data_uri = DataUri.new(uri)

    refute data_uri.data_valid_base64?
    assert_equal "@@@", data_uri.decoded_data
  end

  def test_returns_original_data_when_base64_only_in_payload
    uri = "data:text/plain,base64SGVsbG8="

    assert_equal "base64SGVsbG8=", DataUri.new(uri).decoded_data
  end

  def test_invalid_base64_with_extension_raises
    uri = "data:text/plain;base64,@@@"

    error = assert_raises(ArgumentError) { DataUri.new(uri) }
    assert_equal "malformed base64 content", error.message
  end
  
  def test_valid_question_mark_true_for_valid_data_uris
    assert DataUri.valid?("data:text/plain,abc")
    assert DataUri.valid?("data:,")
    assert DataUri.valid?("data:application/json,{\"a\":1}")
  end
  
  def test_valid_question_mark_false_for_non_data_uris
    refute DataUri.valid?("http://example.com")
    refute DataUri.valid?("data;not,a,uri")
  end
  
  def test_json_helpers_by_mimetype
    uri = "data:application/json,{\"a\":1}"
    du = DataUri.new(uri)
    assert du.json?
    assert_equal({"a"=>1}, du.parse_json)
    assert_equal({a: 1}, du.parse_json(symbolize_names: true))
  end
  
  def test_json_helpers_by_payload_prefix
    json_b64 = "eyJhIjoxfQ==" # {"a":1}
    uri = "data:application/octet-stream;base64,#{json_b64}"
    du = DataUri.new(uri)
    assert du.json?
    assert_equal({"a"=>1}, du.parse_json)
  end
  
  def test_parse_json_raises_when_not_json
    du = DataUri.new("data:text/plain,hello")
    error = assert_raises(ArgumentError) { du.parse_json }
    assert_equal "not JSON", error.message
  end
  
  def test_esip6_param_detection
    assert DataUri.esip6?("data:text/plain;rule=esip6,abc")
    refute DataUri.esip6?("data:text/plain;rule=other,abc")
    refute DataUri.esip6?("not a data uri")
  end
end
