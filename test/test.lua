luaxp = require('luaxp')

_T = {}

local n = 0
local fail = "*** FAIL ***"

_T.testeval = function(test, expect)
	n = n + 1
	local r,m = luaxp.evaluate(test)
	local s = fail
	if (r == nil) then 
		r = "error(" .. tostring(m) .. ")" 
	elseif (string.find(expect, "%%") ~= nil) then
		if (string.find(tostring(r), expect) ~= nil) then 
			s = "MATCH" 
		end
	elseif (tostring(r) == expect) then 
		s = "OK" 
	end
	print(n, test, expect, tostring(r), s)
end

return _T