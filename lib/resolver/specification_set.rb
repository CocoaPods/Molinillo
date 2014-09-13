module Resolver
  class SpecificationSet
    attr_reader :specifications, :name

    def initialize(name, specifications)
      @name = name
      @specifications = specifications
    end
  end
end
