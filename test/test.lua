luaxp = require('luaxp')

_T = {}

local n = 0

_T.testeval = function(test, expect)
	n = n + 1
	local r = luaxp.evaluate(test)
	local s
	if (string.find(expect, "%%") ~= nil) then
		if (string.find(tostring(r), expect) ~= nil) then s = "MATCH" else s = "*** FAIL ***" end
	elseif (tostring(r) == expect) then s = "OK" else s = "*** FAIL ***" end
	print(n, test, expect, tostring(r), s)
end

return _T