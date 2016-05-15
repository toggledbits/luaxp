# luaxp
Luaxp is a simple arithmetic expression parser for Lua.

Luaxp supports simple mathemtical expressions for addition, subtraction, multiplication,
division, modulus, bitwise operations, and logical operations. It has a small library of
built-in functions (abs, cos, sin, floor, ceil, round, etc.).

Through a passed-in context table, Luaxp supports named variables, and custom functions.
See the documentation below for how to implement these.

Luaxp is offered under GPL 3.0.

## Installation ##

Some day. This is all very new. 

Grab it. Put in your shared Lua directory (`/usr/share/lua/...?`) or keep it where you use it. Try out the 
free-form test program `try_luaxp.lua`. This lets you enter expressions and see the results.

TO-DO: Install with LuaRocks

## Bug Reports and Contributions ##

I wrote this library as a port of a similar
library I wrote for JavaScript called lexp.js (Lightweight Expression Parser). It differs slightly
in operation, but the underlying approach is fundamentally the same and it's a very close port. I
did this mainly for fun. I use lexp.js in a dashboard system that I wrote (I wanted
something simpler to set up and
manage than dashing, which is great, but has way too high a setup and learning curve, but I digress),
and figured that somebody might make use of it in Lua as well.

I like bug reports. I like help. I like making things better. If you have suggestions or bug reports
please use use [GitHub Issues](https://github.com/toggledbits/luaxp/issues). If you have a
contribution, have at it! Please try to follow the coding style to keep it consistent, and use spaces
rather than tabs (4 space indenting).

Also, if you're making a feature enhancement contribution, consider looking at my lexp project as well,
and see if the same enhancement would be appropriate there. Since the Lua implementation is born of the
JavaScript one, I think it would be an interesting exercise to try and keep them as close functionally
as possible.

TO-DO: Link to lexp github repository

## Grammar ##

TO-DO

## The Basics ##

To load the library, use a `require()` statement:

```
luaxp = require('luaxp')
```

### compile( expressionString ) ###

The `compile()` function accepts a single argument, the string the containing the expression to be parsed.
The return value is a table containing the tokenized parser results. This is then used as the argument to 
`run` to evaluate the expression.

After parsing and before calling run(), it is generally advisable to call getLastError() to see 
if an error occurred.

Example:

```
luaxp = require('luaxp')

local r = luaxp.compile( "355 / 113" )
```

### run( parsedResult [, executionContext ] ) ###

The `run()` function executed the parsed expression. It takes an optional `executionContext` argument, which 
a table containing variable names and functions.

`run()` returns the result of the expression evaluation. If the evaluation succeeds, this will always be a
Lua `number` or `string` data type. If it fails, a Lua `table` is returned containing a string at the
`message` key to tell you what went wrong.

```
luaxp = require('luaxp')

local r = luaxp.compile( "(355/113) - pi" )

local context = {}
context.pi = math.pi

print("The result of the expression is: " .. luaxp.run( r, context ) )
```

In the above example, a context is created to define the value of "pi" that is used in the parsed expression.
This context is then passed to `run()`, which uses it to dereference the value on the fly.

As of this version, Luaxp does not allow you to create or set variables from within the expression.

### evaluate( expressionString [, executionContext ] ) ###

The `evaluate()` function performs the work of `compile()` and `run()` in one step. There is no
error-checking between--it simply returns `nil` if the expression cannot be parsed, or there is an
evaluation-time error.

## Custom Functions ##

You can define custom functions for your expressions by defining them in the context passed to `run()` or
`evaluate()`. 

It's pretty straightforward to do. Your custom function must be implemented by a Lua function that takes a 
single argument, which I'll call `argv` simply for example purposes. This is an array of the expression values
parsed.

Let's say we want to create a function to convert degrees to radians. The math for that is pretty easy.
It's the value in degrees times "pi" and divided by 180. If you wrote that just as a plain Lua function,
it would probably look something like this:

```
function toRadians(degrees)
    return degrees * math.pi / 180
end
```

To make that a function that your expressions could use, you need to put it into the context that's passed
to `run()`, which is done like this:

```
local context = {}
context.toradians = function( argv )
    return args[1] * math.pi / 180
end
```

Now, when you run your expression, you can pass this context, and the evaluator will know what `toradians`
means in the expression:

```
luaxp = require('luaxp')

local context = {}
context.toradians = function( argv )
    return argv[1] * math.pi / 180
end

print("The cosine of 45 degrees is " .. luaxp.evaluate("cos(toradians(45))", context))
```

Notice that we've used an anonymous function here. You could just as easily do this:

```
-- Define the function
function toRadians(degrees)
    return degrees * math.pi / 180
end

-- Use a function reference in the context
local context = {}
context.toradians = toradians
```

The premise here is simple, if it's not already clean enough. The evaluator will simply look in your passed
context for any name that it doesn't recognize as one of its predefined functions. 
If it finds a table element with a 
key equal to the name, the value is assumed to be a function it can call. The function is called with a 
single argument, a table (as an array) containing all of the arguments that were parsed in the expression.
There is no limit to the number of arguments. Your function is responsible for sanity-checking the number
of arguments, their values/type, and supplying defaults if necessary.

If we run our program (which is available as `example1.lua` in the repository), here's the output:

```
$ lua example1.lua
The cosine of 45 degrees is 0.70710678118655
```