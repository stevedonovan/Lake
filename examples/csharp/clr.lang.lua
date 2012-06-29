-- note that both the compiler name CSC and the
-- language object clr are globals!
if WINDOWS then
  CSC = 'csc'
  if not utils.which(CSC) then
	local ok,winapi = pcall(require,'winapi')
	if not ok then quit 'you need winapi for this' end
	local getenv = os.getenv
	local net = getenv('WINDIR')..'/Microsoft.NET/Framework/v2*'
	local candidates = path.files_from_mask(net)
	if #candidates == 0 then quit("cannot find .NET") end
	winapi.setenv('PATH',getenv'PATH'..';'..candidates[1])
   end
else
  CSC = 'gmcs'
  if not utils.which(CSC) then quit 'mono-devel not installed' end
end

clr = {ext = '.cs',obj_ext='.?'}
clr.link = '$(CSC) -nologo  $(LIBS) -out:$(TARGET) $(SRC)'
-- do this because the extensions are the same on Unix
clr.EXE_EXT = '.exe'
clr.DLL_EXT = '.dll'
clr.LINK_DLL = '-t:library'
clr.LIBPOST = '.dll'
clr.DEFDEF = '-d:'
clr.LIBPARM = '-r:'
clr.flags_handler = function(self,args,compile)
  local flags
  if args.debug or DEBUG then
    flags = '-debug'
  elseif args.optimize or OPTIMIZE then
    flags = '-optimize'
  end
  if args.deps then -- may be passed referenced assemblies as dependencies
     local deps_libs = {}
     for d in list(args.deps) do
        if istarget(d) and d.ptype == 'dll' then
            local target = path.splitext(d.target)
            table.insert(deps_libs,target)
        end
     end
     if #deps_libs > 0 then
        args.libs = args.libs and lake.deps_arg(args.libs) or {}
        list.extend(args.libs,deps_libs)
     end
  end
  return flags
end

if not WINDOWS then
    clr.runner = function(prog,args)
        exec('mono '..prog..args)
    end
end

lake.add_prog(clr)
lake.add_shared(clr)
lake.register(clr,clr.ext)

