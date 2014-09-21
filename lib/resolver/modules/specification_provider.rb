module Resolver
  module SpecificationProvider
    def search_for(_dependency)
      []
    end

    def dependencies_for(_dependency)
      []
    end

    def requirement_satisfied_by?(_requirement, _activated, _spec)
      true
    end

    def name_for_dependency(dependency)
      dependency.inspect
    end

    def sort_dependencies(dependencies)
      dependencies
    end
  end
end
