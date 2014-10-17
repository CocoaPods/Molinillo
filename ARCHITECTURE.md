# Molinillo Architecture

At the highest level, Molinillo is a dependency resolution algorithm.
You hand the `Resolver` a list of dependencies and a 'locking' `DependencyGraph`, and you get a resulting dependency graph out of that.
In order to guarantee that the list of dependencies is properly resolved, however, requires an algorithm smarter than just walking the list of dependencies and activating each, and its own dependencies, in turn.

## Backtracking

At the heart of Molinillo is a backtracking algorithm with forward checking.
Essentially, the resolution process keeps track of two types of states (dependency and possibility) in a stack.
If that stack is ever exhausted, resolution was impossible.
New states are pushed onto the stack for every dependency, and every time a dependency is successfully 'activated', a new state is pushed onto the stack that represents that activation.
This stack-based approach is used because backtracking (also know as *unwinding*) becomes as simple as popping a state off that stack.

### Walkthrough

1. Client initializes `Resolver` with a `SpecificationProvider` and `UI`
2. Client calls `resolve` with an array of user-requested dependencies and a 'locking' `DependencyGraph`
3. The resolver creates a new `Resolution` with those four user-specified parameters and calls `resolve` on it
4. The resolution creates an `initial_state`, which takes the
  - In the process of creating the state, the `SpecificationProvider` is asked to sort the dependencies and return all the `possibilities` for the `initial_requirement`
5. The resolution process now enters its main loop, which continues as long as there is a current `state` to process, and the current state has requirements left to process
6. `UI#indicate_progress` is called
7. Unless the current state is a `PossibilityState`, we have the current state pop off a `PossibilityState` that encapsulates a single possibility
8. Process the topmost state on the stack
9. If there's a possibility for the state, `attempt_to_activate` it (jump to #11)
10. If there's no possibility, `create_conflict` if the state is a `PossibilityState`, and then `unwind_for_conflict` until theres a `DependencyState` with a `possibility` atop the stack
11. Check if there is an existing node in the `activated` dependency graph with the name of the current `requirement`
12. If so, `attempt_to_activate_existing_spec` (jump to #14). If not, `attempt_to_activate_new_spec`
13. Check if there is a `locked` dependency with the current dependency's name. If there is, verify that both the locked dependency and the current `requirement` are satisfied with the current `possibility`. If either is not satisfied, `create_conflict` and `unwind_for_conflict`
14. In either case, if the requirement is satisfied by the existing spec (if existing), or the new spec (if not), a new state is pushed with the now-activated `possibility`'s own dependencies. Go to #5
15. Terminate with the top-most state's dependency graph when there are no more requirements left

## Specification Provider

The `SpecificationProvider` module forms the basis for the key integration point for a client library with Molinillo.
Its methods convert the client's domain-specific model objects into concepts the resolver understands:

- Nested dependencies
- Names
- Requirement satisfaction
- Finding specifications (known internally as `possibilities`)
- Sorting dependencies (for the sake of reasonable resolver performance)
