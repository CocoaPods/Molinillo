module Resolver
  class ResolutionState < Struct.new(:requirements,
                                     :activated,
                                     :requirement,
                                     :possibilities,
                                     :depth,
                                     :conflicts)

    def name
      requirement.name
    end
  end
end
