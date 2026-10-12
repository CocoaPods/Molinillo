# frozen_string_literal: true

module Molinillo
  # An error that occurred during the resolution process
  class ResolverError < StandardError; end

  # An error caused by searching for a dependency that is completely unknown,
  # i.e. has no versions available whatsoever.
  class NoSuchDependencyError < ResolverError
    # @return [Object] the dependency that could not be found
    attr_accessor :dependency

    # @return [Array<Object>] the specifications that depended upon {#dependency}
    attr_accessor :required_by

    # Initializes a new error with the given missing dependency.
    # @param [Object] dependency @see {#dependency}
    # @param [Array<Object>] required_by @see {#required_by}
    def initialize(dependency, required_by = [])
      @dependency = dependency
      @required_by = required_by.uniq
      super()
    end

    # The error message for the missing dependency, including the specifications
    # that had this dependency.
    def message
      sources = required_by.map { |r| "`#{r}`" }.join(' and ')
      message = "Unable to find a specification for `#{dependency}`"
      message += " depended upon by #{sources}" unless sources.empty?
      message
    end
  end

  # An error caused by attempting to fulfil a dependency that was circular
  #
  # @note This exception will be thrown if and only if a {Vertex} is added to a
  #   {DependencyGraph} that has a {DependencyGraph::Vertex#path_to?} an
  #   existing {DependencyGraph::Vertex}
  class CircularDependencyError < ResolverError
    # [Set<Object>] the dependencies responsible for causing the error
    attr_reader :dependencies

    # Initializes a new error with the given circular vertices.
    # @param [Array<DependencyGraph::Vertex>] vertices the vertices in the dependency
    #   that caused the error
    def initialize(vertices)
      super "There is a circular dependency between #{vertices.map(&:name).join(' and ')}"
      @dependencies = vertices.map { |vertex| vertex.payload.possibilities.last }.to_set
    end
  end

  # An error caused by conflicts in version
  class VersionConflict < ResolverError
    # @return [{String => Resolution::Conflict}] the conflicts that caused
    #   resolution to fail
    attr_reader :conflicts

    # @return [{String => Resolution::Conflict}] the unabridged conflicts, including
    #   all original requirement trees. Reporting copies in {#conflicts} may have
    #   redundant trees removed; their requirements remain unmodified.
    attr_reader :original_conflicts

    # @return [SpecificationProvider] the specification provider used during
    #   resolution
    attr_reader :specification_provider

    # Initializes a new error with the given version conflicts.
    # @param [{String => Resolution::Conflict}] conflicts see {#conflicts}
    # @param [SpecificationProvider] specification_provider see {#specification_provider}
    # @param [DependencyGraph, nil] conflict_graph the graph before the final unwind
    #   (without it, requirement trees are left unchanged)
    # @param [String, nil] conflict_name the final conflicting name; other cached
    #   conflicts have no reliable graph snapshot and retain their original trees
    def initialize(conflicts, specification_provider, conflict_graph = nil, conflict_name = nil)
      @original_conflicts = conflicts
      @specification_provider = specification_provider
      @conflicts = conflicts.each_with_object({}) do |(name, conflict), copies|
        copies[name] = conflict.dup
        graph = !conflict_name || conflict_name == name ? conflict_graph : nil
        copies[name].requirement_trees = explanation_trees(conflict, name, graph)
      end

      pairs = []
      @conflicts.each do |name, conflict|
        leaves = conflict.requirement_trees.map(&:last)
        pruned = conflict.requirement_trees.size < conflicts[name].requirement_trees.size
        conflict.requirements.each do |source, conflict_requirements|
          conflict_requirements.each do |r|
            next if pruned && !r.equal?(conflict.locked_requirement) && leaves.none? { |leaf| leaf.equal?(r) }
            pairs << [r, source]
          end
        end
      end

      super "Unable to satisfy the following requirements:\n\n" \
        "#{pairs.map { |r, d| "- `#{r}` required by `#{d}`" }.join("\n")}"
    end

    # Find an inclusion-minimal local explanation, with the triggering
    # requirement and lock held fixed. This is reporting only: do not use it
    # for binding requirements or mutate the live resolution graph/conflicts.
    # Keep the safety checks and deletion proof under one rescue boundary so
    # uncertain provider/context answers always retain the original evidence.
    def explanation_trees(conflict, name, graph) # rubocop:disable Metrics/CyclomaticComplexity
      trees = conflict.requirement_trees
      return trees unless graph && !conflict.underlying_error && trees.size > 1
      vertex = graph.vertex_named(name)
      return trees unless vertex
      graph_requirements = vertex.explicit_requirements + vertex.incoming_edges.map(&:requirement)
      return trees unless trees.all? { |t| !t.empty? && graph_requirements.any? { |r| r.equal?(t.last) } }
      return trees unless trees.any? { |t| t.last.equal?(conflict.requirement) }
      # Older conflicts can have a different context. Never infer a core using
      # a newer activation graph, particularly for context-sensitive providers.
      return trees unless conflict.activated_by_name.all? do |n, spec|
        v = graph.vertex_named(n)
        payload = v && v.payload
        payload = payload.latest_version if payload.respond_to?(:latest_version)
        payload == spec
      end

      possibilities = search_for(conflict.requirement)
      requirements = trees.map(&:last)
      requirements << conflict.locked_requirement if conflict.locked_requirement
      context = explanation_graph(graph)
      baseline = possibilities.map do |possibility|
        context.vertex_named(name).payload = possibility
        requirements.map { |r| requirement_satisfied_by?(r, context, possibility) }
      end
      return trees if baseline.any?(&:all?)

      kept = trees.dup
      # Drop later/transitive occurrences first; preserve explicit roots when
      # either can explain the same failure. Never subtract by value equality.
      order = trees.each_with_index.sort_by { |tree, i| [tree.size == 1 ? 0 : 1, i] }.map(&:first)
      order.reverse_each do |tree|
        next if tree.last.equal?(conflict.requirement)
        remaining = kept.reject { |t| t.equal?(tree) }
        subset = remaining.map(&:last)
        subset << conflict.locked_requirement if conflict.locked_requirement
        reduced_context = explanation_graph(graph, name, subset)
        stable = true
        satisfiable = possibilities.each_with_index.any? do |possibility, i|
          reduced_context.vertex_named(name).payload = possibility
          checks = subset.map do |r|
            original = requirements.index { |original_r| original_r.equal?(r) }
            checked = requirement_satisfied_by?(r, reduced_context, possibility)
            stable = false if checked != baseline[i][original]
            checked
          end
          checks.all?
        end
        # A deleted requirement may enable/disable a prerelease or otherwise
        # change the provider's answers: deletion minimality is unsafe then.
        return trees unless stable
        kept = remaining unless satisfiable
      end
      kept
    rescue StandardError
      # Reporting must never replace the original resolver failure with a
      # provider/context exception. Keep all evidence when a check is uncertain.
      trees
    end
    private :explanation_trees

    # Copy just the graph's vertices and edges, preserving payload/requirement
    # identities but not its action log. Even on older graph implementations,
    # reporting cannot append to or rewind the resolver's live undo history.
    def explanation_graph(graph, name = nil, requirements = nil)
      copy = DependencyGraph.new
      graph.each do |vertex|
        v = DependencyGraph::Vertex.new(vertex.name, vertex.payload)
        v.root = vertex.root?
        v.explicit_requirements.concat(vertex.explicit_requirements.select do |r|
          vertex.name != name || requirements.any? { |kept| kept.equal?(r) }
        end)
        copy.vertices[v.name] = v
      end
      graph.each do |vertex|
        vertex.outgoing_edges.each do |edge|
          next if edge.destination.name == name && requirements.none? { |kept| kept.equal?(edge.requirement) }
          origin = copy.vertex_named(edge.origin.name)
          destination = copy.vertex_named(edge.destination.name)
          e = DependencyGraph::Edge.new(origin, destination, edge.requirement)
          origin.outgoing_edges << e
          destination.incoming_edges << e
        end
      end
      copy
    end
    private :explanation_graph

    require_relative 'delegates/specification_provider'
    include Delegates::SpecificationProvider

    # @return [String] An error message that includes requirement trees,
    #   which is much more detailed & customizable than the default message
    # @param [Hash] opts the options to create a message with.
    # @option opts [String] :solver_name The user-facing name of the solver
    # @option opts [String] :possibility_type The generic name of a possibility
    # @option opts [Proc] :reduce_trees A proc that reduced the list of requirement trees
    # @option opts [Proc] :printable_requirement A proc that pretty-prints requirements
    # @option opts [Proc] :additional_message_for_conflict A proc that appends additional
    #   messages for each conflict
    # @option opts [Proc] :version_for_spec A proc that returns the version number for a
    #   possibility
    def message_with_trees(opts = {})
      solver_name = opts.delete(:solver_name) { self.class.name.split('::').first }
      possibility_type = opts.delete(:possibility_type) { 'possibility named' }
      reduce_trees = opts.delete(:reduce_trees) { proc { |trees| trees.uniq.sort_by(&:to_s) } }
      printable_requirement = opts.delete(:printable_requirement) { proc { |req| req.to_s } }
      additional_message_for_conflict = opts.delete(:additional_message_for_conflict) { proc {} }
      version_for_spec = opts.delete(:version_for_spec) { proc(&:to_s) }
      incompatible_version_message_for_conflict = opts.delete(:incompatible_version_message_for_conflict) do
        proc do |name, _conflict|
          %(#{solver_name} could not find compatible versions for #{possibility_type} "#{name}":)
        end
      end

      full_message_for_conflict = opts.delete(:full_message_for_conflict) do
        proc do |name, conflict|
          o = "\n".dup << incompatible_version_message_for_conflict.call(name, conflict) << "\n"
          if conflict.locked_requirement
            o << %(  In snapshot (#{name_for_locking_dependency_source}):\n)
            o << %(    #{printable_requirement.call(conflict.locked_requirement)}\n)
            o << %(\n)
          end
          o << %(  In #{name_for_explicit_dependency_source}:\n)
          trees = reduce_trees.call(conflict.requirement_trees)

          o << trees.map do |tree|
            t = ''.dup
            depth = 2
            tree.each do |req|
              t << '  ' * depth << printable_requirement.call(req)
              unless tree.last == req
                if spec = conflict.activated_by_name[name_for(req)]
                  t << %( was resolved to #{version_for_spec.call(spec)}, which)
                end
                t << %( depends on)
              end
              t << %(\n)
              depth += 1
            end
            t
          end.join("\n")

          additional_message_for_conflict.call(o, name, conflict)

          o
        end
      end

      conflicts.sort.reduce(''.dup) do |o, (name, conflict)|
        o << full_message_for_conflict.call(name, conflict)
      end.strip
    end
  end
end
