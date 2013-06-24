require 'lake'

-- can suppress chatter...
lake.set_log(function(msg) end)

local TO = {}
TO.__index = TO

function TO:__tostring()
    return "["..self.name.."]"
end

function TO:update()
    print('updating '..tostring(self))
end

local function T(name,time)
    return setmetatable({name=name,time=time or -1},TO)
end

local function update(t)
    t.target:update()
end

B = T('B',10)
C = T('C',10)
A = T('A',10)
D = T('D',0)

tA = target(A, {B, C},update)

default{
    target(D, tA, function(t)
        print('updating D!')
    end)
}
print 'go 1'
lake.go()
print 'go 2'
B.time = 11
lake.go()



