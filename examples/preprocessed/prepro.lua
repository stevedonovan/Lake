local file = arg[1]
local out = arg[2]
io.output(out)
for line in io.lines(file) do
    local proto,expr = line:match '([^%-]+)%->%s*(.+)'
    if proto then
        io.write(proto..'{ return '..expr..'; }\n')
    end
end
io.close()


