test = require('test/test')
testeval = test.testeval -- bring into global space

print("### Luaxp functional test -- expressions")

testeval("172+45-16", "201")
testeval("9*19/3", "57")
testeval("2+3*4+5", "19") -- TO-DO: Correct operator precedence
testeval("100+50*2", "200") -- TO-DO: Correct operator precedence
testeval("25*2+10", "60")
testeval("100+(50*2)", "200")
testeval("25*(2+10)", "300")
testeval("(2+(2+(2+(2+(2+(2+(2+7)))))))", "21")
testeval("(14+(7*(3-9)*4-(9*(8/2))+14)-3)", "-179")
testeval("                         (                    17 * 2                       ) - 4              ", "30")
