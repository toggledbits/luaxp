test = require('test/test')
testeval = test.testeval -- bring into global space

print("### Luaxp functional test -- string parsing")

testeval("\"The rain in Spain\"", "The rain in Spain")
testeval("'The rain in Spain'", "The rain in Spain")
testeval("'\\\\'", "\\")
testeval('"inside \\"quotes\\""', "inside \"quotes\"")
