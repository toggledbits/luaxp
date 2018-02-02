------------------------------------------------------------------------
-- LuaXP is a simple expression evaluator for Lua, based on lexp.js, a
-- lightweight (math) expression parser for JavaScript by the same
-- author.
--
-- Author: Copyright (c) 2016,2018 Patrick Rigney <patrick@toggledbits.com>
-- License: GPL 3.0 (see https://github.com/toggledbits/luaxp/blob/master/LICENSE)
-- Github: https://github.com/toggledbits/luaxp
------------------------------------------------------------------------

local _M = {}

_M._VERSION = "0.9.4"
_M._DEBUG = false -- Caller may set boolean true or function(msg)

-- Binary operators and precedence (lower prec is higher precedence)
_M.binops = {
      { op='.',  prec=-1 }
    , { op='*',  prec= 3 }
    , { op='/',  prec= 3 }
    , { op='%',  prec= 3 }
    , { op='+',  prec= 4 }
    , { op='-',  prec= 4 }
    , { op='<',  prec= 6 }
    , { op='<=', prec= 6 }
    , { op='>',  prec= 6 }
    , { op='>=', prec= 6 }
    , { op='==', prec= 7 }
    , { op='<>', prec= 7 }
    , { op='!=', prec= 7 }
    , { op='~=', prec= 7 }
    , { op='&',  prec= 8 }
    , { op='^',  prec= 9 }
    , { op='|',  prec=10 }
    , { op='=',  prec=14 }
}
local MAXPREC = 99 -- value doesn't matter as long as it's >= any used in binops

local string = require("string")
local math = require("math")
local base = _G

local VREF = 'vref'
local FREF = 'fref'
local UNOP = 'unop'
local BINOP = 'binop'
local TNUL = 'null'

local NULLATOM = { ['type']=TNUL }

local charmap = { t = "\t", r = "\r", n = "\n" }

local reservedWords = { ['false']=false, ['true']=true, pi=3.14159265, ['null']=NULLATOM, ['nil']=NULLATOM }

local function dump(t, seen)
    if seen == nil then seen = {} end
    local typ = base.type(t)
    local st = ""
    if typ == "table" and seen[t]==nil then
        seen[t] = 1
        st = "{ "
        local n,v
        local first = true
        for n,v in pairs(t) do
            if (not first) then st = st .. ", " end
            st = st .. n .. "=" .. dump(v, seen)
            first = false
        end
        st = st .. " }"
        return st
    elseif typ == "string" then
        return string.format("%q", t)
    elseif typ == "boolean" or typ == "number" then
        return tostring(t)
    end
    return string.format("(%s)%s", typ, tostring(t))
end

-- Debug output function. If _DEBUG is false or nil, no output.
-- If function, uses that, otherwise print()
local function D(s, ...)
    if not _M._DEBUG then return end
    local str = string.gsub(s, "%%(%d+)", function( n )
            n = tonumber(n, 10)
            if n < 1 or n > #arg then return "nil" end
            local val = arg[n]
            if type(val) == "table" then
                return dump(val)
            elseif type(val) == "string" then
                return string.format("%q", val)
            end
            return tostring(val)
        end
    )
    if base.type(_M._DEBUG) == "function" then _M._DEBUG(str) else print(str) end
end

-- Forward declarations
local _comp, _run, scan_token

-- Utility functions

-- Value is atom if it matches our pattern, and specific type of atom if matches type passwd
local function isAtom( v, typ )
    return base.type(v) == "table" and v.type ~= nil and ( typ == nil or v.type == typ )
end

-- Special case null atom
local function isNull( v )
    return isAtom( v, TNUL )
end

local function comperror(msg, loc)
    -- print("throwing comperror at " .. tostring(loc) .. ": " .. tostring(msg))
    return error( { source='LuaXP', ['type']='compile', location=loc, message=msg } )
end

local function evalerror(msg, loc)
    -- print("throwing evalerror at " .. tostring(loc) .. ": " .. tostring(msg))
    return error( { source='LuaXP', ['type']='evaluation', location=loc, message=msg } )
end

local function xp_pow(b, x)
    return math.exp(x * math.log(b))
end

local function xp_select(obj, keyname, keyval)
    if base.type(obj) ~= "table" then evalerror("select() requires table/object arg 1") end
    keyname = tostring(keyname)
    keyval = tostring(keyval)
    local i,v
    for i,v in pairs(obj) do
        if tostring(v[keyname]) == keyval then
            return v
        end
    end
    return nil
end

local monthNameMap = {}
local function mapLocaleMonth( m )
    local k
    if m == nil then error("nil month name") end
    local ml = string.lower(tostring(m))
    if ml:match("^%d+$") then
        -- All numeric. Simply return numeric form if valid range.
        k = tonumber(ml) or 0
        if k >=1 and k <= 12 then return k end
    end
    if monthNameMap[ml] ~= nil then -- cached result?
        D("mapLocaleMonth(%1) cached result=%2", ml, monthNameMap[ml])
        return monthNameMap[ml]
    end
    -- Since we can't get locale information directly in a platform-independent way,
    -- deduce it from live results...
    local d = os.date("*t") -- current time and date
    d.day = 1 -- pinned
    for k = 1,12 do
        d.month = k
        local tt = os.time(d)
        local s = os.date("#%b#%B#", tt):lower()
        if s:find("#"..ml.."#") then
            monthNameMap[ml] = k
            return k
        end
    end
    return evalerror("Cannot parse month name '" .. m .. "'")
end

local YMD=0
local DMY=1
local MDY=2
local function guessMDDM()
    local d = os.date( "%x", os.time( { year=2001, month=8, day=22, hour=0 } ) )
    local p = { d:match("(%d+)([/-])(%d+)[/-](%d+)") }
    if p[1] == "2001" then return YMD,p[2]
    elseif tonumber(p[1]) == 22 then return DMY,p[2]
    else return MDY,p[2] end
end

-- Somewhat simple time parsing. Handles the most common forms of ISO 8601, plus many less regular forms.
-- If mm/dd vs dd/mm is ambiguous, it tries to discern using current locale's rule.
local function xp_parse_time( t )
    if type(t) == "number" then return t end -- if already numeric, assume it's already timestamp
    if t == nil or tostring(t):lower() == "now" then return os.time() end
    t = tostring(t) -- force string
    local now = os.time()
    local nd = os.date("*t", now) -- consistent
    local tt = { year=nd.year, month=nd.month, day=nd.day, hour=0, ['min']=0, sec=0 }
    local offset = 0
    -- Try to match a date. Start with two components.
    local order = nil
    local p = { t:match("^%s*(%d+)([/-])(%d+)(.*)") } -- entirely numeric w/sep
    if p[3] == nil then D("match 2") p = { t:match("^%s*(%d+)(%-)(%a+)(.*)") } order=DMY end -- number-word (4-Jul)
    if p[3] == nil then D("match 3") p = { t:match("^%s*(%a+)(%-)(%d+)(.*)") } order=MDY end -- word-number (Jul-4)
    if p[3] ~= nil then
        -- Look ahead for third component behind same separator
        D("Found p1=%1, p2=%2, sep=%3, rem=%4", p[1], p[2], p[3], p[4])
        local sep = p[2]
        t = p[4] or ""
        D("Scanning for 3rd part from: '%1'", t)
        p[4],p[5] = t:match("^%" .. sep .. "(%d+)(.*)")
        if p[4] == nil then
            p[4] = tt.year
        else
            t = p[5] or "" -- advance token
        end
        -- We now have three components. Figure out their order.
        p[5]=t p[6]=p[6]or"" D("p=%1,%2,%3,%4,%5", unpack(p))
        local first = tonumber(p[1]) or 0
        if order == nil and first > 31 then
            -- First is year (can't be month or day), assume y/m/d
            tt.year = first
            tt.month = mapLocaleMonth(p[3])
            tt.day = p[4]
        elseif order == nil and first > 12 then
            -- First is day, assume d/m/y
            tt.day = first
            tt.month = mapLocaleMonth(p[3])
            tt.year = p[4]
        else
            -- Guess using locale formatting
            if order == nil then
                D("Guessing MDY order")
                order = guessMDDM()
            end
            D("MDY order is %1", order)
            if order == 0 then
                tt.year = p[1] tt.month = mapLocaleMonth(p[3]) tt.day = p[4]
            elseif order == 1 then
                tt.day = p[1] tt.month = mapLocaleMonth(p[3]) tt.year = p[4]
            else
                tt.month = mapLocaleMonth(p[1]) tt.day = p[3] tt.year = p[4]
            end
        end
        tt.year = tonumber(tt.year)
        if tt.year < 100 then tt.year = tt.year + 2000 end
        D("Parsed date year=%1, month=%2, day=%3", tt.year, tt.month, tt.day)
    else
        -- YYYYMMDD?
        D("No match to delimited")
        p = { t:match("^%s*(%d%d%d%d)(%d%d)(%d%d)(.*)") }
        if p[3] ~= nil then
            tt.year = p[1]
            tt.month = p[2]
            tt.day = p[3]
            t = p[4] or ""
        else
            D("check %%c format")
            -- Fri Aug  4 16:18:22 2017
            p = { t:match("^%s*%a+%s+(%a+)%s+(%d+)(.*)") } -- with dow
            if p[2] == nil then p = { t:match("^%s*(%a+)%s+(%d+)(.*)") } end -- without dow
            if p[2] ~= nil then
                D("Matches %%c format, 1=%1,2=%2,3=%3", p[1], p[2], p[3])
                tt.day = p[2]
                tt.month = mapLocaleMonth(p[1])
                t = p[3] or ""
                -- Following time and year?
                p = { t:match("^%s*([%d:]+)%s+(%d%d%d%d)(.*)") }
                if p[1] ~= nil then
                    tt.year = p[2]
                    t = (p[1] or "") .. " " .. (p[3] or "")
                else
                    -- Maybe just year?
                    p = { t:match("^%s*(%d%d%d%d)(.*)") }
                    if p[1] ~= nil then
                        tt.year = p[1]
                        t = p[2] or ""
                    end
                end
            else
                D("No luck with any known date format.")
            end
        end
        D("Parsed date year=%1, month=%2, day=%3", tt.year, tt.month, tt.day)
    end
    -- Time? Note: does not support decimal fractions except on seconds component, which is ignored (ISO 8601 allows on any, but must be last component)
    D("Scanning for time from: '%1'", t)
    local hasTZ = false
    local sep = nil
    p = { t:match("^%s*T?(%d%d)(%d%d)(.*)") } -- ISO 8601 (Thhmm) without delimiters
    if p[1] == nil then p = { t:match("^%s*T?(%d+):(%d+)(.*)") } end -- with delimiters
    if p[1] ~= nil then
        -- Hour and minute
        tt.hour = p[1]
        tt['min'] = p[2]
        t = p[3] or ""
        -- Seconds?
        p = { t:match("^:?(%d+)(.*)") }
        if p[1] ~= nil then
            tt.sec = p[1]
            t = p[2] or ""
        end
        -- Swallow decimal on last component?
        p = { t:match("^(%.%d+)(.*)") }
        if p[1] ~= nil then
            t = p[2] or ""
        end
        -- AM or PM?
        p = { t:match("^%s*([AaPp])[Mm]?(.*)") }
        if p[1] ~= nil then
            D("AM/PM is %1", p[1])
            if p[1]:lower() == "p" then tt.hour = tt.hour + 12 end
            t = p[2] or ""
        end
        D("Parsed time is %1:%2:%3", tt.hour, tt['min'], tt.sec)

        -- Timezone Zulu?
        p = { t:match("^([zZ])(.*)") } -- no whitespace, see comment below.
        if p[1] ~= nil then
            -- Zulu
            offset = 0
            hasTZ = true
            t = p[2] or ""
        end
        -- Handling for zones? UTC, GMT, minimally... what about others... EDT, JST, ...?
        -- Offset +/-HH[mm] (e.g. +02, -0500). Not that the pattern requires the TZ spec
        -- to follow the time without spaces between, to distinguish TZ from offsets (below).
        p = { t:match("^([+-]%d%d)(.*)") }
        if p[1] ~= nil then
            hasTZ = true
            offset = 60 * tonumber(p[1])
            t = p[2];
            p = { t:match("^:?(%d%d)(.*)") }
            if p[1] ~= nil then
                if offset < 0 then offset = offset - tonumber(p[1])
                else offset = offset + tonumber(p[1])
                end
                t = p[2] or ""
            end
        end
    end
    -- Is there an offset? Form is (+/-)DDD:HH:MM:SS. If parts are omitted, the offset
    -- is parsed from smallest to largest, so +05:00 is +5 minutes, -35 is minus 35 seconds.
    local delta = 0
    D("Checking for offset from '%1'", t)
    p = { t:match("%s*([+-])(%d+)(.*)") }
    if p[2] ~= nil then
        D("Parsing offset from %1, first part is %2", t, p[2])
        local sign = p[1]
        delta = tonumber(p[2])
        if delta == nil then evalerror("Invalid delta spec: " .. t) end
        t = p[3] or ""
        local k
        for k = 1,3 do
            D("Parsing offset from %1", t)
            p = { t:match("%:(%d+)(.*)") }
            if p[1] == nil then break end
            if k == 3 then delta = delta * 24 else delta = delta * 60 end
            delta = delta + tonumber(p[1])
            t = p[2] or ""
        end
        if sign == "-" then delta = -delta end
        D("Final delta is %1", delta)
    end
    -- There should not be anything left at this point
    if t:match("([^%s])") then
        return evalerror("Unparseable data: " .. t)
    end
    local tm = os.time(tt)
    if hasTZ then
        -- If there's a timezone spec, apply it. Otherwise we assume time was in current (system) TZ
        -- and leave it unmodified.
        local loctime = os.date("*t")
        local epoch = { year=1970, month=1, day=1, hour=0 }
        if loctime.isdst then epoch.isdst = true end
        local locale_offset = os.time( epoch )
        tm = tm - locale_offset -- back to UTC, because conversion assumes current TZ, so undo that.
        tm = tm - ( offset * 60 ) -- apply specified offset
    end
    tm = tm + delta
    return tm -- returns time in UTC
end

-- Date add. First arg is timestamp, then secs, mins, hours, days, months, years
local function xp_date_add( a )
    local tm = xp_parse_time( a[1] )
    if a[2] ~= nil then tm = tm + (tonumber(a[2]) or evalerror("Invalid seconds (argument 2) to dateadd()")) end
    if a[3] ~= nil then tm = tm + 60 * (tonumber(a[3]) or evalerror("Invalid minutes (argument 3) to dateadd()")) end
    if a[4] ~= nil then tm = tm + 3600 * (tonumber(a[4]) or evalerror("Invalid hours (argument 4) to dateadd()")) end
    if a[5] ~= nil then tm = tm + 86400 * (tonumber(a[5]) or evalerror("Invalid days (argument 5) to dateadd()")) end
    if a[6] ~= nil or a[7] ~= nil then
        D("Applying delta months and years to %1", tm)
        local d = os.date("*t", tm)
        d.month = d.month + ( tonumber( a[6] ) or 0 )
        d.year = d.year + ( tonumber( a[7] ) or 0 )
        D("Normalizing month,year=%1,%2", d.month, d.year)
        while d.month < 1 do
            d.month = d.month + 12
            d.year = d.year - 1
        end
        while d.month > 12 do
            d.month = d.month - 12
            d.year = d.year + 1
        end
        tm = os.time(d)
    end
    return tm
end

-- Delta between two times. Returns value in seconds.
local function xp_date_diff( d1, d2 )
    return xp_parse_time( d1 ) - xp_parse_time( d2 or os.time() )
end

local function xp_rtrim(s)
    if base.type(s) ~= "string" then evalerror("String required") end
    return s:gsub("%s+$", "")
end

local function xp_ltrim(s)
    if base.type(s) ~= "string" then evalerror("String required") end
    return s:gsub("^%s+", "")
end

local function xp_trim( s )
    if base.type(s) ~= "string" then evalerror("String required") end
    return xp_ltrim( xp_rtrim( s ) )
end

local function xp_keys( arr )
    if base.type( arr ) ~= "table" then evalerror("Array/table required") end
    local k
    local r = {}
    for k,_ in pairs( arr ) do
        table.insert( r, k )
    end
    return r
end

local function xp_iter( ctx, arr, iter, nom )
    D("xp_iter(ctx,arr,%3,%4)", ctx, arr, iter, nom)
    if ctx == nil then ctx = {} end
    if base.type( arr ) ~= "table" then evalerror("Array/table required") end
    local k,v
    local r = {}
    local ce = _comp( tostring(iter), ctx )
    for k,v in pairs( arr ) do
        ctx[nom or "_"] = v
        D("xp_iter() evaluate %1 against %2", iter, v)
        local t = _run( ce, ctx )
        if t ~= nil and not isNull(t) then
            table.insert( r, t )
        end
    end
    return r
end

local nativeFuncs = {
      ['abs']   = { nargs = 1, impl = function( argv ) if argv[1] < 0 then return -argv[1] else return argv[1] end end }
    , ['sgn']   = { nargs = 1, impl = function( argv ) if argv[1] < 0 then return -1 elseif (argv[1] == 0) then return 0 else return 1 end end }
    , ['floor'] = { nargs = 1, impl = function( argv ) return math.floor(argv[1]) end }
    , ['ceil']  = { nargs = 1, impl = function( argv ) return math.ceil(argv[1]) end }
    , ['round'] = { nargs = 1, impl = function( argv ) local n = argv[1] local p = argv[2] or 0 return math.floor( n * xp_pow(10, p) + 0.5 ) / xp_pow(10, p) end }
    , ['cos']   = { nargs = 1, impl = function( argv ) return math.cos(argv[1]) end }
    , ['sin']   = { nargs = 1, impl = function( argv ) return math.sin(argv[1]) end }
    , ['tan']   = { nargs = 1, impl = function( argv ) return math.tan(argv[1]) end }
    , ['log']   = { nargs = 1, impl = function( argv ) return math.log(argv[1]) end }
    , ['exp']   = { nargs = 1, impl = function( argv ) return math.exp(argv[1]) end }
    , ['pow']   = { nargs = 2, impl = function( argv ) return xp_pow(argv[1], argv[2]) end }
    , ['sqrt']  = { nargs = 1, impl = function( argv ) return math.sqrt( argv[1] ) end }
    , ['min']   = { nargs = 2, impl = function( argv ) if argv[1] <= argv[2] then return argv[1] else return argv[2] end end }
    , ['max']   = { nargs = 2, impl = function( argv ) if argv[1] >= argv[2] then return argv[1] else return argv[2] end end }
    , ['len']   = { nargs = 1, impl = function( argv ) return string.len(tostring(argv[1])) end }
    , ['sub']   = { nargs = 2, impl = function( argv ) local st = tostring(argv[1]) local p = argv[2] local l = (argv[3] or -1) return string.sub(st, p, l) end }
    , ['find']  = { nargs = 2, impl = function( argv ) local st = tostring(argv[1]) local p = tostring(argv[2]) local i = argv[3] or 1 return (string.find(st, p, i) or 0) end }
    , ['upper'] = { nargs = 1, impl = function( argv ) return string.upper(tostring(argv[1])) end }
    , ['lower'] =  { nargs = 1, impl = function( argv ) return string.lower(tostring(argv[1])) end }
    , ['trim'] = { nargs = 1, impl = function( argv ) return xp_trim(tostring(argv[1])) end }
    , ['ltrim'] = { nargs = 1, impl = function( argv ) return xp_ltrim(tostring(argv[1])) end }
    , ['rtrim'] = { nargs = 1, impl = function( argv ) return xp_rtrim(tostring(argv[1])) end }
    , ['tostring'] = { nargs = 1, impl = function( argv ) if isNull(argv[1]) then return "" else return tostring(argv[1]) end end }
    , ['tonumber'] = { nargs = 1, impl = function( argv ) if type(argv[1]) == "boolean" then if argv[1] then return 1 else return 0 end end return tonumber(argv[1], argv[2] or 10) or evalerror('Argument could not be converted to number') end }
    , ['format'] = { nargs = 1, impl = function( argv ) return string.format( unpack(argv) ) end }
    , ['time']  = { nargs = 0, impl = function( argv ) return xp_parse_time( argv[1] ) end }
    , ['strftime'] = { nargs = 1, impl = function( argv ) return os.date(unpack(argv)) end }
    , ['dateadd'] = { nargs = 2, impl = function( argv ) return xp_date_add( argv ) end }
    , ['datediff'] = { nargs = 1, impl = function( argv ) return xp_date_diff( argv[1], argv[2] or os.time() ) end }
    , ['choose'] = { nargs = 2, impl = function( argv ) local ix = argv[1] if ix < 1 or ix > (#argv-2) then return argv[2] else return argv[ix+2] end end }
    , ['select'] = { nargs = 3, impl = function( argv ) return xp_select(argv[1],argv[2],argv[3]) end }
    , ['keys'] = { nargs = 1, impl = function( argv ) return xp_keys( argv[1] ) end }
    , ['iterate'] = { nargs = 2, impl = function( argv ) return xp_iter( argv.context, argv[1], argv[2], argv[3] ) end }
    , ['if'] = { nargs = 2, impl = function( argv ) if argv[1] then return argv[2] or NULLATOM else return argv[3] or NULLATOM end end }
    , ['void'] = { nargs = 0, impl = function( argv ) return NULLATOM end }
}

-- Adapted from "BitUtils", Lua-users wiki at http://lua-users.org/wiki/BitUtils; thank you kind stranger(s)...
local bit = {}
bit['nand'] = function(x,y,z)
    z=z or 2^16
    if z<2 then
        return 1-x*y
    else
        return bit.nand((x-x%z)/z,(y-y%z)/z,math.sqrt(z))*z+bit.nand(x%z,y%z,math.sqrt(z))
    end
end
bit["bnot"]=function(y,z) return bit.nand(bit.nand(0,0,z),y,z) end
bit["band"]=function(x,y,z) return bit.nand(bit["bnot"](0,z),bit.nand(x,y,z),z) end
bit["bor"]=function(x,y,z) return bit.nand(bit["bnot"](x,z),bit["bnot"](y,z),z) end
bit["bxor"]=function(x,y,z) return bit["band"](bit.nand(x,y,z),bit["bor"](x,y,z),z) end

-- Let's get to work

-- Skips white space, returns index of non-space character or nil
local function skip_white( expr, index )
    D("skip_white from %1 in %2", index, expr)
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
    D("scan_numeric from %1 in %2", index, expr)
    local len = string.len(expr)
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
        i = string.find("0123456789ABCDEF", string.upper(ch), 1, true)
        if i == nil or ( base==10 and i==15 ) then break end
        if i > base then comperror("Invalid digit for base "..base, index) end
        val = base * val + (i-1)
        index = index + 1
    end
    -- Parse fractional part, if any
    if (ch == '.' and base==10) then
        local ndec = 0
        index = index + 1 -- get past decimal point
        while (index <= len) do
            ch = string.sub(expr, index, index)
            i = string.byte(ch) - 48
            if i<0 or i>9 then break end
            ndec = ndec + 1
            val = val + ( i * xp_pow( 10, -ndec ) )
            index = index + 1
        end
    end
    -- Parse exponent, if any
    if ( (ch == 'e' or ch == 'E') and base == 10 ) then
        local npow = 0
        local neg = nil
        index = index + 1 -- get base exponent marker
        local st = index
        while (index <= len) do
            ch = string.sub(expr, index, index)
            if neg == nil and ch == "-" then neg = true
            elseif neg == nil and ch == "+" then neg = false
            else
                i = string.byte(ch) - 48
                if i<0 or i>9 then break end
                npow = npow * 10 + i
                if neg == nil then neg = false end
            end
            index = index + 1
        end

        if index == st then comperror("Missing exponent", index) end
        if neg then npow = -npow end
        val = val * xp_pow( 10, npow )
    end
    -- Return result
    D("scan_numeric returning index=%1, val=%2", index, val)
    return index, val
end

-- Parse a string. Trivial at the moment and needs escaping of some kind
local function scan_string( expr, index )
    D("scan_string from %1 in %2", index, expr)
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
    return comperror("Unterminated string", index)
end

-- Parse a function reference. It is treated as a degenerate case of
-- variable reference, i.e. an alphanumeric string followed immediately
-- by an opening parenthesis.
local function scan_fref( expr, index, name )
    D("scan_fref from %1 in %2", index, expr)
    local len = string.len(expr)
    local args = {}
    local parenLevel = 1
    local ch
    local subexp = ""
    while ( true ) do
        if ( index > len ) then return comperror("Unexpected end of argument list", index) end -- unexpected end of argument list

        ch = string.sub(expr, index, index)
        if (ch == ')') then
            D("scan_fref: Found a closing paren while at level %1", parenLevel)
            parenLevel = parenLevel - 1
            if (parenLevel == 0) then
                subexp = xp_trim( subexp )
                D("scan_fref: handling end of argument list with subexp=%1", subexp)
                if string.len(subexp) > 0 then -- PHR??? Need to test out all whitespace strings from the likes of "func( )"
                    table.insert(args, _comp( subexp ) ) -- compile the subexp and put it on the list
                elseif table.getn(args) > 0 then
                    comperror("Invalid subexpression", index)
                end
                index = index + 1
                D("scan_fref returning, function is %1 with %2 args", name, table.getn(args), dump(args))
                return index, { ['type']=FREF, args=args, name=name, pos=index }
            else
                -- It's part of our argument, so just add it to the subexpress string
                subexp = subexp .. ch
                index = index + 1
            end
        elseif ch == "'" or ch == '"' then
            -- Start of string? Swallow it whole and append it to our subexpression
            local qq = ch
            index, ch = scan_string( expr, index )
            subexp = subexp .. qq .. ch .. qq
        elseif (ch == ',' and parenLevel == 1) then -- completed subexpression
            subexp = xp_trim( subexp )
            D("scan_fref: handling argument=%1", subexp)
            if (string.len(subexp) > 0) then
                local r = _comp(subexp)
                if (r == nil) then return comperror("Subexpression failed to compile", index) end
                table.insert( args, r )
                D("scan_fref: inserted argument %1 as %2", subexp, r)
            else
                comperror("Invalid subexpression", index)
            end
            index = skip_white( expr, index+1 )
            subexp = ""
            D("scan_fref: continuing argument scan in %1 from %2", expr, index)
        else
            subexp = subexp .. ch
            if (ch == '(') then parenLevel = parenLevel + 1 end
            index = index + 1
        end
    end
end

-- Parse an array reference
local function scan_aref( expr, index, name )
    D("scan_aref from %1 in %2", index, expr)
    local len = string.len(expr)
    local args = {}
    local parenLevel = 1
    local ch
    local subexp = ""
    while ( true ) do
        if ( index > len ) then return comperror("Unexpected end of array subscript expression", index) end
        ch = string.sub(expr, index, index)
        if (ch == ']') then
            D("scan_aref: Found a closing bracket, subexp=%1", subexp)
            args = _comp(subexp)
            D("scan_aref returning, array is %1", name)
            return index+1, { ['type']=VREF, name=name, index=args, pos=index }
        else
            subexp = subexp .. ch
            index = index + 1
        end
    end
end

-- Scan a variable reference; could turn into a function reference
local function scan_vref( expr, index )
    D("scan_vref from %1 in %2", index, expr)
    local len = string.len(expr);
    local ch, k
    local name = ""
    while (index <= len) do
        ch = string.sub(expr, index, index)
        if (ch == '(') then
            return scan_fref(expr, index+1, name)
        elseif (ch == "[") then
            -- Possible that name is blank. We allow/endorse, for ['identifier'] form of vref (see runtime)
            return scan_aref(expr, index+1, name)
        end
        k = string.find("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_", string.upper(ch), 1, true)
        if (k == nil) then
            break
        elseif (name == "" and k <= 10) then
            return comperror("Invalid identifier", index)
        end

        name = name .. ch
        index = index + 1
    end

    return index, { ['type']=VREF, name=name, pos=index }
end

-- Scan nested expression (called when ( seen while scanning for token)
local function scan_expr( expr, index )
    D("scan_expr from %1 in %2", index, expr)
    local len = string.len(expr)
    local ch, k
    local st = ""
    local parenLevel = 0
    index = index + 1
    while (index <= len) do
        ch = string.sub(expr,index,index)
        if (ch == ')') then
            if (parenLevel == 0) then
                D("scan_expr parsing subexpression=%1", st)
                local r = _comp( st )
                if (r == nil) then return comperror("Subexpression failed to parse", index) end
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
    D("scan_unop from %1 in %2", index, expr)
    local len = string.len(expr)
    local ch, k
    ch = string.sub(expr, index, index)
    if (ch == '-' or ch == '+' or ch == '!' or ch == '#') then
        -- We have a UNOP
        index = index + 1
        local k, r = scan_token( expr, index )
        if (r == nil) then return k, r end
        return k, { r, { ['type']=UNOP, op=ch, pos=index } }
    end
    return index, nil -- Not a UNOP
end

local function scan_binop( expr, index )
    D("scan_binop from %1 in %2", index, expr)
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
        for n,f in ipairs(_M.binops) do
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
            if (k == 1) then return comperror("Invalid operator", index) end
            break
        end

        -- Keep going to find longest match
        op = st
        index = index + 1
    end

    D("scan_binop succeeds with op=%1", op)
    return index, { ['type']=BINOP, op=op, prec=prec, pos=index }
end

-- Scan our next token (forward-declared)
scan_token = function( expr, index )
    D("scan_token from %1 in %2", index, expr)
    local len = string.len(expr)
    index = skip_white(expr, index)
    if (index > len) then return index, nil end

    local ch = string.sub(expr,index,index)
    D("scan_token guessing from %1 at %2", ch, index)
    if (ch == '"' or ch=="'") then
        -- String literal
        return scan_string( expr, index )
    elseif (ch == '(') then
        -- Nested expression
        return scan_expr( expr, index )
    elseif string.find("0123456789", ch, 1, true) ~= nil then
        -- Numeric token
        return scan_numeric( expr, index )
    elseif ch == "." then
        -- Look ahead, could be number without leading 0 or subref
        if index < len and string.find("0123456789", string.sub(expr,index+1,index+1), 1, true) ~= nil then
            return scan_numeric( expr, index )
        end
    end

    -- Check for unary operator
    local k, r
    k, r = scan_unop( expr, index )
    if (r ~= nil) then return k, r end

    -- Variable or function reference?
    k, r = scan_vref( expr, index )
    if (r ~= nil) then return k, r end

    --We've got no idea what we're looking at...
    return comperror("Invalid token",index)
end

local function parse_rpn( lexpr, expr, index, lprec )
    D("parse_rpn: parsing %1 from %2 prec %3 lhs %4", expr, index, lprec, lexpr)
    local len = string.len(expr)
    local stack = {}
    local binop, rexpr, lop, ilast

    ilast = index
    index,lop = scan_binop( expr, index )
    D("parse_rpn: outside lookahead is %1" ,lop)
    while (lop ~= nil and lop.prec <= lprec) do
        -- We're keeping this one
        binop = lop
        D("parse_rpn: mid at %1 handling ", index, binop)
        -- Fetch right side of expression
        index,rexpr = scan_token( expr, index )
        D("parse_rpn: mid rexpr is %1", rexpr)
        if (rexpr == nil) then return comperror("Expected operand", ilast) end
        -- Peek at next operator
        ilast = index -- remember where we were
        index,lop = scan_binop( expr, index )
        D("parse_rpn: mid lookahead is %1", lop)
        while (lop ~= nil and lop.prec < binop.prec) do
            index, rexpr = parse_rpn( rexpr, expr, ilast, lop.prec )
            D("parse_rpn: inside rexpr is %1", rexpr)
            ilast = index
            index, lop = scan_binop( expr, index )
            D("parse_rpn: inside lookahead is %1", lop)
        end
        lexpr = { lexpr, rexpr, binop }
    end
    D("parse_rpn: returning index %1 lhs %2", ilast, lexpr)
    return ilast, lexpr
end

-- Completion of forward declaration
_comp = function( expr )
    local index = 1
    local lhs

    expr = expr or ""
    expr = tostring(expr)
    D("_comp: parse %1", expr)

    index,lhs = scan_token( expr, index )
    index,lhs = parse_rpn( lhs, expr, index, MAXPREC )
    return { lhs }
end

-- Better version, checks one or two operands (AND logic result)
local function check_operand( v1, allow1, v2, allow2 )
    local vt = base.type(v1)
    local res = true
    if v2 ~= nil then
        res = check_operand( v2, allow2 or allow1 )
    end
    if res then
        if base.type(allow1) == "string" then
            res = (vt == allow1)
        elseif base.type(allow1) ~= "table" then
            error("invalid allow1") -- bug, only string and array allowed
        else
            local t
            res = false
            for _,t in ipairs(allow1) do
                if vt == t then
                    res = true
                    break
                end
            end
        end
    end
    return res
end

local function coerce(val, typ)
    local vt = base.type(val)
    D("coerce: attempt (%1)%2 to %3", vt, val, typ)
    if vt == typ then return val end -- already there?
    if typ == "boolean" then
        -- Coerce to boolean
        if vt == "number" then return val ~= 0
        elseif vt == "string" then
            if string.lower(val) == "true" or val == "1" then return true
            elseif string.lower(val) == "false" or val == "0" then return false
            else return #val ~= 0 -- empty string is false, all else is true
            end
        elseif isNull(val) then return false -- null coerces to boolean false
        end
    elseif typ == "string" then
        if vt == "number" then return tostring(val)
        elseif vt == "boolean" and val then return "true"
        elseif vt == "boolean" and not val then return "false"
        elseif isNull(val) then return "" -- null coerces to empty string
        end
    elseif typ == "number" then
        if vt == "boolean" and val then return 1
        elseif vt == "boolean" and not val then return 0
        elseif vt == "string" then
            local n = tonumber(val,10)
            if n ~= nil then return n else evalerror("Coersion of " .. tostring(val) .. " from string to number failed") end
        end
        -- null coerces to NaN? We don't have NaN. Yet...
    end
    if isNull(val) then evalerror("Can't coerce null to " .. typ) end
    evalerror("Can't coerce " .. vt .. " to " .. typ)
end

local function isNumeric(val)
    if isNull(val)then return false end
    local s = tonumber(val, 10)
    if s == nil then return false
    else return true, s
    end
end

-- Pop an item off the stack. If it's a variable reference, resolve it now.
local function fetch( stack, ctx )
    local v
    local e = table.remove( stack, 1 )
    if e == nil then evalerror("Missing expected operand") end
    D("fetch() popped %1", e)
    if isAtom( e, VREF ) then
        D("fetch: evaluating VREF %1 to its value", e.name)
        -- A bit of a kludge. If name is empty but index is defined, we have a quoted reference
        -- such as ['response'], which allows access to identifiers with special characters.
        if ( e.name or "" ) == "" and e.index ~= nil then
            e.name = _run(e.index, ctx, stack)
            e.index = nil
        end
        if reservedWords[e.name:lower()] ~= nil then
            D("fetch: found reserved word %1 for VREF", e.name)
            v = reservedWords[e.name:lower()]
        elseif ctx.__lvars ~= nil and ctx.__lvars[e.name] ~= nil then
            v = ctx.__lvars[e.name]
        else
            v = ctx[e.name]
        end
        if (v == nil) then evalerror("Undefined variable: " .. e.name, e.pos) end
        -- Apply array index if present
        if (e.index ~= nil) then
            if base.type(v) ~= "table" then evalerror(e.name .. " is not an array", e.pos) end
            local ix = _run(e.index, ctx, {}) -- runs same context, separate stack
            D("fetch: applying subscript: %1[%2]", e.name, ix)
            if ix ~= nil then
                v = v[ix]
                if v == nil then evalerror("Subscript " .. ix .. " out of range for " .. e.name, e.pos) end
            else
                evalerror("Subscript evaluation failed", e.pos)
            end
        end
        return v
    end
    return e
end

_run = function( ce, ctx, stack )
    if (ce == nil) then evalerror("Invalid input for argument 1") end
    if stack == nil then stack = {} end
    local index = 1
    local len = table.getn(ce)
    while (index <= len) do
        local v = nil
        local e = ce[index]
        D("_run: next element is %1", e)
        if ( base.type(e) == "number" or base.type(e) == "string" ) then
            D("_run: direct value assignment for (%1)%2", base.type(e), e)
            v = e
        elseif base.type(e) == "table" and not isAtom(e) then
            D("_run: subexpression %1", e)
            v = _run( e, ctx, stack )
        elseif isAtom( e, BINOP ) then
            D("_run: handling BINOP %1", e.op)
            local v2
            if e.op == '.' then
                v2 = table.remove( stack, 1 )
                D("_run: subref lookahead is %1", v2)
            else
                v2 = fetch(stack, ctx) -- something else, evaluate it.
            end
            local v1
            if e.op == '=' then
                -- Must be vref (can't assign to anything else). Special pop il lieu of fetch().
                v1 = table.remove( stack, 1 )
                D("_run: assignment lookahead is %1", v1)
                if not isAtom( v1, VREF ) then evalerror("Invalid assignment", e.pos) end
            else
                v1 = fetch(stack, ctx)
            end
            D("_run: operands are %1, %2", v1, v2)
            if (e.op == '.') then
                D("_run: descend to %1", v2)
                if isAtom(v1) then evalerror("Invalid reference") end
                if not check_operand(v1, "table") then evalerror("Cannot subreference a " .. base.type(v1), e.pos) end
                if not isAtom( v2, VREF ) then evalerror("Invalid subreference", e.pos) end
                if (v2.name or "") == "" and v2.index ~= nil then
                    -- Handle ['reference'] form of vref... name is in index
                    v2.name = _run( v2.index, ctx, stack )
                    v2.index = nil
                end
                v = v1[v2.name]
                if v == nil then evalerror("Subreference not found: " .. tostring(v2.name), v2.pos) end
            elseif (e.op == '+') then
                -- Special case for +, if either operand is a string, treat as concatenation
                if base.type(v1) == "string" or base.type(v2) == "string" then
                    v = coerce(v1, "string") .. coerce(v2, "string")
                else
                    v = coerce(v1, "number") + coerce(v2, "number")
                end
            elseif (e.op == '-') then
                v = coerce(v1, "number") - coerce(v2, "number")
            elseif (e.op == '*') then
                v = coerce(v1, "number") * coerce(v2, "number")
            elseif (e.op == '/') then
                v = coerce(v1, "number") / coerce(v2, "number")
            elseif (e.op == '%') then
                v = coerce(v1, "number") % coerce(v2, "number")
            elseif (e.op == '&') then
                -- If both operands are numbers, bitwise; otherwise boolean
                if base.type(v1) ~= "number" or base.type(v2) ~= "number" then
                    v = coerce(v1, "boolean") and coerce(v2, "boolean")
                else
                    v = bit.band( coerce(v1, "number"), coerce(v2, "number") )
                end
            elseif (e.op == '|') then
                -- If both operands are numbers, bitwise; otherwise boolean
                if base.type(v1) ~= "number" or base.type(v2) ~= "number" then
                    v = coerce(v1, "boolean") or coerce(v2, "boolean")
                else
                    v = bit.bor( coerce(v1, "number"), coerce(v2, "number") )
                end
            elseif (e.op == '^') then
                -- If both operands are numbers, bitwise; otherwise boolean
                if base.type(v1) ~= "number" or base.type(v2) ~= "number" then
                    v = coerce(v1, "boolean") ~= coerce(v2, "boolean")
                else
                    v = bit.bxor( coerce(v1, "number"), coerce(v2, "number") )
                end
            elseif (e.op == '<') then
                if not check_operand(v1, {"number","string"}, v2) then evalerror("Invalid comparison ("
                    .. base.type(v1) .. e.op .. base.type(v2) .. ")", e.pos) end
                v = v1 < v2
            elseif (e.op == '<=') then
                if not check_operand(v1, {"number","string"}, v2) then evalerror("Invalid comparison ("
                    .. base.type(v1) .. e.op .. base.type(v2) .. ")", e.pos) end
                v = v1 <= v2
            elseif (e.op == '>') then
                if not check_operand(v1, {"number","string"}, v2) then evalerror("Invalid comparison ("
                    .. base.type(v1) .. e.op .. base.type(v2) .. ")", e.pos) end
                v = v1 > v2
            elseif (e.op == '>=') then
                if not check_operand(v1, {"number","string"}, v2) then evalerror("Invalid comparison ("
                    .. base.type(v1) .. e.op .. base.type(v2) .. ")", e.pos) end
                v = v1 >= v2
            elseif (e.op == '==') then
                if base.type(v1) == "boolean" or base.type(v2) == "boolean" then
                    v = coerce(v1, "boolean") == coerce(v2, "boolean")
                elseif (base.type(v1) == "number" or base.type(v2) == "number") and isNumeric(v1) and isNumeric(v2) then
                    -- Either is number and both have valid numeric representation, treat both as numbers
                    -- That is 123 > "45" returns true
                    v = coerce(v1, "number") == coerce(v2, "number")
                else
                    v = coerce(v1, "string") == coerce(v2, "string")
                end
            elseif (e.op == '<>' or e.op == '!=' or e.op == '~=') then
                if base.type(v1) == "boolean" or base.type(v2) == "boolean" then
                    v = coerce(v1, "boolean") == coerce(v2, "boolean")
                elseif (base.type(v1) == "number" or base.type(v2) == "number") and isNumeric(v1) and isNumeric(v2) then
                    v = coerce(v1, "number") ~= coerce(v2, "number")
                else
                    v = coerce(v1, "string") ~= coerce(v2, "string")
                end
            elseif e.op == '=' then
                D("_run: making assignment to %1", v1.name)
                -- Can't make assignment to reserved words
                local j
                for j in pairs(reservedWords) do
                    if j == v1.name:lower() then evalerror("Can't assign to reserved word " .. j, e.pos) end
                end
                if ctx[v1.name] ~= nil then
                    ctx[v1.name] = v2
                else
                    if ctx.__lvars == nil then ctx.__lvars = {} end
                    ctx.__lvars[v1.name] = v2
                end
                v = v2
            else
                error("Bug: binop parsed but not implemented by evaluator, binop=" .. e.op, 0)
            end
        elseif isAtom( e, UNOP ) then
            -- Get the operand
            D("_run: handling unop, stack has %1", stack)
            v = fetch(stack, ctx)
            if (v == nil) then error("Stack underflow in unop eval", 0) end
            if (e.op == '-') then
                v = -coerce(v, "number")
            elseif (e.op == '+') then
                -- noop
            elseif (e.op == '!') then
                if base.type(v) == "number" then
                    v = bit.bnot(v)
                else
                    v = not coerce(v, "boolean")
                end
            elseif e.op == '#' then
                D("_run: # unop on %1", v)
                local vt = base.type(v)
                if vt == "string" then
                    v = #v
                elseif vt == "table" then
                    v = #v
                elseif isNull(v) then
                    v = 0
                else
                    v = 1
                end
            else
                error("Bug: unop parsed but not implemented by evaluator, unop=" .. e.op, 0)
            end
        elseif isAtom( e, FREF ) then
            -- Function reference
            D("_run: Handling function %1 with %2 args passed", e.name, #e.args)
            -- Parse our arguments and put each on the stack; push them in reverse so they pop correctly (first to pop is first passed)
            local n, v1, argv
            local argc = #e.args
            argv = {}
            for n=1,argc do
                v = e.args[n]
                D("_run: evaluate function argument %1: %2", n, v)
                v1 = _run(v, ctx, stack)
                if v1 == nil then v1 = NULLATOM end
                D("_run: adding argument result %1", v1)
                argv[n] = v1
            end
            -- Locate the implementation
            local impl = nil
            if nativeFuncs[e.name] ~= nil then
                D("_run: found native func %1", nativeFuncs[e.name])
                impl = nativeFuncs[e.name].impl
                if (argc < nativeFuncs[e.name].nargs) then evalerror("Insufficient arguments to " .. e.name .. "(), need " .. nativeFuncs[e.name].nargs .. ", got " .. argc, e.pos) end
            end
            if (impl == nil and ctx['__functions'] ~= nil) then
                impl = ctx['__functions'][e.name]
                D("_run: context __functions provides implementation")
            end
            if impl == nil then
                D("_run: context provides DEPRECATED-STYLE implementation")
                impl = ctx[e.name]
            end
            if (impl == nil) then evalerror("Unrecognized function: " .. e.name, e.pos) end
            if (base.type(impl) ~= "function") then evalerror("Reference is not a function: " .. e.name, e.pos) end
            -- Run the implementation
            local status
            D("_run: calling %1 with args=%2", e.name, argv)
            argv.context = ctx -- trickery
            status, v = pcall(impl, argv)
            D("_run: finished %1() call, status=%2, result=%3", e.name, status, v)
            if not status then
                if base.type(v) == "table" and v.source == "LuaXP" then
                    v.location = e.pos
                    error(v) -- that one of our errors, just pass along
                end
                error("Execution of function " .. e.name .. "() threw an error: " .. tostring(v))
            end
        elseif isAtom( e, VREF ) then
            D("_run: handling vref, name=%1, push to stack for later eval", e.name)
            v = e -- we're going to push the VREF directly.
        else
            error("Bug: invalid object type in parse tree: " .. tostring(e.type), 0)
        end

        -- Push result to stack, move on in tree
        D("_run: pushing result to stack: %1", v)
        if (v == 0) then v = 0 end -- Huh? Well... long story. Resolve the inconsistency of -0 in Lua. See issue #4.
        table.insert(stack, 1, v) -- at start of array
        index = index + 1
    end
    D("_run: finished, stack has %1: %2", table.getn(stack), stack)
    if #stack then
        return fetch(stack, ctx) -- return first element. Maybe return multiple some day???
    end
    return nil
end

-- PUBLIC METHODS

-- Compile the expression (public method)
function _M.compile( expressionString )
    local s,v,n
    s,v,n = pcall(_comp, expressionString)
    if (s) then
        return  { rpn = v, source = expressionString }
    else
        return nil, v
    end
end

-- Public method to execute compiled expression. Accepts a context (ctx)
function _M.run( compiledExpression, executionContext )
    executionContext = executionContext or {}
    if (compiledExpression == nil or compiledExpression.rpn == nil or base.type(compiledExpression.rpn) ~= "table") then return nil end
    local status, val = pcall(_run, compiledExpression.rpn, executionContext)
    if (status) then
        return val
    else
        return nil, val
    end
end

function _M.evaluate( expressionString, executionContext )
    local r,m = _M.compile( expressionString )
    if (r == nil) then return r,m end -- return error as we got it
    return _M.run( r, executionContext ) -- and directly return whatever run() wants to return
end

-- Return the error message and approximate location of where a parsing error occurred (if used immediately
-- after compile(); if used after run(), returns evaluation error (location is meaningless).
function _M.getLastError( compiledExpression )
    -- Eventually, return the error message and index within the string of where things went wrong
    return "some future error message", 0
end

-- Special exports
_M.dump = dump
_M.isNull = isNull
_M.coerce = coerce
_M.NULL = NULLATOM
_M.evalerror = evalerror

return _M
