# Molinillo Architecture

At the highest level, Molinillo is a dependency resolution algorithm.
You hand the `Resolver` a list of dependencies and a 'locking' `DependencyGraph`, and you get a resulting dependency graph out of that.
In order to guarantee that the list of dependencies is properly resolved, however, requires an algorithm smarter than just walking the list of dependencies and activating each, and its own dependencies, in turn.

## Backtracking

At the heart of Molinillo is a backtracking algorithm with forward checking.
Essentially, the resolution process keeps track of two types of states (dependency and possibility) in a stack.
If that stack is ever exhausted, resolution was impossible.
New states are pushed onto the stack for every dependency, and every time a dependency is successfully 'activated', a new state is pushed onto the stack that represents that activation.
This stack-based approach is used because backtracking (also know as *unwinding*) becomes as simple as popping a state of that stack.


## Specification Provider

The `SpecificationProvider` module forms the basis for the key integration point for a client library with Molinillo.
Its methods convert the client's domain-specific model objects into concepts the resolver understands:

- Nested dependencies
- Names
- Requirement satisfaction
- Finding specifications (known internally as `possibilities`)
- Sorting dependencies (for the sake of reasonable resolver performance)
