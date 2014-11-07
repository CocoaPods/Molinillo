# Molinillo Changelog

## Master

###### Bug Fixes

* Ensure that recurse invocations of `detach_vertex_named` don't lead to
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
