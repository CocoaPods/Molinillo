require 'resolver/result'

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
        activated = {}

        until requested.empty?
          indicate_progress

          self.requested = requested.sort

          attempt_to_activate(requested.shift, activated)
        end

        @ended_at = Time.now

        Result.new([], {})
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
        existing_spec = activated[requested_spec.name]
        if existing_spec

        end
      end

      def activate_spec(_spec_to_activate, _activated)
      end

      def search_for(spec_name)
        specification_provider.search_for(spec_name)
      end

      def possibilities_for_state?(state)
        state && state.possibilities.any?
      end
    end

    def resolve(requested, base = {})
      Resolution.new(specification_provider,
                     resolver_ui,
                     requested,
                     base).
        resolve
    end
  end
end
