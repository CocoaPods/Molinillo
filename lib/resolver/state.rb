module Resolver
  ResolutionState = Struct.new(
    :name,
    :requirements,
    :activated,
    :requirement,
    :possibilities,
    :depth,
    :conflicts,
  )

  class DependencyState < ResolutionState
    def pop_possibility_state
      PossibilityState.new(
        name,
        requirements.dup,
        activated.dup,
        requirement,
        [possibilities.pop],
        depth + 1,
        conflicts.dup,
      )
    end
  end

  class PossibilityState < ResolutionState
  end
end
