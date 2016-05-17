luaxp = require('luaxp')

_T = {}

local n = 0
local fail = "*** FAIL ***"

_T.testeval = function(test, expect, ctx)
	local status = false
	ctx = ctx or {}
	n = n + 1
	local r,m = luaxp.evaluate(test, ctx)
	local s = fail
	if (r == nil) then 
		r = "error(" .. tostring(m) .. ")" 
	elseif (string.find(expect, "%%") ~= nil) then
		if (string.find(tostring(r), expect) ~= nil) then 
			s = "MATCH" 
			status = true
		end
	elseif (tostring(r) == expect) then 
		s = "OK" 
		status = true
	end
	print(n, test, expect, tostring(r), s)
	return status
end

return _T