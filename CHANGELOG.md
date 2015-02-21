# Molinillo Changelog

## 0.2.1

* Allow resolving some pathological cases where the backjumping algorithm would
  skip over a valid possibility.  
  [Samuel Giddins](https://github.com/segiddins)


## 0.2.0

* Institute stricter forward checking by backjumping to the source of a
  conflict, even if that source comes from the existing spec. This further
  improves performance in highly conflicting situations when sorting heuristics
  prove misleading.  
  [Samuel Giddins](https://github.com/segiddins)
  [Smit Shah](https://github.com/Who828)

* Add support for topologically sorting a dependency graph's vertices.  
  [Samuel Giddins](https://github.com/segiddins)


## 0.1.2

##### Enhancements

* Improve performance in highly conflicting situations by backtracking more than
  one state at a time.  
  [Samuel Giddins](https://github.com/segiddins)

##### Bug Fixes

* Ensure that recursive invocations of `detach_vertex_named` don't lead to
  messaging `nil`.  
  [Samuel Giddins](https://github.com/segiddins)
  [CocoaPods#2805](https://github.com/CocoaPods/CocoaPods/issues/2805)

## 0.1.1

* Ensure that an unwanted exception is not raised when an error occurs before
  the initial state has been pushed upon the stack.  
  [Samuel Giddins](https://github.com/segiddins)

## 0.1.0

* Initial release.  
  [Samuel Giddins](https://github.com/segiddins)
