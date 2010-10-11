## Lake - a Lua-based Build Tool

`lake` is the grown-up version of [Bou](http://lua-users.org/wiki/LuaBuildBou). It resembles Ruby's `rake` in that it directly executes dependency rules and does not generate a makefile. Unlike `rake`, it knows about the two most popular compilers currently, `GCC` and Microsoft's `CL` aims to simplify cross-platform development.

There is one file, `lake.lua`, which only depends on LuaFileSystem - the suggested practice is to make a suitable script or batch file to run it from the console. That is, either this for Unix

    # lake
    lua /path/to/lake.lua $*
    
or this
    
    rem lake.bat
    lua \path\to\lake.lua %*
    
Here is a lakefile for building Lua itself:

    LUA='lua'
    LUAC='luac print'
    as_dll = WINDOWS
    if as_dll then
      defs = 'LUA_BUILD_AS_DLL'
    end
    if not WINDOWS then
      defs = 'LUA_USE_LINUX'
    end

    -- build the static library
    lib,ll=c.library{'lua',src='*',exclude={LUA,LUAC},defines=defs}

    -- build the shared library
    if as_dll then
      libl = c.shared{'lua',rules=ll,dynamic=true}
    else
      libl = lib
    end

    -- build the executables
    lua = c.program{'lua',libl,src=LUA,needs='dl math readline',export=not as_dll}
    luac = c.program{'luac',lib,src=LUAC,needs='math'}

    default {lua,luac}

More details can be found in `doc/index.md`

Released under the MIT/X11 licence,
Steve Donovan, 2010