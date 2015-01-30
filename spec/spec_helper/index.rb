module Molinillo
  class TestIndex
    attr_accessor :specs
    include SpecificationProvider

    def initialize(fixture_name)
      File.open(FIXTURE_INDEX_DIR + (fixture_name + '.json'), 'r') do |fixture|
        self.specs = JSON.load(fixture).reduce(Hash.new([])) do |specs_by_name, (name, versions)|
          specs_by_name.tap do |specs|
            specs[name] = versions.map { |s| TestSpecification.new s }.sort_by(&:version)
          end
        end
      end
    end

    def requirement_satisfied_by?(requirement, _activated, spec)
      case requirement
      when TestSpecification
        Gem::Dependency.new(requirement.name, requirement.version).matches_spec?(spec)
      when Gem::Dependency
        requirement.matches_spec?(spec)
      end
    end

    def search_for(dependency)
      specs[dependency.name].select do |spec|
        (dependency.prerelease? ? true : !spec.version.prerelease?) &&
          dependency.matches_spec?(spec)
      end
    end

    def name_for(dependency)
      dependency.name
    end

    def dependencies_for(dependency)
      dependency.dependencies
    end

    def sort_dependencies(dependencies, activated, conflicts)
      dependencies.sort_by do |d|
        [
          activated.vertex_named(d.name).payload ? 0 : 1,
          d.prerelease? ? 0 : 1,
          conflicts[d.name] ? 0 : 1,
          activated.vertex_named(d.name).payload ? 0 : search_for(d).count,
        ]
      end
    end
  end
end
