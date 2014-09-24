module Resolver
  module SpecificationProvider
    def search_for(dependency)
      []
    end

    def dependencies_for(dependency)
      []
    end

    def requirement_satisfied_by?(requirement, activated, spec)
      true
    end

    def name_for(dependency)
      dependency.inspect
    end

    def sort_dependencies(dependencies)
      dependencies
    end
  end
end
