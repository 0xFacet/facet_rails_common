# frozen_string_literal: true

require "minitest/autorun"
require "facet_rails_common/data_uri"

class DataUriTest < Minitest::Test
  def test_decoded_data_with_base64_extension
    uri = "data:text/plain;base64,SGVsbG8="

    assert_equal "Hello", DataUri.new(uri).decoded_data
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
end
