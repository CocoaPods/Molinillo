module Resolver
  class Resolver
    class Resolution
      attr_reader :specification_provider, :resolver_ui, :base, :original_requested

      def initialize(specification_provider, resolver_ui, requested, base)
        @specification_provider = specification_provider
        @resolver_ui = resolver_ui
        @original_requested = requested
        @base = base
        @states = []
        @iteration_counter = 0
      end

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

      def start_resolution
        @started_at = Time.now

        states.push(initial_state)

        debug { "starting resolution (#{@started_at})" }
      end

      def end_resolution
        raise VersionConflict if states.empty?

        debug { "finished resolution (took #{(@ended_at = Time.now) - @started_at} seconds) (#{@ended_at})" }
        debug { 'unactivated: ' + Hash[activated.vertices.reject { |_n, v| v.payload }].keys.join(', ') }
        debug { 'activated: ' + Hash[activated.vertices.select { |_n, v| v.payload }].keys.join(', ') }
      end

      require 'resolver/state'
      require 'resolver/modules/specification_provider'

      attr_accessor :iteration_rate
      attr_accessor :started_at
      attr_accessor :ended_at
      attr_accessor :states

      ResolutionState.new.members.each do |member|
        define_method member do
          state.send(member)
        end
      end

      SpecificationProvider.instance_methods(false).each do |instance_method|
        define_method instance_method do |*args, &block|
          specification_provider.send(instance_method, *args, &block)
        end
      end

      def process_topmost_state
        if possibility
          attempt_to_activate
        else
          unwind_for_conflict until possibility && state.is_a?(DependencyState)
        end
      end

      def possibility
        possibilities.last
      end

      def state
        states.last
      end

      def initial_state
        requirements = original_requested
        graph = DependencyGraph.new.tap { |dg| requirements.each { |r| dg.add_root_vertex(name_for(r), nil) } }
        initial_requirement = requirements.shift
        DependencyState.new(
          name_for(initial_requirement),
          requirements,
          graph,
          initial_requirement,
          search_for(initial_requirement),
          0,
          Set.new
        )
      end

      def unwind_for_conflict
        debug(depth) { 'Unwinding from level ' + state.depth.to_s }
        states.pop
      end

      def indicate_progress
        @iteration_counter += 1
        if iteration_rate.nil?
          if Time.now - started_at >= 60
            iteration_rate = @iteration_counter
          end
        else
          if ((iteration_counter % iteration_rate) == 0)
            resolver_ui.indicate_progress
          end
        end
      end

      def debug(depth = 0, &block)
        resolver_ui.debug(depth, &block)
      end

      def attempt_to_activate
        debug(depth) { 'attempting to activate ' + name + ' at ' + possibility.to_s }
        existing_node = activated.vertex_named(name)
        if existing_node && existing_node.payload
          attempt_to_ativate_existing_spec(existing_node)
        else
          attempt_to_activate_new_spec
        end
      end

      def attempt_to_ativate_existing_spec(existing_node)
        existing_spec = existing_node.payload
        if requirement_satisfied_by?(requirement, activated, existing_spec)
          new_requirements = requirements.dup
          push_state_for_requirements(new_requirements)
        else
          debug(depth) { 'Unsatisfied by existing spec' }
          return unwind_for_conflict
        end
      end

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
          unwind_for_conflict
        end
      end

      def explicitly_locked_spec_named(spec_name)
        vertex = base.root_vertex_named(spec_name)
        vertex.payload if vertex
      end

      def activate_spec
        debug(depth) { 'activated ' + name_for(possibility) + ' at ' + possibility.to_s }
        activated.vertex_named(name_for(possibility)).payload = possibility
        require_nested_dependencies_for(possibility)
      end

      def require_nested_dependencies_for(activated_spec)
        debug(depth) { 'requiring nested dependencies' }

        nested_dependencies = dependencies_for(activated_spec)
        nested_dependencies.each { |d|  activated.add_child_vertex name_for(d), nil, [name_for(activated_spec)] }

        push_state_for_requirements(requirements + nested_dependencies)
      end

      def push_state_for_requirements(new_requirements)
        new_requirement = new_requirements.shift
        states.push DependencyState.new(
          new_requirement ? name_for(new_requirement) : '',
          new_requirements,
          activated.dup,
          new_requirement,
          new_requirement ? search_for(new_requirement) : [],
          depth,
          Set.new
        )
      end
    end
  end
end
