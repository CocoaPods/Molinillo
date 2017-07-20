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
      # @attr [Object] possibility the spec that was unable to be activated due
      #   to a conflict
      # @attr [Object] locked_requirement the relevant locking requirement.
      # @attr [Array<Array<Object>>] requirement_trees the different requirement
      #   trees that led to every requirement for the conflicting name.
      # @attr [{String=>Object}] activated_by_name the already-activated specs.
      Conflict = Struct.new(
        :requirement,
        :requirements,
        :existing,
        :possibility,
        :locked_requirement,
        :requirement_trees,
        :activated_by_name
      )

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
          # TODO: sorting by version here would be a lot better than relying on
          # possibilities having been inserted in the right order...
          possibilities.last
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
        @iteration_counter = 0
        @parents_of = Hash.new { |h, k| h[k] = [] }
      end

      # Resolves the {#original_requested} dependencies into a full dependency
      #   graph
      # @raise [ResolverError] if successful resolution is impossible
      # @return [DependencyGraph] the dependency graph of successfully resolved
      #   dependencies
      def resolve
        start_resolution

        while state
          break unless state.requirements.any? || state.requirement
          indicate_progress
          if state.respond_to?(:pop_possibility_state) # DependencyState
            debug(depth) { "Creating possibility state for #{requirement} (#{possibilities.count} remaining)" }
            state.pop_possibility_state.tap do |s|
              if s
                states.push(s)
                activated.tag(s)
              end
            end
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

      # Sets up the resolution process
      # @return [void]
      def start_resolution
        @started_at = Time.now

        handle_missing_or_push_dependency_state(initial_state)

        debug { "Starting resolution (#{@started_at})\nUser-requested dependencies: #{original_requested}" }
        resolver_ui.before_resolution
      end

      def resolve_activated_specs
        activated.vertices.each do |_, vertex|
          next unless vertex.payload

          latest_version = vertex.payload.possibilities.reverse_each.find do |possibility|
            vertex.requirements.uniq.all? { |req| requirement_satisfied_by?(req, activated, possibility) }
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

      require 'molinillo/state'
      require 'molinillo/modules/specification_provider'

      require 'molinillo/delegates/resolution_state'
      require 'molinillo/delegates/specification_provider'

      include Molinillo::Delegates::ResolutionState
      include Molinillo::Delegates::SpecificationProvider

      # Processes the topmost available {RequirementState} on the stack
      # @return [void]
      def process_topmost_state
        if possibility
          attempt_to_activate
        else
          create_conflict if state.is_a? PossibilityState
          unwind_for_conflict until possibility && state.is_a?(DependencyState)
        end
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

      # Creates the initial state for the resolution, based upon the
      # {#requested} dependencies
      # @return [DependencyState] the initial state for the resolution
      def initial_state
        graph = DependencyGraph.new.tap do |dg|
          original_requested.each do |requested|
            vertex = dg.add_vertex(name_for(requested), nil, true)
            vertex.explicit_requirements << requested
          end
          dg.tag(:initial_state)
        end

        requirements = sort_dependencies(original_requested, graph, {})
        initial_requirement = requirements.shift
        DependencyState.new(
          initial_requirement && name_for(initial_requirement),
          requirements,
          graph,
          initial_requirement,
          possibilities_for_requirement(initial_requirement, graph),
          0,
          {}
        )
      end

      # Unwinds the states stack because a conflict has been encountered
      # @return [void]
      def unwind_for_conflict
        debug(depth) { "Unwinding for conflict: #{requirement} to #{state_index_for_unwind / 2}" }
        conflicts.tap do |c|
          sliced_states = states.slice!((state_index_for_unwind + 1)..-1)
          raise VersionConflict.new(c) unless state
          activated.rewind_to(sliced_states.first || :initial_state) if sliced_states
          state.conflicts = c
          index = states.size - 1
          @parents_of.each { |_, a| a.reject! { |i| i >= index } }
        end
      end

      # @return [Integer] The index to which the resolution should unwind in the
      #   case of conflict.
      def state_index_for_unwind
        index = -1
        conflicts.each do |dependency_name, conflict|
          next unless activated.vertex_named(dependency_name)
          current_requirement = conflict.requirement
          existing_requirement = requirement_for_existing_name(dependency_name)
          [current_requirement, existing_requirement].each do |r|
            until r.nil?
              current_state = find_state_for(r)
              if state_any?(current_state)
                current_index = states.index(current_state)
                index = current_index if current_index > index
                break
              end
              r = parent_of(r)
            end
          end
        end

        index
      end

      # @return [Object] the requirement that led to `requirement` being added
      #   to the list of requirements.
      def parent_of(requirement)
        return unless requirement
        return unless index = @parents_of[requirement].last
        return unless parent_state = @states[index]
        parent_state.requirement
      end

      # @return [Object] the requirement that led to a version of a possibility
      #   with the given name being activated.
      def requirement_for_existing_name(name)
        return nil unless activated.vertex_named(name).payload
        states.find { |s| s.name == name }.requirement
      end

      # @return [ResolutionState] the state whose `requirement` is the given
      #   `requirement`.
      def find_state_for(requirement)
        return nil unless requirement
        states.reverse_each.find { |i| requirement == i.requirement && i.is_a?(DependencyState) }
      end

      # @return [Boolean] whether or not the given state has any possibilities
      #   left.
      def state_any?(state)
        state && state.possibilities.any?
      end

      # @return [Conflict] a {Conflict} that reflects the failure to activate
      #   the {#possibility} in conjunction with the current {#state}
      def create_conflict
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
          possibility && possibility.latest_version,
          locked_requirement,
          requirement_trees,
          activated_by_name
        )
      end

      # @return [Array<Array<Object>>] The different requirement
      #   trees that led to every requirement for the current spec.
      def requirement_trees
        vertex = activated.vertex_named(name)
        vertex.requirements.map { |r| requirement_tree_for(r) }
      end

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
          latest = possibility.latest_version
          # use reject!(!satisfied) for 1.8.7 compatibility
          possibility.possibilities.reject! do |possibility|
            !requirement_satisfied_by?(requirement, activated, possibility)
          end
          if possibility.latest_version.nil?
            # ensure there's a possibility for better error messages
            possibility.possibilities << latest if latest
            create_conflict
            unwind_for_conflict
          else
            activate_new_spec
          end
        end
      end

      # Attempts to update the existing vertex's `PossibilitySet` with a filtered version
      # @return [void]
      def attempt_to_filter_existing_spec(vertex)
        filtered_set = filtered_possibility_set(vertex)
        if !filtered_set.possibilities.empty? &&
            (vertex.payload.dependencies == dependencies_for(possibility.latest_version))
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
      # @param [Object] existing vertex
      # @return [PossibilitySet] filtered possibility set
      def filtered_possibility_set(vertex)
        # Note: we can't just look at the intersection of `vertex.payload.possibilities`
        # and `possibility.possibilities`, because if one of our requirements contains
        # a prerelease version the associated prerelease versions will only appear in
        # one set (but may match all requirements)
        filtered_old_values = vertex.payload.possibilities.select do |poss|
          requirement_satisfied_by?(requirement, activated, poss)
        end
        filtered_new_values = possibility.possibilities.select do |poss|
          vertex.requirements.uniq.all? { |req| requirement_satisfied_by?(req, activated, poss) }
        end

        PossibilitySet.new(vertex.payload.dependencies, filtered_old_values | filtered_new_values)
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
      # @param [Object] activated_possibility the PossibilitySet that has just been
      #   activated
      # @return [void]
      def require_nested_dependencies_for(possibility_set)
        nested_dependencies = dependencies_for(possibility_set.latest_version)
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
      # @return [void]
      def push_state_for_requirements(new_requirements, requires_sort = true, new_activated = activated)
        new_requirements = sort_dependencies(new_requirements.uniq, new_activated, conflicts) if requires_sort
        new_requirement = new_requirements.shift
        new_name = new_requirement ? name_for(new_requirement) : ''.freeze
        possibilities = possibilities_for_requirement(new_requirement)
        handle_missing_or_push_dependency_state DependencyState.new(
          new_name, new_requirements, new_activated,
          new_requirement, possibilities, depth, conflicts.dup
        )
      end

      # Checks a proposed requirement with any existing locked requirement
      # before generating an array of possibilities for it.
      # @param [Object] the proposed requirement
      # @return [Array] possibilities
      def possibilities_for_requirement(requirement, activated = self.activated)
        return [] unless requirement
        if locked_requirement_named(name_for(requirement))
          return locked_requirement_possibility_set(requirement, activated)
        end

        group_possibilities(search_for(requirement))
      end

      # @param [Object] the proposed requirement
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
      # dependency versions that all have the same sub-dependency version constraints.
      # @param [Array] an array of possibilities
      # @return [Array] an array of possibility sets
      def group_possibilities(possibilities)
        possibility_sets = []
        possibility_sets_index = {}

        possibilities.reverse_each do |possibility|
          dependencies = dependencies_for(possibility)
          if index = possibility_sets_index[dependencies]
            possibility_sets[index].possibilities.unshift(possibility)
          else
            possibility_sets << PossibilitySet.new(dependencies, [possibility])
            possibility_sets_index[dependencies] = possibility_sets.count - 1
          end
        end

        possibility_sets.reverse
      end

      # Pushes a new {DependencyState}.
      # If the {#specification_provider} says to
      # {SpecificationProvider#allow_missing?} that particular requirement, and
      # there are no possibilities for that requirement, then `state` is not
      # pushed, and the vertex in {#activated} is removed, and we continue
      # resolving the remaining requirements.
      # @param [DependencyState] state
      # @return [void]
      def handle_missing_or_push_dependency_state(state)
        if state.requirement && state.possibilities.empty? && allow_missing?(state.requirement)
          state.activated.detach_vertex_named(state.name)
          push_state_for_requirements(state.requirements.dup, false, state.activated)
        else
          states.push(state).tap { activated.tag(state) }
        end
      end
    end
  end
end
