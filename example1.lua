luaxp = require('luaxp')

local context = {}
context.toradians = function( argv )
    return argv[1] * math.pi / 180
end

print("The cosine of 45 degrees is " .. luaxp.evaluate("cos(toradians(45))", context))

