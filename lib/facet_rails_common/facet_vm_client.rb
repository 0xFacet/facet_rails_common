module ::FacetVmClient
  include FacetRailsCommon::NumbersToStrings
  
  class StaticCallError < StandardError; end
  
  def self.base_url
    ENV.fetch("FACET_VM_API_BASE_URL")
  end
  
  def self.cached_current_block_number
    Rails.cache.fetch("current_block_number", expires_in: 3.seconds) do
      FacetVm.get_status['current_block_number']
    end
  end
  
  def self.get_transaction(tx_hash)
    url = "#{base_url}/transactions/#{tx_hash}"
    res = make_request(url)['result']
  end
  
  def self.get_status
    url = "#{base_url}/status"
    make_request(url).deep_transform_values(&:to_i)
  end
  
  def self.get_historical_token_state(contract, **kwargs)
    url = "#{base_url}/tokens/#{contract}/historical_token_state"
    make_request(url, kwargs)['result']
  end
  
  def self.static_call(contract:, function:, args: nil)
    url = "#{base_url}/contracts/#{contract}/static-call/#{function}"
    res = make_request(url, { args: numbers_to_strings(args).to_json })
  
    if res["error"]
      raise StaticCallError.new(res["error"].strip)
    else
      res["result"]
    end
  end
  
  def self.make_request(url, query = {}, method: :get, post_body: nil, timeout: 5)
    headers = {}
    headers['Authorization'] = "Bearer #{bearer_token}" if bearer_token
    
    res = begin
      response = HTTParty.send(method, url, { query: query, headers: headers, timeout: timeout, body: post_body }.compact)
      
      if response.code.between?(500, 599)
        raise HTTParty::ResponseError.new(response)
      end
      
      response.parsed_response
    rescue Timeout::Error
      { error: "Not responsive after #{timeout} seconds" }
    rescue ArgumentError => e
      { error: e.message }
    end
    
    res.with_indifferent_access
  end
  
  def self.bearer_token
    ENV['INTERNAL_API_BEARER_TOKEN']
  end
end
