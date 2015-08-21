# Molinillo Changelog

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
