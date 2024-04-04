module FacetRailsCommon::ApplicationControllerMethods
  extend ActiveSupport::Concern
  include FacetRailsCommon::NumbersToStrings
  
  class ::RequestedRecordNotFound < StandardError; end

  included do
    before_action :authorize_short_cache
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
    valid_columns = scope.model.column_names
    
    valid_param_names = param_names.select do |name|
      valid_columns.include?(name.to_s)
    end
    
    valid_param_names.each do |param_name|
      param_values = parse_param_array(params[param_name])
      scope = param_values.present? ? scope.where(param_name => param_values) : scope
    end
    
    scope
  end
  
  def paginate(scope, results_limit: 50)
    sort_by = scope.model.valid_order_query_scope_or_default(params[:sort_by], 'newest_first')
    
    reverse = params[:reverse]&.downcase == 'true'
    
    sort_by += "_reverse" if reverse

    max_results = (params[:max_results] || 25).to_i.clamp(1, results_limit)

    if authorized? && params[:max_results].present?
      max_results = params[:max_results].to_i
    end
    
    scope = scope.public_send(sort_by)
    
    starting_item = scope.model.find_by_page_key(params[:page_key])

    if starting_item
      scope = starting_item.public_send(sort_by.delete_suffix('_reverse'), scope).side(
        reverse ? :before : :after,
        true
      )
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

  def render_paginated_json(scope)
    results, pagination_response = paginate(scope)
    
    render json: {
      result: numbers_to_strings(results),
      pagination: pagination_response
    }
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
  
  def cache_on_block(etag: nil, max_age: 6.seconds, s_max_age: nil, extend_cache_if_block_final: nil, &block)
    etag_value = if defined?(EthBlock) && EthBlock.respond_to?(:most_recently_imported_blockhash)
      [EthBlock.most_recently_imported_blockhash, etag]
    else
      etag
    end
  
    set_cache_control_headers(
      max_age: max_age,
      s_max_age: s_max_age,
      etag: etag_value,
      extend_cache_if_block_final: extend_cache_if_block_final,
      &block
    )
  end
  
  def set_cache_control_headers(max_age:, s_max_age: nil, etag: nil, extend_cache_if_block_final: nil)
    if short_cache?
      max_age = 1.second
      s_max_age = nil
    elsif extend_cache_if_block_final.present? && block_final?(extend_cache_if_block_final)
      max_age = [max_age, 1.hour].max
      s_max_age = [s_max_age, 1.day].max
    end
    
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
  
  def block_final?(resource_or_block_number)
    unless resource_or_block_number.present? && EthBlock.respond_to?(:cached_global_block_number)
      return false
    end
    
    if resource_or_block_number.respond_to?(:block_number)
      resource_or_block_number = resource_or_block_number.block_number
    end
    
    diff = EthBlock.cached_global_block_number - resource_or_block_number
    
    diff > 100
  end
  
  def record_not_found
    render json: { error: "Not found" }, status: 404
  end
  
  def short_cache?
    params[:_short_cache].present?
  end
  
  def authorize_short_cache
    if short_cache? && !authorized?
      render json: { error: "Unauthorized" }, status: :unauthorized
    end
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
