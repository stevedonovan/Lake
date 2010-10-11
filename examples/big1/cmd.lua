f = io.open ('test.bat','w')
f:write 'cl /nologo -c /O1 '
for i = 1,100 do
	f:write(('c%03d.c'):format(i),' ')
end
f:write '\n'
f:close()
