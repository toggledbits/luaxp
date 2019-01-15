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
* master - The current released version this is the version to use/track if you are incorporating LuaXP into other projects;
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

Also, if you're making a feature enhancement contribution, consider looking at my lexp project as well,
and see if the same enhancement would be appropriate there. Since the Lua implementation is born of the
JavaScript one, I think it would be an interesting exercise to try and keep them as close functionally
as possible.

TO-DO: Link to lexp github repository

## Syntax ##

This is a very rough BNF for the parser:

```
<expression> ::= <number>
               | <string>
               | <variable-name>
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

## The Basics ##

To load the library, use a `require()` statement:

```
luaxp = require('luaxp')
```

### compile( expressionString ) ###

The `compile()` function accepts a single argument, the string the containing the expression to be parsed.
If parsing of the expression succeeds, the function returns a table containing the parse tree that is used 
as input to `run()` later. If parsing fails, the function returns two values: `nil` and a string containing
the error message.

Example:

```
luaxp = require('luaxp')

local pr, message
pr,message = luaxp.compile("abs(355/113-pi)")
if (pr == nil) then
    -- Parsing failed
    print("Expression parsing failed. Reason: " .. message)
else
    -- Parsing succeeded, on to other work...
	...
end
```

### run( parsedResult [, executionContext ] ) ###

The `run()` function executes the parsed expression. It takes an optional `executionContext` argument, which 
is a table containing variable names and functions.

`run()` returns the result of the expression evaluation. If the evaluation succeeds, this will always be a
Lua `number` or `string` data type. If it fails, two values are returned: `nil` and a string containing the
error message (i.e. same semantics as `compile()`).

```
luaxp = require('luaxp')

local pr, message
pr,message = luaxp.compile("abs(355 / 113 - pi)" )
if (pr == nil) then error("Parsing failed: " .. message) end

local context = { pi = math.pi }

print("The result of the expression is: " .. luaxp.run( pr, context ) )
```

In the above example, a context is created to define the value of "pi" that is used in the parsed expression.
This context is then passed to `run()`, which uses it to dereference the value on the fly.

As of this version, Luaxp does not allow you to modify variables or create new ones during evaluation.

### evaluate( expressionString [, executionContext ] ) ###

The `evaluate()` function performs the work of `compile()` and `run()` in one step. The function result
is the value of the parsed and evaluated expression, unless a parsing or evaluation error occurs, in which
case the function will return two values: `nil` and an error message.

```
luaxp = require('luaxp')

local result, message
local context = { pi = math.pi }
result,message = luaxp.evaluate("abs(355/113-pi)", context)
if (result == nil) then
    error("Error in evaluation of expression: " .. message)
else
	print("The difference between the two approximations of pi is " .. tostring(result))
end
```

## User-defined Variables ##

The context passed to `evaluate()` and `run()` is used to define named variables and custom functions
that can be used in expressions. We've seen in the above examples for these functions how that works.
For variables, it's simple a matter of defining a table element with the value to be used:

```
local context
context.pi = math.pi
context.minrange = 0
context.maxrange = 100
```

These are referred to in expressions simply by their names as defined (case sensitive):

```
$ lua try_luaxp.lua
Running with Luaxp version 0.9.2
Context variables defined:  minrange=0 pi=3.14159265 maxrange=100

EXP> pi
Expression result: 3.14159265

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
luaxp = require('luaxp')

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
