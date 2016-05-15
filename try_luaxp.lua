local luaxp = require('luaxp')

local io = require("io")

local r, s

local ctx = { pi = 3.14159265, min = "1", max="100" }
io.write("Context variables defined: ")
for r,s in pairs(ctx) do io.write(" " .. r .. "=" .. s) end
io.write("\n")

while (true) do 
	io.write("\nEXP> ")
	io.flush()
	s = io.read()
	r = luaxp.compile(s)
	io.write("Compile result: ")
	io.write(luaxp.dump(r))
	io.write("\n")
	io.write("Expression result: " .. tostring(luaxp.run(r, ctx)).."\n")
end

