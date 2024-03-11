module FacetRailsCommon::ApplicationControllerMethods
  extend ActiveSupport::Concern
  include FacetRailsCommon::NumbersToStrings
  
  class ::RequestedRecordNotFound < StandardError; end

  included do
    before_action :authorize_all_requests_if_required
    around_action :use_read_only_database_if_available
    rescue_from ::RequestedRecordNotFound, with: :record_not_found
    delegate :expand_cache_key, to: ActiveSupport::Cache
  end
  
  class_methods do
    def cache_actions_on_block(**options)
      around_action(**options.slice(:only, :except)) do |controller, action_block|
        controller.cache_on_block(**options.except(:only, :except)) do
          action_block.call
        end
      end
    end
  end
  
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
  
  def cache_on_block(etag: nil, max_age: 6.seconds, s_max_age: nil, cache_forever_with: nil, &block)
    unless defined?(EthBlock)
      return set_cache_control_headers(max_age: max_age, s_max_age: s_max_age, etag: etag, &block)
    end
    
    if cache_forever_with && EthBlock.respond_to?(:cached_global_block_number)
      current = EthBlock.cached_global_block_number
      diff = current - cache_forever_with
      
      if diff > 64
        max_age = [max_age, 1.hour].max
        s_max_age = [s_max_age, 1.day].max
      end
    end   
    
    etag_components = [EthBlock.most_recently_imported_blockhash, etag]
    
    set_cache_control_headers(max_age: max_age, s_max_age: s_max_age, etag: etag_components, &block)
  end
  
  def set_cache_control_headers(max_age:, s_max_age: nil, etag: nil)
    params = { public: true }
    params['s-maxage'] = s_max_age if s_max_age.present?
    
    expires_in(max_age, **params)
    
    response.headers['Vary'] = 'Authorization'
    
    if block_given?
      if etag
        version = Rails.cache.fetch("etag-version") { rand }
        
        yield if stale?(etag: expand_cache_key(etag, version), public: true)
      else
        yield
      end
    else
      raise "Need block if etag is set" if etag
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
