module Resolver
  module SpecificationProvider
    def search_for(_dependency)
      []
    end

    def requirement_satisfied_by?(_requirement, _activated, _spec)
      true
    end

    def name_for_specification(spec)
      spec.inspect
    end
  end
end
