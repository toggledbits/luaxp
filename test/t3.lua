test = require('test/test')
testeval = test.testeval -- bring into global space

print("### Luaxp functional test -- unary operators")

testeval("-0", "0")
testeval("+0", "0")
testeval("!0", "1")
testeval("!1", "0")
testeval("!255", "0")
testeval("-100", "-100")
testeval("-1e3", "-1000")
testeval("+1e3", "1000")
