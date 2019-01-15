# luaxp
Luaxp is a simple arithmetic expression parser for Lua.

Luaxp supports simple mathemtical expressions for addition, subtraction, multiplication,
division, modulus, bitwise operations, and logical operations. It has a small library of
built-in functions (abs, cos, sin, floor, ceil, round, etc.).

Through a passed-in context table, Luaxp supports named variables, and custom functions.
See the documentation below for how to implement these.

Luaxp is offered under MIT License as of October 29, 2018 (beginning with version 0.9.7).

## Github

There are three branches in the Github repository:
* master - The current released version; this is the version to use/track if you are incorporating LuaXP into other projects;
* develop - The current development version, which may contain work in progress, partial implementations, debugging code, etc. ("the bleeding edge");
* stable - The current stable development code, which contains only completed and tested functionality, but may still contain debug messages and lack some optimizations and refinement.

Code moves from the develop branch to the stable branch to the master branch. There is no release schedule. Releases are done as needed.

## Installation ##

Some day. This is all very new. 

Grab it. Put in your shared Lua directory (`/usr/share/lua/...?`) or keep it where you use it. Try out the 
free-form test program `try_luaxp.lua`. This lets you enter expressions and see the results.

TO-DO: Install with LuaRocks

## Known Issues ##

As of version 0.9.7, the following are known issues or enhancement that are currently being considered:

None

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

Also, if you're making a feature enhancement contribution, consider looking at [my lexp project](https://github.com/toggledbits/lexpjs) as well,
and see if the same enhancement would be appropriate there. Since the Lua implementation is born of the
JavaScript one, I think it would be an interesting exercise to try and keep them as close functionally
as possible.

## Syntax ##

This is a very rough BNF for the parser:

```
<expression> ::= <number>
               | <string>
               | <variable-name>
               | <variable-name> "[" <array-subscript> "]"
               | <function-name> "(" <argument-list> ")"
               | <expression> <binary-operator> <expression>
               | <unary-operator> <expression>
               | "(" <expression> ")"
               
<argument-list> ::= "" | <expression-list>
                  
<expression-list> ::= <expression> [ "," <expression-list> ]

<unary-operator> ::= "-" | "+" | "!"

<binary-operator> ::= "+" | "-" | "*" | "/" | "%"
                    | "&" | "|" | "^"
                    | "<" | "<=" | ">" | ">=" | "==" | "=" | "<>" | "!="
                    
<array-subscript> :== <number> | <expression> /* must eval to number */

<number> ::= <decimal-integer>
           | "0x" <hexadecimal-integer>
           | "0b" <binary-integer>
           | "0" <octal-integer>
           | <decimal-rational-number>
         
<string> ::= "'" <characters> "'"
           | '"' <characters> '"'
           
<variable-name> ::= <letter> { <letter> | <digit> | "_" | "." }

<function-name> ::= <letter> { <letter> | <digit> | "_" }
```

This is intentionally simplified and doesn't exhaustively convey the full syntax, which would be too detailed to convey the concept quickly. Specific elements of the syntax such are array and dot notation for traversal of trees/structures is not shown (e.g. expressions forms "weather.current" and "weather['current'], which are equivalent).

## The Basics ##

To load the library, use a `require()` statement:

```
luaxp = require "luaxp"
```

### compile( expressionString ) ###

The `compile()` function accepts a single argument, the string the containing the expression to be parsed.
If parsing of the expression succeeds, the function returns a table containing the parse tree that is used 
as input to `run()` later. If parsing fails, the function returns two values: `nil` and a table containing information about the error.

Example:

```
luaxp = require('luaxp')

local parsedExp,err = luaxp.compile("abs(355/113-pi)")
if parsedExp == nil then
    -- Parsing failed
    print("Expression parsing failed. Reason: " .. luaxp.dump(err))
else
    -- Parsing succeeded, on to other work...
	...
end
```

This example uses the LuaXP public function `dump()` to display the contents of the `err` table returned.

### run( parsedExp [, executionContext ] ) ###

The `run()` function executes the parsed expression. It takes an optional `executionContext` argument, which 
is a table containing variable names and functions.

`run()` returns the result of the expression evaluation. If the evaluation succeeds, the first return value will always be non-`nil`. If it fails, two values are returned: `nil` and a string containing the
error message (i.e. same semantics as `compile()`). You should always check for evaluation errors, as these are errors that were not or could not be detected in parsing (e.g. a sub-expression used as a divisor evaluates to zero, thus an attempt to divide by zero).

```
luaxp = require "luaxp" 

local parsedExp, cerr = luaxp.compile("abs(355 / 113 - pi)" )
if parsedExp == nil then error("Parsing failed: " .. cerr.message) end

local context = { pi = math.pi }

local resultValue, rerr = luaxp.run( parsedExp, context )
if resultValue == nil then
    error("Evaluation failed: " .. rerr.message)
else
    print("Result:", luaxp.isNull(resultValue) and "NULL" or tostring(resultValue) )
end
```

In the above example, a context is created to define the value of "pi" that is used in the parsed expression.
This context is then passed to `run()`, which uses it to dereference the value on the fly.

The code also checks the return value for the special "null" value. If the result of an expression results in "no value", LuaXP does not use Lua `nil`, it has its own indicator, and your code should check for this as shown above.

As of this version, Luaxp does not allow you to modify variables or create new ones during evaluation.

### evaluate( expressionString [, executionContext ] ) ###

The `evaluate()` function performs the work of `compile()` and `run()` in one step. The function result
is the value of the parsed and evaluated expression, unless a parsing or evaluation error occurs, in which
case the function will return two values: `nil` and an error message.

```
luaxp = require "luaxp"

local context = { pi = math.pi }
local resultValue,err = luaxp.evaluate("abs(355/113-pi)", context)
if resultValue == nil then
    error("Error in evaluation of expression: " .. err.message)
else
	print("The difference between the two approximations of pi is " .. tostring(result))
end
```

### Other Functions and Values

The LuaXP `dump()` function will return a string containing a safely-printable representation of the passed value. If the value passed is a table, for example, `dump()` will display it in a Lua-like table initialization syntax (tuned for readability, not for re-use as actual Lua code).

The `isNull()` function returns a boolean indicating if the passed argument is LuaXP's null value.

The `null` and `NULL` constants (synonyms) are the represtations of LuaXP's null value. Thus the test `returnValue==luaxp.null` in Lua is equivalent to `isNull(returnvalue)`. The constants can also be used to initialize values when creating the execution context.

### Reserved Words

The words `true` and `false` are reserved and evaluate to their respective boolean values. The words `null`, `NULL`, and `nil` evaluate to the LuaXP null value.

The reserved words `pi` and `PI` (synonyms) are provided as a convenience and evaluate to the underyling Lua Math library implementation of `math.pi`.

### Error Returns

If a LuaXP call results in an error (`nil` first return value), the error table (second return value) contains the following elements:
* `type` - Always included, the string "compile" or "evaluation" to indicate the stage at which the error was detected.
* `message` - Always included, text describing the error.
* `location` - Sometimes included, the character position at which the error was detected, if available.

The _try_luaxp.lua_ example included with LuaXP shows how the `location` value can be used to provide feedback to the user when errors occur. Try entering "0b2" and "max(1,2,nosuchname)" into this example program.

## Context Variables ##

The context passed to `evaluate()` and `run()` is used to define named variables and custom functions
that can be used in expressions. We've seen in the above examples for these functions how that works.
For variables, it's simple a matter of defining a table element with the value to be used:

```
local context = {}
context.minrange = 0
context.maxrange = 100

-- or the more streamlined:

local context = { minrange=0, maxrange=100 }
```

These may be referred to in expressions simply by their names as defined (case sensitive):

```
$ lua try_luaxp.lua
Running with Luaxp version 0.9.2
Context variables defined:
    minrange=0 
    maxrange=100

EXP> maxrange
Expression result: 100

EXP> (maxrange-minrange)/2
Expression result: 50

EXP> nonsense
Expression evaluation failed: Undefined variable: nonsense
```

Variables can also use dotted notation to traverse a tree of values in the context:

```
context.device = {}
context.device.class = "motor"
context.device.info = { location="MR1-15-C02", specs={ manufacturer="Danfoss", model="EM5-18-184T", frame="T", voltage="460", hp="5" } }
```

In expressions, the value `device.class` would therefore be *motor*. Referring simply to `device`, however, would return a runtime
evaluation error.

The second more complex example shows that dotted notation can be used to traverse more deeply-nested structure. In this example,
one could derive the horsepower of the example motor by referring to `device.info.specs.hp`.

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
luaxp = "luaxp"

local context = {}
context.toradians = function( argv )
    return argv[1] * math.pi / 180
end

print("The cosine of 45 degrees is " .. luaxp.evaluate("cos(toradians(45))", context))
```

Although we have used an anonymous function in this example, there is no reason you could not separately
define a named function, and simply use a reference to the function name in the context assignment, like
this:

```
function toRadians(argv)
    return argv[1] * math.pi / 180
end
context.toradians = toRadians
```

The premise here is simple, if it's not already clear enough. The evaluator will simply look in your passed
context for any name that it doesn't recognize as one of its predefined functions. 
If it finds a table element with a 
key equal to the name, the value is assumed to be a function it can call. The function is called with a 
single argument, a table (as an array) containing all of the arguments that were parsed in the expression.
There is no limit to the number of arguments. Your function is responsible for sanity-checking the number
of arguments, their values/type, and supplying defaults if necessary.

Note in the above example that we defined our function with an uppercase letter "R" in the name,
but when we made the context assignment, the context element has all lower case. This means that 
any expression would also need to use all lower case. The name used in evaluation is the name on
the context element, not the actual name of the function.

If we run our program (which is available as `example1.lua` in the repository), here's the output:

```
$ lua example1.lua
The cosine of 45 degrees is 0.70710678118655
```

## "Local" Variables

The evaluator supports assignment of a value to local variable. If multiple expressions are evaluated using the same context, the local variables defined by earlier expressions are visible to the later ones.

```
luaxp = require "luaxp"

ctx = {}
result = luaxp.evaluate( "v=100", ctx )
print(result) -- prints 100

result = luaxp.evaluate( "v=v*2", ctx )
print(result) -- prints 200

result = luaxp.evaluate( "v/5", ctx )
print(result) -- prints 40
```

The local variables accumulated in the context are stored under the `__lvars` key. Thus, in this example, `ctx.__lvars.v` would be defined and have the value 40 in Lua after all three evaluations.

Local variables are in scope before context variables (that is, if a local variable has the same name as a context variable, the local variable will always take precedence):

```
luaxp = require "luaxp"

ctx = {}
ctx.alpha = 57 -- context variable definition
result = luaxp.evaluate( "alpha", ctx )
print(result) -- prints 57 as expected

-- This expression creates a local variable with the same name
luaxp.evaluate( "alpha=99", ctx )

-- Now that we've set local alpha, we can't "see" the context variable
result = luaxp.evaluate( "alpha", ctx )
print(result) -- prints 99

-- If we print what's in the context, we see two different values, one
-- for the original context variable as we defined it, the other for 
-- the local variable defined by the expression evaluation.
print(ctx.alpha) -- prints 57
print(ctx.__lvars.alpha) -- prints 99
```