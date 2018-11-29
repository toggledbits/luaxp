# LuaXP Change Log #

## 0.9.8 ##

* Implement split( string, sep ) function; splits string to array on sep (e.g. split( "1,2,3", ",") returns array [1,2,3]). Sep is a Lua pattern, so special chars must be escaped in the Lua pattern way (e.g. to use "+" as a separator, must specify "%+").
* Implement join( array, sep ) function; joins array elements with sep into string result (e.g. join( list( 1,2,3 ), ":") result is "1:2:3" ).

## 0.9.7 ##

* Support deferred evaluation for if() and iterate(), and logical operators (&&/and, ||/or)
* Change license to MIT License (previously GPL3)

## 0.9.4 ##

* Numerous bug fixes.
* Test suite.
* Iteration, lists (arrays), assignments (issue #3).
* Improve error reporting (issue #2).