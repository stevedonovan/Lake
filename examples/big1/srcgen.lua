require 'pl'

t = text.Template [[
#include <stdio.h>
#include "header.h"
$HEADERS
int $NAME(void) { return 0; }
]]

function pick (prob)
    return math.random() < prob
end

for i = 1,100 do
    local name = 'c'..('%03d'):format(i)
    local headers = List()
    if pick(0.3) then headers:append 'first' end
    if pick(0.5) then headers:append 'second' end
    if pick(0.1) then headers:append 'third' end
    headers = headers:map [[|x| '#include "'..x..'.h"']]:join '\n'
    file.write(name..'.c',t:substitute {NAME = name, HEADERS = headers})
end
