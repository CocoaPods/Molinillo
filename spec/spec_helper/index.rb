module Resolver
  class TestIndex
    attr_accessor :specs
    include ::Resolver::SpecificationProvider

    def initialize(fixture_name)
      File.open(FIXTURE_INDEX_DIR + (fixture_name + '.json'), 'r') do |fixture|
        self.specs = JSON.load(fixture).reduce(Hash.new([])) do |specs_by_name, (name, versions)|
          specs_by_name.tap do |specs|
            specs[name] = versions.map { |s| TestSpecification.new s }.sort { |x, y| x.version <=> y.version }
          end
        end
      end
    end

    def requirement_satisfied_by?(requirement, _activated, spec)
      case requirement
      when TestSpecification
        VersionKit::Dependency.new(requirement.name, requirement.version).satisfied_by?(spec.version)
      when VersionKit::Dependency
        requirement.satisfied_by?(spec.version)
      end
    end

    def search_for(dependency)
      includes_pre_release = dependency.requirement_list.requirements.any? do |r|
        VersionKit::Version.new(r.reference_version).pre_release?
      end
      specs[dependency.name].reject do |spec|
        includes_pre_release ? false : spec.version.pre_release?
      end
    end

    def name_for(dependency)
      dependency.name
    end

    def dependencies_for(dependency)
      dependency.dependencies
    end

    def sort_dependencies(dependencies)
      dependencies.sort { |x, y| x.name <=> y.name }
    end
  end
end
