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
        :activated_by_name,
        :root_error
      )

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

        activated.freeze
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
          begin
            attempt_to_activate
          rescue CircularDependencyError => e
            create_conflict(e)
            unwind_for_conflict until possibility && state.is_a?(DependencyState)
          end
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
          original_requested.each { |r| dg.add_vertex(name_for(r), nil, true).tap { |v| v.explicit_requirements << r } }
          dg.tag(:initial_state)
        end

        requirements = sort_dependencies(original_requested, graph, {})
        initial_requirement = requirements.shift
        DependencyState.new(
          initial_requirement && name_for(initial_requirement),
          requirements,
          graph,
          initial_requirement,
          initial_requirement && search_for(initial_requirement),
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
          unless state
            error = c.values.map(&:root_error).detect {|e| ! e.nil? }
            raise error || VersionConflict.new(c)
          end
          activated.rewind_to(sliced_states.first || :initial_state) if sliced_states
          state.conflicts = c
          index = states.size - 1
          @parents_of.each { |_, a| a.reject! { |i| i >= index } }
        end
      end

      # @return [Integer] The index to which the resolution should unwind in the
      #   case of conflict.
      def state_index_for_unwind
        # TODO maybe move all this somewhere else
        conflict_set = Set.new
        conflicts.each do |key, conflict|
          conflict_set.add key

          parents = conflict.requirements.keys.select do |parent|
            parent.is_a?(TestSpecification)
          end.map {|p| name_for(p) }
          conflict_set.merge parents

          parents.map do |name|
            predecessors = activated.vertex_named(name).recursive_predecessors
            conflict_set.merge predecessors.map {|p| name_for(p) }
          end
        end

        index = states.size - 2
        until index < 0
          current_state = @states[index]
          if current_state.conflict_set
            conflict_set.merge current_state.conflict_set
          end
          if (
              current_state.is_a?(DependencyState) &&
              state_any?(current_state) &&
              conflict_set.include?(current_state.name)
          )
            current_state.conflict_set = conflict_set.dup
            return index
          end
          index -= 1
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
      def create_conflict(root_error=nil)
        vertex = activated.vertex_named(name)
        locked_requirement = locked_requirement_named(name)

        requirements = {}
        unless vertex.explicit_requirements.empty?
          requirements[name_for_explicit_dependency_source] = vertex.explicit_requirements
        end
        requirements[name_for_locking_dependency_source] = [locked_requirement] if locked_requirement
        vertex.incoming_edges.each { |edge| (requirements[edge.origin.payload] ||= []).unshift(edge.requirement) }

        activated_by_name = {}
        activated.each { |v| activated_by_name[v.name] = v.payload if v.payload }
        conflicts[name] = Conflict.new(
          requirement,
          requirements,
          vertex.payload,
          possibility,
          locked_requirement,
          requirement_trees,
          activated_by_name,
          root_error
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
        existing_node = activated.vertex_named(name)
        if existing_node.payload
          debug(depth) { "Found existing spec (#{existing_node.payload})" }
          attempt_to_activate_existing_spec(existing_node)
        else
          attempt_to_activate_new_spec
        end
      end

      # Attempts to activate the current {#possibility} (given that it has
      # already been activated)
      # @return [void]
      def attempt_to_activate_existing_spec(existing_node)
        existing_spec = existing_node.payload
        if requirement_satisfied_by?(requirement, activated, existing_spec)
          new_requirements = requirements.dup
          push_state_for_requirements(new_requirements)
        else
          create_conflict
          debug(depth) { "Unsatisfied by existing spec (#{existing_node.payload})" }
          unwind_for_conflict
        end
      end

      # Attempts to activate the current {#possibility} (given that it hasn't
      # already been activated)
      # @return [void]
      def attempt_to_activate_new_spec
        if new_spec_satisfied?
          activate_spec
        else
          create_conflict
          unwind_for_conflict
        end
      end

      # @return [Boolean] whether the current spec is satisfied as a new
      # possibility.
      def new_spec_satisfied?
        unless requirement_satisfied_by?(requirement, activated, possibility)
          debug(depth) { 'Unsatisfied by requested spec' }
          return false
        end

        locked_requirement = locked_requirement_named(name)

        locked_spec_satisfied = !locked_requirement ||
          requirement_satisfied_by?(locked_requirement, activated, possibility)
        debug(depth) { 'Unsatisfied by locked spec' } unless locked_spec_satisfied

        locked_spec_satisfied
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
      def activate_spec
        conflicts.delete(name)
        debug(depth) { "Activated #{name} at #{possibility}" }
        activated.set_payload(name, possibility)
        require_nested_dependencies_for(possibility)
      end

      # Requires the dependencies that the recently activated spec has
      # @param [Object] activated_spec the specification that has just been
      #   activated
      # @return [void]
      def require_nested_dependencies_for(activated_spec)
        nested_dependencies = dependencies_for(activated_spec)
        debug(depth) { "Requiring nested dependencies (#{nested_dependencies.join(', ')})" }
        nested_dependencies.each do |d|
          activated.add_child_vertex(name_for(d), nil, [name_for(activated_spec)], d)
          parent_index = states.size - 1
          parents = @parents_of[d]
          parents << parent_index if parents.empty?
        end

        push_state_for_new_requirements(requirements + nested_dependencies)
      end

      def push_state_for_new_requirements(requirements)
        requirements = sort_dependencies(requirements, activated, conflicts)
        idx = 0
        requirements.sort_by! do |r|
          idx += 1
          existing_node = activated.vertex_named(r.name)
          [
            original_requested.include?(r) ? 0 : 1,
            existing_node && existing_node.payload ? 0 : 1,
            idx
          ]
        end
        push_state_for_requirements(requirements)
      end

      # Pushes a new {DependencyState} that encapsulates both existing and new
      # requirements
      # @param [Array] new_requirements
      # @return [void]
      def push_state_for_requirements(new_requirements, new_activated = activated)
        new_requirement = new_requirements.shift
        new_name = new_requirement ? name_for(new_requirement) : ''.freeze
        possibilities = new_requirement ? search_for(new_requirement) : []
        handle_missing_or_push_dependency_state DependencyState.new(
          new_name, new_requirements, new_activated,
          new_requirement, possibilities, depth, conflicts.dup
        )
      end

      # Pushes a new {DependencyState}.
      # If the {#specification_provider} says to
      # {SpecificationProvider#allow_missing?} that particular requirement, and
      # there are no possibilities for that requirement, then `state` is not
      # pushed, and the node in {#activated} is removed, and we continue
      # resolving the remaining requirements.
      # @param [DependencyState] state
      # @return [void]
      def handle_missing_or_push_dependency_state(state)
        if state.requirement && state.possibilities.empty? && allow_missing?(state.requirement)
          state.activated.detach_vertex_named(state.name)
          push_state_for_requirements(state.requirements.dup, state.activated)
        else
          states.push(state).tap { activated.tag(state) }
        end
      end
    end
  end
end
