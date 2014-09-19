require 'resolver/dependency_graph'

module Resolver
  # Features
  #
  # - Supports multiple resolution groups with the limitation of only one
  #   version activated for a given library among them.
  #
  class Resolver
    attr_reader :specification_provider, :resolver_ui

    def initialize(specification_provider, resolver_ui)
      @specification_provider = specification_provider
      @resolver_ui = resolver_ui
    end

    class Resolution
      require 'set'

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
        @started_at = Time.now

        states.push(initial_state)

        while state
            break unless state.requirements.any? || state.requirement
            indicate_progress
            puts '...'
            states.push(state.pop_possibility_state) unless state.is_a? PossibilityState
            process_topmost_state
        end

        if states.empty?
          raise 'das'
        end

        @ended_at = Time.now

        p 'unactivated: ' + activated.vertices.reject {|n,v| v.payload}.keys.join(' ')
        p 'activated: ' + activated.vertices.select {|n,v| v.payload}.keys.join(' ')

        activated.freeze
      end

      private

      require 'resolver/state'

      attr_accessor :iteration_rate
      attr_accessor :started_at
      attr_accessor :ended_at
      attr_accessor :states

      ResolutionState.new.members.each do |member|
        define_method member do
          state.send(member)
        end
      end

      def process_topmost_state
        possibility ? attempt_to_activate(possibility) : unwind_for_conflict
      end

      def possibility
        possibilities.last
      end

      def state
        states.last
      end

      def name_for(dependency)
        specification_provider.name_for_dependency(dependency)
      end

      def initial_state
        requirements = original_requested
        graph = DependencyGraph.new.tap { |dg| requirements.each { |r| dg.add_root_vertex(name_for(r), nil) } }
        initial_requirement = p requirements.shift
        DependencyState.new(
          name_for(initial_requirement),
          requirements,
          graph,
          initial_requirement,
          search_for(initial_requirement),
          0,
          Set.new,
        )
      end

      def unwind_for_conflict
        p 'Unwinding from ' + state.depth.to_s
        state.tap do |s|
          states.pop
        end
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

      def attempt_to_activate(requested_spec)
        p 'attempting to activate ' + name + ' at ' + requested_spec.version.to_s
        existing_node = activated.vertex_named(name)
        if existing_node && existing_node.payload
          attempt_to_ativate_existing_spec(requested_spec, existing_node)
        else
          attempt_to_activate_new_spec(requested_spec)
        end
      end

      def attempt_to_ativate_existing_spec(requested_spec, existing_node)
        existing_spec = existing_node.payload
        if specification_provider.requirement_satisfied_by?(requested_spec, activated, existing_spec)
          new_requirements = requirements.dup
          new_requirement = new_requirements.shift
          states.push DependencyState.new(
            new_requirement ? name_for(new_requirement) : "",
            new_requirements,
            activated.dup,
            new_requirement,
            new_requirement ? search_for(new_requirement) : [],
            state.depth + 1,
            Set.new,
          )
        else
          unwind_for_conflict
        end
      end

      def attempt_to_activate_new_spec(requested_spec)
        satisfied = begin
          locked_spec = explicitly_locked_spec_named(name)
          requested_spec_satisfied = specification_provider.requirement_satisfied_by?(requirement, activated, possibility)
          locked_spec_satisfied =
            !locked_spec || specification_provider.requirement_satisfied_by?(locked_spec, activated, possibility)
          p 'Unsatisfied by requested spec' unless requested_spec_satisfied
          p 'Unsatisfied by locked spec' unless locked_spec_satisfied
          requested_spec_satisfied && locked_spec_satisfied
        end
        if satisfied
          activate_spec(requested_spec)
        else
          unwind_for_conflict
        end
      end

      def explicitly_locked_spec_named(spec_name)
        vertex = base.root_vertex_named(spec_name)
        vertex.payload if vertex
      end

      def activate_spec(spec_to_activate)
        p 'activated ' + spec_to_activate.name + ' at ' + spec_to_activate.version.to_s
        activated.vertex_named(name_for(spec_to_activate)).payload = spec_to_activate
        require_nested_dependencies_for(spec_to_activate)
      end

      def require_nested_dependencies_for(activated_spec)
        p 'requiring nested dependencies'
        nested_dependencies = specification_provider.dependencies_for(activated_spec)
        nested_dependencies.each { |d|  activated.add_child_vertex name_for(d), nil, [name_for(activated_spec)] }

        new_requirements = requirements + nested_dependencies
        new_requirement = new_requirements.shift
        states.push DependencyState.new(
          new_requirement ? name_for(new_requirement) : "",
          new_requirements,
          activated.dup,
          new_requirement ,
          new_requirement ? search_for(new_requirement) : [],
          state.depth + 1,
          Set.new,
        )
      end

      def search_for(dependency)
        raise 'hell' unless dependency
        specification_provider.search_for(dependency)
      end
    end

    def resolve(requested, base)
      Resolution.new(specification_provider,
                     resolver_ui,
                     requested,
                     base).
        resolve
    end
  end
end
