module Resolver
  module SpecificationProvider
    def search_for(_dependency)
      []
    end

    def requirement_satisfied_by?(requirement, activated, spec)
      true
    end

    def name_for_specification(spec)
      spec.inspect
    end
  end
end
