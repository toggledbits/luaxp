-- Find the luaxp we're going to test
local moduleName = arg[1] or "luaxp"
local L = require(moduleName)
local json = require "dkjson"

-- FOCUSTEST, when set, debug on for specific test number
FOCUSTEST = 0

-- Load Test Data
local testData = arg[2] or "test/testdata.json"

local mt = getmetatable(_G)
if mt == nil then
  mt = {}
  setmetatable(_G, mt)
end

__STRICT = true
mt.__declared = {}

mt.__newindex = function (t, n, v)
  if __STRICT and not mt.__declared[n] then
    local w = debug.getinfo(2, "S").what
    if w ~= "C" then
      print("ASSIGNMENT TO GLOBAL "..n)
      -- error("assign to undeclared global variable '"..n.."'", 2)
    end
    mt.__declared[n] = true
  end
  rawset(t, n, v)
end

mt.__index = function (t, n)
  if not mt.__declared[n] and debug.getinfo(2, "S").what ~= "C" then
    print("REFERENCE TO UNDECLARED GLOBAL " .. n)
    print(debug.traceback())
    error("variable '"..n.."' is not declared", 2)
  end
  return rawget(t, n)
end

local function debugPrint( msg )
    print(string.char(27) .. "[0;34;40m" .. msg .. string.char(27) .. "[0m") -- debug in blue
end
-- Uncomment the line below to enable debugging
--L._DEBUG = debugPrint

local ctx = {}
local nTest = 0
local nErr = 0
local nSkip = 0

local RED = string.char(27) .. "[0;31;40m"
local YELLOW = string.char(27) .. "[0;33;40m"
local RESET = string.char(27) .. "[0m"

local function fail(m, ...)
    local msg
    if m == nil then msg = "Incorrect result, check manually"
    else msg = string.format(m, ...) end
    print(RED .. "     >>>>> FAIL, " .. msg .. RESET)
    nErr = nErr + 1
end

local function skip(s, ...)
    nTest = nTest + 1
    print(string.format("%03d: %s", nTest, s))
    print(string.format(YELLOW .. "     ***** SKIPPED, ", nTest) .. string.format(...) .. RESET)
    nSkip = nSkip + 1
end

--[[ Evaluate the passed string s. Compare to the expected result.
     To pass, the result must have the same value and data type as
     expected. If the expression is meant to throw an error, then
     failExpect may contain a fragment of the expected error message,
     and it is a failure for the expression to not fail or fail with
     any other message.
--]]
local function eval(s, expected, failExpect, comment, ...)
    local pdebug
    nTest = nTest + 1
    if nTest == FOCUSTEST then pdebug = L._DEBUG ; L._DEBUG = debugPrint end
    local r,err = L.evaluate(s, ctx)
    L._DEBUG = pdebug
    local mm, errmsg
    if r == nil then
        -- There was an error
        if type(err) == "table" then
            mm = string.format("(%s error at %s) %s", err.type, err.location or "unknown", err.message)
            errmsg = err.message
        else
            mm = string.format("(RUNTIME ERROR) %s", tostring(err))
            errmsg = err
        end
    elseif r == L.NULL then
        mm = string.format("(luaxp)NULL")
    else
        mm = string.format("(%s)%s", type(r), L.dump(r))
    end
    print(string.format("%03d: %s=%s", nTest, s, mm))
    if comment ~= nil then
        print("     NOTE: " .. comment)
    end
    if r == nil then
        if failExpect == nil or not string.find( errmsg, failExpect ) then
            -- If you get here and you think your string matches, you may need to escape special (pattern) chars
            fail("unexpected error thrown: %s (%s)", mm, failExpect)
        end
    elseif failExpect ~= nil then
        fail("expected error not thrown (%s)", failExpect)
    elseif expected ~= nil then
        if type(expected) == "function" then
            expected( r, ... )
        elseif type(r) == type(expected) then
            if type(r) == "number" then
                local delta = r - expected
                if math.abs(delta) > 0.00001 then
                    fail("expected (%s)%s, delta %f", type(expected), tostring(expected), delta)
                end
            elseif type(r) == "table" then
                for k,v in pairs(expected) do
                    if r[k] == nil or r[k] ~= v then
                        fail("expected (%s)%s, missing %s", type(expected), dump(expected), tostring(k))
                    end
                end
            else
                if r ~= expected then
                    fail("expected (%s)%s", type(expected), tostring(expected))
                end
            end
        else
            fail("expected (%s)%s", type(expected), tostring(expected))
        end
    else
        print(YELLOW .. "     !!!!! WARNING, test has no defined expected result; check manually." .. RESET)
    end
    return r
end

-- ********************* TIME PARSING TESTS **********************
--[[
    NOTA BENE! These tests were largely written to run on a system configured
               for the America/New York time zone. If run in a different zone,
               errors would be expected and adjustments would need to be made.
--]]
local function doTimeTests()
    local now = eval("time()", function( result ) if result ~= os.time() then fail() end end)
    local localeDateTime = eval("strftime(\"%x %X\", " .. now .. ")", nil, nil, "The result should be current date in locale format")
    eval("strftime(\"%b %B\", time())", nil, nil, "The result should be abbrev and full name for current month in locale language/format")
    eval("time('2014-04-28T16:00-04:00')", 1398715200)
    eval("time('2017-01-20T12:00:00-05:00')", 1484931600)
    eval("time('2013-07-08T09:10:00.553-04:00')", 1373289000)
    eval("time('2019-03-26T09:29:00-0000')", 1553592540)
    eval("time('2019-05-01T10:00:00+0100')", 1556701200)
    eval("time('20180128T151617-0500')", 1517170577)
    eval("time('2013-07-13')", 1373688000)
    eval("time('12/21/2021T0000')", 1640062800)
    eval("time('8/8/2008 8:8:8')", 1218197288)
    eval("time('7/7/7 7:7:7')", 1183806427)
    eval("time('13/11/2011')", 1321160400)
    eval("time('12:45')", function( result ) local dn = os.date("*t") local dr = os.date("*t", result) if not (dr.hour == 12 and dr.min == 45 and dr.year == dn.year and dr.month == dn.month and dr.day == dn.day and dr.sec == 0 ) then fail() end end)
    eval("time('0300')", function( result ) local dn = os.date("*t") local dr = os.date("*t", result) if not (dr.hour == 3 and dr.min == 0 and dr.year == dn.year and dr.month == dn.month and dr.day == dn.day and dr.sec == 0 ) then fail() end end)
    eval("time('8/1 1:45pm')", function( result ) local dn = os.date("*t") local dr = os.date("*t", result) if not (dr.hour == 13 and dr.min == 45 and dr.year == dn.year and dr.month == 8 and dr.day == 1 and dr.sec == 0 ) then fail() end end)
    eval("time('8/1/15 3:17am')", 1438413420)
    eval("time('Mon Jan 29 9:43:00 2018')", 1517236980)
    eval("time('Jan 31 2018')", 1517374800)
    eval("time('Jul 4 09:43p')", function( result ) local dn = os.date("*t") local dr = os.date("*t", result) if not (dr.hour == 21 and dr.min == 43 and dr.year == dn.year and dr.month == 7 and dr.day == 4 and dr.sec == 0 ) then fail() end end)
    eval("time('10-Nov-2018')", 1541826000)
    eval("time('" .. localeDateTime .. "')", now)
    eval("time('Mar 10 2014 +24:00:00')", 1394510400)
    eval("time('Oct 1 2009 +30:00:00:00')", 1256961600)
    eval("time('Sep 21 2012 15:30 -12:15')", 1348255065)
    eval("time('13/11/2011 garbage-at-end')", 1321142400, "Unparseable data")
    local thn = eval("dateadd('2018-06-15', 45, 30, 15, 6, 3, 2)", 1600716645)
    eval("datediff(dateadd(time(),0,0,0,1))", 86400)
    eval("dateadd('1980-09-01',0,0,0,0,360)", 1283313600)
    -- Test date() function, builds date from y,m,d,h,m,s arguments; any null=current
    eval("date(2019,11,4,15,5,0)", 1572897900,nil,"Matched result assumes local TZ is America/New York")
    eval("strftime('%c', date(null,null,null,6,30,0))", nil, nil, "Result should be today 6:30am local time")
    eval("strftime('%c', date(2020))", nil, nil, "Result should be year 2020 today's month, day, and current time")
    eval("strftime('%c', date(null,1,1,0,0,0))", nil, nil, "Result is midnight Jan 1 of this year")

    if ctx.response ~= nil then
        eval("strftime(\"%c\", response.loadtime)", nil, nil, "The result should comport with the loadtime value in sample.json")
    else
        skip("strftime(\"%c\", response.loadtime)", "file sample1.json could not be loaded")
    end
end

local function doStringOpsTests()
    eval('"Es gibt kein Bier auf Hawaii"', "Es gibt kein Bier auf Hawaii")
    eval("'Ich bin Berliner!'", "Ich bin Berliner!")
    eval("'Hello \"there\"'", 'Hello "there"')
    eval('"Well, \'hello\' to you too"', "Well, 'hello' to you too")
    eval("'collaborate' + 'learn'", "collaboratelearn")
    eval("'abc'-'def'", nil, "string to number failed")
    eval("'abc'*'def'", nil, "string to number failed")
    eval("'*'*20", nil, "string to number failed")
    eval("'abc'/'def'", nil, "string to number failed")
    eval("99 + ' bottles of beer on the wall'", "99 bottles of beer on the wall")
    eval("'There are ' + 0 + ' remaining.'", "There are 0 remaining.")
    eval('"What is the reason?', nil, "Unterminated string")
    eval("'New York' == 'NEW YORK'", false)
    eval("'New York' == 'New York'", true)
    eval("'New York' == 'Philadelphia'", false)
    eval("'New York' != 'NEW YORK'", true)
    eval("'New York' != 'New York'", false)
    eval("'New York' != 'Philadelphia'", true)
end

local function doNumericParsingTests()
    eval("0",0)
    eval("1",1)
    eval("-1",-1)
    eval("-1+1",0)
    eval("186282",186282)
    eval("-255",-255)
    eval("077",63)
    eval("0x1F",31)
    eval("0b0011",3)
    eval("1e3", 1000)
    eval("1E", nil, "Missing exponent")
    eval("10e-1",1)
    eval("-0.567112E+06", -567112)
    eval(".7177", 0.7177)
    eval("'123'+321", 444)
    eval("tonumber(123)+321",444)
    eval("pi",3.14159265)
    eval("0xgg", nil, "Invalid")
    eval("0ff", nil, "Invalid")
    eval("0b2", nil, "Invalid")
end

local function doNumericOpsTests()
    eval("123 + 456", 579)
    eval("579-123", 456)
    eval("8--1", 9)
    eval("-8-1", -9)
    eval("-8--9", 1)
    eval("123*4", 492)
    eval("492/123", 4)
    eval("127 % 100", 27)
    eval("400 % 100", 0)
    eval("300 < 400", true)
    eval("300 < 300", false)
    eval("300 < 200", false)
    eval("500 > 100", true)
    eval("500 > 500", false)
    eval("500 > 600", false)
    eval("300 <= 400", true)
    eval("300 <= 300", true)
    eval("300 <= 200", false)
    eval("500 >= 100", true)
    eval("500 >= 500", true)
    eval("500 >= 600", false)
    eval("500 == 500", true)
    eval("500 != 500", false)
    eval("500 == 600", false)
    eval("500 != 600", true)
    eval("15&8",8)
    eval("7&8",0)
    eval("2|4",6)
    eval("6^4",2)
    eval("!8", -9)
    eval("!0", -1)

    -- Precedence tests
    eval("1+2*3", 7)
    eval("1*2-4", -2)
    eval("8-32/4", 0)
    eval("1+(2-4)", -1)
    eval("(((((((((( 24 ))))))))))", 24)
    eval("2+4>5", true)
    eval("2+6!=6", true)
    eval("1==1&4", true, nil, "Equiv (1==1)&4 so true&4 is true; not 1==(1&4), 1==0 is false")
    eval("1==(1&4)", false)
    eval("1+1&5", 0, nil, "Equiv (1+1)&5 so 2&5 is 0; not 1+(1&5), 1+1 is 2")
    eval("1+(1&5)", 2)
    eval("3|4+7", 11, nil, "Equiv 3|(4+7), 3|11 is 11; not (3|4)+7, 7+7 is 14")
    eval("(3|4)+7", 14)
end

local function doBooleanOpsTests()
    -- Note !0 and !1 are treated as number, not boolean, and produce a 32-bit bitwise result. See num ops tests
    eval("true", true)
    eval("false", false)
    eval("!'0'",true)
    eval("!'1'",false)
    eval("true&1",true)
    eval("true&0",false)
    eval("true&'true'", true)
    eval("'false'&'false'", false)
    eval("'false'&'true'", false)
    eval("'true'&'true'", true)
    eval("'false'|'false'", false)
    eval("'false'|'true'", true)
    eval("'true'|'true'", true)
    eval("'false'^'false'", false)
    eval("'false'^'true'", true)
    eval("'true'^'true'", false)
    eval("true && true", true)
    eval("true && false", false)
    eval("false && true", false)
    eval("true || true", true)
    eval("true || false", true)
    eval("false || false", false)
    eval("true and true", true)
    eval("true and false", false)
    eval("false and true", false)
    eval("true or true", true)
    eval("true or false", true)
    eval("false or false", false)
    eval("true and true or false", true)
    eval("true and false or false", false)
    eval("true and 'yes' or 'no'", "yes")
    eval("false and 'yes' or 'no'", "no")
end

local function doMathFuncTests()
    eval("abs(123)", 123)
    eval("abs(-123)", 123)
    eval("abs(0)", 0)
    eval("abs(-0)", 0)
    eval("sgn(123)", 1)
    eval("sgn(-123)", -1)
    eval("sgn(0)", 0)
    eval("sgn(-0)", 0)
    eval("round(1.1111,2)", 1.11)
    eval("round(1.78,0)", 2)
    eval("round(0, 4)", 0)
    eval("sqrt(64)",8)
    eval("sin(pi/2)",1)
    eval("cos(pi/2)",0)
    eval("sin(0)",0)
    eval("cos(0)",1)
    eval("sqrt(2)/2")
    eval("acos(1)", 0)
    eval("asin(0)", 0)
    eval("atan(pi)")
    eval("cos('wilma')", nil, "Non%-numeric argument 1")
    eval("sin(45 * pi / 180)", nil, nil, "The result should be about sqrt(2)/2 = 0.707...")
    eval("floor(123)",123)
    eval("floor(0.123*1000)", 123.0, nil, "There is a known Lua rounding error here, but == comparisons on floats are always dangerous in any language")
    eval("floor(1.8)", 1)
    eval("floor(1.2)", 1)
    eval("floor(-1.2)", -2)
    eval("ceil(1.8)", 2)
    eval("ceil(1.2)", 2)
    eval("ceil(-1.2)", -1)
    eval("pow(10,2)", 100)
    eval("pow(10,-1)", 0.1)
    eval("min(1,9)", 1)
    eval("min(9,1)", 1)
    eval("max(1,9)", 9)
    eval("max(9,1)", 9)
    eval("array=list(5,16,2,6,-1,15,12)", nil, nil, "Array setup for next test")
    eval("min(1,2,3,array)", -1)
    eval("max(1,2,3,array)", 16)
    eval("randomseed(123)", 123)
    eval("randomseed()", os.time(), nil, "May be slightly off sometimes")
    eval("random()", nil, nil, "Random number between 0 and 1")
    eval("random(100)", nil, nil, "Random number between 1 and 100")
    eval("random(20,30)", nil, nil, "Random number between 20 and 30")
end

local function doStringFuncTests()
    eval("(123)..(456)", "123456")
    eval("'abc'..987", "abc987")
    eval("'abc'+987", "abc987")
    eval("45+'°C'", "45°C")
    eval("len('The rain in Spain stays mainly in the plain.')", 44)
    eval("sub('The rain in Spain stays mainly in the plain.', 5, 8)", "rain")
    eval("sub('The rain in Spain stays mainly in the plain.', 40, 49)", "lain.")
    eval("sub('The rain in Spain stays mainly in the plain.', 35, -5)", "the pl")
    eval("sub('The rain in Spain stays mainly in the plain.', 39)", "plain.")
    eval("sub('[in brackets]', 2, -2)", "in brackets")
    eval("sub('Jack\\'s house', 1, 6)", "Jack's")
    eval("sub('A back slash (\\\\) is a screening character', 14, 16)", "(\\)")
    eval('sub("Start from a \\"Hello, World!\\" program", 14, 28)', '"Hello, world!"')
    eval("find('The rain in Spain stays mainly in the plain.', 'not there')", 0)
    eval("find('The rain in Spain stays mainly in the plain.', 'plain.')", 39)
    eval("upper('The rain in Spain stays mainly in the plain.')", "THE RAIN IN SPAIN STAYS MAINLY IN THE PLAIN.")
    eval("lower('The rain in Spain stays mainly in the plain.')", "the rain in spain stays mainly in the plain.")
    eval("format('I like %s, I buy %dkg at a time.', 'cheese', 5)", "I like cheese, I buy 5kg at a time.")
    eval("rtrim('   only on the right   ')", "   only on the right")
    eval("ltrim('   only on the left   ')", "only on the left   ")
    eval("trim('      both sides     ')", "both sides")
    eval("tostring(true)", "true")
    eval("tostring(123)", "123")
    eval("tostring(1.23)", "1.23")
    eval("tostring('cardiovascular')", "cardiovascular")
    eval("tonumber(true)", 1)
    eval("tonumber(false)", 0)
    eval("tonumber(123)", 123)
    eval("tonumber(12.3)", 12.3)
    eval("tonumber('456')", 456)
    eval("tonumber('1e5')", 100000)
    eval("tonumber('dog and cat')", nil, "could not be converted")
    eval("tonumber('1E',16)", 30)
    eval("tonumber('-7f',16)", nil, nil, "Known limitation in Lua tonumber(), ignore this case.")
    eval("tonumber('377',8)", 255)
    eval("tonumber('-377',8)", nil, nil, "Known limitation in Lua tonumber(), ignore this case.")
    eval("tonumber('1001',2)", 9)
    eval("split('A,B,C,D,E', ',')", nil, nil, "Array of 5 elements")
    eval("split('F,G,H')", nil, nil, "Array of 3 elements")
    eval("join(split('Z+Y+X+W+V+U', '%+'), 'M')", "ZMYMXMWMVMU")
end

local function doMiscFuncTests()
    eval("if(1==1,\"true\",\"false\")", "true")
    eval("if(7==8,\"true\",\"false\")", "false")
    eval("if(null,\"true\",\"false\")", "false")
    eval("if(7==8,\"true\")", L.NULL)
    eval("if(1==1,null,123)", L.NULL)

    eval("choose(3,\"default\",\"A\",\"B\",\"C\",\"D\")", "C")
    eval("choose(9,\"default\",\"A\",\"B\",\"C\",\"D\")", "default")

    eval("#list(1,2,3,4,5,9)", 6, nil, "Returns table of six elements")
    eval("list(time(),strftime('%c',time()))", nil, nil, "Returns two-element array with timestamp and string time")
    eval("first(list('dog','cat','mouse',time(),upper('leaf')))", "dog")
    eval("first(list())", L.NULL, nil, "First element of empty list returns null")
    eval("last(list('dog','cat','mouse',time(),upper('leaf')))", "LEAF")
    eval("last(list())", L.NULL, nil, "Last element of empty list returns null")
    eval("last('cat')", L.NULL, nil, "Invalid data returns null", "Test constant")
    eval("last(tonumber('123'))", L.NULL, nil, "Invalid data returns null", "Test expression")

    if ctx.response ~= nil then
        eval("#keys(response.rooms)", 23)
        eval("i=''", "",nil,"Setup for next test")
        eval("iterate(list(1,2,3,4,5,6), '_' )", nil, nil, "Returns array of 6 elements")
        eval("iterate(list(1,2,3,4,5,6), _ )", nil, nil, "Returns array of 6 elements; same result as previous")
        eval("#iterate(response.rooms,'void(i = i + \",\" + _.name)')", 0, nil, "Iterator using anonymous upvalue and empty result array")
        eval("#i", 254, nil, "Expected length of string may change if data altered")
        eval('#iterate(response.devices,"if(device.room==10,device.id)","device")', 7, nil, "Expected number of matching rooms may change if data altered")
        eval('#iterate(response.devices, if(device.room==10,device.id) , "device" )', 7, nil, "(LATE EVAL) Expected number of matching rooms may change if data altered")
        eval('map(list(6,5,4,3,2,1), _*16)', nil, nil, "Returns 6 elements with val = 16 x key (e.g. 3=48)")
        eval('map(list(6,5,4,3,2,1), "_*16")', nil, nil, "Result same as previous")
        eval('map(list("dog","cat","goldfish","ferret"))', nil, nil, "Returns table (key=val): dog=1,cat=2,goldfish=3,ferret=4")
    else
        nSkip = nSkip + 9
    end

    --[[ Not yet, maybe some day
    eval("Z=list()", nil, nil, "Set up for next test")
    eval("Z.abc=123", 123, nil, "Subref assignment")
    eval("Z.abc", 123, nil, "Subref assignment check")
    --]]
end

local function doMiscSyntaxTests()
    -- Variable assignment
    ctx.__lvars = ctx.__lvars or {}
    ctx.__lvars.lv = "lv"
    ctx.ctv = "ctv"
    ctx.k = nil ctx.__lvars.k = nil
    eval("lv", "lv") -- value sourced from __lvars (new style)
    eval("ctv", "ctv") -- value sourced from ctx (old style, deprecated)
    eval("i=25",25)
    eval("i", 25)
    if ctx.__lvars.i == nil or ctx.__lvars.i ~= 25 then fail("VARIABLE NOT FOUND IN __LVARS") end
    eval("k", nil, "Undefined var")

    -- Nesting
    eval("min(70,max(20,min(60,max(30,min(50,40)))))", 40)

    -- Quoted identifiers, subreferences, select()
    if ctx.response ~= nil then
        ctx.response['bad name!'] = ctx.response.loadtime
        eval("['response'].['bad name!']", ctx.response.loadtime, nil, "Quoted identifiers allow chars otherwise not permitted")
        eval("response.notthere", L.NULL)
        eval("response.notthere.reallynotthere", nil, "Can't dereference through null")
        ctx.__options = { nullderefnull=true }
            eval("response.notthere", L.NULL, nil, "with nullderefnull set")
            eval("response.notthere.reallynotthere", L.NULL, nil, "nullderefnull")
        ctx.__options = nil
        eval("select( response.rooms, 'id', '14' ).name", "Front Porch")
    else
        skip("['response'].['loadtime']", "JSON data not loaded")
        skip("response.notthere", "JSON data not loaded")
        skip("select( response.rooms, 'id', '14' ).name", "JSON data not loaded")
        skip("response.notthere.reallynotthere", nil, "Can't dereference through null")
        skip("select( response.rooms, 'id', '14' ).name", "Front Porch")
    end

    -- Syntax abuse
    eval("true=123", nil, "reserved word")
    eval("1,2", nil, "Invalid operator")
    eval("a[", nil, "Unexpected end of array subscript")
    eval("123+array]", nil, "Invalid operator")
    eval("+", nil, "Expected operand")

    -- Array subscripts
    ctx.__lvars = ctx.__lvars or {}
    ctx.__lvars.array = {11,22,33,44,55}
        eval("array[4]", 44)
        eval("array[19]", nil, "out of range")
        ctx.__options = { subscriptmissnull=true }
        eval("array[19]", L.NULL, nil, "with 'subscriptmissnull' set")
        ctx.__options = nil
    eval("i=list('A','B','C','D')", {'A','B','C','D'}, nil)
    eval("i[2]='X'", 'X', nil, "Array assignment")
    eval("i[2]", "X", nil)
    eval("#i", 4, nil)
    eval("i", {'A','X','C','D'}, nil)
    eval("k=4", 4, nil)
    eval("i[k]", "D", nil, "Array index vref")
    eval("i[k-1]", "C", nil, "Array index expression")
    eval("i   [    k ]", "D", nil, "Array index vref excess whitespace")
    eval("i                [ k-1            ]", "C", nil, "Array index expression excess whitespace")

    eval("true.val", nil, "Cannot subreference")
    eval("true[1]", nil, "not an array")
    eval("ff(1, )", nil, "Invalid subexpr") eval("ff( ,1)", nil, "Invalid subexpr")

    -- Custom functions
    ctx.__functions = { doublestring = function( argv ) return argv[1]..argv[1] end }
    eval("doublestring('galaxy')", "galaxygalaxy", nil, "Test custom function in __functions table (preferred)")
    ctx.dubstr = ctx.__functions.doublestring
    eval("dubstr('planet')", "planetplanet", nil, "Test custom function in context root (deprecated)")

    -- External resolver
    ctx.__functions = { __resolve = function( name, ctx ) if name == "MagicName" then return "Magic String" else return nil end end }
    eval("MagicName+' was found'", "Magic String was found", nil, "Test last-resort resolver (name found)")
    eval("PlainName", nil, "Undefined variable", "Test last-resort resolver (name not found)")

    eval("tonumber         ( 123 )", 123, nil, "Excess whitespace in function ref")

    ctx.__functions = nil
end

local function doNullTests()
    eval("null", L.NULL)
    eval("nil", L.NULL)
    eval("null*4", nil, "Can't coerce null")
    eval("null/null", nil, "Can't coerce null")
    eval("tostring(null)", "")
    eval("null + 'abc'", "abc")
    eval("null & 123", false, nil, "null coerces to boolean false, and bool & number = bool")
    eval("null==0", false)
    eval("null==null", true)
    eval("null~=null", false)
    eval("null==1", false)
    eval("null==true", false)
    eval("null==false", true)
    eval("null==''", true)
    eval("len(null)", 0, nil, "The length of null is zero.")
    eval("null and false", L.NULL, nil, "Lua style")
    eval("null & false", false, nil, "C style (null coerced to boolean before op)")
    eval("null and true", L.NULL)
    eval("null & true", false)
    eval("true and null", L.NULL)
    eval("true & null", false)
    eval("false and null", false)
    eval("false & null", false)
    eval("null or true", true)
    eval("null or false", false)
    eval("true or null", true)
    eval("false or null", L.NULL)
    eval("false | null", false, nil, "C style")
end

local function doRegressionTests()
    local t = ctx -- save current context

    -- For this test, use special context.
    local s = '{"coord":{"lon":-84.56,"lat":33.39},"weather":[{"id":800,"main":"Clear","description":"clear sky","icon":"01d"}],"base":"stations","main":{"temp":281.29,"pressure":1026,"humidity":23,"temp_min":278.15,"temp_max":285.15},"visibility":16093,"wind":{"speed":5.1,"deg":150},"clouds":{"all":1},"dt":1517682900,"sys":{"type":1,"id":789,"message":0.0041,"country":"US","sunrise":1517661125,"sunset":1517699557},"id":0,"name":"Peachtree City","cod":200}'
    ctx = { response = json.decode(s) }
    eval("response.weather[1].description", "clear sky")
    eval("if( response.fuzzball==null, 'NO DATA', response.fuzzball.description )", "NO DATA", nil, "Late eval")
    eval("if( response['fuzzball']==null, 'NO DATA', response.fuzzball.description )", "NO DATA", nil, "Late eval")

    -- Special context here as well.
    ctx = json.decode('{"val":8,"ack":true,"ts":1517804967381,"q":0,"from":"system.adapter.mihome-vacuum.0","lc":"xyz","_id":"mihome-vacuum.0.info.state","type":"state","common":{"name":"Vacuum state","type":"number","read":true,"max":30,"states":{"1":"Unknown 1","2":"Sleep no Charge","3":"Sleep","5":"Cleaning","6":"Returning home","7":"Manuell mode","8":"Charging","10":"Paused","11":"Spot cleaning","12":"Error?!"}},"native":{}}')
    ctx = { response=ctx }
    eval("response.val", 8, nil, "Specific test for atom mis-identification (issue X) discovered by SiteSensor user")

    ctx = t -- restore prior context
end

-- Load JSON data into context, if we can.
if json then
    local file = io.open( testData, "r" )
    if file then
        local s = file:read("*all")
        file:close()
        ctx.response = json.decode(s)
    else
    print(RED.."JSON data could not be loaded!"..RESET)
    end
end

--[[
--]]
print("luaxp.null is "..tostring(L.NULL))
doNumericParsingTests()
doNullTests()
doNumericOpsTests()
doStringOpsTests()
doBooleanOpsTests()
doMathFuncTests()
doStringFuncTests()
doTimeTests()
doMiscSyntaxTests()
doMiscFuncTests()
doRegressionTests()

print("")
print(string.format("Using module %s %s, ran %d tests, %d skipped, %d errors.", moduleName, tostring(L._VERSION), nTest, nSkip, nErr))
if ctx.response == nil then
    print(RED.."JSON data not loaded, some tests skipped"..RESET)
end
