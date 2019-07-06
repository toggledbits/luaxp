# LuaXP Change Log

## 0.9.9

* Ignore whitespace between function name and paren in function refs (do same for array refs), so syntax isn't so strict.
* Slight optimizations throughout.
* Add Lua `..` string concatenation operator.
* POTENTIAL BREAKING CHANGE: the "+" operator now does a better job identifying strings containing numbers as numbers, and handling the operation as addition rather than string concatenation. I doubt this will present any issues except for (hopefully rare) cases where you actually want `"123"+"456"` to equal "123456". The `..` operator (Lua string concatentation) as been added for deterministic handling as strings (e.g. `'123'..'456'` will always produce the string '123456' and not the number 579).

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