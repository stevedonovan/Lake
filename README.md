## Lake - a Lua-based Build Tool

`lake` is a build engine written in Lua, similar to Ruby's [rake](http://rake.rubyforge.org/).
It is not a makefile generator, but evaluates dependencies directly - that is, it is an
interpreter of dependency rules, not a makefile compiler.  This is a sensible design decision
because `lake` is small (about 70K pure Lua, 250K together with Lua and LuaFileSystem) enough
to carry around.

Much of the inspiration for `lake` comes from Martin Fowler's article on [dependency-driven
programming](http://martinfowler.com/articles/rake.html) in `rake`.

There is one file, `lake`, which only depends on LuaFileSystem. On Unix, you can
simply make it executable and put it on your path.


Or for Windows:

    rem lake.bat
    lua \path\to\lake %*

Apart from being quick & compact, these are the features of interest:

   - it is an embedded DSL (Domain Specific Language) - all the normal functionality of Lua is
available
   - it knows about both `GCC` and Microsoft Visual C++ compilers, and does cross-platform builds
   - it knows about building Lua extensions in C or C++

For example, a lakefile for building a GTK application can be as simple as:

    c.program{'hello',needs='gtk'}

Creating a binary Lua extension:

    c.shared{'mylib',needs='lua'}

`lake` can be used to automate other tools as well. This will convert all JPEG files in the
current directory to PNG, but only if the PNG file does not exist or the JPEG file has changed.

    to_png = rule('.jpg','.png',
      'convert $(INPUT) $(TARGET)'
    )

    default(to_png '*')

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
Steve Donovan, 2010-2013

