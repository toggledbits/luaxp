test = require('test/test')
testeval = test.testeval -- bring into global space

print("### Luaxp functional test -- user variables and functions")

testeval("pi", "3.14159(%d+)", { pi=math.pi })
testeval("toradians(90)", "1.5707(%d+)", { toradians=function(a) return a[1]*math.pi/180 end })
testeval("dot.something.dot.another", "correct", { dot = { something = { dot = { another = "correct" } } }, another="wrong" } )
