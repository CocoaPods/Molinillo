# frozen_string_literal: true

# rubocop:disable Metrics/CyclomaticComplexity
# rubocop:disable Metrics/LineLength
# rubocop:disable Style/Semicolon

module Molinillo
  class NaiveResolver
    def self.resolve(index, dependencies)
      activated = Molinillo::DependencyGraph.new
      level = 0
      dependencies.each { |d| activated.add_child_vertex(d.name, nil, [nil], d) }
      activated.tag(level)
      possibilities_by_level = {}
      loop do
        vertex = activated.find { |a| !a.requirements.empty? && a.payload.nil? }
        break unless vertex
        possibilities = possibilities_by_level[level] ||= index.search_for(Gem::Dependency.new(vertex.name, '>= 0.0.0-a'))
        possibilities.select! do |spec|
          vertex.requirements.all? { |r| r.requirement.satisfied_by?(spec.version) && (!spec.version.prerelease? || r.prerelease?) } &&
            spec.dependencies.all? { |d| v = activated.vertex_named(d.name); !v || !v.payload || d.satisfied_by?(v.payload.version) }
        end
        warn "level = #{level} possibilities = #{possibilities.map(&:to_s)} requirements = #{vertex.requirements.map(&:to_s)}"
        if spec = possibilities.pop
          warn "trying #{spec}"
          activated.set_payload(vertex.name, spec)
          spec.dependencies.each do |d|
            activated.add_child_vertex(d.name, nil, [spec.name], d)
          end
          level += 1
          warn "tagging level #{level}"
          activated.tag(level)
          next
        end
        level = possibilities_by_level.reverse_each.find(proc { [-1, nil] }) { |_l, p| !p.empty? }.first
        warn "going back to level #{level}"
        possibilities_by_level.reject! { |l, _| l > level }
        return nil if level < 0
        activated.rewind_to(level)
        activated.tag(level)
      end

      activated
    end

    def self.warn(*); end
  end
end
