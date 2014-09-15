module Resolver
  module SpecificationProvider
    def search_for(_specification_name)
      []
    end

    def requirement_satisfied_by?(requirement, activated, spec)
      true
    end
  end
end
