# Molinillo Architecture

At the highest level, Molinillo is a dependency resolution algorithm.
You hand the `Resolver` a list of dependencies and a 'locking' `DependencyGraph`, and you get a resulting dependency graph out of that.
In order to guarantee that the list of dependencies is properly resolved, however, an algorithm is required that is smarter than just walking the list of dependencies and activating each, and its own dependencies, in turn.

## Backtracking

At the heart of Molinillo is a [backtracking](http://en.wikipedia.org/wiki/Backtracking) algorithm with [forward checking](http://en.wikipedia.org/wiki/Look-ahead_(backtracking)).
Essentially, the resolution process keeps track of two types of states (dependency and possibility) in a stack.
If that stack is ever exhausted, resolution was impossible.
New states are pushed onto the stack for every dependency, and every time a dependency is successfully 'activated' a new state is pushed onto the stack that represents that activation.
This stack-based approach is used because backtracking (also known as *unwinding*) becomes as simple as popping a state off that stack.

### Walkthrough

1. The client initializes a `Resolver` with a `SpecificationProvider` and `UI`
2. The client calls `resolve` with an array of user-requested dependencies and an optional 'locking' `DependencyGraph`
3. The `Resolver` creates a new `Resolution` with those four user-specified parameters and calls `resolve` on it
4. The `Resolution` creates an `initial_state`, which takes the user-requested dependencies and puts them into a `DependencyState`
  - In the process of creating the state, the `SpecificationProvider` is asked to sort the dependencies and return all the `possibilities` for the `initial_requirement` (taking into account whether the dependency is `locked`). These possibilities are then grouped into `PossibilitySet`s, with each set representing a group of versions for the dependency which share the same sub-dependency requirements
  - A `DependencyGraph` is created that has all of these requirements point to `root_vertices`
5. The resolution process now enters its main loop, which continues as long as there is a current `state` to process, and the current state has requirements left to process
6. `UI#indicate_progress` is called to allow the client to report progress
7. If the current state is a `DependencyState`, we have it pop off a `PossibilityState` that encapsulates a `PossibilitySet` for that dependency
8. Process the topmost state on the stack
9. If there is a non-empty `PossibilitySet` for the state, `attempt_to_activate` it (jump to #11)
10. If there is no non-empty `PossibilitySet` for the state, `create_conflict` if the state is a `PossibilityState`, and then `unwind_for_conflict` until there's a `DependencyState` with a non-empty `PossibilitySet` atop the stack
11. Check if there is an existing vertex in the `activated` dependency graph for the dependency this state's `requirement` relates to
12. If there is no existing vertex in the `activated` dependency graph for the dependency this state's `requirement` relates to, `activate_new_spec`. This creates a new vertex in the `activated` dependency graph, with it's payload set to the possibility's `PossibilitySet`. It also pushes a new `DependencyState`, with the now-activated `PossibilitySet`'s own dependencies. Go to #6
13. If there is an existing, `activated` vertex for the dependency, `attempt_to_filter_existing_spec`
  - This filters the contents of the existing vertex's `PossibilitySet` by the current state's `requirement`
  - If any possibilities remain within the `PossibilitySet`, it updates the activated vertex's payload with the new, filtered state and pushes a new `DependencyState`
  - If no possibilities remain within the `PossibilitySet` after filtering, or if the current state's `PossibilitySet` had a different set of sub-dependecy requirements to the existing vertex's `PossibilitySet`, `create_conflict` and `unwind_for_conflict`, back to the last `DependencyState` that has a chance to not generate a conflict. Go to #6
15. Terminate with the topmost state's dependency graph when there are no more requirements left
16. For each vertex with a payload of allowable versions for this resolution (i.e., a `PossibilitySet`), pick a single specific version.

## Specification Provider

The `SpecificationProvider` module forms the basis for the key integration point for a client library with Molinillo.
Its methods convert the client's domain-specific model objects into concepts the resolver understands:

- Nested dependencies
- Names
- Requirement satisfaction
- Finding specifications (known internally as `possibilities`)
- Sorting dependencies (for the sake of reasonable resolver performance)
