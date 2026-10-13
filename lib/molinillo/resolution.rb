# frozen_string_literal: true

module Molinillo
  class Resolver
    # A specific resolution from a given {Resolver}
    class Resolution
      # A conflict that the resolution process encountered
      # @attr [Object] requirement the requirement that immediately led to the conflict
      # @attr [{String,Nil=>[Object]}] requirements the requirements that caused the conflict
      # @attr [Object, nil] existing the existing spec that was in conflict with
      #   the {#possibility}
      # @attr [Object] possibility_set the set of specs that was unable to be
      #   activated due to a conflict.
      # @attr [Object] locked_requirement the relevant locking requirement.
      # @attr [Array<Array<Object>>] requirement_trees the different requirement
      #   trees that led to every requirement for the conflicting name.
      # @attr [{String=>Object}] activated_by_name the already-activated specs.
      # @attr [Object] underlying_error an error that has occurred during resolution, and
      #    will be raised at the end of it if no resolution is found.
      Conflict = Struct.new(
        :requirement,
        :requirements,
        :existing,
        :possibility_set,
        :locked_requirement,
        :requirement_trees,
        :activated_by_name,
        :underlying_error
      )

      class Conflict
        # @return [Object] a spec that was unable to be activated due to a conflict
        def possibility
          possibility_set && possibility_set.latest_version
        end
      end

      # A collection of possibility states that share the same dependencies
      # @attr [Array] dependencies the dependencies for this set of possibilities
      # @attr [Array] possibilities the possibilities
      PossibilitySet = Struct.new(:dependencies, :possibilities)

      class PossibilitySet
        # String representation of the possibility set, for debugging
        def to_s
          "[#{possibilities.join(', ')}]"
        end

        # @return [Object] most up-to-date dependency in the possibility set
        def latest_version
          possibilities.last
        end
      end

      # Details of the state to unwind to when a conflict occurs, and the cause of the unwind
      # @attr [Integer] state_index the index of the state to unwind to
      # @attr [Object] state_requirement the requirement of the state we're unwinding to
      # @attr [Array] requirement_tree for the requirement we're relaxing
      # @attr [Array] conflicting_requirements the requirements that combined to cause the conflict
      # @attr [Array] requirement_trees for the conflict
      # @attr [Array] requirements_unwound_to_instead array of unwind requirements that were chosen over this unwind
      UnwindDetails = Struct.new(
        :state_index,
        :state_requirement,
        :requirement_tree,
        :conflicting_requirements,
        :requirement_trees,
        :requirements_unwound_to_instead
      )

      class UnwindDetails
        include Comparable

        # We compare UnwindDetails when choosing which state to unwind to. If
        # two options have the same state_index we prefer the one most
        # removed from a requirement that caused the conflict. Both options
        # would unwind to the same state, but a `grandparent` option will
        # filter out fewer of its possibilities after doing so - where a state
        # is both a `parent` and a `grandparent` to requirements that have
        # caused a conflict this is the correct behaviour.
        # @param [UnwindDetail] other UnwindDetail to be compared
        # @return [Integer] integer specifying ordering
        def <=>(other)
          if state_index > other.state_index
            1
          elsif state_index == other.state_index
            reversed_requirement_tree_index <=> other.reversed_requirement_tree_index
          else
            -1
          end
        end

        # @return [Integer] index of state requirement in reversed requirement tree
        #    (the conflicting requirement itself will be at position 0)
        def reversed_requirement_tree_index
          @reversed_requirement_tree_index ||=
            if state_requirement
              requirement_tree.reverse.index(state_requirement)
            else
              999_999
            end
        end

        # @return [Boolean] where the requirement of the state we're unwinding
        #    to directly caused the conflict. Note: in this case, it is
        #    impossible for the state we're unwinding to be a parent of
        #    any of the other conflicting requirements (or we would have
        #    circularity)
        def unwinding_to_primary_requirement?
          requirement_tree.last == state_requirement
        end

        # @return [Array] array of sub-dependencies to avoid when choosing a
        #    new possibility for the state we've unwound to. Only relevant for
        #    non-primary unwinds
        def sub_dependencies_to_avoid
          @requirements_to_avoid ||=
            requirement_trees.map do |tree|
              index = tree.index(state_requirement)
              tree[index + 1] if index
            end.compact
        end

        # @return [Array] array of all the requirements that led to the need for
        #    this unwind
        def all_requirements
          @all_requirements ||= requirement_trees.flatten(1)
        end
      end

      # @return [SpecificationProvider] the provider that knows about
      #   dependencies, requirements, specifications, versions, etc.
      attr_reader :specification_provider

      # @return [UI] the UI that knows how to communicate feedback about the
      #   resolution process back to the user
      attr_reader :resolver_ui

      # @return [DependencyGraph] the base dependency graph to which
      #   dependencies should be 'locked'
      attr_reader :base

      # @return [Array] the dependencies that were explicitly required
      attr_reader :original_requested

      # Initializes a new resolution.
      # @param [SpecificationProvider] specification_provider
      #   see {#specification_provider}
      # @param [UI] resolver_ui see {#resolver_ui}
      # @param [Array] requested see {#original_requested}
      # @param [DependencyGraph] base see {#base}
      def initialize(specification_provider, resolver_ui, requested, base)
        @specification_provider = specification_provider
        @resolver_ui = resolver_ui
        @original_requested = requested
        @base = base
        @states = []
        @state_requirements_by_name = {}
        @iteration_counter = 0
        # Keyed by identity: requirements that are equal but come from different
        # parents must keep their own parent, whatever the provider's `eql?`.
        @parents_of = Hash.new { |h, k| h[k] = [] }.compare_by_identity
        @prune_doomed_possibilities = prune_doomed_possibilities?
        @doom_knowledge = 0
        activate_pruning if @prune_doomed_possibilities && [:eager, :adaptive].include?(prune_schedule)
        @search_results = {}.compare_by_identity
        @dependency_names = {}.compare_by_identity
        @specification_dependencies = {}.compare_by_identity
        @unwind_search_domains = {}.compare_by_identity
      end

      # Resolves the {#original_requested} dependencies into a full dependency
      #   graph
      # @raise [ResolverError] if successful resolution is impossible
      # @return [DependencyGraph] the dependency graph of successfully resolved
      #   dependencies
      def resolve
        start_resolution

        while state
          if !state.requirement && state.requirements.empty?
            break unless (vertex = unsatisfied_activated_vertex)
            unwind_for_unsatisfied_vertex(vertex)
            next
          end
          indicate_progress
          if state.respond_to?(:pop_possibility_state) # DependencyState
            push_possibility_state
          end
          process_topmost_state
        end

        resolve_activated_specs
      ensure
        end_resolution
      end

      # @return [Integer] the number of resolver iterations in between calls to
      #   {#resolver_ui}'s {UI#indicate_progress} method
      attr_accessor :iteration_rate
      private :iteration_rate

      # @return [Time] the time at which resolution began
      attr_accessor :started_at
      private :started_at

      # @return [Array<ResolutionState>] the stack of states for the resolution
      attr_accessor :states
      private :states

      private

      # Pushes the next possibility state and tags its graph before processing it.
      # @return [void]
      def push_possibility_state
        skip_doomed_possibility_sets(state) if @pruning_active && !speculating_over_budget?
        debug(depth) { "Creating possibility state for #{requirement} (#{possibilities.count} remaining)" }
        state.pop_possibility_state.tap do |s|
          if s
            push_state(s)
            activated.tag(s)
          end
        end
      end

      # Sets up the resolution process
      # @return [void]
      def start_resolution
        @started_at = Time.now

        push_initial_state

        debug { "Starting resolution (#{@started_at})\nUser-requested dependencies: #{original_requested}" }
        resolver_ui.before_resolution
      end

      # @return [DependencyGraph::Vertex, nil] an activated vertex none of
      #   whose possibilities satisfies all of its requirements, now that every
      #   requirement is known.
      def unsatisfied_activated_vertex
        activated.vertices.values.find do |vertex|
          next unless vertex.payload
          vertex.payload.possibilities.none? do |possibility|
            vertex.requirements.all? { |req| requirement_satisfied_by?(req, activated, possibility) }
          end
        end
      end

      # Creates a conflict for the given activated vertex, as if its most
      # recently processed requirement had just been found to be unsatisfiable,
      # and unwinds for it.
      # @param [DependencyGraph::Vertex] vertex
      # @return [void]
      def unwind_for_unsatisfied_vertex(vertex)
        requirement = states.reverse_each.find { |s| s.name == vertex.name }.requirement
        verification_state = PossibilityState.new(
          vertex.name, [], activated, requirement, [vertex.payload], depth, conflicts.dup, unused_unwind_options.dup
        )
        push_state(verification_state)
        activated.tag(verification_state)
        debug(depth) { "Unsatisfied by its requirements: #{vertex.payload}" }
        create_conflict
        unwind_for_conflict
      end

      def resolve_activated_specs
        activated.vertices.each do |_, vertex|
          next unless vertex.payload

          latest_version = vertex.payload.possibilities.reverse_each.find do |possibility|
            vertex.requirements.all? { |req| requirement_satisfied_by?(req, activated, possibility) }
          end

          activated.set_payload(vertex.name, latest_version)
        end
        activated.freeze
      end

      # Ends the resolution process
      # @return [void]
      def end_resolution
        resolver_ui.after_resolution
        debug do
          "Finished resolution (#{@iteration_counter} steps) " \
          "(Took #{(ended_at = Time.now) - @started_at} seconds) (#{ended_at})"
        end
        debug { 'Unactivated: ' + Hash[activated.vertices.reject { |_n, v| v.payload }].keys.join(', ') } if state
        debug { 'Activated: ' + Hash[activated.vertices.select { |_n, v| v.payload }].keys.join(', ') } if state
      end

      require_relative 'state'
      require_relative 'modules/specification_provider'

      require_relative 'delegates/resolution_state'
      require_relative 'delegates/specification_provider'

      include Molinillo::Delegates::ResolutionState
      include Molinillo::Delegates::SpecificationProvider

      # The provider contract declares these queries pure. Keep successful
      # answers local to this resolution, by input identity (not value equality
      # across requirements from different parents). Duplicate search arrays so
      # callers cannot mutate the cache or the provider's original array.
      def search_for(dependency)
        note_reached_name(dependency) if @prune_doomed_possibilities
        @search_results.fetch(dependency) do
          @search_results[dependency] = super.dup.freeze
        end.dup
      end

      def name_for(dependency)
        @dependency_names.fetch(dependency) do
          @dependency_names[dependency] = super
        end
      end

      # Only when pruning doomed possibilities, whose opt-in contract requires
      # `dependencies_for` not to depend on resolution state: the derivation
      # asks for the same specifications' dependencies many times. Without
      # the opt-in, every call still reaches the provider, as in base
      # Molinillo. Keyed by specification identity; the array is duplicated
      # on return so callers cannot mutate the cache; exceptions are never
      # cached.
      def dependencies_for(specification)
        return super unless @prune_doomed_possibilities
        @specification_dependencies.fetch(specification) do
          @specification_dependencies[specification] = super.dup.freeze
        end.dup
      end

      public :search_for, :name_for

      # Processes the topmost available {RequirementState} on the stack
      # @return [void]
      def process_topmost_state
        if possibility
          attempt_to_activate
        else
          create_conflict
          unwind_for_conflict
        end
      rescue CircularDependencyError => underlying_error
        # Once every state has been unwound, #raise_error_unless_state re-raises
        # the circular dependency error recorded on a conflict as the final
        # result; it must not be treated as a new conflict.
        raise unless state
        create_conflict(underlying_error)
        unwind_for_conflict
      end

      # @return [Object] the current possibility that the resolution is trying
      #   to activate
      def possibility
        possibilities.last
      end

      # @return [RequirementState] the current state the resolution is
      #   operating upon
      def state
        states.last
      end

      # Creates and pushes the initial state for the resolution, based upon the
      # {#requested} dependencies
      # @return [void]
      def push_initial_state
        graph = DependencyGraph.new
        requested = original_requested.reject { |r| ignorable_missing_requirement?(r, graph) }
        requested.each do |requirement|
          vertex = graph.add_vertex(name_for(requirement), nil, true)
          vertex.explicit_requirements << requirement
        end
        graph.tag(:initial_state)

        push_state_for_requirements(requested, true, graph)
      end

      # Unwinds the states stack because a conflict has been encountered
      # @return [void]
      def unwind_for_conflict
        details_for_unwind = build_details_for_unwind
        unwind_options = unused_unwind_options
        debug(depth) { "Unwinding for conflict: #{requirement} to #{details_for_unwind.state_index / 2}" }
        conflicts.tap do |c|
          sliced_states = states.slice!((details_for_unwind.state_index + 1)..-1)
          forget_states(sliced_states) if sliced_states
          raise_error_unless_state(c, sliced_states && sliced_states.last)
          activated.rewind_to(sliced_states.first || :initial_state) if sliced_states
          state.conflicts = c
          state.unused_unwind_options = unwind_options
          filter_possibilities_after_unwind(details_for_unwind)
          index = states.size - 1
          @parents_of.each { |_, a| a.reject! { |i| i >= index } }
          state.unused_unwind_options.reject! { |uw| uw.state_index >= index }
        end
      end

      # Raises a VersionConflict error, or any underlying error, if there is no
      # current state
      # @return [void]
      def raise_error_unless_state(conflicts, conflict_state = nil)
        return if state

        error = conflicts.values.map(&:underlying_error).compact.first
        pruned, other = pruning_evidence(conflicts, error)
        if error
          attach_pruning_reasons(error, conflicts, pruned, other)
          raise error
        end
        raise VersionConflict.new(conflicts, specification_provider,
                                  conflict_state && conflict_state.activated,
                                  conflict_state && conflict_state.name,
                                  pruned, other)
      end

      # Collect relevant and other pruning reasons in the original evaluation order.
      # @return [Array<Hash>]
      def pruning_evidence(conflicts, error)
        pruned = @pruning_active ? pruned_possibilities_for(conflicts, error) : {}
        other = @pruning_active ? other_pruned_possibilities_for(pruned) : {}
        [pruned, other]
      end

      # Attach pruning evidence without replacing the underlying failure.
      # @return [void]
      def attach_pruning_reasons(error, conflicts, pruned, other)
        if error.respond_to?(:pruned_possibilities=)
          error.pruned_possibilities = pruned unless pruned.empty?
          unless other.empty?
            error.other_pruned_possibilities = other
            # A circular dependency error reports the names in its cycle.
            names = error.respond_to?(:dependencies) ? error.dependencies.map { |d| name_for(d) } : conflicts.keys
            error.other_pruned_possibilities_affect_explanation =
              error.send(:other_pruned_possibilities_fail_on?, names, method(:name_for))
          end
        end
      end

      # @return [UnwindDetails] Details of the nearest index to which we could unwind
      def build_details_for_unwind
        # Get the possible unwinds for the current conflict
        current_conflict = conflicts[name]
        @set_choice_conflict_requirements = nil
        binding_requirements = binding_requirements_for_conflict(current_conflict)
        unwind_details = unwind_options_for_requirements(binding_requirements)
        if @set_choice_conflict_requirements && unwind_details.all? { |detail| detail.state_index == -1 }
          unwind_details.concat(unwind_options_for_set_choices(@set_choice_conflict_requirements, binding_requirements))
        end

        last_detail_for_current_unwind = unwind_details.sort.last
        current_detail = last_detail_for_current_unwind

        # Look for past conflicts that could be unwound to affect the
        # requirement tree for the current conflict
        all_reqs = last_detail_for_current_unwind.all_requirements
        all_reqs_size = all_reqs.size
        relevant_unused_unwinds = unused_unwind_options.select do |alternative|
          diff_reqs = all_reqs - alternative.requirements_unwound_to_instead
          next if diff_reqs.size == all_reqs_size
          # Find the highest index unwind whilst looping through
          current_detail = alternative if alternative > current_detail
          alternative
        end

        # Add the current unwind options to the `unused_unwind_options` array.
        # The "used" option will be filtered out during `unwind_for_conflict`.
        state.unused_unwind_options += unwind_details.reject { |detail| detail.state_index == -1 }

        # Update the requirements_unwound_to_instead on any relevant unused unwinds
        relevant_unused_unwinds.each do |d|
          (d.requirements_unwound_to_instead << current_detail.state_requirement).uniq!
        end
        unwind_details.each do |d|
          (d.requirements_unwound_to_instead << current_detail.state_requirement).uniq!
        end

        current_detail
      end

      # @param [Array<Object>] binding_requirements array of requirements that combine to create a conflict
      # @return [Array<UnwindDetails>] array of UnwindDetails that have a chance
      #    of resolving the passed requirements
      def unwind_options_for_requirements(binding_requirements)
        unwind_details = []

        # The ancestors of the binding requirements are shared between their
        # requirement trees (for a circular conflict, every requirement along
        # the cycle is binding), so look each one's state and stack index up
        # once instead of scanning the stack for every tree.
        states_by_requirement = {}.compare_by_identity
        state_for = lambda do |requirement|
          states_by_requirement.fetch(requirement) do
            states_by_requirement[requirement] = find_state_for(requirement)
          end
        end
        state_indices = {}.compare_by_identity
        states.each_with_index { |s, i| state_indices[s] = i }

        trees = []
        binding_requirements.reverse_each do |r|
          partial_tree = [r]
          trees << partial_tree
          unwind_details << UnwindDetails.new(-1, nil, partial_tree, binding_requirements, trees, [])

          # If this requirement has alternative possibilities, check if any would
          # satisfy the other requirements that created this conflict
          requirement_state = state_for.call(r)
          if conflict_fixing_possibilities?(requirement_state, binding_requirements)
            unwind_details << UnwindDetails.new(
              state_indices[requirement_state],
              r,
              partial_tree,
              binding_requirements,
              trees,
              []
            )
          end

          # Next, look at the parent of this requirement, and check if the requirement
          # could have been avoided if an alternative PossibilitySet had been chosen
          parent_r = parent_of(r)
          next if parent_r.nil?
          partial_tree.unshift(parent_r)
          requirement_state = state_for.call(parent_r)
          if requirement_state.possibilities.any? { |set| !set.dependencies.include?(r) }
            unwind_details << UnwindDetails.new(
              state_indices[requirement_state],
              parent_r,
              partial_tree,
              binding_requirements,
              trees,
              []
            )
          end

          # Finally, look at the grandparent and up of this requirement, looking
          # for any possibilities that wouldn't create their parent requirement
          grandparent_r = parent_of(parent_r)
          until grandparent_r.nil?
            partial_tree.unshift(grandparent_r)
            requirement_state = state_for.call(grandparent_r)
            if requirement_state.possibilities.any? { |set| !set.dependencies.include?(parent_r) }
              unwind_details << UnwindDetails.new(
                state_indices[requirement_state],
                grandparent_r,
                partial_tree,
                binding_requirements,
                trees,
                []
              )
            end
            parent_r = grandparent_r
            grandparent_r = parent_of(parent_r)
          end
        end

        unwind_details
      end

      # @param [DependencyState] state
      # @param [Array] binding_requirements array of requirements
      # @return [Boolean] whether or not the given state has any possibilities
      #    that could satisfy the given requirements
      def conflict_fixing_possibilities?(state, binding_requirements)
        return false unless state

        state.possibilities.any? do |possibility_set|
          possibility_set.possibilities.any? do |poss|
            possibility_satisfies_unwind_requirements?(poss, binding_requirements)
          end
        end
      end

      # Filter's a state's possibilities to remove any that would not fix the
      # conflict we've just rewound from
      # @param [UnwindDetails] unwind_details details of the conflict just
      #   unwound from
      # @return [void]
      def filter_possibilities_after_unwind(unwind_details)
        return unless state && !state.possibilities.empty?

        if unwind_details.unwinding_to_primary_requirement?
          filter_possibilities_for_primary_unwind(unwind_details)
        else
          filter_possibilities_for_parent_unwind(unwind_details)
        end
      end

      # Filter's a state's possibilities to remove any that would not satisfy
      # the requirements in the conflict we've just rewound from
      # @param [UnwindDetails] unwind_details details of the conflict just unwound from
      # @return [void]
      def filter_possibilities_for_primary_unwind(unwind_details)
        unwinds_to_state = unused_unwind_options.select { |uw| uw.state_index == unwind_details.state_index }
        unwinds_to_state << unwind_details
        unwind_requirement_sets = unwinds_to_state.map(&:conflicting_requirements)

        state.possibilities.reject! do |possibility_set|
          possibility_set.possibilities.none? do |poss|
            unwind_requirement_sets.any? do |requirements|
              possibility_satisfies_unwind_requirements?(poss, requirements)
            end
          end
        end
      end

      # Whether a candidate should remain available for an unwind. A queued
      # requirement can introduce dependencies that change the provider's
      # context (e.g. enabling a prerelease), so a contextual rejection is not
      # final until the queue is exhausted. Keep only candidates admitted by
      # every same-name search domain, and never relax a locked requirement.
      # Final acceptance still uses #unsatisfied_activated_vertex once all
      # requirements are known. Binding-requirement analysis stays strict.
      # @param [Object] possibility
      # @param [Array<Object>] requirements
      # @return [Boolean]
      def possibility_satisfies_unwind_requirements?(possibility, requirements)
        return true if possibility_satisfies_requirements?(possibility, requirements)
        return false if self.requirements.empty?

        name = name_for(possibility)
        locked_requirement = locked_requirement_named(name)
        requirements.all? do |requirement|
          next true unless name_for(requirement) == name
          if requirement.equal?(locked_requirement)
            possibility_satisfies_requirements?(possibility, [requirement])
          else
            begin
              unwind_search_domain_includes?(requirement, possibility)
            rescue NoSuchDependencyError
              # A missing domain cannot contain this candidate. A speculative
              # search must not replace the current conflict with a new error.
              false
            end
          end
        end
      end

      # A pure search domain may be consulted repeatedly while filtering the
      # same candidate. Index positive matches by identity, and memoize the
      # original Array#include? answer for non-identical candidates. Never use
      # spec eql?/hash as a replacement for ==: providers may only define ==.
      # Failed searches are not cached, preserving the caller's error handling.
      # @param [Object] requirement
      # @param [Object] possibility
      # @return [Boolean]
      def unwind_search_domain_includes?(requirement, possibility)
        domain = @unwind_search_domains.fetch(requirement) do
          candidates = search_for(requirement).dup
          identities = {}.compare_by_identity
          candidates.each { |candidate| identities[candidate] = true }
          @unwind_search_domains[requirement] = [candidates, identities, {}.compare_by_identity]
        end
        return true if domain[1].key?(possibility)
        domain[2].fetch(possibility) do
          domain[2][possibility] = domain[0].include?(possibility)
        end
      end

      # @param [Object] possibility a single possibility
      # @param [Array] requirements an array of requirements
      # @return [Boolean] whether the possibility satisfies all of the
      #    given requirements for its name. Requirements for other names (which
      #    the binding requirements of a circular dependency conflict include,
      #    see {#requirements_along_cycle}) do not constrain it.
      def possibility_satisfies_requirements?(possibility, requirements)
        name = name_for(possibility)

        activated.tag(:swap)
        vertex = activated.vertex_named(name)
        activated.set_payload(name, possibility) if vertex
        # Requirements on other names (e.g. along a circular dependency) say
        # nothing about this possibility, so only same-name ones are checked.
        same_name_requirements = requirements.select { |r| name_for(r) == name }
        # The requirements are checked together, so whether one of them is
        # satisfied may depend on the others being present on the vertex
        # (e.g. a prerelease requirement allowing prerelease versions).
        added = missing_context_requirements(vertex, same_name_requirements)
        vertex.explicit_requirements.concat(added) if vertex
        begin
          satisfied = same_name_requirements.all? { |r| requirement_satisfied_by?(r, activated, possibility) }
        ensure
          added.size.times { vertex.explicit_requirements.pop }
          activated.rewind_to(:swap)
        end

        satisfied
      end

      # Avoid deduplicating the entire vertex requirement list on every
      # candidate check. Exact objects already present need no augmentation.
      # Otherwise Array#- keeps the original hash/eql? membership semantics;
      # duplicates on its right-hand side do not affect the result.
      # @param [DependencyGraph::Vertex, nil] vertex
      # @param [Array<Object>] requirements
      # @return [Array<Object>]
      def missing_context_requirements(vertex, requirements)
        return [] unless vertex
        present = requirements.all? do |requirement|
          vertex.explicit_requirements.any? { |r| r.equal?(requirement) } ||
            vertex.incoming_edges.any? { |edge| edge.requirement.equal?(requirement) }
        end
        return [] if present
        raw_requirements = vertex.incoming_edges.map(&:requirement) + vertex.explicit_requirements
        requirements - raw_requirements
      end

      # Filter's a state's possibilities to remove any that would (eventually)
      # create a requirement in the conflict we've just rewound from
      # @param [UnwindDetails] unwind_details details of the conflict just unwound from
      # @return [void]
      def filter_possibilities_for_parent_unwind(unwind_details)
        unwinds_to_state = unused_unwind_options.select { |uw| uw.state_index == unwind_details.state_index }
        unwinds_to_state << unwind_details

        # Deduplicate by identity: the same UnwindDetails object can be listed
        # more than once, and hashing these structs by value (including their
        # requirement trees) is quadratic in the length of the trees. Repeated
        # entries only repeat elements of `allowed_possibility_sets` and
        # `requirements_to_avoid`, so the result is the same.
        primary_unwinds = unwinds_to_state.select(&:unwinding_to_primary_requirement?).uniq(&:object_id)
        parent_unwinds = unwinds_to_state.reject(&:unwinding_to_primary_requirement?).uniq(&:object_id)

        allowed_possibility_sets = primary_unwinds.flat_map do |unwind|
          states[unwind.state_index].possibilities.select do |possibility_set|
            possibility_set.possibilities.any? do |poss|
              possibility_satisfies_unwind_requirements?(poss, unwind.conflicting_requirements)
            end
          end
        end

        requirements_to_avoid = parent_unwinds.flat_map(&:sub_dependencies_to_avoid)

        state.possibilities.reject! do |possibility_set|
          !allowed_possibility_sets.include?(possibility_set) &&
            (requirements_to_avoid - possibility_set.dependencies).empty?
        end
      end

      # @param [Conflict] conflict
      # @return [Array] minimal array of requirements that would cause the passed
      #    conflict to occur.
      def binding_requirements_for_conflict(conflict)
        return [conflict.requirement] if conflict.possibility.nil?

        # Requirements are tracked by identity here (and below): equal requirements
        # declared by different parents lead to different unwind options, so they
        # must not be merged by a provider's value-based `eql?`/`hash`.
        possible_binding_requirements = conflict.requirements.values.flatten(1).uniq(&:object_id)

        # When there's a `CircularDependency` error the conflicting requirement
        # (the one causing the circular) won't be `conflict.requirement`
        # (which won't be for the right state, because we won't have created it,
        # because it's circular).
        # We need to make sure we have that requirement in the conflict's list,
        # otherwise we won't be able to unwind properly, so we just return all
        # the requirements for the conflict, together with the requirements
        # along the cycle: changing any state that introduced one of them could
        # break the cycle (e.g. an older version of a package that closes it).
        if conflict.underlying_error
          return (possible_binding_requirements + requirements_along_cycle(conflict.underlying_error)).uniq(&:object_id)
        end

        possibilities = search_for(conflict.requirement)

        # If all the requirements together don't filter out all possibilities,
        # then the only two requirements we need to consider are the initial one
        # (where the dependency's version was first chosen) and the last. The
        # conflict was then caused by which possibility sets were chosen, not by
        # the requirements' versions, so any later state for this name that
        # narrowed the existing possibility set by choosing one of its sets can
        # also fix it by choosing another (see #unwind_options_for_set_choices).
        if binding_requirement_in_set?(nil, possible_binding_requirements, possibilities)
          @set_choice_conflict_requirements = possible_binding_requirements
          return [conflict.requirement, requirements_for_existing_name(name_for(conflict.requirement)).first].compact
        end

        # Loop through the possible binding requirements, removing each one
        # that doesn't bind. Use a `reverse_each` as we want the earliest set of
        # binding requirements, and don't use `reject!` as we wish to refine the
        # array *on each iteration*. Only the conflicting requirement object
        # itself is always kept: other requirements that are merely equal to it
        # (e.g. the same constraint declared by several parents) are redundant
        # and must be pruned like any other, otherwise each of them becomes a
        # candidate unwind and the resolver unwinds to the most recent one,
        # which cannot fix the conflict on its own.
        binding_requirements = possible_binding_requirements.dup
        possible_binding_requirements.reverse_each do |req|
          next if req.equal?(conflict.requirement)
          unless binding_requirement_in_set?(req, binding_requirements, possibilities)
            binding_requirements = binding_requirements.reject { |r| r.equal?(req) }
          end
        end

        binding_requirements
      end

      # Unwind options for a conflict caused by the choice of possibility sets
      # (see #binding_requirements_for_conflict): the states for the conflicting
      # name, other than the binding ones, that still have a possibility set
      # satisfying all of the conflict's requirements. Only these states are
      # candidates; unlike binding requirements, their parents are not, since
      # avoiding a requirement that did not exclude any version cannot fix the
      # conflict.
      # @param [Array] conflict_requirements all of the conflict's requirements
      # @param [Array] binding_requirements the conflict's binding requirements
      # @return [Array<UnwindDetails>]
      def unwind_options_for_set_choices(conflict_requirements, binding_requirements)
        name = name_for(binding_requirements.first)
        requirements_for_existing_name(name).each_with_object([]) do |requirement, details|
          next if binding_requirements.include?(requirement)
          requirement_state = find_state_for(requirement)
          next unless conflict_fixing_possibilities?(requirement_state, conflict_requirements)
          tree = [requirement]
          details << UnwindDetails.new(
            states.index(requirement_state),
            requirement,
            tree,
            conflict_requirements,
            [tree],
            []
          )
        end
      end

      # @param [Object] requirement we wish to check
      # @param [Array] possible_binding_requirements array of requirements
      # @param [Array] possibilities array of possibilities the requirements will be used to filter
      # @return [Boolean] whether or not the given requirement is required to filter
      #    out all elements of the array of possibilities.
      def binding_requirement_in_set?(requirement, possible_binding_requirements, possibilities)
        possibilities.any? do |poss|
          possibility_satisfies_requirements?(poss, possible_binding_requirements.reject { |r| r.equal?(requirement) })
        end
      end

      # @param [CircularDependencyError] error
      # @return [Array<Object>] the requirements on the edges of the activated
      #   graph that form the cycle reported by `error`. The error's
      #   dependencies are ordered along the cycle's path (from the destination
      #   of the edge that could not be added to its origin), and the edges are
      #   still in the graph because this is called before unwinding.
      def requirements_along_cycle(error)
        return [] unless error.respond_to?(:dependencies)
        names = error.dependencies.map { |dependency| name_for(dependency) }
        names.each_cons(2).flat_map do |from, to|
          vertex = activated.vertex_named(from)
          next [] unless vertex
          vertex.outgoing_edges.select { |edge| edge.destination.name == to }.map(&:requirement)
        end
      end

      # @param [Object] requirement
      # @return [Object] the requirement that led to `requirement` being added
      #   to the list of requirements.
      def parent_of(requirement)
        return unless requirement
        return unless index = @parents_of[requirement].last
        return unless parent_state = @states[index]
        parent_state.requirement
      end

      # @param [String] name
      # @return [Array<Object>] the requirements whose states chose the
      #   possibility set of the existing spec with the given name, starting
      #   with the one that first activated it.
      def requirements_for_existing_name(name)
        return [] unless vertex = activated.vertex_named(name)
        return [] unless vertex.payload
        states.select { |s| s.name == name }.map(&:requirement).uniq
      end

      # @!group Doomed possibilities
      #
      # Only used when the provider opts in with
      # {SpecificationProvider#prune_doomed_possibilities?}; otherwise
      # {#search_for} is the provider's and none of this runs.
      #
      # A possibility is *doomed* when it cannot be part of any resolution of
      # {#original_requested}, whatever else is chosen. Doomed possibilities are
      # removed from {#search_for} results (unless every result is doomed, so
      # that conflicts are still explained in terms of real versions), so the
      # rest of the resolver -- activation, unwinding, conflict analysis --
      # behaves as if they were not in the index. A conflict caused by such a
      # possibility is thus found once, here, instead of being re-derived every
      # time the search backtracks past it. Why each pruned possibility was
      # doomed is recorded and reported by {VersionConflict}.
      #
      # A possibility is doomed if one of its dependencies (other than ones that
      # may be ignored as missing) has no viable candidate. A candidate for a
      # dependency on `name` is viable if it is not doomed and is returned by
      # `search_for` for every *forced* requirement on `name`. A requirement is
      # forced when every resolution must satisfy it: a user-requested
      # requirement, or a dependency shared by every candidate of a name that
      # is itself forced. Locks are ignored (a lock only narrows the
      # candidates, so ignoring it errs towards "viable"), except that a
      # requirement on a locked name that may be ignored as missing is never
      # forced or unviable, and locked names are never pruned. See
      # {SpecificationProvider#prune_doomed_possibilities?} for the provider
      # contracts this relies on.

      # Records that the resolver has searched for `dependency`'s name (called
      # from {#search_for} when pruning is enabled).
      # @param [Object] dependency
      # @return [void]
      def note_reached_name(dependency)
        name = name_for(dependency)
        return if reached_names.key?(name)
        reached_names[name] = true
        @doom_knowledge += 1
      end

      # Starts pruning doomed possibilities. This happens at the first conflict:
      # until then the search has never backtracked, so pruning could only
      # have saved the work of finding that first conflict, and resolutions
      # without conflicts cost nothing extra.
      # @return [void]
      def activate_pruning
        @pruning_active = true
        @doom_knowledge += 1
      end

      # Records a conflict and starts deriving facts if this is the first one.
      # @return [void]
      def record_pruning_conflict
        @conflict_count = @conflict_count.to_i + 1
        activate_pruning unless @pruning_active
      end

      # Drops the doomed possibilities from the possibility sets that `state`
      # would try next (the last ones), unless every remaining possibility is
      # doomed. Possibilities are only checked when they are about to be tried,
      # so the cost is proportional to the resolver's own work, and conflict
      # analysis still sees the provider's search results.
      # @param [DependencyState] state
      # @return [void]
      def skip_doomed_possibility_sets(state) # rubocop:disable Metrics/CyclomaticComplexity
        sets = state.possibilities
        return if sets.empty? || !state.requirement || locked_requirement_named(state.name)
        forced_requirements
        loop do
          set = sets.last
          viable = set.possibilities.reject { |p| doomed_possibility?(p) }
          return if viable.size == set.possibilities.size
          unless viable.empty?
            record_pruned_possibilities(state.name, set.possibilities - viable)
            sets[-1] = PossibilitySet.new(set.dependencies, viable)
            return
          end
          # Keep the set if every remaining possibility is doomed, so that the
          # conflict is found (and explained) with real versions.
          return unless sets[0...-1].any? { |s| s.possibilities.any? { |p| !doomed_possibility?(p) } }
          record_pruned_possibilities(state.name, set.possibilities)
          sets.pop
        end
      end

      # @param [Object] dependency
      # @return [Array] the provider's possibilities for `dependency`
      #   Searches are cached by identity and, per name and `hash`, by `==`:
      #   different versions of a package often declare equal requirements.
      #   (A requirement type whose `hash` is not consistent with `==` only
      #   misses this cache.)
      def unpruned_search_for(dependency)
        @unpruned_search_for ||= {}.compare_by_identity
        @unpruned_search_for.fetch(dependency) do
          bucket = ((@unpruned_search_for_by_value ||= {})[[name_for(dependency), dependency.hash]] ||= [])
          entry = bucket.find { |requirement, _| requirement == dependency }
          unless entry
            @derivation_work = @derivation_work.to_i + 1
            candidates = with_no_such_dependency_error_handling { specification_provider.search_for(dependency) }
            entry = [dependency, candidates]
            bucket << entry
          end
          @unpruned_search_for[dependency] = entry.last
        end
      end

      # @param [Object] possibility
      # @return [Boolean] whether `possibility` cannot be part of any resolution
      def doomed_possibility?(possibility)
        !doomed_reason(possibility).nil?
      end

      # @param [Object] possibility
      # @return [PruningReason, nil] why `possibility` cannot be part of any
      #   resolution, or nil if it is viable (as far as can be told)
      def doomed_reason(possibility)
        doomed_reason_and_blockers(possibility, unreached_depth).first
      end

      # How many levels of names the resolver has not reached yet are explored
      # by the lazy schedule.
      UNREACHED_DEPTH = 1
      # Depth used for "unlimited" exploration.
      UNLIMITED_DEPTH = 1_000_000
      private_constant :UNREACHED_DEPTH, :UNLIMITED_DEPTH

      # When and how far doomed possibilities are derived. Not a provider
      # setting: MOLINILLO_PRUNE_SCHEDULE selects it for experiments only.
      #   lazy     -- start at the first conflict, explore one level of
      #               unreached names
      #   eager    -- start immediately, explore everything reachable
      #   adaptive -- start immediately and explore everything reachable, but
      #               only while the derivation work stays within a budget:
      #               a fraction of the resolver's own work (iterations) that
      #               doubles with each conflict (1/4 before the first, up to
      #               4x after four). Over budget, no new possibility is
      #               checked and unreached names are not explored, so a
      #               resolution that never conflicts pays at most about a
      #               quarter extra, while one that keeps conflicting gets
      #               eager-like pruning.
      # @return [Symbol]
      def prune_schedule
        @prune_schedule ||= (ENV['MOLINILLO_PRUNE_SCHEDULE'] || 'lazy').to_sym
      end

      # @return [Integer] how many levels of unreached names to explore now
      def unreached_depth
        case prune_schedule
        when :eager then UNLIMITED_DEPTH
        when :adaptive
          return UNLIMITED_DEPTH unless derivation_over_budget?
          @conflict_count.to_i.zero? ? 0 : UNREACHED_DEPTH
        else UNREACHED_DEPTH
        end
      end

      # The adaptive schedule only explores beyond reached names while the
      # provider calls made to derive doomed possibilities stay within a
      # budget that grows with the resolver's own work (iterations), so its
      # cost stays within a constant factor of the unpruned search.
      # @return [Boolean]
      # Under the adaptive schedule, before the first conflict, derivation is
      # speculative and stops when over budget. After it, the adaptive
      # schedule is never weaker than the lazy one.
      # @return [Boolean]
      def speculating_over_budget?
        prune_schedule == :adaptive && @conflict_count.to_i.zero? && derivation_over_budget?
      end

      def derivation_over_budget?
        factor = 2**[@conflict_count.to_i, ADAPTIVE_MAX_DOUBLINGS].min
        @derivation_work.to_i * ADAPTIVE_INITIAL_DIVISOR > factor * (@iteration_counter + ADAPTIVE_BUDGET_BASE)
      end
      ADAPTIVE_INITIAL_DIVISOR = Integer(ENV.fetch('MOLINILLO_ADAPTIVE_DIVISOR', 4))
      ADAPTIVE_MAX_DOUBLINGS = 4
      ADAPTIVE_BUDGET_BASE = Integer(ENV.fetch('MOLINILLO_ADAPTIVE_BASE', 256))
      private_constant :ADAPTIVE_INITIAL_DIVISOR, :ADAPTIVE_MAX_DOUBLINGS, :ADAPTIVE_BUDGET_BASE

      # Names the resolver has searched for are explored fully, other names
      # only {UNREACHED_DEPTH} levels deep: beyond that, the candidates of a
      # dependency are assumed viable (unless there are none, or the forced
      # requirements exclude all of them). This keeps the cost proportional to
      # the part of the index the resolver actually visits. A "viable" answer that relied on that
      # assumption is provisional: it is reused until one of the names it
      # assumed about (its blockers) is reached.
      #
      # @param [Object] possibility
      # @param [Integer] depth how many more unreached names may be explored
      # @return [Array(PruningReason, Array<String>)] the reason `possibility`
      #   is doomed (nil if it is viable as far as can be told), and, for a
      #   provisional answer, the unreached names it depends on (empty if the
      #   answer is final)
      def doomed_reason_and_blockers(possibility, depth) # rubocop:disable Metrics/CyclomaticComplexity
        cache = (@doomed_reasons ||= {}.compare_by_identity)
        return [cache[possibility], NO_BLOCKERS] if cache.key?(possibility)
        provisional = (@provisionally_viable ||= {}.compare_by_identity)
        if (entry = provisional[possibility])
          blockers, explored_depth = entry
          # The lazy schedule reuses an answer from a shallower exploration
          # too (its depth is fixed, so that only happens within nested
          # checks); the other schedules re-explore when allowed deeper.
          reusable = prune_schedule == :lazy || explored_depth >= depth
          return [nil, blockers] if reusable && blockers.none? { |n| reached_names.key?(n) }
          provisional.delete(possibility)
        end
        # Treat a possibility as viable while its own dependencies are being
        # checked: doomed-ness is a least fixed point, so dependency cycles
        # alone never doom anything, and erring towards "viable" is always
        # sound (it only prunes less).
        cache[possibility] = nil
        blockers = NO_BLOCKERS
        @derivation_work = @derivation_work.to_i + 1
        dependencies_for(possibility).each do |dependency|
          reason, dependency_blockers = unviable_reason(possibility, dependency, depth)
          if reason
            @doom_knowledge += 1
            return [cache[possibility] = reason, NO_BLOCKERS]
          end
          blockers |= dependency_blockers unless dependency_blockers.empty?
        end
        unless blockers.empty?
          cache.delete(possibility)
          provisional[possibility] = [blockers, depth]
        end
        [nil, blockers]
      end

      # @param [Object] possibility the possibility that depends on `requirement`
      # @param [Object] requirement
      # @param [Integer] depth how many more unreached names may be explored
      # @return [Array(PruningReason, Array<String>)] why no resolution can
      #   satisfy `requirement` (nil if it can, as far as can be told), and the
      #   unreached names a provisional answer depends on
      def unviable_reason(possibility, requirement, depth) # rubocop:disable Metrics/CyclomaticComplexity
        candidates = unpruned_search_for(requirement)
        if candidates.empty?
          return [nil, NO_BLOCKERS] if allow_missing?(requirement)
          return [PruningReason.new(possibility, requirement, :missing, [], []), NO_BLOCKERS]
        end
        # For a locked name, an empty set of locked possibilities lets a
        # requirement that is allowed to be missing be ignored.
        return [nil, NO_BLOCKERS] if may_be_ignored?(requirement)

        name = name_for(requirement)
        viable = viable_candidates_for(requirement)
        excluding = viable.size < candidates.size ? forced_requirements_with_sources(name) : []
        if viable.empty?
          return [PruningReason.new(possibility, requirement, :incompatible, [], excluding), NO_BLOCKERS]
        end
        unless reached_names.key?(name)
          return [nil, [name]] if depth <= 0 || speculating_over_budget?
          depth -= 1
        end

        reasons = []
        viable.each do |candidate|
          reason, blockers = doomed_reason_and_blockers(candidate, depth)
          return [nil, blockers] unless reason
          reasons << reason
        end
        [PruningReason.new(possibility, requirement, :candidates_doomed, reasons, excluding), NO_BLOCKERS]
      end

      NO_BLOCKERS = [].freeze
      private_constant :NO_BLOCKERS

      # @return [Hash{String => true}] the names the resolver has searched for
      def reached_names
        @reached_names ||= {}
      end

      # @param [Object] requirement
      # @return [Array] the possibilities for `requirement` that also match
      #   every forced requirement on its name
      def viable_candidates_for(requirement)
        candidates = unpruned_search_for(requirement)
        cache = (@viable_candidates ||= {}.compare_by_identity)
        cache.fetch(requirement) do
          name = name_for(requirement)
          forced = forced_candidates[name]
          cache[requirement] = if forced
                                 # Membership is cached per possibility: the same
                                 # possibilities are candidates of many requirements.
                                 possibilities_in(candidates, forced)
                               else
                                 candidates
                               end
        end
      end

      # @return [Hash{String => Array}] for each name with forced requirements,
      #   the possibilities that match all of them
      def forced_candidates
        @forced_candidates ||= forced_requirements.each_with_object({}) do |(name, requirements), h|
          h[name] = requirements.map { |r, _| unpruned_search_for(r) }.reduce { |a, b| possibilities_in(a, b) }
        end
      end

      # @param [String] name
      # @return [Array<Array>] the forced requirements on `name` with their
      #   sources, as `[requirement, source]` pairs
      def forced_requirements_with_sources(name)
        forced_requirements.fetch(name, [])
      end

      # @param [Array] possibilities
      # @param [Array] others
      # @return [Array] the elements of `possibilities` that are also in
      #   `others`, compared with `eql?`/`hash` (identity for objects that do
      #   not define them). This relies on possibilities that are `==` being
      #   the same object or `eql?` (see
      #   {SpecificationProvider#prune_doomed_possibilities?}).
      def possibilities_in(possibilities, others)
        set = ((@possibility_sets ||= {}.compare_by_identity)[others] ||=
                 others.each_with_object({}) { |other, h| h[other] = true })
        possibilities.select { |p| set.key?(p) }
      end

      # @return [Hash{String => Array<Array>}] the forced requirements, by name,
      #   as `[requirement, source]` pairs. The source is the
      #   {SpecificationProvider#name_for_explicit_dependency_source} for a
      #   user request, or "every version of NAME" for a dependency that every
      #   candidate of a forced NAME declares.
      def forced_requirements # rubocop:disable Metrics/CyclomaticComplexity
        forced = (@forced_requirements ||= {})
        @forced_queue ||= original_requested.map { |r| [r, name_for_explicit_dependency_source, true] }
        # The derivation is resumable: under the adaptive schedule it stops
        # when over budget and continues later. A partial set of forced
        # requirements is sound (it only prunes less).
        until @forced_queue.empty?
          break if speculating_over_budget?
          requirement, source, unchecked = @forced_queue.shift
          @derivation_work = @derivation_work.to_i + 1
          next if unchecked && (unpruned_search_for(requirement).empty? || may_be_ignored?(requirement))
          name = name_for(requirement)
          requirements = (forced[name] ||= [])
          next if requirements.any? { |r, _| r.equal?(requirement) }
          requirements << [requirement, source]
          @forced_candidates = nil
          @viable_candidates = nil

          candidates = requirements.map { |r, _| unpruned_search_for(r) }.reduce { |a, b| possibilities_in(a, b) }
          # Doomed candidates are not excluded here (that would need a
          # traversal of everything reachable from them); sharing a dependency
          # across all candidates is then a stronger condition, so still sound.
          next if candidates.empty?
          shared = dependencies_for(candidates.first).select do |dependency|
            candidates.all? { |candidate| dependencies_for(candidate).include?(dependency) }
          end
          shared.each do |dependency|
            next if unpruned_search_for(dependency).empty? || may_be_ignored?(dependency)
            @forced_queue << [dependency, "every version of `#{name}`"]
          end
        end
        forced
      end

      # @param [Object] requirement
      # @return [Boolean] whether `requirement` has possibilities but could
      #   still be ignored as missing, because its name is locked and the
      #   provider allows it to be missing.
      def may_be_ignored?(requirement)
        locked_requirement_named(name_for(requirement)) && allow_missing?(requirement)
      end

      # @param [String] name
      # @param [Array] possibilities that were pruned from a search for `name`
      # @return [void]
      def record_pruned_possibilities(name, possibilities)
        pruned = ((@pruned_possibilities ||= {})[name] ||= [])
        possibilities.each { |p| pruned << p unless pruned.any? { |q| q.equal?(p) } }
      end

      # @param [{String => Conflict}] conflicts
      # @param [ResolverError, nil] error the underlying error being raised
      # @return [{String => Array<PruningReason>}] the pruned possibilities
      #   that are relevant to `conflicts` and `error`, and why they were
      #   pruned. A pruned possibility is relevant if
      #   - its name is a conflicting name, and it is a possibility for every
      #     requirement on that name in the conflict (so it would have been a
      #     candidate), or
      #   - its name is in one of the conflicts' requirement trees (or in the
      #     cycle of a circular dependency `error`), and it is a possibility
      #     for one of the requirements on that name there,
      #   and it is not the version the explanation already shows was chosen.
      def pruned_possibilities_for(conflicts, error = nil) # rubocop:disable Metrics/CyclomaticComplexity
        return {} unless @pruned_possibilities
        requirements_by_name = Hash.new { |h, k| h[k] = [] }
        conflict_requirements = {}
        chosen = []
        conflicts.each do |name, conflict|
          conflict_requirements[name] = conflict.requirements.values.flatten(1).
                                        reject { |r| r.equal?(conflict.locked_requirement) }
          conflict.requirement_trees.flatten(1).each { |r| requirements_by_name[name_for(r)] << r }
          chosen.concat(conflict.activated_by_name.values)
        end
        if error.respond_to?(:dependencies)
          error.dependencies.each { |d| requirements_by_name[name_for(d)] }
        end

        names = (conflict_requirements.keys + requirements_by_name.keys).uniq
        names.each_with_object({}) do |name, h|
          pruned = @pruned_possibilities[name]
          next unless pruned
          relevant = pruned.select do |possibility|
            next false if chosen.any? { |c| c.equal?(possibility) }
            if (requirements = conflict_requirements[name])
              requirements.all? { |r| !possibilities_in([possibility], unpruned_search_for(r)).empty? }
            elsif requirements_by_name[name].empty?
              true # in the cycle of a circular dependency
            else
              requirements_by_name[name].any? { |r| !possibilities_in([possibility], unpruned_search_for(r)).empty? }
            end
          end
          reasons = relevant.map { |p| doomed_reason(p) }.compact
          h[name] = reasons unless reasons.empty?
        end
      end

      # @param [{String => Array<PruningReason>}] relevant the result of
      #   {#pruned_possibilities_for}
      # @return [{String => Array<PruningReason>}] every other possibility that
      #   was pruned during the resolution, and why
      def other_pruned_possibilities_for(relevant)
        return {} unless @pruned_possibilities
        @pruned_possibilities.each_with_object({}) do |(name, pruned), h|
          reported = relevant.fetch(name, [])
          reasons = pruned.reject { |p| reported.any? { |r| r.possibility.equal?(p) } }.
                    map { |p| doomed_reason(p) }.compact
          h[name] = reasons unless reasons.empty?
        end
      end

      # @!endgroup

      # @param [Object] requirement
      # @return [ResolutionState] the state whose `requirement` is the given
      #   `requirement`.
      def find_state_for(requirement)
        return nil unless requirement
        states.find { |i| requirement == i.requirement }
      end

      # @param [Object] underlying_error
      # @return [Conflict] a {Conflict} that reflects the failure to activate
      #   the {#possibility} in conjunction with the current {#state}
      def create_conflict(underlying_error = nil)
        record_pruning_conflict if @prune_doomed_possibilities
        vertex = activated.vertex_named(name)
        locked_requirement = locked_requirement_named(name)

        requirements = {}
        unless vertex.explicit_requirements.empty?
          requirements[name_for_explicit_dependency_source] = vertex.explicit_requirements
        end
        requirements[name_for_locking_dependency_source] = [locked_requirement] if locked_requirement
        vertex.incoming_edges.each do |edge|
          (requirements[edge.origin.payload.latest_version] ||= []).unshift(edge.requirement)
        end

        activated_by_name = {}
        activated.each { |v| activated_by_name[v.name] = v.payload.latest_version if v.payload }
        conflicts[name] = Conflict.new(
          requirement,
          requirements,
          vertex.payload && vertex.payload.latest_version,
          possibility,
          locked_requirement,
          requirement_trees,
          activated_by_name,
          underlying_error
        )
      end

      # @return [Array<Array<Object>>] The different requirement
      #   trees that led to every requirement for the current spec.
      def requirement_trees
        vertex = activated.vertex_named(name)
        vertex.requirements.map { |r| requirement_tree_for(r) }
      end

      # @param [Object] requirement
      # @return [Array<Object>] the list of requirements that led to
      #   `requirement` being required.
      def requirement_tree_for(requirement)
        tree = []
        while requirement
          tree.unshift(requirement)
          requirement = parent_of(requirement)
        end
        tree
      end

      # Indicates progress roughly once every second
      # @return [void]
      def indicate_progress
        @iteration_counter += 1
        @progress_rate ||= resolver_ui.progress_rate
        if iteration_rate.nil?
          if Time.now - started_at >= @progress_rate
            self.iteration_rate = @iteration_counter
          end
        end

        if iteration_rate && (@iteration_counter % iteration_rate) == 0
          resolver_ui.indicate_progress
        end
      end

      # Calls the {#resolver_ui}'s {UI#debug} method
      # @param [Integer] depth the depth of the {#states} stack
      # @param [Proc] block a block that yields a {#to_s}
      # @return [void]
      def debug(depth = 0, &block)
        resolver_ui.debug(depth, &block)
      end

      # Attempts to activate the current {#possibility}
      # @return [void]
      def attempt_to_activate
        debug(depth) { 'Attempting to activate ' + possibility.to_s }
        existing_vertex = activated.vertex_named(name)
        if existing_vertex.payload
          debug(depth) { "Found existing spec (#{existing_vertex.payload})" }
          attempt_to_filter_existing_spec(existing_vertex)
        else
          activate_new_spec
        end
      end

      # Attempts to update the existing vertex's `PossibilitySet` with a filtered version
      # @return [void]
      def attempt_to_filter_existing_spec(vertex)
        filtered_set = filtered_possibility_set(vertex)
        if !filtered_set.possibilities.empty?
          activated.set_payload(name, filtered_set)
          new_requirements = requirements.dup
          push_state_for_requirements(new_requirements, false)
        else
          create_conflict
          debug(depth) { "Unsatisfied by existing spec (#{vertex.payload})" }
          unwind_for_conflict
        end
      end

      # Generates a filtered version of the existing vertex's `PossibilitySet` using the
      # current state's `requirement`
      # @param [Object] vertex existing vertex
      # @return [PossibilitySet] filtered possibility set
      def filtered_possibility_set(vertex)
        PossibilitySet.new(vertex.payload.dependencies, vertex.payload.possibilities & possibility.possibilities)
      end

      # @param [String] requirement_name the spec name to search for
      # @return [Object] the locked spec named `requirement_name`, if one
      #   is found on {#base}
      def locked_requirement_named(requirement_name)
        vertex = base.vertex_named(requirement_name)
        vertex && vertex.payload
      end

      # Add the current {#possibility} to the dependency graph of the current
      # {#state}
      # @return [void]
      def activate_new_spec
        conflicts.delete(name)
        debug(depth) { "Activated #{name} at #{possibility}" }
        activated.set_payload(name, possibility)
        require_nested_dependencies_for(possibility)
      end

      # Requires the dependencies that the recently activated spec has
      # @param [Object] possibility_set the PossibilitySet that has just been
      #   activated
      # @return [void]
      def require_nested_dependencies_for(possibility_set)
        nested_dependencies = dependencies_for(possibility_set.latest_version).
                              reject { |d| ignorable_missing_requirement?(d, activated) }
        debug(depth) { "Requiring nested dependencies (#{nested_dependencies.join(', ')})" }
        nested_dependencies.each do |d|
          activated.add_child_vertex(name_for(d), nil, [name_for(possibility_set.latest_version)], d)
          parent_index = states.size - 1
          parents = @parents_of[d]
          parents << parent_index if parents.empty?
        end

        push_state_for_requirements(requirements + nested_dependencies, !nested_dependencies.empty?)
      end

      # Pushes a new {DependencyState} that encapsulates both existing and new
      # requirements
      # @param [Array] new_requirements
      # @param [Boolean] requires_sort
      # @param [Object] new_activated
      # @return [void]
      def push_state_for_requirements(new_requirements, requires_sort = true, new_activated = activated)
        new_requirements = sort_dependencies(new_requirements.uniq, new_activated, conflicts) if requires_sort
        new_requirement = nil
        loop do
          new_requirement = new_requirements.shift
          break if new_requirement.nil? || !state_for_requirement?(new_requirement)
        end
        new_name = new_requirement ? name_for(new_requirement) : ''.freeze
        possibilities = possibilities_for_requirement(new_requirement)
        possibilities = try_unsatisfying_possibility_sets_last(new_requirement, possibilities, new_activated)
        handle_missing_or_push_dependency_state DependencyState.new(
          new_name, new_requirements, new_activated,
          new_requirement, possibilities, depth, conflicts.dup, unused_unwind_options.dup
        )
      end

      # Orders possibility sets so that those with no possibility satisfying
      # `requirement` in the current context are tried last. They are kept
      # rather than discarded, since whether `requirement` is satisfied can
      # depend on requirements that have not been seen yet (e.g. a prerelease
      # becoming acceptable once a prerelease requirement is added); whether a
      # possibility really satisfies all of its requirements is checked once
      # every requirement is known (see {#unsatisfied_activated_vertex}).
      # @param [Object] requirement
      # @param [Array<PossibilitySet>] possibility_sets
      # @param [DependencyGraph] activated
      # @return [Array<PossibilitySet>] the reordered possibility sets
      def try_unsatisfying_possibility_sets_last(requirement, possibility_sets, activated)
        # A partition cannot change the order of zero or one set. Do not ask
        # context-sensitive providers to recheck every version when there is
        # no ordering decision to make; final verification is still required.
        return possibility_sets if possibility_sets.size < 2
        return possibility_sets unless requirement && activated.vertex_named(name_for(requirement))

        unsatisfying, satisfying = possibility_sets.partition do |possibility_set|
          possibility_set.possibilities.none? { |p| requirement_satisfied_by?(requirement, activated, p) }
        end
        unsatisfying + satisfying
      end

      # Checks a proposed requirement with any existing locked requirement
      # before generating an array of possibilities for it.
      # @param [Object] requirement the proposed requirement
      # @param [Object] activated
      # @return [Array] possibilities
      def possibilities_for_requirement(requirement, activated = self.activated)
        return [] unless requirement
        if locked_requirement_named(name_for(requirement))
          return locked_requirement_possibility_set(requirement, activated)
        end

        group_possibilities(search_for(requirement))
      end

      # @param [Object] requirement the proposed requirement
      # @param [Object] activated
      # @return [Array] possibility set containing only the locked requirement, if any
      def locked_requirement_possibility_set(requirement, activated = self.activated)
        all_possibilities = search_for(requirement)
        locked_requirement = locked_requirement_named(name_for(requirement))

        # Longwinded way to build a possibilities array with either the locked
        # requirement or nothing in it. Required, since the API for
        # locked_requirement isn't guaranteed.
        locked_possibilities = all_possibilities.select do |possibility|
          requirement_satisfied_by?(locked_requirement, activated, possibility)
        end

        group_possibilities(locked_possibilities)
      end

      # Build an array of PossibilitySets, with each element representing a group of
      # dependency versions that all have the same sub-dependency version constraints
      # and are contiguous.
      # @param [Array] possibilities an array of possibilities
      # @return [Array<PossibilitySet>] an array of possibility sets
      def group_possibilities(possibilities)
        possibility_sets = []
        current_possibility_set = nil

        possibilities.reverse_each do |possibility|
          dependencies = dependencies_for(possibility)
          if current_possibility_set && dependencies_equal?(current_possibility_set.dependencies, dependencies)
            current_possibility_set.possibilities.unshift(possibility)
          else
            possibility_sets.unshift(PossibilitySet.new(dependencies, [possibility]))
            current_possibility_set = possibility_sets.first
          end
        end

        possibility_sets
      end

      # Pushes a new {DependencyState}.
      # If the {#specification_provider} says to
      # {SpecificationProvider#allow_missing?} that particular requirement, and
      # there are no possibilities for that requirement, then `state` is not
      # pushed, that requirement is removed from the vertex in {#activated}
      # (and the vertex itself, if nothing else requires it), and we continue
      # resolving the remaining requirements.
      # @param [DependencyState] state
      # @return [void]
      def handle_missing_or_push_dependency_state(state)
        if state.requirement && state.possibilities.empty? && allow_missing?(state.requirement)
          ignore_missing_requirement(state.activated, state.name, state.requirement)
          push_state_for_requirements(state.requirements.dup, false, state.activated)
        else
          push_state(state).tap { activated.tag(state) }
        end
      end

      # Pushes the given state onto the stack, indexing its requirement by name.
      # @param [ResolutionState] state
      # @return [Array<ResolutionState>] the stack of states
      def push_state(state)
        (@state_requirements_by_name[state.name] ||= []) << state.requirement if state.requirement
        states.push(state)
      end

      # Removes the requirements of states that have been sliced off the stack
      # from the by-name index.
      # @param [Array<ResolutionState>] sliced_states
      # @return [void]
      def forget_states(sliced_states)
        sliced_states.reverse_each do |s|
          next unless s.requirement
          reqs = @state_requirements_by_name.fetch(s.name)
          index = reqs.rindex { |r| r.equal?(s.requirement) }
          reqs.delete_at(index) if index
        end
      end

      # @param [Object] requirement
      # @return [Boolean] whether a state on the stack is for an equal requirement.
      #   Only states for the same name are compared, so this is linear in the
      #   number of states for that name rather than in the size of the stack.
      #   This assumes that requirements which are `==` have the same
      #   {SpecificationProvider#name_for}, which any provider should satisfy
      #   since a requirement's name determines the vertex it applies to.
      def state_for_requirement?(requirement)
        reqs = @state_requirements_by_name[name_for(requirement)]
        reqs ? reqs.any? { |r| r == requirement } : false
      end

      # Whether `requirement` has no possibilities and the
      # {#specification_provider} allows it to be missing, in which case it is
      # ignored before it is added to the graph: it never gets an edge (so it
      # cannot close a cycle) or an explicit requirement entry (so it never
      # takes part in conflicts).
      # @param [Object] requirement
      # @param [DependencyGraph] graph the graph the requirement would be added to
      # @return [Boolean]
      def ignorable_missing_requirement?(requirement, graph)
        return allow_missing?(requirement) if search_for(requirement).empty?
        name = name_for(requirement)
        return false unless locked_requirement_named(name)

        # For a locked name the possibilities are the search results that
        # satisfy the locked requirement, which the provider may judge in the
        # context of the vertex; check them as if the requirement had been
        # added, then undo that.
        graph.tag(:ignorable_missing_requirement)
        vertex = graph.add_vertex(name, nil, false)
        vertex.explicit_requirements << requirement
        begin
          missing = locked_requirement_possibility_set(requirement, graph).empty?
        ensure
          vertex.explicit_requirements.pop
          graph.rewind_to(:ignorable_missing_requirement)
        end
        missing && allow_missing?(requirement)
      end

      # Removes a requirement that is allowed to be missing from the vertex it
      # was added to, keeping any other requirements on that vertex. The vertex
      # is only detached once nothing requires it any more.
      # @param [DependencyGraph] graph
      # @param [String] name
      # @param [Object] requirement
      # @return [void]
      def ignore_missing_requirement(graph, name, requirement)
        return unless vertex = graph.vertex_named(name)

        # Whether a requirement has possibilities does not depend on the
        # resolution state, so this need not be undone when unwinding.
        vertex.explicit_requirements.delete(requirement)
        vertex.incoming_edges.select { |edge| edge.requirement == requirement }.each do |edge|
          graph.delete_edge(edge)
        end
        graph.detach_vertex_named(name) if vertex.requirements.empty?
      end
    end
  end
end
