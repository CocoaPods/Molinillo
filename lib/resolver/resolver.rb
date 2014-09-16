require 'resolver/result'
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

      attr_reader :specification_provider, :resolver_ui, :base

      def initialize(specification_provider, resolver_ui, requested, base)
        @specification_provider = specification_provider
        @resolver_ui = resolver_ui
        @requested = requested
        @base = base
        @errors = []
        @conflicts = Set.new
        @iteration_counter = 0
      end

      def resolve
        @started_at = Time.now
        activated = DependencyGraph.new

        requested.each { |d| required_by(d) << nil }

        until requested.empty?
          indicate_progress

          self.requested = specification_provider.sort_dependencies(requested)

          attempt_to_activate(requested.shift, activated)
        end

        @ended_at = Time.now

        Result.new(activated.freeze, conflicts.freeze)
      end

      private

      attr_accessor :errors
      attr_accessor :dependencies_for
      attr_accessor :conflicts
      attr_accessor :missing_specs
      attr_accessor :iteration_rate
      attr_accessor :started_at
      attr_accessor :ended_at
      attr_accessor :requested

      def required_by(object)
        @required_by ||= {}
        @required_by[object] ||= []
      end

      def indicate_progress
        @iteration_counter += 1
        if iteration_rate.nil?
          if ((Time.now - started_at) % 3600).round >= 1
            iteration_rate = @iteration_counter
          end
        else
          if ((iteration_counter % iteration_rate) == 0)
            resolver_ui.indicate_progress
          end
        end
      end

      def resolve_conflict(_current_state, _states)
      end

      def find_conflict_state(_current_state, _states)
      end

      def unwind_for_conflict(_conflict_state)
      end

      def attempt_to_activate(requested_spec, activated)
        requested_name = specification_provider.name_for_specification(requested_spec)
        existing_node = activated.vertex_named(requested_name)
        if existing_node
          attempt_to_ativate_existing_spec(requested_spec, existing_node, activated)
        else
          attempt_to_activate_new_spec(requested_name, requested_spec, activated)
        end
      end

      def attempt_to_ativate_existing_spec(requested_spec, existing_node, activated)
        existing_spec = existing_node.payload
        if specification_provider.requirement_satisfied_by?(requested_spec, activated, existing_spec)
          required_by(requested_spec).each do |r|
            parent_node = activated.vertex_named(r)
            activated.add_edge(parent_node, existing_node)
          end
        else

        end
      end

      def attempt_to_activate_new_spec(name, requested_spec, activated)
        specs = search_for(requested_spec)
        satisfied_spec = specs.reverse_each.find do |s|
          locked_spec = explicitly_locked_spec_named(name)
          requested_spec_satisfied = specification_provider.requirement_satisfied_by?(requested_spec, activated, s)
          locked_spec_satisfied =
            !locked_spec || specification_provider.requirement_satisfied_by?(locked_spec, activated, s)
          requested_spec_satisfied && locked_spec_satisfied
        end
        activate_spec(name, satisfied_spec, required_by(requested_spec), activated)
        true
      end

      def explicitly_locked_spec_named(name)
        vertex = base.root_vertex_named(name)
        vertex.payload if vertex
      end

      def activate_spec(name, spec_to_activate, required_by, activated)
        activated.add_child_vertex(name, spec_to_activate, required_by)
        require_nested_dependencies_for(spec_to_activate)
      end

      def require_nested_dependencies_for(activated_spec)
        name = specification_provider.name_for_specification(activated_spec)
        nested_dependencies = specification_provider.dependencies_for(activated_spec)
        nested_dependencies.each { |d| required_by(d) << name }
        requested.unshift(*nested_dependencies)
      end

      def search_for(dependency)
        specification_provider.search_for(dependency)
      end

      def possibilities_for_state?(state)
        state && state.possibilities.any?
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
