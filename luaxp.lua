------------------------------------------------------------------------
-- LUAXP version 0.1.0 2016-05-15
-- LuaXP is a simple expression evaluator for Lua, based on lexp.js, a
-- lightweight (math) expression parser for JavaScript by the same
-- author.
--
-- Author: Patrick Rigney <patrick@toggledbits.com>
-- License: GPL 3.0 (see Github/LICENSE for details)
-- Github: 
------------------------------------------------------------------------
local _M = {}

local string = require("string")
local math = require("math")
local base = _G

local VREF = 'vref'
local FREF = 'fref'
local UNOP = 'unop'
local BINOP = 'binop'

_M.version = "0.9.1"
_M.debug = false

local binops = { 
	  { op='*', prec=3 }
	, { op='/', prec=3 }
	, { op='%', prec=3 }
	, { op='+', prec=4 }
	, { op='-', prec=4 }
	, { op='<', prec=6 }
	, { op='<=', prec=6 }
	, { op='>', prec=-6 }
	, { op='>=', prec=6 }
	, { op='==', prec=7 }
	, { op='<>', prec=7 }
	, { op='!=', prec=7 }
	, { op='~=', prec=7 }
	, { op='&', prec=8 }
	, { op='^', prec=9 }
	, { op='|', prec=10 }
	, { op='=', prec=14 }
}
local MAXPREC = 99 -- value doesn't matter as long as it's >= any used in binops

local charmap = { t = "\t", r = "\r", n = "\n" }

local function pow(b, x)
	return math.exp(x * math.log(b))
end

local nativeFuncs = {
	  abs = { nargs = 1, impl = function( argv ) if (argv[1] < 0) then return -argv[1] else return argv[1] end end }
	, sgn = { nargs = 1, impl = function( argv ) if (argv[1] < 0) then return -1 elseif (argv[1] == 0) then return 0 elseif (argv[1] == -0) then return -0 else return 1 end end }
	, floor = { nargs = 1, impl = function( argv ) return math.floor(argv[1]) end }
	, ceil = { nargs = 1, impl = function( argv ) return math.ceil(argv[1]) end }
	, round = { nargs = 1, impl = function( argv ) local n = argv[1] local p = argv[2] or 0 return math.floor( n * pow(10, p) + 0.5 ) / pow(10, p) end }
	, cos = { nargs = 1, impl = function( argv ) return math.cos(argv[1]) end }
	, sin = { nargs = 1, impl = function( argv ) return math.sin(argv[1]) end }
	, tan = { nargs = 1, impl = function( argv ) return math.tan(argv[1]) end }
	, log = { nargs = 1, impl = function( argv ) return math.log(argv[1]) end }
	, exp = { nargs = 1, impl = function( argv ) return math.exp(argv[1]) end }
	, pow = { nargs = 2, impl = function( argv ) return pow(argv[1], argv[2]) end }
	, sqrt = { nargs = 1, impl = function( argv ) return math.sqrt( argv[1] ) end }
	, min = { nargs = 2, impl = function( argv ) if (argv[1] <= argv[2]) then return argv[1] else return argv[2] end end }
	, max = { nargs = 2, impl = function( argv ) if (argv[1] >= argv[2]) then return argv[1] else return argv[2] end end }
	, len = { nargs = 1, impl = function( argv ) return string.len(tostring(argv[1])) end }
	, sub = { nargs = 2, impl = function( argv ) local st = tostring(argv[1]) local p = argv[2] local l = argv[3] or -1 return string.sub(st, p, l) end }
	, upper = { nargs = 1, impl = function( argv ) return string.upper(tostring(argv[1])) end }
	, lower =  { nargs = 1, impl = function( argv ) return string.lower(tostring(argv[1])) end }
	, tonumber = { nargs = 1, impl = function( argv ) return tonumber(argv[1], argv[2] or 10) end }
	, time = { nargs = 0, impl = function() return os.time() end }
}

-- Adapted from "BitUtils", Lua-users wiki at http://lua-users.org/wiki/BitUtils; think you kind stranger(s)...
local bit = {}
bit['nand'] = function(x,y,z)
    z=z or 2^16
    if z<2 then
        return 1-x*y
    else
        return bit.nand((x-x%z)/z,(y-y%z)/z,math.sqrt(z))*z+bit.nand(x%z,y%z,math.sqrt(z))
    end
end
bit["bnot"]=function(y,z)
    return bit.nand(bit.nand(0,0,z),y,z)
end
bit["band"]=function(x,y,z)
    return bit.nand(bit["bnot"](0,z),bit.nand(x,y,z),z)
end
bit["bor"]=function(x,y,z)
    return bit.nand(bit["bnot"](x,z),bit["bnot"](y,z),z)
end
bit["bxor"]=function(x,y,z)
    return bit["band"](bit.nand(x,y,z),bit["bor"](x,y,z),z)
end

-- Forward declarations
local _comp
local scan_token

_M._debug = function(s)
	if (_M.debug) then print(s) end
end

_M.dump = function(t)
	local typ = base.type(t)
	st = "(" .. typ .. ")"
	if (typ == "table") then 
		st = st .. "{ "
		local n,v
		local first = true
		for n,v in pairs(t) do
			if (not first) then st = st .. ", " end
			st = st .. n .. "=" .. _M.dump(v)
			first = false
		end
		st = st .. "}"
	else
		st = st .. tostring(t)
	end
	return st
end

local function error( msg, index )
	_M._debug(msg .. " at " .. index)
	return index, nil
end

-- Skips white space, returns index of non-space character or nil
local function skip_white( expr, index )
	_M._debug("skip_white from " .. index .. " in " .. expr)
	local len = string.len(expr)
	local ch
	while (index <= len) do
		ch = string.sub(expr, index, index)
		if ( not (ch == ' ' or ch == '\t') ) then return index end
		index = index + 1
	end
	return index
end

-- Scan a numeric token. Supports fractional and exponent specs in
-- decimal numbers, and binary, octal, and hexadecimal integers.
local function scan_numeric( expr, index ) 
	_M._debug("scan_numeric from " .. index .. " in " .. expr)
	local len = string.len(expr)
	local start = index
	local ch, i
	local val = 0
	local base = 0
	-- Try to guess the base first
	ch = string.sub(expr, index, index)
	if (ch == '0' and index < len) then
		-- Look to next character
		index = index + 1
		ch = string.sub(expr, index, index)
		if (ch == 'b' or ch == 'B') then 
			base = 2
			index = index + 1
		elseif (ch == 'x' or ch == 'X') then
			base = 16
			index = index + 1
		elseif (ch == '.') then
			base = 10 -- going to be a decimal number
		else
			base = 8
		end
	end
	if (base <= 0) then base = 10 end
	-- Now parse the whole part of the number
	while (index <= len) do
		ch = string.sub(expr, index, index)
		if (ch == '.') then break end
		i = string.find("0123456789ABCDEF", string.upper(ch))
		if (i == nil) then break end
		if (i > base) then break end
		val = base * val + (i-1)
		index = index + 1
	end
	-- Parse fractional part, if any
	if (ch == '.' and base==10) then 
		local ndec = 0
		index = index + 1 -- get past decimal point
		while (index <= len) do
			ch = string.sub(expr, index, index)
			i = string.find("0123456789", ch)
			if (i == nil) then break end
			ndec = ndec - 1
			val = val + (i-1) * pow(10, ndec)
			index = index + 1
		end
	end
	-- Parse exponent, if any
	if ( (ch == 'e' or ch == 'E') and base == 10 ) then
		local npow = 0
		index = index + 1 -- get base exponent marker
		while (index <= len) do 
			ch = string.sub(expr, index, index)
			i = string.find("0123456789", ch)
			if (i == nil) then break end
			npow = npow * 10 + (i-1)
			index = index + 1
		end
		val = val * pow(10,npow)
	end
	-- Return result
	_M._debug("scan_numeric returning index=" .. index .. ", val=" .. val)
	return index, val
end

-- Parse a string. Trivial at the moment and needs escaping of some kind
local function scan_string( expr, index )
	_M._debug("scan_string from " .. index .. " in " .. expr)
	local len = string.len(expr)
	local st = ""
	local i
	local qchar = string.sub(expr, index, index)
	index = index + 1
	while (index <= len) do
		i = string.sub(expr, index, index)
		if (i == '\\' and index < len) then
			index = index + 1
			i = string.sub(expr, index, index)
			if (charmap[i] ~= nil) then i = charmap[i] end
		elseif (i == qchar) then
			-- PHR??? Should we do the double char style of quoting? don''t won''t ??
			index = index + 1
			return index, st
		end
		st = st .. i
		index = index + 1
	end
	return error("Unterminated string", index)
end

-- Parse a function reference. It is treated as a degenerate case of 
-- variable reference, i.e. an alphanumeric string followed immediately
-- by an opening parenthesis.	
local function scan_fref( expr, index, name )
	_M._debug("scan_fref from " .. index .. " in " .. expr)
	local len = string.len(expr)
	local args = {}
	local parenLevel = 1
	local ch
	local subexp = ""
	while ( true ) do
		if ( index > len ) then return error("Unexpected end of argument list", index) end -- unexpected end of argument list
		
		ch = string.sub(expr, index, index)
		if (ch == ')') then
			_M._debug("scan_fref: Found a closing paren while at level " .. parenLevel)
			parenLevel = parenLevel - 1
			if (parenLevel == 0) then
				_M._debug("scan_fref: handling end of argument list with subexp=" .. subexp)
				if (string.len(subexp) > 0) then -- PHR??? Need to test out all whitespace strings from the likes of "func( )"
					table.insert(args, _comp( subexp ) ) -- compile the subexp and put it on the list
				end
				index = index + 1
				_M._debug("scan_fref returning, function is " .. name .. " with " .. table.getn(args) .. " arguments: " .. _M.dump(args))
				return index, { type=FREF, args=args, name=name }
			else
				-- It's part of our argument, so just add it to the subexpress string
				subexp = subexp .. ch
				index = index + 1
			end
		elseif (ch == ',' and parenLevel == 1) then -- completed subexpression
			_M._debug("scan_fref: handling argument=" .. subexp)
			if (string.len(subexp) > 0) then 
				local r = _comp(subexp)
				if (r == nil) then return error("Subexpression failed to compile", index) end
				table.insert(args, r)
				_M._debug("scan_fref: inserted argument " .. subexp .. " as " .. _M.dump(r))
			end
			index = skip_white( expr, index+1 )
			subexp = ""
			_M._debug("scan_fref: continuing argument scan in " .. expr .. " from " .. index)
		else
			subexp = subexp .. ch
			if (ch == '(') then parenLevel = parenLevel + 1 end
			index = index + 1
		end
	end
end

-- Scan a variable reference; could turn into a function reference
-- TODO: Dotted notation for table traversal (supported in lexp.js)
local function scan_vref( expr, index )
	_M._debug("scan_vref from " .. index .. " in " .. expr)
	local len = string.len(expr);
	local ch, k
	local name = ""
	while (index <= len) do
		ch = string.sub(expr, index, index)
		if (ch == '(') then
			-- Found possible function reference; parse argument list
			return scan_fref(expr, index+1, name)
		end
		k = string.find("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_", string.upper(ch))
		if (k == nil) then 
			break 
		elseif (name == "" and k <= 10) then 
			return error("Invalid identifier", index) -- Invalid identifier (can't start with digit)
		end
		
		name = name .. ch
		index = index + 1
	end
	
	return index, { type=VREF, name=name }
end

-- Scan nested expression (called when ( seen while scanning for token)
local function scan_expr( expr, index )
	_M._debug("scan_expr from " .. index .. " in " .. expr)
	local len = string.len(expr)
	local ch, k
	local st = ""
	local parenLevel = 0
	index = index + 1
	while (index <= len) do
		ch = string.sub(expr,index,index)
		if (ch == ')') then
			if (parenLevel == 0) then
				_M._debug("scan_expr parsing subexpression=" .. st)
				local r = _comp( st )
				if (r == nil) then return error("Subexpression failed to parse", index) end
				return index+1, r -- pass as single-element sub-expression
			end
			parenLevel = parenLevel - 1
		elseif (ch == '(') then
			parenLevel = parenLevel + 1
		end
		-- Add character to subexpression string (note drop-throughs from above conditionals)
		st = st .. ch
		index = index + 1
	end
	return index, nil -- Unexpected end of expression/unmatched paren group
end

local function scan_unop( expr, index )
	_M._debug("scan_unop from " .. index .. " in " .. expr)
	local len = string.len(expr)
	local ch, k
	ch = string.sub(expr, index, index)
	if (ch == '-' or ch == '+' or ch == '!') then
		-- We have a UNOP
		index = index + 1
		local k, r = scan_token( expr, index )
		if (r == nil) then return k, r end
		return k, { r, { type=UNOP, op=ch } }
	end
	return error("Invalid unary operator", index) -- Not a UNOP
end

local function scan_binop( expr, index )
	_M._debug("scan_binop from " .. index .. " in " .. expr)
	local len = string.len(expr)
	local matched = false
	index = skip_white(expr, index)
	if (index > len) then return index, nil end

	local op = ""
	local ch
	local k = 0
	local prec
	while (index <= len) do
		ch = string.sub(expr,index,index)
		local st = op .. ch
		local matched = false
		k = k + 1
		for n,f in ipairs(binops) do
			if (string.sub(f.op,1,k) == st) then
				-- matches something
				matched = true
				prec = f.prec
				break;
			end
		end
		if (not matched) then
			-- Didn't match anything. If we matched nothing on the first character, that's an error.
			-- Otherwise, op now contains the name of the longest-matching binop in the catalog.
			if (k == 1) then return error("Invalid operator", index) end
			break
		end
		
		-- Keep going to find longest matching binop
		op = st
		index = index + 1
	end

	_M._debug("scan_binop succeeds with op="..op)
	return index, { type=BINOP, op=op, prec=prec }
end

-- Scan our next token (forward-declared)
function scan_token( expr, index )
	_M._debug("scan_token from " .. index .. " in " .. expr)
	local len = string.len(expr)
	local index = skip_white(expr, index)
	if (index > len) then return index, nil end
	
	local ch = string.sub(expr,index,index)
	_M._debug("scan_token guessing from " .. ch .. " at " .. index)
	if (ch == '"' or ch=="'") then
		-- String literal
		return scan_string( expr, index )
	elseif (ch == '(') then
		-- Nested expression
		return scan_expr( expr, index )
	elseif (string.find("0123456789ABCDEF", ch) ~= nil) then
		-- Numeric token
		return scan_numeric( expr, index )
	end
	
	-- Check for unary operator
	local k, r
	k, r = scan_unop( expr, index )
	if (r ~= nil) then return k, r end
	
	-- Variable or function reference?
	k, r = scan_vref( expr, index )
	if (r ~= nil) then return k, r end
	
	--We've got no idea what we're looking at...
	return error("Invalid token", index)
end

local function parse_rpn( lexpr, expr, index, lprec )
	_M._debug("parse_rpn: parsing " .. expr .. " from " .. index .. " prec " .. lprec .. " lhs " .. _M.dump(lexpr))
	local len = string.len(expr)
	local stack = {}
	local binop, rexpr, lop, ilast

	ilast = index
	index,lop = scan_binop( expr, index )
	_M._debug("parse_rpn: outside lookahead is " .. _M.dump(lop))
	while (lop ~= nil and lop.prec <= lprec) do
		-- We're keeping this one
		binop = lop
		_M._debug("parse_rpn: mid at " .. index .. " handling " .. _M.dump(binop))
		-- Fetch right side of expression
		index,rexpr = scan_token( expr, index )
		_M._debug("parse_rpn: mid rexpr is " .. _M.dump(rexpr))
		if (rexpr == nil) then return error("Expected operand", index) end
		-- Peek at next operator
		ilast = index -- remember where we were
		index,lop = scan_binop( expr, index )
		_M._debug("parse_rpn: mid lookahead is " .. _M.dump(lop))
		while (lop ~= nil and lop.prec < binop.prec) do
			index, rexpr = parse_rpn( rexpr, expr, ilast, lop.prec )
			_M._debug("parse_rpn: inside rexpr is " .. _M.dump(rexpr))
			ilast = index
			index, lop = scan_binop( expr, index )
			_M._debug("parse_rpn: inside lookahead is " .. _M.dump(lop))
		end
		lexpr = { lexpr, rexpr, binop }
	end
	_M._debug("parse_rpn: returning index " .. ilast .. " lhs " .. _M.dump(lexpr))
	return ilast, lexpr
end

-- Completion of forward declaration
function _comp( expr )
	local index = 1
	local lhs
	
	expr = expr or ""
	expr = tostring(expr)
	_M._debug("_comp: parse " .. expr)
	
	index,lhs = scan_token( expr, index )
	index,lhs = parse_rpn( lhs, expr, index, MAXPREC )
	return { lhs }
end

local function _run( ce, ctx, stack )
	if (ce == nil) then return nil end
	local index = 1
	local stack = {}
	local len = table.getn(ce)
	while (index <= len) do
		local e = ce[index]
		if ( base.type(e) == "number" or base.type(e) == "string" ) then
			_M._debug("_run: literal value, pushing to value stack, value is " .. tostring(e))
			table.insert(stack, e)
		elseif (base.type(e) == "table" and e.type == nil) then
			_M._debug("_run: subexpression: " .. _M.dump(e))
			local v = _run( e, ctx )
			if (v == nil) then return nil end
			table.insert(stack, v)
		elseif (e.type == BINOP) then
			_M._debug("_run: handling BINOP " .. e.op)
			local v2 = table.remove(stack)
			if (base.type(v2) ~= "number" and e.op ~= "+") then return nil end
			local v1 = table.remove(stack)
			if (base.type(v1) ~= "number" and e.op ~= "+") then return nil end
			if (e.op == '+') then
				-- Special case for +, if either operand is a string, treat as concatenation
				if (base.type(v1) == "string" or base.type(v2) == "string") then
					v1 = v1 .. v2
				else
					v1 = v1 + v2
				end
			elseif (e.op == '-') then
				v1 = v1 - v2
			elseif (e.op == '*') then
				v1 = v1 * v2
			elseif (e.op == '/') then
				v1 = v1 / v2
			elseif (e.op == '%') then
				v1 = v1 % v2
			elseif (e.op == '&') then
				v1 = bit.band(v1, v2)
			elseif (e.op == '|') then
				v1 = bit.bor(v1, v2)
			elseif (e.op == '^') then 
				v1 = bit.bxor(v1, v2)
			elseif (e.op == '<') then
				if (v1 < v2) then v1 = 1 else v1 = 0 end
			elseif (e.op == '<=') then
				if (v1 <= v2) then v1 = 1 else v1 = 0 end
			elseif (e.op == '>') then
				if (v1 > v2) then v1 = 1 else v1 = 0 end
			elseif (e.op == '>=') then
				if (v1 >= v2) then v1 = 1 else v1 = 0 end
			elseif (e.op == '=' or e.op == '==') then
				if (v1 == v2) then v1 = 1 else v1 = 0 end
			elseif (e.op == '<>' or e.op == '!=' or e.op == '~=') then
				if (v1 ~= v2) then v1 = 1 else v1 = 0 end
			else
				_M._debug("Unrecognized BINOP=" .. e.op)
				return nil
			end
			-- Put our result back on the stack
			table.insert(stack, v1)
		elseif (e.type == UNOP) then
			-- Get the operand
			_M._debug("_run: handling unop, stack has " .. table.getn(stack))
			local v = table.remove(stack)
			if (v == nil) then return nil end
			if (e.op == '-') then
				v = -v
			elseif (e.op == '+') then
				-- noop
			elseif (e.op == '!') then 
				if (v == 0) then v = 1 else v = 0 end
			else
				_M._debug("Unrecognized UNOP=" .. e.op)
				return nil
			end
			-- Push result back on stack
			table.insert(stack, v)
		elseif (e.type == FREF) then
			-- Function reference
			_M._debug("_run: Handling function " .. e.name .. " with " .. table.getn(e.args) .. " arguments passed");
			-- Parse our arguments and put each on the stack; push them in reverse so they pop correctly (first to pop is first passed)
			local n, v, v1, argv
			local argc = table.getn(e.args)
			argv = {}
			for n=1,argc do
				v = e.args[n]
				_M._debug("_run: evaluate function argument " .. n .. ": " .. _M.dump(v))
				v1 = _run(v, ctx)
				if (v1 == nil) then return nil end
				_M._debug("_run: adding argument result " .. _M.dump(v1))
				argv[n] = v1
			end
			-- Locate the implementation
			local impl = nil
			if (nativeFuncs[e.name] ~= nil) then
				_M._debug(_M.dump(nativeFuncs[e.name]))
				impl = nativeFuncs[e.name].impl
				if (argc < nativeFuncs[e.name].nargs) then _M._debug("Insufficient arguments, need " .. nativeFuncs[e.name].nargs .. ", got " .. argc) return nil end -- Not enough arguments
			elseif (ctx ~= nil) then
				impl = ctx[e.name]
			end
			if (impl == nil) then
				_M._debug("Unrecognized function=" .. e.name)
				return nil
			end
			-- Run the implementation
			v = impl(argv)
			_M._debug("_run: finished " .. e.name .. "() call, result=" .. _M.dump(v))
			table.insert(stack, v)
		elseif (e.type == VREF) then
			_M._debug("_run: handling vref, name=" .. e.name)
			if (ctx == nil or ctx[e.name] == nil) then
				_M._debug("Undefined variable=" .. e.name)
				return nil
			end
			table.insert(stack, ctx[e.name])
		else
			_M._debug("Invalid object type=" .. e.type)
			return nil
		end
		
		index = index + 1
	end
	_M._debug("_run: finished, stack has " .. table.getn(stack) .. ": " .. _M.dump(stack))
	if (table.getn(stack) > 0) then
		return table.remove(stack)
	end
	return nil
end

-- PUBLIC METHODS

-- Compile the expression (public method)
_M.compile = function ( expressionString )
	return { rpn = _comp(expressionString) }
end

-- Public method to execute compiled expression. Accepts a context (ctx)
_M.run = function ( compiledExpression, executionContext )
	executionContext = executionContext or {}
	if (compiledExpression == nil or compiledExpression.rpn == nil or base.type(compiledExpression.rpn) ~= "table") then return nil end
	return _run( compiledExpression.rpn, executionContext )
end

_M.evaluate = function ( expressionString, executionContext )
	return _M.run( _M.compile ( expressionString ), executionContext )
end

-- Return the error message and approximate location of where a parsing error occurred (if used immediately
-- after compile(); if used after run(), returns evaluation error (location is meaningless).
_M.getLastError = function ( compiledExpression )
	-- Eventually, return the error message and index within the string of where things went wrong
	return "some future error message", 0
end

return _M
