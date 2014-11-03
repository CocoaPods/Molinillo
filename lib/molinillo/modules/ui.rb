module Molinillo
  # Conveys information about the resolution process to a user.
  module UI
    # The {IO} object that should be used to print output. `STDOUT`, by default.
    #
    # @return [IO]
    def output
      STDOUT
    end

    # Called roughly every {#progress_rate}, this method should convey progress
    # to the user.
    #
    # @return [void]
    def indicate_progress(resolution, step)
      case step
      when :iteration
        nil
      when :start_resolution
        "Starting resolution (#{resolution.started_at})"
      when :create_possibility_state
        "Creating possibility state (#{resolution.possibilities.count} remaining)"
      when :attempt_to_activate
        "Attempting to activate #{resolution.possibility}"
      when :activate_spec
        "Activated #{resolution.name} at #{resolution.possibility}"
      when :require_nested_dependencies
        # TODO Or should we make indicate_progress take extra args so that we
        #      don't need to query for the nested dependencies here again?
        nested_dependencies = resolution.dependencies_for(resolution.possibility)
        "Requiring nested dependencies (#{nested_dependencies.map(&:to_s).join(', ')})"
      when :unsatisfied_by_existing_spec
        'Unsatisfied by existing spec'
      when :unsatisfied_by_requested_spec
        'Unsatisfied by requested spec'
      when :unsatisfied_by_locked_spec
        'Unsatisfied by locked spec'
      when :unwind_for_conflict
        "Unwinding from level #{resolution.state.depth}"
      when :finished_resolution
        m = "Finished resolution (#{resolution.iteration_counter} steps) "
        m << "(Took #{(ended_at = Time.now) - resolution.started_at} seconds) (#{ended_at})\n"
        m << 'Unactivated: ' + Hash[resolution.activated.vertices.reject { |_n, v| v.payload }].keys.join(', ') << "\n"
        m << 'Activated: ' + Hash[resolution.activated.vertices.select { |_n, v| v.payload }].keys.join(', ')
        m
      else
        raise "Unrecognized step `#{step}'"
      end
    end

    # How often progress should be conveyed to the user via
    # {#indicate_progress}, in seconds. A third of a second, by default.
    #
    # @return [Float]
    def progress_rate
      0.33
    end
  end
end
