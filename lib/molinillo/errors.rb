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

  # Formats the possibilities that were pruned because they cannot be part of
  # any resolution (see {SpecificationProvider#prune_doomed_possibilities?}).
  module PrunedPossibilitiesMessage
    # How many possibilities {#pruned_possibilities_message} lists in its
    # section for {#other_pruned_possibilities}.
    MAX_OTHER_PRUNED_POSSIBILITIES = 5

    # @return [Boolean] whether the message lists {#other_pruned_possibilities}:
    #   only when no relevant pruned possibility is listed, or when pruning may
    #   have changed the explanation itself (see
    #   {#other_pruned_possibilities_affect_explanation?}).
    def show_other_pruned_possibilities?
      pruned_possibilities.empty? || other_pruned_possibilities_affect_explanation?
    end

    # @return [Boolean] whether one of {#other_pruned_possibilities} fails (at
    #   the end of its chain of reasons) on a name the explanation reports a
    #   conflict for. Trying such a version would have led the search into the
    #   reported conflict, so without pruning that conflict may have been
    #   explained differently (or another conflict reported).
    def other_pruned_possibilities_affect_explanation?
      @other_pruned_possibilities_affect_explanation ? true : false
    end

    # @param [String] indent prefix for every line
    # @return [String] the sections explaining {#pruned_possibilities} and
    #   then, if {#show_other_pruned_possibilities?},
    #   {#other_pruned_possibilities} (at most
    #   {MAX_OTHER_PRUNED_POSSIBILITIES} of them), each starting with two
    #   newlines, or an empty string if nothing is listed
    def pruned_possibilities_message(indent = '')
      relevant = unique_pruning_reasons(pruned_possibilities)
      other = unique_pruning_reasons(other_pruned_possibilities).
              reject { |r| relevant.any? { |o| o.possibility.equal?(r.possibility) } }
      message = ''.dup
      unless relevant.empty?
        message << "\n\n#{indent}These versions were not considered, because they cannot be part of any resolution:\n"
        message << pruning_reason_lines(relevant, indent).join("\n")
      end
      if !other.empty? && show_other_pruned_possibilities?
        message << "\n\n#{indent}Other versions that were not considered, " \
          "because they cannot be part of any resolution:\n"
        lines = pruning_reason_lines(other.first(MAX_OTHER_PRUNED_POSSIBILITIES), indent)
        more = other.size - MAX_OTHER_PRUNED_POSSIBILITIES
        lines << "#{indent}- (and #{more} more)" if more > 0
        message << lines.join("\n")
      end
      message
    end

    private

    # @param [Array<String>] conflict_names
    # @param [Proc] name_for
    # @return [Boolean] see {#other_pruned_possibilities_affect_explanation?}
    def other_pruned_possibilities_fail_on?(conflict_names, name_for)
      other_pruned_possibilities.each_value.any? do |reasons|
        reasons.any? do |reason|
          reason.failing_dependencies.any? { |d| conflict_names.include?(name_for.call(d)) }
        end
      end
    end

    def unique_pruning_reasons(pruned)
      reasons = []
      pruned.each_value do |rs|
        rs.each { |r| reasons << r unless reasons.any? { |o| o.possibility.equal?(r.possibility) } }
      end
      reasons
    end

    def pruning_reason_lines(reasons, indent)
      reasons.flat_map do |reason|
        first, *rest = reason.explanation
        ["#{indent}- #{first}"] + rest.map { |l| "#{indent}  #{l}" }
      end
    end
  end

  # An error caused by attempting to fulfil a dependency that was circular
  #
  # @note This exception will be thrown if and only if a {Vertex} is added to a
  #   {DependencyGraph} that has a {DependencyGraph::Vertex#path_to?} an
  #   existing {DependencyGraph::Vertex}
  class CircularDependencyError < ResolverError
    include PrunedPossibilitiesMessage

    # [Set<Object>] the dependencies responsible for causing the error
    attr_reader :dependencies

    # @return [{String => Array<PruningReason>}] see
    #   {VersionConflict#pruned_possibilities}
    def pruned_possibilities
      @pruned_possibilities || {}
    end
    attr_writer :pruned_possibilities

    # @return [{String => Array<PruningReason>}] see
    #   {VersionConflict#other_pruned_possibilities}
    def other_pruned_possibilities
      @other_pruned_possibilities || {}
    end
    attr_writer :other_pruned_possibilities

    # @return [Boolean] see
    #   {PrunedPossibilitiesMessage#other_pruned_possibilities_affect_explanation?}
    attr_writer :other_pruned_possibilities_affect_explanation

    # @return [String] the error message, followed by
    #   {#pruned_possibilities_message} if possibilities were pruned
    def message
      super + pruned_possibilities_message
    end

    # Initializes a new error with the given circular vertices.
    # @param [Array<DependencyGraph::Vertex>] vertices the vertices in the dependency
    #   that caused the error
    def initialize(vertices)
      super "There is a circular dependency between #{vertices.map(&:name).join(' and ')}"
      @dependencies = vertices.map { |vertex| vertex.payload.possibilities.last }.to_set
    end
  end

  # Why a possibility was pruned because it cannot be part of any resolution
  # (see {SpecificationProvider#prune_doomed_possibilities?}).
  #
  # @attr [Object] possibility the pruned possibility
  # @attr [Object] dependency the dependency of {#possibility} that no
  #   resolution can satisfy
  # @attr [Symbol] kind why {#dependency} cannot be satisfied:
  #   `:missing` (it has no possibilities at all), `:incompatible` (every
  #   possibility conflicts with one of {#excluded_by}), or
  #   `:candidates_doomed` (every remaining possibility was itself pruned, see
  #   {#candidate_reasons})
  # @attr [Array<PruningReason>] candidate_reasons for `:candidates_doomed`,
  #   why each possibility for {#dependency} was pruned
  # @attr [Array<Array>] excluded_by requirements that every resolution must
  #   satisfy and that exclude some (for `:incompatible`, all) possibilities
  #   for {#dependency}, as `[requirement, source]` pairs
  PruningReason = Struct.new(:possibility, :dependency, :kind, :candidate_reasons, :excluded_by)

  class PruningReason
    # @param [Integer] depth how many levels of {#candidate_reasons} to include
    # @param [Integer] max_candidates how many candidate reasons to include per
    #   level
    # @return [Array<String>] a human-readable explanation, one line per
    #   reason, nested reasons indented by two spaces
    def explanation(depth = 3, max_candidates = 2) # rubocop:disable Metrics/CyclomaticComplexity
      line = "`#{possibility}` depends on `#{dependency}`, ".dup
      line << case kind
              when :missing
                'which no available version satisfies'
              when :incompatible
                "but every version that satisfies it conflicts with #{excluded_by_text}"
              else
                'and every version that could satisfy it cannot be used either' +
                  (excluded_by.empty? ? '' : " (or conflicts with #{excluded_by_text})")
              end
      lines = [line]
      return lines unless kind == :candidates_doomed
      line << ':'
      if depth <= 1
        lines << '  - ...'
        return lines
      end
      candidate_reasons.first(max_candidates).each do |reason|
        first, *rest = reason.explanation(depth - 1, max_candidates)
        lines << "  - #{first}"
        rest.each { |l| lines << "  #{l}" }
      end
      more = candidate_reasons.size - max_candidates
      lines << "  - (and #{more} more)" if more > 0
      lines
    end

    # @return [Array<Object>] the dependencies at the end of this reason's
    #   chain: {#dependency} itself, or for `:candidates_doomed` the failing
    #   dependencies of {#candidate_reasons}
    def failing_dependencies
      return [dependency] unless kind == :candidates_doomed
      candidate_reasons.flat_map(&:failing_dependencies)
    end

    # @return [String] a human-readable explanation
    def to_s
      explanation.join("\n")
    end

    private

    def excluded_by_text
      excluded_by.map { |requirement, source| "`#{requirement}` (required by #{source})" }.join(' and ')
    end
  end

  # An error caused by conflicts in version
  class VersionConflict < ResolverError
    include PrunedPossibilitiesMessage

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

    # @return [{String => Array<PruningReason>}] for each name involved in the
    #   conflicts, the possibilities that were not considered because they
    #   cannot be part of any resolution, and why. Empty unless the provider
    #   opts in to {SpecificationProvider#prune_doomed_possibilities?}.
    attr_reader :pruned_possibilities

    # @return [{String => Array<PruningReason>}] every other possibility that
    #   was not considered because it cannot be part of any resolution: those
    #   not relevant to the explanation, or for names the (possibly abridged)
    #   explanation no longer mentions. Listed, up to a limit, in a trailing
    #   section of {#message} and {#message_with_trees}.
    attr_reader :other_pruned_possibilities

    # Initializes a new error with the given version conflicts.
    # @param [{String => Resolution::Conflict}] conflicts see {#conflicts}
    # @param [SpecificationProvider] specification_provider see {#specification_provider}
    # @param [DependencyGraph, nil] conflict_graph the graph before the final unwind
    #   (without it, requirement trees are left unchanged)
    # @param [String, nil] conflict_name the final conflicting name; other cached
    #   conflicts have no reliable graph snapshot and retain their original trees
    # @param [{String => Array<PruningReason>}] pruned_possibilities see {#pruned_possibilities}
    # @param [{String => Array<PruningReason>}] other_pruned_possibilities see
    #   {#other_pruned_possibilities}
    def initialize(conflicts, specification_provider, # rubocop:disable Metrics/ParameterLists
                   conflict_graph = nil, conflict_name = nil,
                   pruned_possibilities = {}, other_pruned_possibilities = {})
      @original_conflicts = conflicts
      @specification_provider = specification_provider
      @conflicts = conflicts.each_with_object({}) do |(name, conflict), copies|
        copies[name] = conflict.dup
        graph = !conflict_name || conflict_name == name ? conflict_graph : nil
        copies[name].requirement_trees = explanation_trees(conflict, name, graph)
      end
      initialize_pruned_possibilities(pruned_possibilities, other_pruned_possibilities)

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
        "#{pairs.map { |r, d| "- `#{r}` required by `#{d}`" }.join("\n")}" \
        "#{pruned_possibilities_message}"
    end

    # Retain only pruning reasons relevant to the reporting conflict.
    # @return [void]
    def initialize_pruned_possibilities(pruned_possibilities, other_pruned_possibilities)
      # Only report pruned possibilities for names that the (possibly
      # abridged) explanation still mentions.
      @pruned_possibilities = pruned_possibilities
      @other_pruned_possibilities = other_pruned_possibilities
      unless pruned_possibilities.empty?
        reported_names = @conflicts.flat_map do |name, conflict|
          [name] + conflict.requirement_trees.flatten(1).map { |r| name_for(r) }
        end
        @pruned_possibilities, dropped = pruned_possibilities.partition { |name, _| reported_names.include?(name) }.
                                         map(&:to_h)
        @other_pruned_possibilities = dropped.merge(other_pruned_possibilities) { |_, a, b| a + b }
      end
      unless @other_pruned_possibilities.empty?
        @other_pruned_possibilities_affect_explanation =
          other_pruned_possibilities_fail_on?(@conflicts.keys, method(:name_for))
      end
    end
    private :initialize_pruned_possibilities

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
    # The message ends with {#pruned_possibilities_message}, if any possibilities
    # were pruned (relevant ones first, then the others).
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

      message = conflicts.sort.reduce(''.dup) do |o, (name, conflict)|
        o << full_message_for_conflict.call(name, conflict)
      end.strip
      message << pruned_possibilities_message
    end
  end
end
