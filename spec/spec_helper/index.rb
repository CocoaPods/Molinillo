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
      pre_release = dependency_pre_release?(dependency)
      specs[dependency.name].reject do |spec|
        pre_release ? false : spec.version.pre_release?
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
          dependency_pre_release?(d) ? 0 : 1,
          conflicts[d.name] ? 0 : 1,
          specs[d.name].count,
        ]
      end
    end

    private

    def dependency_pre_release?(dependency)
      dependency.requirement_list.requirements.any? do |r|
        VersionKit::Version.new(r.reference_version).pre_release?
      end
    end
  end
end
