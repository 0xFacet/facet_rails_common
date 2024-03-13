require 'order_query'

module FacetRailsCommon::OrderQuery
  extend ActiveSupport::Concern
  include ::OrderQuery

  included do
    class_attribute :order_query_scopes, default: []
  end

  class_methods do
    def order_query(name, *spec)
      self.order_query_scopes |= [name.dup]

      super
    end
    
    def valid_order_query_scope?(name)
      return false unless name.present?
      order_query_scopes.include?(name.to_sym)
    end
  end
end
