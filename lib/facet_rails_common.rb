# frozen_string_literal: true

require_relative "facet_rails_common/version"
require_relative "facet_rails_common/numbers_to_string"
require_relative "facet_rails_common/application_controller_methods"

if defined?(FacetVmClient)
  raise NameError, "The constant name 'FacetVmClient' is already in use. Please make sure there are no naming collisions."
end

require_relative "facet_rails_common/facet_vm_client"

module FacetRailsCommon
end
