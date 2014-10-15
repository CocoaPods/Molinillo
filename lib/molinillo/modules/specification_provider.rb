module Molinillo
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

    def name_for_explicit_dependency_source
      'user-specified dependency'
    end

    # Sort dependencies so that the ones that are easiest to resolve are first.
    # Easiest to resolve is (usually) defined by:
    #   1) Is this dependency already activated?
    #   2) How relaxed are the requirements?
    #   3) Are there any conflicts for this dependency?
    #   4) How many possibilities are there to satisfy this dependency?
    #
    def sort_dependencies(dependencies, activated, conflicts)
      dependencies.sort_by do |dependency|
        name = name_for(dependency)
        [
          activated.vertex_named(name).payload ? 0 : 1,
          conflicts[name] ? 0 : 1,
        ]
      end
    end
  end
end
