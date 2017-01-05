# frozen_string_literal: true
module VersionKit
  class Dependency
    attr_accessor :optional
    alias optional? optional
  end
end

module Molinillo
  class TestSpecification
    attr_accessor :name, :version, :dependencies
    def initialize(hash)
      self.name = hash['name']
      self.version = VersionKit::Version.new(hash['version'])
      self.dependencies = hash.fetch('dependencies') { Hash.new }.map do |(name, requirement)|
        requirements = requirement.split(',').map(&:chomp)
        optional = requirements.delete('optional')
        VersionKit::Dependency.new(name, requirements).tap { |d| d.optional = optional }
      end
    end

    def ==(other)
      name == other.name &&
        version == other.version &&
        dependencies == other.dependencies
    end

    def to_s
      "#{name} (#{version})"
    end

    def inspect
      "#<#{self.class} name=#{name} version=#{version} dependencies=[#{dependencies.join(', ')}]>"
    end
  end
end
