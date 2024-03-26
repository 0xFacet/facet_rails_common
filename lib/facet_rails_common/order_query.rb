require 'order_query'

module FacetRailsCommon::OrderQuery
  extend ActiveSupport::Concern
  include ::OrderQuery

  class InvalidOrderQueryConfig < StandardError; end

  included do
    class_attribute :order_query_scopes, default: []
    class_attribute :page_key_attributes
  end

  class_methods do
    # Modified to accept a hash of order queries and a single set of key attributes
    def initialize_order_query(order_specs, page_key_attributes:)
      if page_key_attributes.blank?
        raise InvalidOrderQueryConfig, "page_key_attributes must be present"
      end
      
      self.page_key_attributes = page_key_attributes

      order_specs.each do |name, order_spec|
        order_query(name, *order_spec)
      end
    end

    def order_query(name, *spec)
      self.order_query_scopes |= [name.dup]

      super
    end
    
    def valid_order_query_scope?(name)
      return false unless name.present?
      order_query_scopes.include?(name.to_sym)
    end

    # Unified find_by_page_key method based on class-wide key attributes
    def find_by_page_key(key)
      key_values = key.split("-")
      key_hash = page_key_attributes.zip(key_values).to_h
      find_by(key_hash)
    end
  end

  # Instance method for generating a page key based on class-wide key attributes
  def page_key
    self.class.page_key_attributes.map { |attr| public_send(attr) }.join("-")
  end
end
