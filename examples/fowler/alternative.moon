-- alternative.moon
task = target

task.codeGen nil, ->
    print 'codeGen'

task.compile 'codeGen',->
    print 'compile'

task.dataLoad 'codeGen',->
    print 'dataLoad'

task.test 'compile dataLoad',->
    print 'test'

default 'test'
