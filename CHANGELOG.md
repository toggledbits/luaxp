# LuaXP Change Log

DEPRECATION ANNOUNCEMENT: AS OF LUAXP 1.1, THE SEARCH FOR LOCAL VARIABLES AS TOP-LEVEL KEYS IN THE CONTEXT WILL BE REMOVED, AND ONLY THE `__lvars` KEY IN THE CONTEXT (WHICH IS ITSELF A TABLE) WILL BE USED.

## 1.0.2

* Add array manipulation functions `push( array, element [, maxelements] )`, `pop( array )`, `unshift( array, element [,maxelements] )`, `shift( array )`. The `push()` and `unshift()` functions add an element to the end or front of the array, respectively (i.e. `push()` appends, `unshift()` prepends); the array is modified in place, and is also returned as the function value. Therefore, the `array` argument may only be the name of an array, it cannot be an expression (e.g. `push( d, 1 )` is valid, while `push( list(), 1 )` is not). If the `maxelements` argument is given, the array size is limited to the provided value, with excess elements falling off the "far" end of the array. The `pop()` and `shift()` functions remove and return the last and first, respectively, elements from the array. They return `null` if the array is empty. The array used does not need to exist prior to use--if it does not exist, these functions will create it as an empty array before performing their respective operations. That is, assuming variable `d` does not exist, `push( d, 1 )` has the same effect as `d=list()` followed by `push( d, 1 )`. If the named `array` variable exists but is not an array, a runtime error occurs.
* Add function `sum( ... )` which returns the sum of its arguments. Nulls, and other data that cannot be coerced to a number are skipped silently. Any arrays are traversed and their elements handled in the same way, for example, `sum(list(1,2,3))` returns 6, and `sum(4,5,6,list(1,2,3))` returns 24.
* Add function `count( ... )` which returns the number of non-null arguments. If any argument is an array, the array's elements are scanned and included in the count. That is, `count(4,5,6,list(1,2,3))` is 6. This allows `count()` and `sum()` to work together to calculate a reliable mean when the data contains nulls or sub-lists. This approach is also consistent with `min()` and `max()`.
* The function `replace( string, fstr, rstr )` was previously documented but never implemented. It now exists. It is an analog for Lua's `string.gsub()` (e.g. patterns apply), except that a function/expression cannot be used as the replacement argument `rstr` currently; only strings may be used. It returns the modified string.
* Additional tests for the above functions, and several test jig updates for more current handling of local variables in the test environment, have been implemented.

## 1.0.1

* Add `indexof( array, item [, start] )` function to find item in array with optional starting index. Returns 0 if item not found.

## 1.0.0

* Add `date(year[, month[ ,day[ ,hour[ ,min[ ,sec]]]]])` function to create datetime from parts as arguments. The current value is used for any part not provided or `null` (e.g. `date(null,1,1,0,0,0)` returns midnight Jan 1 of the current year. Trailing `null` arguments may be omitted (i.e. `date(2019,11,4)` is the same as `date(2019,11,4,null,null,null)`). Time is built in the current timezone.
* Add `map(array[, expr[, varname]])`; similar to `iterate()`, it loops over the array, performing `expr` on each value, and builds a table with key as the original value, and the result of the expression as the value. For example, `map(list("dog","cat","fish"), _+" food")` returns a table `{ "dog"="dog food", "cat"="cat food", "fish"="fish food" }`. If either the value or the result of the expression is `null`, it is omitted from the result table. In the expression, the value is represented by the pseudo-variable `_` (underscore). If you give `varname` (third argument) to `map()`, that string will be used as the variable name instead. The special additional pseudo-variable `__` (two underscores) is populated with the index in the array of each value as processed, such that `map(list("dog","cat","fish"), __)` yields `{ "dog"=1, "fish"=3, "cat"=2 }`. If no expression is given, the default `__` (two underscores--the array index) is used (that is, `map(array)` is equivalent to `map(array, __)`).
* The `timepart([timestamp[, utc]])` function, which returns the time parts (a table with keys year, month, day, hour, min, sec, isdst) for the given timestamp (optional, default current time/date), not accepts an optional `utc` argument, which when *true* returns the UTC parts rather than the local time parts.
* POTENTIAL BREAKING CHANGE: LuaXP now attempts to load a `bit` (bitlib, etc.) module. If such a module can be loaded and contains the required functions, it is used; otherwise, the legacy internal implementation (weak, but wiggling) is used. Note that the results of these various implementations vary, so the user/integrator is advised to choose a library and be consistent. 
* POTENTIAL BREAKING CHANGE: The `__` name is now a reserved word.

## 0.9.9

* Ignore whitespace between function name and paren in function refs (do same for array refs), so syntax isn't so strict.
* Slight optimizations throughout.
* Add Lua `..` string concatenation operator.
* POTENTIAL BREAKING CHANGE: the "+" operator now does a better job identifying strings containing numbers as numbers, and handling the operation as addition rather than string concatenation. I doubt this will present any issues except for (hopefully rare) cases where you actually want `"123"+"456"` to equal "123456". The `..` operator (Lua string concatentation) has been added for deterministic handling as strings (e.g. `'123'..'456'` will always produce the string '123456' and not the number 579).

## 0.9.8

* Implement `split( string, sep )` function; splits `string` to an array on `sep` (e.g. `split( "1,2,3", ",")` returns array [1,2,3]). `Sep` is a Lua pattern, so special chars must be escaped in the Lua pattern way (e.g. to use "+" as a separator, must specify "%+").
* Implement `join( array, sep )` function; joins array elements with `sep` into a string result (e.g. `join( list( 1,2,3 ), ":")` result is "1:2:3" ).

## 0.9.7

* Support deferred evaluation for `if()` and `iterate()`, and logical operators (&&/and, ||/or)
* Change license to MIT License (previously GPL3)

## 0.9.4

* Numerous bug fixes.
* Test suite.
* Iteration, lists (arrays), assignments (issue #3).
* Improve error reporting (issue #2).