module FacetRailsCommon::ApplicationControllerMethods
  include FacetRailsCommon::NumbersToStrings
  
  class ::RequestedRecordNotFound < StandardError; end

  def self.included(base)
    base.before_action :authorize_all_requests_if_required
    base.around_action :use_read_only_database_if_available
    base.rescue_from ::RequestedRecordNotFound, with: :record_not_found
    base.delegate :expand_cache_key, to: ActiveSupport::Cache
  end
  
  private
  
  def parse_param_array(param, limit: 100)
    Array(param).map(&:to_s).map do |param|
      param =~ /\A0x([a-f0-9]{2})+\z/i ? param.downcase : param
    end.uniq.take(limit)
  end
  
  def filter_by_params(scope, *param_names)
    param_names.each do |param_name|
      param_values = parse_param_array(params[param_name])
      scope = param_values.present? ? scope.where(param_name => param_values) : scope
    end
    scope
  end
  
  def paginate(scope, results_limit: 50)
    sort_by = if params[:sort_by].present? && scope.respond_to?(params[:sort_by])
      params[:sort_by]
    else
      'newest_first'
    end
    
    if params[:reverse].present?
      sort_by += "_reverse"
    end

    max_results = (params[:max_results] || 25).to_i.clamp(1, results_limit)

    if authorized? && params[:max_results].present?
      max_results = params[:max_results].to_i
    end
    
    scope = scope.public_send(sort_by)
    
    starting_item = scope.model.find_by_page_key(params[:page_key])

    if starting_item
      scope = starting_item.public_send(sort_by, scope).after
    end

    results = scope.limit(max_results + 1).to_a
    
    has_more = results.size > max_results
    results.pop if has_more
    
    page_key = results.last&.page_key
    pagination_response = {
      page_key: page_key,
      has_more: has_more
    }
    
    [results, pagination_response, sort_by]
  end

  def authorized?
    authorization_header = request.headers['Authorization']
    return false if authorization_header.blank?
  
    token = authorization_header.remove('Bearer ').strip
    stored_tokens = JSON.parse(ENV.fetch('API_AUTH_TOKENS', "[]"))
    
    stored_tokens.include?(token)
  rescue JSON::ParserError
    Airbrake.notify("Invalid API_AUTH_TOKEN format: #{ENV.fetch('API_AUTH_TOKENS', "[]")}")
    false
  end
  
  def cache_on_block(etag: nil, max_age: 6.seconds, cache_forever_with: nil, &block)
    unless defined?(EthBlock)
      return set_cache_control_headers(max_age: max_age, etag: etag, &block)
    end
    
    if cache_forever_with && EthBlock.respond_to?(:cached_global_block_number)
      current = EthBlock.cached_global_block_number
      diff = current - cache_forever_with
      max_age = [max_age, 1.day].max if diff > 64
    end
    
    etag_components = [EthBlock.most_recently_imported_blockhash, etag]
    
    set_cache_control_headers(max_age: max_age, etag: etag_components, &block)
  end
  
  def set_cache_control_headers(max_age:, etag: nil)
    expires_in(0, "s-maxage": max_age, public: true)
    
    response.headers['Vary'] = 'Authorization'
    
    if etag
      version = Rails.cache.fetch("etag-version") { rand }
      addition = ActionController::Base.perform_caching ? '' : rand
      versioned_etag = expand_cache_key([etag, version, addition])
      
      yield if stale?(etag: versioned_etag, public: true)
    else
      yield
    end
  end
  
  def record_not_found
    render json: { error: "Not found" }, status: 404
  end
  
  def authorize_all_requests_if_required
    if ENV['REQUIRE_AUTHORIZATION'].present? && ENV['REQUIRE_AUTHORIZATION'] != 'false'
      unless authorized?
        render json: { error: "Unauthorized" }, status: :unauthorized
      end
    end
  end
  
  def use_read_only_database_if_available
    if ENV['DATABASE_REPLICA_URL'].present?
      ActiveRecord::Base.connected_to(role: :reading) { yield }
    else
      yield
    end
  end
end
