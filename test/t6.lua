test = require('test/test')
testeval = test.testeval -- bring into global space

print("### Luaxp functional test -- native functions")

testeval("abs(-34)", "34")
testeval("abs(0)", "0")
testeval("abs(34)", "34")
testeval("sgn(-33)", "-1")
testeval("sgn(0)", "0")
testeval("sgn(-0)", "-0") -- PR: Need to resolve this ambiguity
testeval("sgn(42)", "1")
testeval("floor(42)", "42")
testeval("floor(42.4242)", "42")
testeval("floor(-34.123)", "-35")
testeval("floor(0)", "0")
testeval("ceil(42)", "42")
testeval("ceil(42.4242)", "43")
testeval("ceil(-34.123)", "-34")
testeval("ceil(0)", "0")
testeval("round(42,2)", "42")
testeval("round(42.4242,2)", "42.42")
testeval("round(-34.123,2)", "-34.12")
testeval("round(-34.825,2)", "-34.83")
testeval("round(0,2)", "0")
testeval("round(15.2,0)", "15")
testeval("round(15.8,0)", "16")
testeval("round(42.42)", "42")
testeval("round(84.84)", "85")

testeval("cos(0)", "1")
testeval("cos(1)", "0.5403(%d*)")
testeval("cos(-1)", "0.5403(%d*)")
testeval("sin(0)", "0")
testeval("sin(1)", "0.8414(%d*)")
testeval("sin(-1)", "-0.8414(%d*)")

testeval("log(10)", "2.3025(%d*)")
testeval("exp(3)", "20.085(%d*)")
testeval("pow(10,4)", "10000")
testeval("pow(10,-2)", "0.01")
testeval("pow(2,8)", "256")
testeval("pow(2,0)", "1")
testeval("pow(10,0)", "1")

testeval("sqrt(4)","2")
testeval("sqrt(81)","9")

testeval("min(1,10)","1")
testeval("min(10,1)","1")
testeval("max(1,10)","10")
testeval("max(10,1)","10")

testeval("len('12345')", "5")

testeval("sub('abcdef',3,4)", "cd")
testeval("sub('This is the end',13)", "end")

testeval("upper('case')", "CASE")
testeval("upper('CASE')", "CASE")
testeval("lower('case')", "case")
testeval("lower('CASE')", "case")

testeval("tonumber('123')", "123")
testeval("tonumber('111',2)", "7")
testeval("tonumber('177',8)", "127")
testeval("tonumber('a0',16)", "160")

testeval("time()", "%d+")

