## Command-line Flags

        Lake version 1.0  A Lua-based Build Engine
        -v verbose
        -n don't synthesize target
        -d initial directory
        -t test (show but don't execute commands)
        -s strict compile
        -g debug build
        -f FILE read a named lakefile
        -e EXPR evaluate an expression
        -l FILE build a shared library/DLL
        -p FILE build a program
        -lua FILE build a Lua binary extension

## Globals

    WINDOWS
    PLAT
    DIRSEP
    TESTING
    LOCAL_EXEC (572)
    EXE_EXT
    DLL_EXT
    LIBS
    CFLAGS
    INPUT
    TARGET
    DEPENDS
    ALL_TARGETS
    OPTIMIZE
    
    C_LINK_PREFIX
    C_LINK_DLL
    C_EXE_EXPORT
    C_STRIP
    C_LIBSTATIC
    LIB_PREFIX
    LIB_EXT 
    C_LIBPARM
    C_LIBPOST
    C_LIBDIR
    C_DEFDEF
    LIB_PREFIX
    SUBSYSTEM
    C_LIBDYNAMIC
    
    
These can be set on the command-line (like make) and in the environment variable LAKE_PARMS
        
        CC - the C compiler (gcc unless cl is available)
        CXX - the C++ compiler (g++ unless cl is available)
        FC - the Fortran compiler (gfortran)
        OPTIMIZE - (O1)
        STRICT - strict compile (also -s command-line flag)
        DEBUG - debug build (also -g command-line flag)
        PREFIX - (empty string. e.g. PREFIX=arm-linux makes CC become arm-linux-gcc etc)
        NEEDS - any needs a build may require, for instance 'socket' or 'gtk': works with needs parameter
        LUA_INCLUDE,LUA_LIB - (usually deduced from environment)
        WINDOWS - true for Windows
        PLAT - platform deduced from uname if not windows, 'Windows' otherwise
        MSVC - true if we're using cl
        EXE_EXT -  extension of programs on this platform
        DLL_EXT - extension of shared libraries on this platform
        DIRSEP - directory separator on this platform
        NO_COMBINE - don't allow the compiler to compile multiple files at once (if it is capable)
        NODEPS - don't do automatic dependency generation
    
      
### Languages

    c
    cpp
    f
    c99
    wresource
    
### Basic Variables (933)

These will only substituted when the actual target is run. They are related to target fields like so:

    INPUT   t.input
    TARGET  t.target
    DEPENDS t.deps
    LIBS    t.libs
    CFLAGS  = t.cflags
    
##   Program Fields

        name -- name of target (or first value of table)
        lua -- build against Lua libs
        needs -- higher-level specification of target link requirements
        libdir -- list of lib directories
        libs -- list of libraries
        libflags -- list of flags for linking
        subsystem -- (Windows) GUi application
        strip -- strip symbols from output
        rules,inputs -- explicit set of compile targets
        shared,dll -- a DLL or .so (with lang.library)
        deps -- explicit dependencies of a target (or subsequent values in table)
        export -- this executable exports its symbols
        dynamic -- link dynamically against runtime (default true for GCC, override for MSVC)
        static -- statically link this target
        headers -- explicit list of header files (not usually needed with auto deps)
        odir -- output directory; if true then use 'debug' or 'release'; prepends PREFIX
        src -- src files, may contain directories or wildcards (extension deduced from lang or `ext`)
        exclude =true,	-- a similar list that should be excluded from the source list (e.g. if src='*')
        ext -- extension of source, if not the usual. E.g. ext='.cxx'
        defines -- C preprocessor defines
        incdir -- list of include directories
        flags -- extra compile flags
        debug -- override global default set by -g or DEBUG variable
        optimize -- override global default set by OPTIMIZE variable
        strict -- strict compilation of files
        base -- base directory for source and includes
        

