-- see http://martinfowler.com/articles/rake.html#DependencyBasedProgramming

actions,deps = {},{}

function actions.codeGen ()
  print 'codeGen'
end

deps.compile = 'codeGen'
function actions.compile ()
    print 'compile'
end

deps.dataLoad = 'codeGen'
function actions.dataLoad ()
    print 'dataLoad'
end

deps.test = 'compile dataLoad'
function actions.test ()
    print 'test'
end

for name,fun in pairs(actions) do
    target(name,deps[name],fun)
end

default 'test'



