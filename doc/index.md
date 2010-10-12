## Why Yet Another Build Engine?

`lake` is a build engine written in Lua, similar to Ruby's [rake](http://rake.rubyforge.org/). It is not a makefile generator, but evaluates dependencies directly - that is, it is an interpreter of dependency rules, not a makefile compiler.  This is a sensible design decision because `lake` is small (about 50K pure Lua, 250K together with Lua and LuaFileSystem) enough to carry around.

Much of the inspiration for `lake` comes from Martin Fowler's article on [dependency-driven programming](http://martinfowler.com/articles/rake.html) in `rake`.

Naturally, this is not a new idea in the Lua universe. [PrimeMover](http://primemover.sourceforge.net/) is similar in concept. There are a number of Lua-to-makefile generators, like [premake](premake.sourceforge.net/projects/) and [hamster](http://luaforge.net/projects/hamster/) - the former can also generate SCons output.

Apart from being quick & compact, these are the features of interest:

   - it is an embedded DSL (Domain Specific Language) - all the normal functionality of Lua is available
   - it knows about both `GCC` and Microsoft Visual C++ compilers, and does cross-platform builds
   - it knows about building Lua extensions in C or C++

## `lake` as a Compiler Front-end

Generally, build rules for `lake` are expressed in _lakefiles_, which are Lua scripts. But it is possible to use `lake` directly on a source file. Consider this simple C program:

    $> cat hello.c
    #include <stdio.h>
    int main(int argc, char **argv)
    {
      int i;
      printf("hello, world!\n");
      for (i = 0; i < argc; ++i) {
            printf("%d %s\n",i,argv[i]);
      }
      return 0;
    }

Passing this as an argument to `lake` causes the program to be compiled, linked and then run:

    $> lake hello.c
    cl /nologo -c /O1 /showIncludes  hello.c
    link /nologo hello.obj  /OUT:hello.exe
    hello.exe
    hello, world!
    0 hello.exe

Thereafter, the program is up-to-date and will not be rebuilt until the source file changes.

    $> lake hello.c one two three
    hello.exe one two three
    hello, world!
    0 hello.exe
    1 one
    2 two
    3 three

On Windows, the Microsoft compiler is the default, if it is found on the path,  but it is straightforward to override the compiler on the command line:

    $> lake CC=gcc hello.c one two three
    gcc -c -O1 -MMD  hello.c
    gcc hello.o  -o hello.exe
    hello.exe one two three
    hello, world!
    0 hello.exe
    1 one
    2 two
    3 three

On Linux, we default to using gcc:

    $ lake hello.c
    gcc -c -O1 -MMD  hello.c
    gcc hello.o  -o hello
    ./hello
    hello, world!
    0 ./hello

## Invoking `lake`

Like `make`, `lake` looks for a file called 'lakefile'.  Simularly, you can say `lake -f any.lake` where `any.lake` contains the lakefile commands.

Typing `lake --help` gives some more options. `-d` is followed by a directory, and means 'change to that directory and run'.  `-t` is useful for testing; it will show the commands but won't execute them.

`-s` means 'strict compile'; uses '-pedantic -Wall' for `GCC`; '/WX' for `CL`. Alternatively, you can set `STRICT=true` at the start of your lakefile.

How to customize the operation of `lake` itself? There are several ways (in order of evaluation):

   - if an environment variable `LAKE_PARMS` exists, then it's assumed to contain `VAR=VALUE` pairs separated by semi-colons
   - you can set variables at the command-line with `VAR=VALUE` (as with Make)
   - if a file `lakeconfig` is found in the current directory, it will then be loaded 
   - if `~/.lake/config` exists, it will read. (On Windows, `~` is your home directory like `C:\Documents and Settings\SJDonova` or `C:\Users\sdonovan` )
   -  you can of course explicitly say `require 'mymodule'` in your lakefile.

## Basic lakefiles

The simplest hello-world lakefile is straightforward; it builds a C program named 'hello', with no explicit source files, so we use the program name:

    $> cat lakefile
    c.program{'hello'}

    $> lake
    gcc -c -O1 -MMD  hello.c
    gcc hello.o  -o hello.exe

This lakefile automatically understands a 'clean' target, and the `-g` option forces a debug build:

    $> lake clean
    removing        hello.exe
    removing        hello.o
    $> lake -g
    gcc -c -g -MMD  hello.c
    gcc hello.o  -o hello.exe

(You can achieve the same effect as `-g` by passing `DEBUG=true` on the command-line)

If cl.exe is on your path, then we would get:

    $> lake -g
    cl /nologo -c /Zi /showIncludes  hello.c
    link /nologo hello.obj  /OUT:hello.exe

`lake` knows the common flags that these compilers use to achieve common goals - in this case, a debug build.  This places less stress on human memory (which is not a renewable resource) especially if you are working with a compiler which is foreign to you.

Now, what if `hello.c` had a call to a math function?  No problem with Windows (it's part of the C runtime) but on Unix it is a separate library.  A lakefile that expresses this _need_ is:

    c.program{'hello',needs='math'}

On Unix, we will now get the necessary `-lm`. All this can be done with a makefile, but it would already be an irritating mess, even if it just handled `GCC` alone.  The purpose of `lake` is to express build rules in a high-level, cross-platform way. 

Note here that we have been implicitly using a cool Lua feature, which is that a function call does not need parens if the single argument is a table.  Lua does not support named arguments as such, but the table syntax is very flexible and does the same job elegantly.

The next step is multi-file programs.  In `examples/first`:

    $> cat lakefile
    c.program{'first',src='one,two',needs='math'}

    $> lake
    gcc -c -O1 -MMD  one.c
    gcc -c -O1 -MMD  two.c
    gcc one.o two.o   -o first.exe

Here the source files are explicitly defined by the `src` parameter (without extension), and the project name continues to define the name of the output file.

This simple lakefile does dependency checking; if a source file changes, then it is recompiled, and the program is relinked since it depends on the output of the compilation.  We don't need to rebuild files that have not changed.

    $> touch one.c
    $> lake
    gcc -c -O1 -MMD  one
    gcc one.o two.o   -o first.exe

Actually, `lake` goes further than this. Both `one.c` and `two.c` depend on `common.h`; if you modify this common dependency, then both source files are rebuilt. This is done because `lake` knows about the `GCC` `-MMD` flag, which generates a file containing the non-system header files encountered during compilation:

    $> cat one.d
    one.o: one.c common.h

One tiresome aspect of constructing robust makefiles is explicitly listing the dependencies.  (This is not a criticism of `make`, which does what it does well, and it does not pretend to understand the tools it is running, whereas `lake` has been designed to be very tool-aware for your convenience.) This also works for the `CL` compiler using the somewhat obscure `/showIncludes` flag.

So the lakefiles for even fairly large code bases can be short and sweet. In `examples/big1` there are a hundred generated .c files, with randomly assigned header dependencies:

    $> cd examples/big1
    $> cat lakefile
    c.program {'name',src='*'}

Here `src` is a wildcard, again assuming an extension of `.c` for C files. The initial build takes some time, but thereafter rebuilding is quick. 

By default, `lake` tries to compile as many files as it can with one compiler invocation.  Both `GCC` and `CL` support this, but not if you have explicitly specified an output directory.  The global `NO_COMBINE` can be used to switch off this attempt to be helpful.

## The Concept of Needs

Building a target often requires particular system libraries. For equivalent functionality, these libraries may be different. For the example above, a Linux program needs `libm.a` if it wants to link to `fabs` and `sin` etc, but a Windows program does not.  We express this as the _need_ 'math' and let `lake` sort it out.  Other common Linux needs are 'dl' if you want to load dynamic libraries directly using `dlopen`.  On the other side, Windows programs need to link against `wsock32` to do standard Berkerly-style sockets programming; the need 'sockets' expresses this portably.   The need 'readline' is superfluous on Windows, since the shell provides much of this functionality out of the box, and on Linux it also implies linking against `ncurses` and `history`; on OS X linking against `readline` is sufficient.

There are also two predefined needs for GTK+ programming: 'gtk' and 'gthread'. These are implemented using `pkg-config` which returns the include directories and libraries necessary to build against these packages.

If a need is unknown, then `lake` assumes that `pkg-config` knows about it. For instance, installing the computer vision library OpenCV updates the package database:

    $ pkg-config --cflags --libs opencv
    -I/usr/local/include/opencv  -L/usr/local/lib -lcxcore -lcv -lhighgui -lcvaux -lml

Needs can be specified by the `NEEDS` global variable. If I wanted to build a program with OpenCV, I can either say:

    $ lake NEEDS=opencv camera.c
    
or I can make all programs in a directory build with this need by creating a file `lakeconfig` with the single line:

    NEEDS = 'opencv'
    
and then `lake camera.c` will work properly.

## Release, Debug  and Cross-Compile Builds

If `program` has a field setting `odir=true` then it will put output files into a directory `release` or `debug` depending if this is was a release or debug build (`-g` or `DEBUG=true`.)

This is obviously useful when switching between build versions, and can be used to build multiple versions at once.  See `examples/releases' - the lakefile is

    -- maintaining separate release & debug builds
    PROG={'main',src='../hello',odir=true}
    release = c.program(PROG)
    set_flags {DEBUG=true}
    debug = c.program(PROG)
    default{release,debug}
    
Please note that global variables affecting the build should be changed using `set_flags()`

This feature naturally interacts with cross-compilation.  If the global `PREFIX` was set to `arm-linux` then the compiler becomes `arm-linux-gcc` etc.  The release directory would become `arm-linux-release`.

`odir` can explicitly be set to a directory name.  Due to tool limitations, `lake` cannot combine multiple files in a single compilation if `odir` is set.

## Shared Libraries

Unix shared libraries and Windows DLLs are similar, in the sense that both orcas and sharks are efficient underwater predators but are still very different animals.

Consider `lib1.c` in `examples/lib1`; the lakefile is simply:

    c.shared {'lib1'}

which results in the following compilation:

    gcc -c -O1 -MMD  lib1.c
    gcc lib1.o  -shared -o lib1.dll

(Naturally, the result will be `lib1.so` on Unix.)

By default, `GCC` exports symbols; using the MS tool `dumpbin` on Windows reveals that the function `answer` is exported. However, `CL` does not. You need to specify exports explicitly, either by using the `__declspec(dllexport)` decoration, or with a DEF file:

    $> cat lib1.def
    LIBRARY lib1.dll
    EXPORTS
            answer

    $> lake
    cl /nologo -c /O1 /showIncludes  lib1.c
    link /nologo lib1.obj /DEF:lib1.def  /DLL /OUT:lib1.dll
       Creating library lib1.lib and object lib1.exp

So on Windows, if there is a file with the same name as the DLL with extension .def, then it will be used in the link stage automatically.

(Most cross-platform code tends to conditionally define `EXPORT` as `__declspec(dllexport)` which is also understood by `GCC` on Windows.)

There is a C program `needs-lib.c` which links dynamically against `lib1.dll`. The lakefile that expresses this dependency is:

    lib = c.shared {'lib1'}
    c.program{'needs-lib1',lib}

Which results in:

    gcc -c -O1 -MMD  needs-lib1.c
    gcc -c -O1 -MMD  lib1.c
    gcc lib1.o lib1.def  -shared -o lib1.dll
    gcc needs-lib1.o lib1.dll  -o needs-lib1.exe

In this lakefile, the result of compiling the DLL (its _target_) is added as an explicit dependency to the C program target.  `GCC` can happily link against the DLL itself (the recommended practice) but `CL` needs to link against the 'import library'. Again, the job of `lake` is to know this kind of thing.

## Linking against the C Runtime

This is an example where different compilers behave in different ways, and is a story of awkward over-complication. On Unix, programs link dynamically against the C runtime (libc) unless explicitly asked not to, whereas `CL` links statically. To link a Unix program statically, add `static=true` to your program options; to link a Windows `CL` program dynamically, add `dynamic=true`.

It is tempting to force consistent operation, and always link dynamically, but this is not a wise consistency, because since 2005, `CL` will then link against `msvcr80.dll`, `msvcr90.dll` and so on which in effect you will have to redistribute with your application anyway, either as a private side-by-side assembly or via `VCDist`.

Here is the straight `CL` link versus the dynamic build for comparison:

    link /nologo test1.obj  /OUT:test1.exe

    link /nologo test1.obj msvcrt.lib /OUT:test1.exe && mt -nologo -manifest test1.e
    xe.manifest -outputresource:test1.exe;1

The first link gives a filesize of 48K, versus 6K for the second. But the dynamically linked executable has an embedded manifest which is only satisfied by the _particular_ version of the runtime for that version of `CL` (and it is picky about sub-versions as well.) - so you have to copy that exact DLL (msvcr80.dll, msvcr90.dll, depending) into the same directory as your executable, and redistribute it alongside.  So the size savings are only worth it for larger programs which ship with a fair number of DLLs. This is (for instance) the strategy adopted by Lua for Windows.

## Building Lua Extensions

`lake` has special support for building Lua C/C++ extensions. In `examples/lua` there is this lakefile:

    c.shared{'mylib',lua=true}

And the build is:

    gcc -c -O1 -MMD -Ic:/lua/include   mylib.c
    gcc mylib.o mylib.def  -Lc:/lua/lib  -llua5.1  -shared -o mylib.dll

`lake` will attempt to auto-detect your Lua installation, which can be a little hit-and-miss on Windows if you are not using Lua for Windows. It may be necessary to set `LUA_INCLUDE` and `LUA_LIBDIR` explicitly.

On Linux with a 'canonical' Lua install, things are simpler:

    gcc -c -O1 -MMD -fPIC mylib.c
    gcc mylib.o   -shared -o mylib.so

On Debian/Ubuntu, liblua5.1-dev puts the include files in its own directory:

    gcc -c -O1 -MMD -I/usr/include/lua5.1 -fPIC mylib.c
    gcc mylib.o   -shared -o mylib.so

With Lua for Windows, you have to be a little careful about the runtime dependency for non-trivial extensions. LfW uses the VC2005 compiler, so either get this, or use `GCC` with LIBS='-lmsvcr80'. (It is also possible to configure Mingw so that it links against `libmsvcr80.a` by default.)  The situation you are trying to avoid is having multiple run-tiime dependencies, since this will bite you because of imcompatible heap allocators.

The `lua=true` option also applies to programs embedding Lua. It is actually recommended to link such programs against the shared library across platforms, to ensure that the whole Lua API is available.

## Partitioning the Build

Consider the case where there are several distinct groups of source files, with different defines, include directories, etc. For instance, some files may be C, some C++, for instance the project in `examples/main`.  One perfectly good approach is to build a static libraries for distinct groups:

    lib = c.library{'lib'}
    cpp.program{'main',lib}

(It may seem silly to have a library containing exactly one object file, but you are asked to imagine that there are dozens or maybe even hundreds of files.)

This lakefile shows how this can also modelled with _groups_; 

    main = cpp.group{'main'}
    lib = c.group{'lib'}
    cpp.program{'main',inputs={main,lib}}

There is main.cpp and lib.c, and they are to compiled separately and linked together. 

`program` normally constructs a compile rule and populates it using the source, even if it is just inferred from the program name.  Any options that only make sense to the compile rule get passed on, like `incdir` or `defines`. But if `inputs` is specified directly, then `program` just does linking. `group`, on the other hand, never does any linking, and can only understand options for the compile stage.


## A More Realistic Example

Lua is not a difficult language to build from source, but there are a number of subtleties involved. For instance, it is built as a standalone executable with exported symbols on Unix, and as a stub program linked against a DLL on Windows. Here is the lakefile, section by section:

    LUA='lua'
    LUAC='luac print'

    as_dll = WINDOWS
    if as_dll then
      defs = 'LUA_BUILD_AS_DLL'
    end
    if not WINDOWS then
      defs = 'LUA_USE_LINUX'
    end

The first point (which should not come as too much of a suprise) is that this is actually a Lua program. All the power of the language is available in lakefiles. `lake` sets some standard globals like WINDOWS and PLAT.

    -- build the static library
    lib,ll=c.library{'lua',src='*',exclude={LUA,LUAC},defines=defs}

The Lua static library (`.a` or `.lib`) is built from all the C files in the directory, _except_ for the files corresponding to the programs `lua` and `luac`. Depending on our platform, we also have to set some preprocessor defines.

    -- build the shared library
    if as_dll then
      libl = c.shared{'lua',inputs=ll,dynamic=true}
    else
      libl = lib
    end

On Windows (or Unix _if_ we wanted) a DLL is built as well as a static library. This DLL shares the same _inputs_ as the static library - these are the second thing returned by the first `library` call.  The `dynamic` option forces the DLL to be dynamically linked against the runtime (this is not true by default for `CL`.)

    -- build the executables
    lua = c.program{'lua',libl,src=LUA,needs='dl math readline',export=not as_dll,dynamic=true}
    luac = c.program{'luac',lib,src=LUAC,needs='math'}

    default {lua,luac}

The `lua` program either links against the static or the dynamic library; if statically linked, then it has to export its symbols (otherwise Lua C extensions could not find the Lua API symbols). Again, always link against the runtime (`dynamic`).

This executable needs to load symbols from shared libraries ('dl'), to support interactive command-line editing ('readline') and needs the maths libraries ('math').  Expressing as needs simplifies things enormously, because `lake` knows that a program on Linux that needs 'readline' will also need to link against 'history' and 'ncurses', whereas on OS X it just needs to link against 'readline'.  On Windows, the equivalent functionality is part of the OS.

The `luac` program always links statically.

Finally, we create a target with name 'default' which depends on the both of these programs, so that typing 'lake' will build everything.

Expressing the Lua build as a lakefile makes the build _intents_ and _strategies_ clear, whereas it would take you a while to work these out from the makefile itself  It also is inherently more flexible; it works for both `CL` and `GCC`, a debug build just requires `-g` and it can be persuaded easily to give a `.so` library on Unix.

## Massaging Tool Output

Although in many ways an easier language to learn initially than C, C++ is sometimes its own worst enemy. The extensive use of templates in Boost and the standard library can make error messages painful to understand at first.

Consider the following silly C++ program (and remember that we start by writing silly programs):

    // errors.cpp
    #include <iostream>
    #include <string>
    #include <list>
    using namespace std;

    int main()
    {
      list<string> ls;
      ls.append("hello");
      cout << "that's all!" << endl;
      return 0;
    }

The original error message is:

    errors.cpp:9: error: 'class std::list<std::basic_string<char, std::char_traits<char>, std::allocator<char> >, 
    std::allocator<std::basic_string<char, std::char_traits<char>, std::allocator<char> > > >' has no member named 
    'append'

Seasoned C++ programmers learn to filter their error messages mentally. `lake` provides the ability to filter the output of a compiler, and reduce irrelevant noise. Here is the lakefile:

    if CC ~= 'g++' then quit 'this filter is g++ specific' end
    output_filter(cpp,function(line)
      return line:gsub('std::',''):
        gsub('basic_string%b<>','string'):
        gsub(',%s+allocator%b<>',''):
        gsub('class ',''):gsub('struct ','')
    end)
    
    cpp.program {'errors'}

And now the error is reduced to:

    errors.cpp:9: error: 'list<string >' has no member named 'append'

We have thrown away information, true, but it is implementation-specific stuff which is likely to confuse and irritate the newcomer.

Such an output filter can be added to `~/.lake/config` or brought explicitly in with `require 'cpp-error'` and becomes available to all of your C++ projects.

## Custom Rules

There are tasks other than program building which can benefit from dependency checking.  For instance, say I have a number of jpegs and Markdown files which I wish to convert into PNG and HTML respectively.  We construct a _rule_, which maps files of one extension onto files of another extension, using a command.  We populate the rule with _targets_, and then use the 'default' target to make sure that these targets are checked.

    to_png = rule('.jpg','.png',
      'convert $(INPUT) $(TARGET)' -- uses ImageMagick
    )

    to_html = rule('.md','.html',
      'lua /dev/lua/FAQ/markdown.lua $(INPUT)'
    )

    default {to_png '*', to_html '*'}

Calling rule objects generates targets, using a filename or a wildcard.

(This example isn't meant to be portable, just an efficient way to solve a specific problem.)

## Rule-based Programming

Martin Fowler has an [article](http://martinfowler.com/articles/rake.html) on using Rake for managing tasks with  dependencies.  Here is his first rakefile:

    task :codeGen do
      # do the code generation
    end

    task :compile => :codeGen do
      #do the compilation
    end

    task :dataLoad => :codeGen do
      # load the test data
    end

    task :test => [:compile, :dataLoad] do
      # run the tests
    end

This lakefile is equivalent:

    task = target

    task('codeGen',nil,function()
      print 'codeGen'
    end)

    task('compile','codeGen',function()
      print 'compile'
    end)

    task('dataLoad','codeGen',function()
      print 'dataLoad'
    end)

    task('test','compile dataLoad',function()
      print 'test'
    end)

Try various commands like 'lake compile' and 'lake test' to see how the actions are called.

You may find Lua's anonymous function syntax a little noisy. But there's nearly always another way to do things in Lua. This style is probably more natural for Lua programmers:

    -- fun.lua
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

An entertaining aspect to this style of programming is that the order of the dependencies firing is fairly arbitrary (except that the sub-dependencies must fire first) so that they could be done in parallel.

## Lake as a Lua Library

I have a feeling that there is a small, compact dependencies library buried inside `lake.lua` in the same way that there is a thin athletic person inside every fat couch potato.  To do its job without external dependencies, `lake` defines a lot of useful functionality which can be used for other purposes. Also, these facilities are very useful within more elaborate lakefiles.

In the same directory as `lake.lua`, we can load it as a module:

    $ lua -llake
    Lua 5.1.4  Copyright (C) 1994-2008 Lua.org, PUC-Rio
    > t = expand_args('*','.c',true)
    > = #t
    112
    > for i = 1,10 do print(t[i]) end
    examples/hello.c
    examples/test1/src/test1.c
    examples/first/one.c
    examples/first/two.c
    examples/lib1/needs-lib1.c
    examples/lib1/lib1.c
    examples/lua/mylib.c
    examples/big1/c087.c
    examples/big1/c014.c
    examples/big1/c007.c

`expand_args` is a file grabber which recursively looks into directories, if the third parameter is `true`.

    > for s in list {'one','two','three'} do print(s) end
    one
    two
    three

`list` can also be passed a space-or-comma separated string.  There are other useful functions for working with lists and tables:

    > ls = {1,2}
    > append_list(ls,{3,4})
    > forall(ls,print)
    1
    2
    3
    4
    > = index_list({10,20,30},20)
    2
    > ls = {ONE=1}
    > append_table(ls,{TWO=2,THREE=3})
    > for k,v in pairs(ls) do print(k,v) end
    THREE   3
    TWO     2
    ONE     1

There are cross-platform functions for doing common things with paths and files

    > = tmpname()
    /tmp/lua_KZSFkZ
    > f = tmpcpy 'hello dolly\n'
    > = f
    /tmp/lua_07J5r8
    > readfile(f)
    hello dolly

These work as expected on the other side of the fence (please note that `os.tmpname()` is _not_ safe on Windows since it doesn't prepend the temp directory!).  

    > = expanduser '~/.lake'
    C:\Documents and Settings\SJDonova/.lake
    > = tmpname()
    C:\DOCUME~1\SJDonova\LOCALS~1\Temp\s3uk.
    > = which 'ls'
    d:\utils\bin\ls.exe
    ....
    > = expanduser '~/.lake'
    /home/steve/.lake
    > = join('bonzo','dog','.txt')
    bonzo/dog.txt
    > = basename 'billy.boy'
    billy.boy
    > = extension_of 'billy.boy'
    .boy
    > =  basename '/tmp/billy.boy'
    billy.boy
    > = replace_extension('billy.boy','.girl')
    billy.girl
    > for d in dirs '.' do print(d) end
    ./doc
    ./examples
    
There is a subsitution function which replaces any global variables, unless they are in an exclusion list:

    > FRED = 'ok'
    > = subst('$(FRED) $(DEBUG)')
    ok
    > return  subst('$(FRED) $(DEBUG)',{DEBUG=true})
    ok $(DEBUG)

## Future Directions

`PrimeMover` can operate as a completely self-contained package, with embedded Lua interpreter. This would be a useful thing to emulate.

There is a need for a compact dependency-driven programming framework in Lua; see for instance this [stackoverflow](http://stackoverflow.com/questions/882764/embedding-rake-in-a-c-app-or-is-there-a-lake-for-lua) question.  A refactoring of `lake` would make it easier to include only this functionality as a library.  The general cross-platform utilities could be extracted and perhaps contribute to a [proposed project](http://github.com/lua-shellscript/lua-shellscript)
 for a general scripting support library.

I've done some experiments in using `rake` to build complex Java projects, which I will include as due course as optional modules (any rakefile can use `require` to load extra functionality.)

Dependency-driven programming goes beyond operations on files. A more general framework would work with any set of objects which supported a property which behaved like a timestamp.  

This style is also a good fit for parallel operations, since the exact order of dependency rule firing is not important. Integrating [Lua Lanes](http://kotisivu.dnainternet.net/askok/bin/lanes/index.html) would allow `lake` to efficiently use multiple cores, not only like `make -j` but any time-consuming tasks that need to be scheduled.


