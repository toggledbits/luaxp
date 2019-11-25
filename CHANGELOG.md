# LuaXP Change Log

## 1.0

* Add `date(year[, month[ ,day[ ,hour[ ,min[ ,sec]]]]])` function to create datetime from parts as arguments. The current value is used for any part not provided (e.g. `date(null,1,1,0,0,0)` returns midnight Jan 1 of the current year. Trailing `null` arguments may be omitted (i.e. `date(2019,11,4)` is the same as `date(2019,11,4,null,null,null)`). Time is built in the current timezone.
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

* Implement split( string, sep ) function; splits string to array on sep (e.g. split( "1,2,3", ",") returns array [1,2,3]). Sep is a Lua pattern, so special chars must be escaped in the Lua pattern way (e.g. to use "+" as a separator, must specify "%+").
* Implement join( array, sep ) function; joins array elements with sep into string result (e.g. join( list( 1,2,3 ), ":") result is "1:2:3" ).

## 0.9.7

* Support deferred evaluation for if() and iterate(), and logical operators (&&/and, ||/or)
* Change license to MIT License (previously GPL3)

## 0.9.4

* Numerous bug fixes.
* Test suite.
* Iteration, lists (arrays), assignments (issue #3).
* Improve error reporting (issue #2).