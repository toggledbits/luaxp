local luaxp = require "luaxp"
local io = require "io"

local r, s, v, m
local ctx = { minrange = 0, maxrange=100, Device_Num_217={ status="OK", time=140394202, states={ { id="100", value="Hundred" }, { id="290", value="abc" } } } }

io.write("Running with Luaxp version " .. luaxp._VERSION .. "\n")
io.write("Context variables defined:\n")
for r,s in pairs(ctx) do io.write("    " .. r .. "=" .. luaxp.dump(s) .. "\n") end
io.write("\n")

ctx.__functions = {}
ctx.__functions.whiz = function(argv) return string.rep("*",argv[1]) end

local function showErrorLocation( exprString, errStruct )
    if errStruct and errStruct.location then
        io.write(exprString)
        io.write("\n")
        io.write(string.rep(" ", errStruct.location-1))
        io.write("^\n")
    end
end

while (true) do 
	io.write("\nEXP> ")
	io.flush()
	s = io.read()
	if (s == nil) then break end
	r, m = luaxp.compile(s)
	if (r == nil) then
		io.write("Expression parse failed: " .. luaxp.dump(m) .. "\n")
        showErrorLocation( s, m )
	else
        if false then
            io.write("Compiled result: ")
            io.write(luaxp.dump(r))
            io.write("\n")
        end
		v,m = luaxp.run(r, ctx)
		if (v == nil) then
			io.write("Expression evaluation failed: " .. luaxp.dump(m) .. "\n")
            showErrorLocation( s, m )
		else
			io.write("Expression result: " .. ( luaxp.isNull(v) and "(null)" or luaxp.dump(v) ).."\n")
		end
	end
end
