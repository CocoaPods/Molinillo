module Resolver
  class Resolver
    # A specific resolution from a given {Resolver}
    class Resolution
      # A conflict that the resolution process encountered
      # @attr [Object] requirement the requirement that caused the conflict
      # @attr [Object, nil] existing the existing spec that was in conflict with
      #   the {#possibility}
      # @attr [Object] possibility the spec that was unable to be activated due
      #   to a conflict
      Conflict = Struct.new(
        :requirements,
        :existing,
        :possibility
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
          unless state.is_a? PossibilityState
            debug(depth) { "creating possibility state (#{possibilities.count} remaining)" }
            state.pop_possibility_state.tap { |s| states.push(s) if s }
          end
          process_topmost_state
        end

        end_resolution

        activated.freeze
      end

      private

      # Sets up the resolution process
      # @return [void]
      def start_resolution
        @started_at = Time.now

        states.push(initial_state)

        debug { "starting resolution (#{@started_at})" }
      end

      # Ends the resolution process
      # @return [void]
      def end_resolution
        debug { "finished resolution (took #{(@ended_at = Time.now) - @started_at} seconds) (#{@ended_at})" }
        debug { 'unactivated: ' + Hash[activated.vertices.reject { |_n, v| v.payload }].keys.join(', ') }
        debug { 'activated: ' + Hash[activated.vertices.select { |_n, v| v.payload }].keys.join(', ') }
      end

      require 'resolver/state'
      require 'resolver/modules/specification_provider'

      # @return [Integer] the number of resolver iterations in between calls to
      #   {#resolver_ui}'s {UI#indicate_progress} method
      attr_accessor :iteration_rate

      # @return [Time] the time at which resolution begain
      attr_accessor :started_at

      # @return [Time] the time at which resolution finished
      attr_accessor :ended_at

      # @return [Array<ResolutionState>] the stack of states for the resolution
      attr_accessor :states

      ResolutionState.new.members.each do |member|
        define_method member do |*args, &block|
          state.send(member, *args, &block)
        end
      end

      SpecificationProvider.instance_methods(false).each do |instance_method|
        define_method instance_method do |*args, &block|
          specification_provider.send(instance_method, *args, &block)
        end
      end

      # Processes the topmost available {RequirementState} on the stack
      # @return [void]
      def process_topmost_state
        if possibility
          attempt_to_activate
        else
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
        graph = DependencyGraph.new.tap { |dg| original_requested.each { |r| dg.add_root_vertex(name_for(r), nil) } }
        requirements = sort_dependencies(original_requested, graph, {})
        initial_requirement = requirements.shift
        DependencyState.new(
          name_for(initial_requirement),
          requirements,
          graph,
          initial_requirement,
          search_for(initial_requirement),
          0,
          {}
        )
      end

      # Unwinds the states stack because a conflict has been encountered
      # @return [void]
      def unwind_for_conflict
        if depth > 0
          debug(depth) { 'Unwinding from level ' + state.depth.to_s }
          conflicts.tap do |c|
            states.pop
            state.conflicts = c
          end
        else
          raise VersionConflict.new(conflicts)
        end
      end

      # @return [Conflict] a {Conflict} that reflects the failure to activate
      #   the {#possibility} in conjunction with the current {#state}
      def create_conflict
        if vertex = activated.vertex_named(name)
          existing = vertex.payload
        end
        conflicts[name] = Conflict.new(
          vertex.incoming_requirements + [requirement],
          existing,
          possibility
        )
      end

      # Indicates progress roughly once every second
      # @return [void]
      def indicate_progress
        @iteration_counter += 1
        if iteration_rate.nil?
          if Time.now - started_at >= 1.0
            iteration_rate = @iteration_counter
          end
        else
          if ((iteration_counter % iteration_rate) == 0)
            resolver_ui.indicate_progress
          end
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
        debug(depth) { 'attempting to activate ' + possibility.to_s }
        existing_node = activated.vertex_named(name)
        if existing_node && existing_node.payload
          attempt_to_ativate_existing_spec(existing_node)
        else
          attempt_to_activate_new_spec
        end
      end

      # Attempts to activate the current {#possibility} (given that it has
      # already been activated)
      # @return [void]
      def attempt_to_ativate_existing_spec(existing_node)
        existing_spec = existing_node.payload
        if requirement_satisfied_by?(requirement, activated, existing_spec)
          existing_node.incoming_requirements << requirement
          new_requirements = requirements.dup
          push_state_for_requirements(new_requirements)
        else
          create_conflict
          debug(depth) { 'Unsatisfied by existing spec' }
          unwind_for_conflict
        end
      end

      # Attempts to activate the current {#possibility} (given that it hasn't
      # already been activated)
      # @return [void]
      def attempt_to_activate_new_spec
        satisfied = begin
          locked_spec = explicitly_locked_spec_named(name)
          requested_spec_satisfied = requirement_satisfied_by?(requirement, activated, possibility)
          locked_spec_satisfied = !locked_spec || requirement_satisfied_by?(locked_spec, activated, possibility)
          debug(depth) { 'Unsatisfied by requested spec' } unless requested_spec_satisfied
          debug(depth) { 'Unsatisfied by locked spec' } unless locked_spec_satisfied
          requested_spec_satisfied && locked_spec_satisfied
        end
        if satisfied
          activate_spec
        else
          create_conflict
          unwind_for_conflict
        end
      end

      # @param [String] spec_name the spec name to search for
      # @return [Object] the explicitly locked spec named `spec_name`, if one
      #   is found on {#base}
      def explicitly_locked_spec_named(spec_name)
        vertex = base.root_vertex_named(spec_name)
        vertex.payload if vertex
      end

      # Add the current {#possibility} to the dependency graph of the current
      # {#state}
      # @return [void]
      def activate_spec
        conflicts.delete(name)
        debug(depth) { 'activated ' + name_for(possibility) + ' at ' + possibility.to_s }
        vertex = activated.vertex_named(name_for(possibility))
        vertex.payload = possibility
        vertex.incoming_requirements << requirement
        require_nested_dependencies_for(possibility)
      end

      # Requires the dependencies that the recently activated spec has
      # @param [Object] activated_spec the specification that has just been
      #   activated
      # @return [void]
      def require_nested_dependencies_for(activated_spec)
        debug(depth) { 'requiring nested dependencies' }

        nested_dependencies = dependencies_for(activated_spec)
        nested_dependencies.each { |d|  activated.add_child_vertex name_for(d), nil, [name_for(activated_spec)] }

        push_state_for_requirements(requirements + nested_dependencies)
      end

      # Pushes a new {DependencyState} that encapsulates both existing and new
      # requirements
      # @param [Array] new_requirements
      # @return [void]
      def push_state_for_requirements(new_requirements)
        new_requirements = sort_dependencies(new_requirements, activated, conflicts)
        new_requirement = new_requirements.shift
        states.push DependencyState.new(
          new_requirement ? name_for(new_requirement) : '',
          new_requirements,
          activated.dup,
          new_requirement,
          new_requirement ? search_for(new_requirement) : [],
          depth,
          conflicts.dup
        )
      end
    end
  end
end
