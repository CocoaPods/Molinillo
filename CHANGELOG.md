# Molinillo Changelog

## Master

##### Enhancements

* Add `SpecificationProvider#prune_doomed_possibilities?` (default false). When
  a provider opts in, possibilities that cannot be part of any resolution (a
  dependency that no available version satisfies, or that conflicts with a
  requirement every resolution must satisfy) are removed from search results,
  so the resolver does not re-derive the same failure after every backtrack.
  `VersionConflict#pruned_possibilities` and the error messages explain which
  relevant versions were not considered and why; the other pruned versions are
  listed (up to five) in `#other_pruned_possibilities` and a trailing section.  
  [Samuel Giddins](https://github.com/segiddins)

* Run fuzz specs on current Ruby versions with distinct extra random seeds and
  a working naive-resolver oracle.
  [Samuel Giddins](https://github.com/segiddins)

* Document resolver-payload requirements for graph cycle errors and the
  tag/rewind recovery contract for non-atomic child-vertex additions.
  [Samuel Giddins](https://github.com/segiddins)

* Check whether a requirement already has a state by comparing it only with
  the requirements of states for the same name, instead of with every state
  on the stack, removing a quadratic cost from resolving large graphs.  
  [Samuel Giddins](https://github.com/segiddins)

* Reuse successful pure provider searches and names within a resolution,
  keyed by input identity. Returned search arrays remain independent, failed
  searches are not cached, and context-sensitive satisfaction checks are unchanged.
  [Samuel Giddins](https://github.com/segiddins)

* Avoid repeated requirement-list deduplication during context checks: recognize
  already-present objects by identity, then preserve value-based subtraction for
  missing requirements without a redundant right-hand-side `uniq` pass.
  [Samuel Giddins](https://github.com/segiddins)

* Avoid redundant context checks when ordering zero or one possibility set;
  the order cannot change, and final context-sensitive verification is retained.
  [Samuel Giddins](https://github.com/segiddins)

* Index pure unwind search domains by identity and memoize value-equality
  membership fallback answers, avoiding repeated specification/version scans
  while preserving providers whose specifications define only `==`.
  [Samuel Giddins](https://github.com/segiddins)

* Prune redundant requirement trees from terminal `VersionConflict` explanations
  when a smaller unsatisfiable subset can be verified in the conflict-time
  context. `conflicts` contains reporting copies with pruned `requirement_trees`;
  `original_conflicts` retains the complete trees, and `Conflict#requirements`
  remains unchanged. Circular, stale, or context-sensitive conflicts that cannot
  be safely reduced keep their original explanations. This affects reporting
  only, not resolution or backtracking.
  [Samuel Giddins](https://github.com/segiddins)

##### Bug Fixes

* Raise a `CircularDependencyError` (instead of an `ArgumentError` claiming
  there is no path) for circular dependencies whose vertices were added to the
  graph in an order other than topological order, which depended on the order
  dependencies were requested in. Circular dependency errors now always report
  the shortest path.  
  [Samuel Giddins](https://github.com/segiddins)

* Fix `DependencyGraph.tsort` raising an `ArgumentError` for any input, since
  `TSort` passes the node iterator a block rather than a positional argument.  
  [Samuel Giddins](https://github.com/segiddins)

* Make `DependencyGraph#==` symmetric: a graph is no longer considered equal to
  another graph that has additional vertices, and the comparison always
  returns a boolean.  
  [Samuel Giddins](https://github.com/segiddins)

* Rewinding a `DependencyGraph` now also undoes explicit requirements added by
  `add_child_vertex` after the tag being rewound to.  
  [Samuel Giddins](https://github.com/segiddins)

* Copying a `DependencyGraph` no longer records the copy's reconstruction in
  a log shared with the original. The copy now starts with its own empty log;
  previously rewinding the copy to a tag from before the copy emptied the copy
  or raised, and changes to the copy were spliced into the original's log.  
  [Samuel Giddins](https://github.com/segiddins)

* `DependencyGraph::Log#each` no longer enumerates actions that were undone by
  a rewind.  
  [Samuel Giddins](https://github.com/segiddins)

* `DependencyGraph#delete_edge` removes a single edge, and rewinding past it
  restores exactly the edge that was removed. Previously it removed every equal
  edge but undoing it restored only one, and undoing the deletion of an edge
  that did not exist added that edge to the graph.  
  [Samuel Giddins](https://github.com/segiddins)

* An action that raises while being applied to a `DependencyGraph` (for example
  `set_payload` for a vertex that does not exist) is no longer left in the log,
  where it previously caused a later `rewind_to` to raise.  
  [Samuel Giddins](https://github.com/segiddins)

* Rewinding a `DependencyGraph` to a tag that is not in its log raises without
  undoing anything. Previously it undid the entire log before raising.  
  [Samuel Giddins](https://github.com/segiddins)

* Raise the recorded `CircularDependencyError` once every alternative has been
  exhausted, instead of crashing with a `NoMethodError` when it is re-raised
  inside the resolver's circular-dependency conflict handling.  
  [Samuel Giddins](https://github.com/segiddins)

* Avoid exponential unwinding when several parents declare requirements that
  are equal (`==`) to the conflicting one but are distinct objects: such
  duplicates are now pruned from the binding requirements like any other
  redundant requirement, independent of the provider's `eql?` semantics.  
  [Samuel Giddins](https://github.com/segiddins)

* Consider the requirements along a circular dependency when unwinding from
  it, so that a resolution using an older version of a package that closes the
  cycle is found instead of raising a `CircularDependencyError`.  
  [Samuel Giddins](https://github.com/segiddins)

* Track requirements by identity when working out which states to unwind to,
  so that equal requirements declared by different parents are traced back to
  their own parents even when the provider's requirements have a value-based
  `eql?`/`hash` (as Bundler gives `Gem::Dependency`).  
  [Samuel Giddins](https://github.com/segiddins)

* Find a resolution (instead of raising a `VersionConflict`) when an earlier
  requirement on a name narrowed its possibilities by choosing one of several
  possibility sets, e.g. `a (!= 2.0)`, `a (>= 0)` and `a (< 3.0)` where only
  `a 2.0` has different dependencies.  
  [Samuel Giddins](https://github.com/segiddins)

* When `allow_missing?` lets a requirement with no possibilities be skipped,
  ignore only that requirement instead of removing the whole vertex, which
  dropped other (satisfiable) requirements on the same name, removed already
  activated specs from the result, or crashed with a `NoMethodError`.  
  [Samuel Giddins](https://github.com/segiddins)

* Ignore a requirement that `allow_missing?` lets be missing before it is added
  to the dependency graph, so that it can no longer close a circular dependency
  or take part in conflicts with the other requirements on the same name. This
  calls `search_for` (and, when it finds nothing, `allow_missing?`) for each
  requirement when it is added, rather than only when it is processed.  
  [Samuel Giddins](https://github.com/segiddins)

* Make resolution independent of the order in which requirements are
  processed when `requirement_satisfied_by?` depends on the other requirements
  on the same name (e.g. prereleases only being allowed once a prerelease
  requirement exists). Possibilities that do not satisfy a requirement yet are
  now tried last instead of being discarded, and whether every activated spec
  satisfies all of its requirements is checked once they are all known.  
  [Samuel Giddins](https://github.com/segiddins)

* Keep search-domain-valid unwind candidates while unprocessed requirements
  may change the provider's context, instead of permanently rejecting a
  prerelease before a later dependency allows it. Locked requirements remain
  strict, and every activated specification is still verified once all
  requirements are known. This fixes requirement-order dependence when a
  release candidate fails (for example, because of a circular dependency)
  before the prerelease-enabling dependency is processed.
  [Samuel Giddins](https://github.com/segiddins)


## 0.8.0 (2021-08-09)

##### Breaking

* Support for Ruby 2.0, 2.1 and 2.2 has been dropped, the minimum supported
  Ruby version is now 2.3.  
  [David Rodríguez](https://github.com/deivid-rodriguez)

##### Enhancements

* Use `Array#-` in unwind logic, since it performs better than `Array#&`, so it
  speeds up resolution.  
  [Lukas Oberhuber](https://github.com/lukaso)

* Allow specification provider to customize how dependencies are compared when
  grouping specifications with the same dependencies.  
  [David Rodríguez](https://github.com/deivid-rodriguez)

##### Bug Fixes

* None.  


## 0.7.0 (2020-10-21)

##### Breaking

* Support for Ruby 1.8.7 and 1.9.3 has been dropped, the minimum supported
  Ruby version is now 2.0.  
  [Samuel Giddins](https://github.com/segiddins)

##### Enhancements

* Circular dependency errors include the full (shortest) path between the
  circularly-dependent vertices.  
  [Samuel Giddins](https://github.com/segiddins)

##### Bug Fixes

* None.  


## 0.6.6 (2018-08-07)

##### Enhancements

* Improve performance of `Vertex#path_to?`.  
  [Samuel Giddins](https://github.com/segiddins)

* Allow customization of string used to say that a version conflict has occurred
  for a particular name by passing in the `:incompatible_version_message_for_conflict` 
  key when constructing a version conflict message with trees.  
  [Samuel Giddins](https://github.com/segiddins)

##### Bug Fixes

* None.  


## 0.6.5 (2018-03-22)

##### Enhancements

* Improve performance of recursive vertex methods.  
  [Samuel Giddins](https://github.com/segiddins)

##### Bug Fixes

* None.  


## 0.6.4 (2017-10-29)

##### Enhancements

* Reduce memory usage during resolution by making the `Vertex#requirements`
  array unique.  
  [Grey Baker](https://github.com/greysteil)
  [Jan Krutisch](https://github.com/halfbyte)

##### Bug Fixes

* None.  


## 0.6.3 (2017-09-06)

##### Enhancements

* None.  

##### Bug Fixes

* Handle the case where an unwind occurs to a requirement that directly caused
  the current conflict but could also have been unwound to directly from
  previous conflicts. In this case, filtering must not remove any possibilities
  that could have avoided the previous conflicts (even if they would not avoid
  the current one).  
  [Grey Baker](https://github.com/greysteil)


## 0.6.2 (2017-08-25)

##### Enhancements

* None.  

##### Bug Fixes

* Insist each PossibilitySet contains contiguous versions. Fixes a regression
  where an older dependency version with identical sub-dependencies to the
  latest version may be preferred over the second-latest version.  
  [Grey Baker](https://github.com/greysteil)


## 0.6.1 (2017-08-01)

##### Enhancements

* None.  

##### Bug Fixes

* Allow the set of dependencies for a given possibility to change over time,
  fixing a regression in 0.6.0.  
  [Samuel Giddins](https://github.com/segiddins)


## 0.6.0 (2017-07-27)

##### Breaking

* Objects returned by `dependencies_for` and passed to `resolve` must properly implement
  both `==` and `eql?`, such that they return `true` when they exhibit the same behavior in
  `requirement_satisfied_by?`.  

##### Enhancements

* Speed up dependency resolution by considering multiple possible versions of a
  dependency at once, grouped by sub-dependencies. Groups are then filtered as
  additional requirements are introduced. If a group's sub-dependencies cause
  conflicts the entire group can be discarded, which reduces the number of
  possibilities that have to be tested to find a resolution.  
  [Grey Baker](https://github.com/greysteil)
  [Samuel Giddins](https://github.com/segiddins)
  [#69](https://github.com/CocoaPods/Molinillo/pull/69)

* Check for locked requirements when generating a new state's possibilities
  array, and reduce possibilities set accordingly. Reduces scope for erroneous
  VersionConflict errors.  
  [Grey Baker](https://github.com/greysteil)
  [#67](https://github.com/CocoaPods/Molinillo/pull/67)

* Add `VersionConflict#message_with_trees` for consumers who prefer a more verbose
  conflict message that includes full requirement trees for all conflicts.  
  [Samuel Giddins](https://github.com/segiddins)

##### Bug Fixes

* Improve unwinding by considering previous conflicts for the same dependency
  when deciding which state to unwind to. Previously, prior conflicts were
  stored in a hash indexed by their name, with only the most recent conflict
  stored for each dependency. With this fix, Molinillo can resolve anything
  that's thrown at it. 🎉  
  [Grey Baker](https://github.com/greysteil)
  [#73](https://github.com/CocoaPods/Molinillo/pull/73)

* Only raise CircularDependency errors if they prevent resolution.  
  [Ian Young](https://github.com/iangreenleaf)
  [Grey Baker](https://github.com/greysteil)
  [#78](https://github.com/CocoaPods/Molinillo/pull/78)

* Consider additional (binding) requirements that caused a conflict when
  determining which state to unwind to. Previously, in some cases Molinillo
  would erroneously throw a VersionConflict error if multiple requirements
  combined to cause a conflict.  
  [Grey Baker](https://github.com/greysteil)
  [#72](https://github.com/CocoaPods/Molinillo/pull/72) 

* Consider previous conflicts when determining the state to unwind to. If a
  previous conflict, for a different dependency, is the reason we ended up with
  the current conflict, then unwinding to a state that would not have caused
  that conflict could prevent the current one, too.  
  [Grey Baker](https://github.com/greysteil)
  [#72](https://github.com/CocoaPods/Molinillo/pull/72)


## 0.5.7 (2017-03-03)

##### Enhancements

* None.  

##### Bug Fixes

* Keep a stack of parents per requirement, so unwinding past a swap point that
  updated the parent of the requirement works.  
  [Samuel Giddins](https://github.com/segiddins)
  [bundler#5425](https://github.com/bundler/bundler/issues/5425)


## 0.5.6 (2017-02-08)

##### Enhancements

* None.  

##### Bug Fixes

* Only reset the parent of a requirement after swapping when its original parent
  was the same vertex being swapped.  
  [Samuel Giddins](https://github.com/segiddins)
  [bundler#5359](https://github.com/bundler/bundler/issues/5359)
  [bundler#5362](https://github.com/bundler/bundler/issues/5362)


## 0.5.5 (2017-01-07)

##### Enhancements

* None.  

##### Bug Fixes

* Only remove requirements from the to-be-resolved list if there are no
  activated vertices depending upon them after swapping.  
  [Samuel Giddins](https://github.com/segiddins)
  [bundler#5294](https://github.com/bundler/bundler/issues/5294)


## 0.5.4 (2016-11-14)

##### Enhancements

* None.  

##### Bug Fixes

* Fix unwinding when both sides of a conflict have a common parent
  requirement.  
  [Samuel Giddins](https://github.com/segiddins)
  [bundler#5154](https://github.com/bundler/bundler/issues/5154)


## 0.5.3 (2016-10-28)

##### Enhancements

* None.  

##### Bug Fixes

* Fixed a regression in v0.5.2 that could cause resolution to fail after
  swapping, because stale dependencies would still be in the requirements
  list.  
  [Samuel Giddins](https://github.com/segiddins)
  [#48](https://github.com/CocoaPods/Molinillo/issues/48)

* Rename `Action.name` to `Action.action_name` to avoid overriding
  `Module.name`.  
  [Samuel Giddins](https://github.com/segiddins)
  [#50](https://github.com/CocoaPods/Molinillo/issues/50)


## 0.5.2 (2016-10-24)

##### Enhancements

* None.  

##### Bug Fixes

* Fixed a bug where `Resolution#parent_of` would return the incorrect parent for
  a dependency after swapping had occurred, resulting in resolution failing.  
  [Samuel Giddins](https://github.com/segiddins)
  [bundler#5059](https://github.com/bundler/bundler/issues/5059)


## 0.5.1 (2016-09-12)

##### Enhancements

* None.  

##### Bug Fixes

* Fixed a bug where `Resolution#parent_of` would return the incorrect parent for
  a dependency, resulting in resolution failing.  
  [Samuel Giddins](https://github.com/segiddins)
  [bundler#4961](https://github.com/bundler/bundler/issues/4961)


## 0.5.0 (2016-06-14)

##### Enhancements

* Add an operation log to `DependencyGraph` to eliminate the need for graph
  copies during dependency resolution, resulting in a 3-100x speedup and
  reduction in allocations.  
  [Samuel Giddins](https://github.com/segiddins)
  [bundler#4376](https://github.com/bundler/bundler/issues/4376)

* Remove all metaprogramming to reduce array allocation overhead and improve
  discoverability.  
  [Samuel Giddins](https://github.com/segiddins)

##### Bug Fixes

* None.  


## 0.4.5 (2016-04-30)

##### Enhancements

* For performance, don't needlessly dup objects in
  `Resolution#push_state_for_requirements`.  
  [Joe Rafaniello](https://github.com/jrafanie)

##### Bug Fixes

* Recursively prune requirements when removing an orphan after swapping.  
  [Daniel DeLeo](https://github.com/danielsdeleo)
  [berkshelf/solve#57](https://github.com/berkshelf/solve/issues/57)


## 0.4.4 (2016-02-28)

##### Bug Fixes

* Fix mutating a frozen string in `NoSuchDependencyError#message`.  
  [Samuel Giddins](https://github.com/segiddins)


## 0.4.3 (2016-02-18)

##### Enhancements

* Add frozen string literal comments to all ruby files.  
  [Samuel Giddins](https://github.com/segiddins)

##### Bug Fixes

* Prune the dependency list when removing an orphan after swapping.  
  [Samuel Giddins](https://github.com/segiddins)
  [bundler/bundler#4276](https://github.com/bundler/bundler/issues/4276)


## 0.4.2 (2016-01-30)

##### Bug Fixes

* Detaching a vertex correctly removes it from the list of successors of its
  predecessors.  
  [Samuel Giddins](https://github.com/segiddins)

* Vertices orphaned after swapping dependencies are properly cleaned up from the
  graph of activated specs.  
  [Samuel Giddins](https://github.com/segiddins)
  [bundler/bundler#4198](https://github.com/bundler/bundler/issues/4198)


## 0.4.1 (2015-12-30)

##### Enhancements

* Ensure every API is 100% documented.  
  [Samuel Giddins](https://github.com/segiddins)
  [#22](https://github.com/CocoaPods/Molinillo/issues/22)


## 0.4.0 (2015-07-27)

##### API Breaking Changes

* The `DependencyGraph` no longer treats root vertices specially, nor does it
  maintain a direct reference to `edges`. Additionally, `Vertex` no longer
  has a reference to its parent graph.  

##### Enhancements

* Resolution has been sped up by 25x in some pathological cases, and in general
  recursive operations on a `DependencyGraph` or `Vertex` are now `O(n)`.  
  [Samuel Giddins](https://github.com/segiddins)
  [Bundler#3803](https://github.com/bundler/bundler/issues/3803)

* Re-sorting of dependencies is skipped when the unresolved dependency list has
  not changed, speeding up resolution of fully locked graphs.  
  [Samuel Giddins](https://github.com/segiddins)


## 0.3.1 (2015-07-24)

##### Enhancements

* Add `Conflict#activated_by_name` to allow even richer version conflict
  messages.  
  [Samuel Giddins](https://github.com/segiddins)

##### Bug Fixes

* Ensure `Conflict#requirement_trees` is exhaustive.  
  [Samuel Giddins](https://github.com/segiddins)
  [Bundler#3860](https://github.com/bundler/bundler/issues/3860)


## 0.3.0 (2015-06-29)

##### Enhancements

* Add the ability to optionally skip dependencies that have no possibilities.  
  [Samuel Giddins](https://github.com/segiddins)


## 0.2.3 (2015-03-28)

##### Bug Fixes

* Silence a silly MRI warning about declaring private attributes.  
  [Piotr Szotkowski](https://github.com/chastell)
  [Bundler#3516](https://github.com/bundler/bundler/issues/3516)
  [Bundler#3525](https://github.com/bundler/bundler/issues/3525)


## 0.2.2 (2015-03-27)

##### Bug Fixes

* Use an ivar in `DependencyGraph#initialize_copy` to silence an MRI warning.  
  [Samuel Giddins](https://github.com/segiddins)
  [Bundler#3516](https://github.com/bundler/bundler/issues/3516)


## 0.2.1 (2015-02-21)

* Allow resolving some pathological cases where the backjumping algorithm would
  skip over a valid possibility.  
  [Samuel Giddins](https://github.com/segiddins)


## 0.2.0 (2014-12-25)

* Institute stricter forward checking by backjumping to the source of a
  conflict, even if that source comes from the existing spec. This further
  improves performance in highly conflicting situations when sorting heuristics
  prove misleading.  
  [Samuel Giddins](https://github.com/segiddins)
  [Smit Shah](https://github.com/Who828)

* Add support for topologically sorting a dependency graph's vertices.  
  [Samuel Giddins](https://github.com/segiddins)


## 0.1.2 (2014-11-19)

##### Enhancements

* Improve performance in highly conflicting situations by backtracking more than
  one state at a time.  
  [Samuel Giddins](https://github.com/segiddins)

##### Bug Fixes

* Ensure that recursive invocations of `detach_vertex_named` don't lead to
  messaging `nil`.  
  [Samuel Giddins](https://github.com/segiddins)
  [CocoaPods#2805](https://github.com/CocoaPods/CocoaPods/issues/2805)

## 0.1.1 (2014-11-06)

* Ensure that an unwanted exception is not raised when an error occurs before
  the initial state has been pushed upon the stack.  
  [Samuel Giddins](https://github.com/segiddins)

## 0.1.0 (2014-10-26)

* Initial release.  
  [Samuel Giddins](https://github.com/segiddins)
