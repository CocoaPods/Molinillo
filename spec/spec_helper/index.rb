# frozen_string_literal: true

module Molinillo
  FIXTURE_DIR = Pathname.new('spec/resolver_integration_specs')
  FIXTURE_INDEX_DIR = FIXTURE_DIR + 'index'

  class TestIndex
    attr_accessor :specs
    include SpecificationProvider

    def self.from_fixture(fixture_name)
      new(TestIndex.specs_from_fixture(fixture_name))
    end

    def self.specs_from_fixture(fixture_name)
      @specs_from_fixture ||= {}
      @specs_from_fixture[fixture_name] ||= File.open(FIXTURE_INDEX_DIR + (fixture_name + '.json'), 'r') do |fixture|
        JSON.load(fixture).reduce(Hash.new([])) do |specs_by_name, (name, versions)|
          specs_by_name.tap do |specs|
            specs[name] = versions.map { |s| TestSpecification.new s }.sort_by(&:version)
          end
        end
      end
    end

    def initialize(specs_by_name)
      self.specs = specs_by_name
    end

    def requirement_satisfied_by?(requirement, activated, spec)
      if spec.version.prerelease? && !requirement.prerelease?
        vertex = activated.vertex_named(spec.name)
        return false if vertex.requirements.none?(&:prerelease?)
      end

      case requirement
      when TestSpecification
        requirement.version == spec.version
      when Gem::Dependency
        requirement.requirement.satisfied_by?(spec.version)
      end
    end

    def search_for(dependency)
      @search_for ||= {}
      @search_for[dependency] ||= begin
        specs[dependency.name].select do |spec|
          dependency.requirement.satisfied_by?(spec.version)
        end
      end
      @search_for[dependency].dup
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

  class BundlerIndex < TestIndex
    # Some bugs we want to write a regression test for only occurs when
    # Molinillo processes dependencies in a specific order for the given
    # index and demands. This sorting logic ensures we hit the repro case
    def sort_dependencies(dependencies, activated, conflicts)
      dependencies.sort_by do |dependency|
        name = name_for(dependency)
        [
          activated.vertex_named(name).payload ? 0 : 1,
          amount_constrained(dependency),
          conflicts[name] ? 0 : 1,
          activated.vertex_named(name).payload ? 0 : search_for(dependency).count,
        ]
      end
    end

    def amount_constrained(dependency)
      @amount_constrained ||= {}
      @amount_constrained[dependency.name] ||= begin
        all = specs[dependency.name].size
        if all <= 1
          all - all_leq_one_penalty
        else
          search = search_for(dependency).size
          search - all
        end
      end
    end

    def all_leq_one_penalty
      1_000_000
    end
  end

  class BundlerSingleAllNoPenaltyIndex < BundlerIndex
    def all_leq_one_penalty
      0
    end
  end

  class ReverseBundlerIndex < BundlerIndex
    def sort_dependencies(*)
      super.reverse
    end
  end

  class RandomSortIndex < TestIndex
    def sort_dependencies(dependencies, _activated, _conflicts)
      dependencies.shuffle
    end
  end

  class CocoaPodsIndex < TestIndex
    def sort_dependencies(dependencies, activated, conflicts)
      dependencies.sort_by do |d|
        [
          activated.vertex_named(d.name).payload ? 0 : 1,
          d.prerelease? ? 0 : 1,
          conflicts[d.name] ? 0 : 1,
          search_for(d).count,
        ]
      end
    end

    def requirement_satisfied_by?(requirement, activated, spec) # rubocop:disable Metrics/CyclomaticComplexity
      requirement = case requirement
                    when TestSpecification
                      Gem::Dependency.new(requirement.name, requirement.version)
                    when Gem::Dependency
                      requirement
                    end

      version = spec.version
      return false unless requirement.requirement.satisfied_by?(version)
      shared_possibility_versions, prerelease_requirement = possibility_versions_for_root_name(requirement, activated)
      return false if !shared_possibility_versions.empty? && !shared_possibility_versions.include?(version)
      return false if version.prerelease? && !prerelease_requirement
      true
    end

    private

    def possibility_versions_for_root_name(requirement, activated)
      prerelease_requirement = requirement.prerelease?
      existing = activated.vertices.values.map do |vertex|
        next unless vertex.payload
        next unless vertex.name.split('/').first == requirement.name.split('/').first

        prerelease_requirement ||= vertex.requirements.any?(&:prerelease?)

        if vertex.payload.respond_to?(:possibilities)
          vertex.payload.possibilities.map(&:version)
        else
          [vertex.payload.version]
        end
      end.compact.flatten(1)

      [existing, prerelease_requirement]
    end
  end

  class BerkshelfIndex < TestIndex
    # The bug we want to write a regression test for only occurs when
    # Molinillo processes dependencies in a specific order for the given
    # index and demands. This sorting logic ensures we hit the repro case
    # when using the index file "swap_child_with_successors"
    def sort_dependencies(dependencies, activated, conflicts)
      dependencies.sort_by do |dependency|
        name = name_for(dependency)
        [
          activated.vertex_named(name).payload ? 0 : 1,
          conflicts[name] ? 0 : 1,
          activated.vertex_named(name).payload ? 0 : versions_of(name),
        ]
      end
    end

    def versions_of(dependency_name)
      Array(specs[dependency_name]).count
    end
  end

  INDICES = [
    TestIndex,
    BundlerIndex,
    ReverseBundlerIndex,
    BundlerSingleAllNoPenaltyIndex,
    RandomSortIndex,
    CocoaPodsIndex,
    BerkshelfIndex,
  ].freeze
end
