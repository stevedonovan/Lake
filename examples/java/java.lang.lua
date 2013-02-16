local jbin = ENV.JDK or quit 'please set JDK envrionment variable'
JDK = ENV.JDK
jbin = path.join(jbin,'bin')
ENV.PATH = ENV.PATH .. ENV.SEP .. jbin

java = {ext='.java', obj_ext = '.class'}
java.output_in_same_dir = true
java.EXE_EXT = '.jar'
java.DLL_EXT = '.jar'
java.LINK_DLL = ''
java.output_in_same_dir = true
java.compile = 'javac $(CFLAGS) $(INPUT)'
java.compile_combine = java.compile
java.please_combine = true -- not just a hint!
java.link = 'jar -cfm $(TARGET) $(LIBS) $(DEPENDS)'

lake.add_group(java)
lake.add_prog(java)
lake.add_shared(java)

function java:flags_handler(args,compile)
    if compile then
        local flags=''
        if args.classpath then
            libs = lake.deps_arg(args.classpath)
            if libs[1] ~= '.' then table.insert(libs,1,'.') end
            flags = '-classpath "'..table.concat(libs,';')..'"'
        end
        if args.version_source then
            flags = flags..' -source '..args.version_source
        end
        if args.version_target then
            flags = flags..' -target '..args.version_target
        end
        return flags
    else
        local klass = args.entry or 'Main'
        if args.package then
            klass = args.package..'.'..klass
        end
        local tmp = file.temp()
        file.write(tmp,'Main-Class: '..klass..'\n')
        return tmp
    end
end

function java:args_handler(args)
    if args.package then
        args.src = args.package:gsub('%.','/')..'/*'
    end
    if args.cdir and not args.classpath then
        args.classpath = args.cdir
    end
    if not args.src then
        args.entry = args.name
    end
end

lake.add_program_option 'classpath version_source version_target package entry'

function java.javah (name,classpath,entry)
    return target(name,classpath,function(t)
        if not path.exists(t.target) then
            utils.shell('javah -o %s -classpath "%s" %s',t.target,t.deps[1],entry)
        end
    end)
end

lake.define_need('java',function()
    JPLAT = WINDOWS and 'win32' or 'linux'
    return {
        incdir = '$(JDK)/include, $(JDK)/include/$(JPLAT)'
    }
end)

java.runner = function(prog,args)
    local flags = ''
    if path.extension_of(prog) == '.jar' then
        flags = '-jar '
    end
    exec('java '..flags..prog..' '..args)
end


