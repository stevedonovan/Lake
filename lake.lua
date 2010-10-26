-- Lake - a make-like build framework in Lua
-- Freely distributable for any purpose, as long as copyright notice is retained.
-- (And remember my dog did not eat your homework)
-- Steve Donovan, 2007-2010

local usage = [[
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
]]

require 'lfs'
local append = table.insert
local verbose = false
local specific_targets = {}
local nbuild = 0
local all_targets_list = {}
local attributes = lfs.attributes
local env = os.getenv
local concat = table.concat

local TMPSPEC = '_t_.spec'
local specfile
local outspec
local lakefile

TESTING = false

DIRSEP = package.config:sub(1,1)
WINDOWS = DIRSEP == '\\'

---some useful library functions for manipulating file paths, lists, etc.
-- search for '--end_of_libs' to skip to the Meat of the Matter!

function warning(reason,...)
    local str = reason:format(...)
    io.stderr:write('lake: ',str,'\n')
end

function quit(reason,...)
    warning(reason,...)
    finalize()
    os.exit(1)
end

function choose(cond,v1,v2)
    if type(cond) == 'string' then
        cond = cond~='0' and cond~='false'
    end
    if cond then return v1 else return v2 end
end

function pick(a,b)
    if a ~= nil then return a else return b end
end

function copyfile(src,dest)
    local inf,err = io.open(src,'r')
    if err then quit(err) end
    local outf,err = io.open(dest,'w')
    if err then quit(err) end
    outf:write(inf:read('*a'))
    outf:close()
    inf:close()
end

function writefile (name,text)
    local outf,err = io.open(name,'w')
    if not outf then quit('%s',err) end
    outf:write(text);
    outf:close()
    return true
end

function readfile (name)
    local inf,err = io.open(name,'r')
    if not inf then return false,err end
    local res = inf:read('*a')
    inf:close()
    return res
end


local function at(s,i)
    return s:sub(i,i)
end

function filetime(fname)
    local time,err = attributes(fname,'modification')
    if time then
        return time
    else
        return -1
    end
end

function exists(path,fname)
    if fname then fname = join(path,fname) else fname = path end
    if attributes(fname) ~= nil then
        return fname
    end
end

-- is @path a directory?
function isdir(path)
    return attributes(path,'mode') == 'directory'
end

-- is @path a file?
function isfile(path)
    return attributes(path,'mode') == 'file'
end

-- is this an absolute @path?
function isabs(path)
    if WINDOWS then return path:find '^"*%a:' ~= nil
    else return path:find '^/' ~= nil
    end
end

function quote_if_necessary (file)
    if file:find '%s' then
        file = '"'..file..'"'
    end
    return file
end

-- this is used for building up strings when the initial value might be nil
--  s = concat_str(s,"hello")
local function concat_str (v,u,no_quote)
    if not no_quote then u = quote_if_necessary(u) end
    return (v or '')..' '..u
end

function joins (path,file)
    return path..'/'..file
end

function get_files (files,path,pat,recurse)
    for f in lfs.dir(path) do
        if f ~= '.' and f ~= '..' then
            local file = f
            if path ~= '.' then file  = join(path,file) end  --wuz joins?
            if recurse and isdir(file) then
                get_files(files,file,pat,recurse)
            elseif f:find(pat) then
                append(files,file)
            end
        end
    end
end

function get_directories (dir)
    local res = {}
    for f in lfs.dir(dir) do
        if f ~= '.' and f ~= '..' then
            local path = join(dir,f) --wuz joins?
            if isdir(path) then append(res,path) end
        end
    end
    return res
end

function files_from_mask (mask,recurse)
    local path,pat = splitpath(mask)
    if not pat:find('%*') then return nil end
    local files = {}
    if path=='' then path = '.' end
    -- turn shell-style wildcard into Lua regexp
    pat = pat:gsub('%.','%%.'):gsub('%*','.*')..'$'
    get_files(files,path,pat,recurse)
    return files
end

function mask(mask)
    return list(files_from_mask(mask))
end

function dirs(dir)
    return list(get_directories(dir))
end

function split(s,re)
    local i1 = 1
    local ls = {}
    while true do
        local i2,i3 = s:find(re,i1)
        if not i2 then
            append(ls,s:sub(i1))
            return ls
        end
        append(ls,s:sub(i1,i2-1))
        i1 = i3+1
    end
end

function split2(s,delim)
  return s:match('([^'..delim..']+)'..delim..'(.*)')
end

-- given a path @path, return the directory part and a file part.
-- if there's no directory part, the first value will be empty
function splitpath(path)
    local i = #path
    local ch = at(path,i)
    while i > 0 and ch ~= '/' and ch ~= '\\' do
        i = i - 1
        ch = at(path,i)
    end
    if i == 0 then
        return '',path
    else
        return path:sub(1,i-1), path:sub(i+1)
    end
end

-- given a path @path, return the root part and the extension part
-- if there's no extension part, the second value will be empty
function splitext(path)
    local i = #path
    local ch = at(path,i)
    while i > 0 and ch ~= '.' do
        if ch == '/' or ch == '\\' then
            return path,''
        end
        i = i - 1
        ch = at(path,i)
    end
    if i == 0 then
        return path,''
    else
        return path:sub(1,i-1),path:sub(i)
    end
end

-- return the directory part of @path
function dirname(path)
    local p1,p2 = splitpath(path)
    return p1
end

-- return the file part of @path
function basename(path)
    local p1,p2 = splitpath(path)
    return p2
end

function extension_of(path)
    local p1,p2 = splitext(path)
    return p2
end

function expanduser(path)
    if path:sub(1,1) == '~' then
        local home = env 'HOME'
        if not home then -- has to be Windows
            home = env 'USERPROFILE' or (env 'HOMEDRIVE' .. env 'HOMEPATH')
        end
        return home..path:sub(2)
    else
        return path
    end
end


function replace_extension (path,ext)
    local p1,p2 = splitext(path)
    return p1..ext
end

-- return the path resulting from combining @p1,@p2 and optionally @p3 (an extension);
-- if @p2 is already an absolute path, then it returns @p2
function join(p1,p2,p3)
	if p3 then p2 = p2 .. p3 end -- extension part
    if isabs(p2) then return p2 end
    local endc = at(p1,#p1)
    if endc ~= '/' and endc ~= '\\' then
        p1 = p1..DIRSEP
    end
    return p1..p2
end

-- this expands any $(VAR) occurances in @s (where VAR is a global varialable).
-- If VAR is not present, then the expansion is just the empty string, unless
-- it is on the @exclude list, where it remains unchanged, ready for further
-- expansion at a later stage.
function subst(str,exclude,T)
    local count
	T = T or _G
    repeat
        local excluded = 0
        str, count = str:gsub('%$%(([%w,_]+)%)',function (f)
            if exclude and exclude[f] then
                excluded = excluded + 1
                return '$('..f..')'
            else
                local s = T[f]
                if not s then return ''
                else return s end
            end
        end)
        --count = count - excluded
        --print(count,str)
    until count == 0 or exclude
    return str
end

function substitute (str,T) return subst(str,nil,T) end

-- this executes a shell command @cmd, which may contain % string.format specifiers,
-- in which case any extra arguments are used. It may contain ${VAR} which will
-- be substituted
function shell_nl(cmd,...)
    cmd = subst(cmd):format(...)
    local inf = io.popen(cmd..' 2>&1','r')
    if not inf then return '' end
    local res = inf:read('*a')
    inf:close()
    return res
end

-- a convenient function which gets rid of the trailing line-feed from shell()
function shell(cmd,...)
    return (shell_nl(cmd,...):gsub('\n$',''))
end

-- splits a list separated by ' ' or ','. Note that some hackery is needed
-- to preserve double quoted items.

local marker = string.char(4)
local function hide_spaces(q) return q:gsub(' ',marker) end

function split_list(s)
    s = s:gsub('^%s+',''):gsub('%s+$','') -- trim the string
    s = s:gsub('"[^"]+"',hide_spaces)
    local i1 = 1
    local ls = {}
    local function append_item (item)
        item = item:gsub('\\ ',' ')
        append(ls,item)
    end
    while true do
        local i2,i3 = s:find('[^\\][%s,]+',i1)
        if not i2 then
            append_item(s:sub(i1))
            break
        end
        append_item(s:sub(i1,i2))
        i1 = i3+1
    end
    for i = 1,#ls do
        if ls[i]:find(marker) then
            ls[i] = ls[i]:gsub(marker,' ') --:gsub('"','')
        end
    end
    return ls
end

function forall(ls,action)
    for i,v in ipairs(ls) do
        action(v)
    end
end

-- useful global function which deletes a list of files @items
function remove(items)
    if type(items) == 'string' then
        items = split_list(items)
    end
    forall(items,function(f)
        if os.remove(f) then
            print ('removing',f)
        end
    end)
end

function remove_files (mask)
    local cmd
    if WINDOWS then
        cmd = 'del '..mask
    else
        cmd = 'rm '..mask
    end
    exec(cmd)
end

function is_simple_list (t)
    return type(t) == 'table' and t[1]
end

function append_list(l1,l2)
    for i,v in ipairs(l2) do
        append(l1,v)
    end
    return l1
end

function copy_list (l1)
    return append_list({},l1)
end

function copy_table (t)
    local res = {}
    for k,v in pairs(t) do
        res[k] = v
    end
    return res
end

function append_table(l1,l2)
    if not l2 then return end
    for k,v in pairs(l2) do
        l1[k] = v
    end
    return l1
end


function erase_list(l1,l2)
    for i,v in ipairs(l2) do
        local idx = index_list(l1,v)
        if idx then
            table.remove(l1,idx)
        end
    end
end

function concat_list(pre,ls,sep)
    local res = ''
    for i,v in ipairs(ls) do
        if v ~= '' then
            res = res..pre..v..sep
        end
    end
    return res
end

function index_list(ls,val)
    for i,v in ipairs(ls) do
        if v == val then return i end
    end
end

function find_list(ls,field,value)
    for i,v in ipairs(ls) do
        if v[field] == value then
            return v
        end
    end
end

-- used to iterate over a list, which may be given as a string:
--  for val in list(ls) do ... end
--  for val in list 'one two three' do .. end
function list(ls)
    if type(ls) == 'string' then
        ls = split_list(ls)
    end
    local n = #ls
    local i = 0
    return function()
        i = i + 1
        if i > n then return nil end
        return ls[i]
    end
end

function append_unique(ls,val)
    if not index_list(ls,val) then
        return append(ls,val)
    end
end

function column_list(ls,f)
    local res = {}
    for i,t in ipairs(ls) do
        append(res,t[f])
    end
    return res
end

function parm_list_concat(ls,istart)
    local s = ' '
    istart = istart or 1
    for i = istart,#ls do
        local a = ls[i]
        if a:find(' ') then a = '"'..a..'"' end
        s = s..a..' '
    end
    return s
end

-- readlines(f) works like f:lines(), except it will handle lines separated by '\'
function readlines(f)
    return function()
        local line = ''
        repeat
            local l = f:read()
            if not l then return nil end
            local last = l:sub(-1,-1)
            if last == '\\' then
                l = l:sub(1,-2)
            end
            line = line..l
        until last ~= '\\'
        return line
    end
end

-- for debug purposes: dump out a table
function dump(ls,msg)
    print ('<<<',msg)
    if type(ls) == 'table' then
        for i,v in pairs(ls) do
            print(i,v)
        end
    else
        print(ls)
    end
    print '>>'
end

function tmpname ()
    local res = os.tmpname()
    if WINDOWS then -- note this necessary workaround for Windows
        res = env 'TMP'..res
    end
    return res
end

function tmpcpy (s)
    local res = tmpname()
    local ok,err = writefile(res,s)
    if not ok then return nil,err end
    return res
end


function which (prog)
    if isabs(prog) then return prog end
    if WINDOWS  then -- no 'which' commmand, so do it directly
        if extension_of(prog) == '' then prog = prog..'.exe' end
        local path = split(env 'PATH',';')
        for dir in list(path) do
            local file = exists(dir,prog)
            if file then return file end
        end
        return false
    else
        return shell('which %s 2> /dev/null',prog)
    end
end

--end_of_libs---------------------------------------------

local interpreters = {
    ['.lua'] = 'lua', ['.py'] = 'python',
}

local check_options

if WINDOWS then
    LOCAL_EXEC = ''
    EXE_EXT = '.exe'
    DLL_EXT = '.dll'
else
    LOCAL_EXEC = './'
    EXE_EXT = ''
    DLL_EXT = '.so'
end


LIBS = ''
CFLAGS = ''


local function inherits_from (c)
	local mt = {__index = c}
	return function(t)
		return setmetatable(t,mt)
	end
end

local function appender ()
	return setmetatable({},{
		__call = function(t,a)
			check_options(a)
			append_table(t,a)
		end
	})
end


c = {ext='.c'}
local CI = inherits_from(c)
c.defaults = appender()

-- these chaps inherit from C lang for many of their fields
cpp = CI{ext='.cpp'}
f = CI{ext='.f'}
c99 = CI{ext='.c'}

cpp.defaults = appender()
f.defaults = appender()
c99.defaults = appender()

wresource = {ext='.rc'}


local extensions = {
    ['.c'] = c, ['.cpp'] = cpp, ['.cxx'] = cpp, ['.C'] = cpp,
    ['.f'] = f, ['.for'] = f, ['.f90'] = f,
}

function register(lang,extra)
    extensions[lang.ext] = lang
    if extra then
        for e in list(deps_arg(extra)) do
            extensions[e] = lang
        end
    end
end

-- @doc any <var>=<value> pair means set the global variable <var> to the <value>, as a string.
function process_var_pair(a)
    local var,val = split2(a,'=')
    if var then
        _G[var] = val
        return true
    end
end

-- @doc dependencies are stored as lists, but if you go through deps_arg, then any string
-- delimited with ' ' or ',' will be converted into an appropriate list.
function deps_arg(deps,base)
    if type(deps) == 'string' then
        deps = split_list(deps)
    end
	if base then
		for i = 1,#deps do
			deps[i] = join(base,deps[i])
		end
	end
    return deps
end

-- expand_args() goes one step further than deps_args(); it will expand a wildcard expression into a list of files
-- as well as handling lists as strings. If the argument is a table, it will attempt
-- to expand each string - e.g. {'a','b c'} => {'a','b','c'}
function expand_args(src,ext,recurse,base)
    if type(src) == 'table' then
        local res = {}
        for s in list(src) do
            for l in list(split_list(s)) do
				if base then l = join(base,l) end
                append_list(res,expand_args(l,ext,recurse))
            end
        end
        return res
    end
	local items = split_list(src)
	if #items > 1 then return expand_args(items,ext,recurse,base) end
	src = items[1]
    -- @doc 'src' if it is a directory, then regard that as an implicit wildcard
	if base then src = join(base,src) end
    if ext and isdir(src) and not isfile(src..ext) then
        src = src..'/*'
    end
    if src:find('%*') then
		if src:find '%*$' then src = src..ext end
		return files_from_mask(src,recurse)
    else
        local res = deps_arg(src) --,base)
        if ext then
            -- add the extension to the list of files
            for i = 1,#res do res[i] = res[i]..ext end
        end
        return res
    end
end

function foreach(ls,action)
    ls = expand_args(ls)
    return function()
        forall(ls,action)
    end
end

local tmt,tcnt = {},1

function istarget (t)
    return type(t) == 'table' and getmetatable(t) == tmt
end

local function new_target(tname,deps,cmd,upfront)
    local t = setmetatable({},tmt)
	if tname == '*' then
		tname = '*'..tcnt
		tcnt = tcnt + 1
	end
    t.target = tname
    t.deps = deps_arg(deps)
    t.cmd = cmd
    if upfront then
        table.insert(all_targets_list,1,t)
    else
        append(all_targets_list,t)
    end
    if type(cmd) == 'string' then
        if specfile then
            -- @doc [checking against specfile]  for each target, we check the command generated
            -- against the stored command, and delete the target if the command is different.
            local oldcmd = specfile:read()
            if oldcmd ~= cmd then
                if verbose then
                    print(oldcmd); print(cmd)
                    print('removing '..tname)
                end
                os.remove(tname)
            end
        end
        if outspec then outspec:write(cmd,'\n') end
    end
    return t
end

function phony(deps,cmd)
	return new_target('*',deps,cmd,true)
end

target = new_target -- global alias

--- @doc [Rule Objects] ----
-- serve two functions (1) define a conversion operation between file types (such as .c -> .o)
-- and (2) manage a list of dependent files.

local rt = {} -- metatable for rule objects
rt.__index = rt

-- create a rule object, mapping input files with extension @in_ext to
-- output files with extension @out_ext, using an action @cmd
function rule(in_ext,out_ext,cmd)
    local r = {}
    r.in_ext = in_ext
    r.out_ext = out_ext
    r.cmd = cmd
    r.targets = {}
    r.depends_on = rt.depends_on
    setmetatable(r,rt)
    return r
end

-- this is used by the CL output parser: e.g, cl will put out 'hello.c' and this
-- code will return 'release\hello.d' and '..\hello.c'
function rt.deps_filename (r,name)
    local t = find_list(r.targets,'base',splitext(name))
    return replace_extension(t.target,'.d'), t.input
end

-- add a new target to a rule object, with name @tname and optional dependencies @deps.
-- @tname may have an extension, but this will be ignored.
-- if there are no explicit dependencies, we assume that we are dependent on the input file.
-- Also, any global dependencies that have been set for this rule with depends_on().
-- In addition, we look for .d dependency files that have been auto-generated by the compiler.
function rt.add_target(r,tname,deps)
    tname = splitext(tname)
    local input = tname..r.in_ext
    local base = basename(tname)
    local target_name = base..r.out_ext
    if r.output_dir then
        target_name = join(r.output_dir,target_name)
    end
    if not deps and r.uses_dfile then
        deps = deps_from_d_file(replace_extension(target_name,'.d'))
    end
    if not deps then
        deps = {input}
    end
    if r.global_deps then
        append_list(deps,r.global_deps)
    end
    local t = new_target(target_name,deps,r.cmd)
    t.name = tname
    t.input = input
    t.rule = r
    t.base = base
    t.cflags = r.cflags
    append(r.targets,t)
    return t
end

-- @doc the rule object's call operation is overloaded, equivalent to add_target() with
-- the same arguments @tname and @deps.
-- @tname may be a shell wildcard, however.
function rt.__call(r,tname,deps)
    if tname:find('%*') then
        if extension_of(tname) == '' then
            tname = tname..r.in_ext
        end
        for f in mask(tname) do
            r:add_target(f)
        end
    else
        r:add_target(tname,deps)
    end
    return r
end

local function extract_rule(deps)
    local ldeps =  column_list(deps.targets,'target')
    if #ldeps == 0 and deps.parent then
        -- @doc no actual files were added to this rule object.
        -- But the rule has a parent, and we can deduce the single file to add to this rule
        -- (This is how a one-liner like c.program 'prog' works)
        local base = splitext(deps.parent.target)
        local t = deps:add_target(base)
        return {t.target}
    else
        return ldeps
    end
end

local function isrule(r)
    return r.targets ~= nil
end

function rt.depends_on(r,s)
    s = deps_arg(s)
    if not r.global_deps then
        r.global_deps = s
    else
        append_list(r.global_deps,s)
    end
end

local function parse_deps_line (line)
    line = line:gsub('\n$','')
    -- each line consists of a target, and a list of dependencies; the first item is the source file.
    local target,deps = line:match('([^:]+):%s*(.+)')
    if target and deps then
        return target,split_list(deps)
    end
end

function deps_from_d_file(file)
    local line,err = readfile(file)
    if not line or #line == 0 then return false,err end
    local _,deps = parse_deps_line(line:gsub(' \\',' '))
    -- @doc any absolute paths are regarded as system headers; don't include.
    local res = {}
    for d in list(deps) do
        if not isabs(d) then
            append(res,d)
        end
    end
    return res
end

function rules_from_deps(file,extract_include_paths)
    extract_include_paths = not extract_include_paths -- default is true!
    local f,err = io.open(file,'r')
    if not f then quit(err) end
    local rules = {}
    for line in readlines(f) do  -- will respect '\'
        if not line:find('^#') then -- ignore Make-style comments
            local target,deps = parse_deps_line(line)
            if target and deps then
                -- make a rule to translate the source file into an object file,
                -- and set the include paths specially, unless told not to...
                local paths
                if extract_include_paths then
                    paths = {}
                    for i = 2,#deps do
                        local path = splitpath(deps[i])
                        if path ~= '' then
                            append_unique(paths,path)
                        end
                    end
                end
                append(rules,compile{deps[1],incdir=paths,nodeps=true})
            end
        end
    end
    f:close()
    return depends(unpack(rules))
end

function is_target_list (t)
    return type(t) == 'table' and t.target_list
end

function depends(...)
    local pr = {}
    local ls = {}
    local args = {...}
    if #args == 1 and is_simple_list(args[1]) then
        args = args[1]
    end
    for t in list(args) do
        if is_target_list(t) then
            append_list(ls,t.target_list)
        else
            append(ls,t)
        end
    end
    pr.target_list = ls
    return pr
end

function all_targets()
    local res = {}
    for t in list(all_targets_list) do
        append(res,t.target)
    end
    return res
end

-- given a filename @fname, find out the corresponding target object.
function target_from_file(fname,target)
    return find_list(all_targets_list,target or 'target',fname)
end

-- these won't be initially subsituted
local basic_variables = {INPUT=true,TARGET=true,DEPENDS=true,JARFILE=true,LIBS=true,CFLAGS=true}

function exec(s,dont_fail)
    local cmd = subst(s)
    print(cmd)
    if not TESTING then
        local res = os.execute(cmd)
        if res ~= 0 then
            if not dont_fail then quit ("failed with code %d",res) end
            return res
        end
    end
end

function subst_all_but_basic(s)
    return subst(s,basic_variables)
end

local current_rule,first_target,combined_targets = nil,nil,{}

function fire(t)
    if not t.fake then
        -- @doc compilers often support the compiling of multiple files at once, which
        -- can be a lot faster. The trick here is to combine the targets of such tools
        -- and make up a fake target which does the multiple compile.
        if t.rule and t.rule.can_combine then
            -- collect a list of all the targets belonging to this particular rule
            if not current_rule then
                current_rule = t.rule
                first_target = t
            end
            if current_rule == t.rule then
                append(combined_targets,t.input)
                -- this is key: although we defer compilation, we have to immediately
                -- flag the target as modified
                lfs.touch(t.target)
                return
            end
        end
        -- a target with new rule was encountered, and we have to actually compile the
        -- combined targets using a fake target.
        if #combined_targets > 0 then
            local fake_target = copy_table(first_target)
            fake_target.fake = true
            fake_target.input = concat(combined_targets,' ')
            fire(fake_target)
            current_rule,first_target,combined_targets = nil,nil,{}
            -- can now pass through and fire the target we were originally passed
        end
    end
    local ttype = type(t.cmd)
    --- @doc basic variables available to actions:
    -- they are kept in the basic_variables table above, since then we can use
    -- subst_all_but_basic() to replace every _other_ variable in command strings.
    INPUT = t.input
    TARGET = t.target
    JARFILE = t.jarfile
    if t.deps then
        local deps = t.deps
        if t.link and t.link.massage_link then
            deps = t.link.massage_link(t.name,deps,t)
        end
        DEPENDS = concat(deps,' ')
    end
    LIBS = t.libs
    CFLAGS = t.cflags
    if t.dir then change_dir(t.dir) end
    if ttype == 'string' and t.cmd ~= '' then -- it's a non-empty shell command
        if t.rule and t.rule.filter and not TESTING then
            local cmd = subst(t.cmd)
            print(cmd)
            local filter = t.rule.filter
            local tmpfile = tmpname()
            local redirect,outf
            if t.rule.stdout then
                redirect = '>'; outf = io.stdout
            else
                redirect = '2>'; outf = io.stderr
            end
            local code = os.execute(cmd..' '..redirect..' '..tmpfile)
            filter({TARGET,INPUT,t.rule},'start')
            local inf = io.open(tmpfile,'r')
            for line in inf:lines() do
                line = filter(line)
                if line then outf:write(line,'\n') end
            end
            inf:close()
            os.remove(tmpfile)
            filter(t.base,'end')
            if code ~= 0 then quit ("failed with code %d",code) end
        else
            exec(t.cmd)
        end
    elseif ttype == 'function' then -- a Lua function
        (t.cmd)(t)
    else -- nothing happened, but we are satisfied (empty command target)
        nbuild = nbuild - 1
    end
    if t.dir then change_dir '!' end
    nbuild = nbuild + 1
end

function check(time,t)
    if not t then return end
    if not t.deps then
        -- unconditional action
        fire(t)
        return
    end

    if verbose then print('target: '..t.target) end

    if t.deps then
        -- the basic out-of-date check compares last-written file times.
        local deps_changed = false
        for dfile in list(t.deps) do
            local tm = filetime(dfile)
            check (tm,target_from_file(dfile))
            tm = filetime(dfile)
            if verbose then print(t.target,dfile,time,tm) end
            deps_changed = deps_changed or tm > time or tm == -1
        end
        -- something's changed, so do something!
        if deps_changed then
            fire(t)
        end
    end
end

local function get_deps (deps)
    if isrule(deps) then
        -- this is a rule object which has a list of targets
        return extract_rule(deps)
    elseif istarget(deps) then
        return deps.target
    else
        return deps
    end
end

local function deps_list (target_list)
    deps = {}
    for target in list(target_list) do
        target = get_deps(target)
        if type(target) == 'string' then
            append(deps,target)
        else
            append_list(deps,target)
        end
    end
    return deps
end

function get_dependencies (deps)
    deps = get_deps(deps)
    if deps.target_list then
        -- this is a list of dependencies
        deps = deps_list(deps.target_list)
    elseif is_simple_list(deps) then
        deps = deps_list(deps)
    end
    return deps
end

-- often the actual dependencies are not known until we come to evaluate them.
-- this function goes over all the explicit targets and checks their dependencies.
-- Dependencies may be simple file names, or rule objects, which are here expanded
-- into a set of file names.  Also, name references to files are resolved here.
function expand_dependencies(t)
    if not t or not t.deps then return end
    local deps = get_dependencies(t.deps)
    -- we already have a list of explicit dependencies.
    -- @doc Lake allows dependency matching against target _names_ as opposed
    -- to target _files_, for instance 'lua51' vs 'lua51.dll' or 'lua51.so'.
    -- If we can't match a target by filename, we try to match by name
    -- and update the dependency accordingly.
    for i = 1,#deps do
        local name = deps[i]
        if type(name) ~= 'string' then
            name = get_dependencies(name)
            deps[i] = name
            if type(name) ~= 'string' then dump(name,'NOT FILE'); quit("not a file name") end
        end
        local target = target_from_file(name)
        if not target then
            target = target_from_file(name,'name')
            if target then
                deps[i] = target.target
            elseif not exists(name) then
                quit("cannot find dependency '%s'",name)
            end
        end
    end
    if verbose then dump(deps,t.name) end

    -- by this point, t.deps has become a simple array of files
    t.deps = deps


    for dfile in list(t.deps) do
        expand_dependencies (target_from_file(dfile))
    end
end

local synth_target,synth_args_index


function update_pwd ()
    PWD = lfs.currentdir():lower()..DIRSEP
end

local function safe_dofile (name)
    local stat,err = pcall(dofile,name)
    if not stat then
        quit(err)
    end
end

local lakefile

function process_args()
    -- arg is not set in interactive lua!
    if arg == nil then return end
    -- this var is set by Lua for Windows
    LUA_DEV = env 'LUA_DEV'
    -- @doc [config] try load lakeconfig in the current directory
    if exists 'lakeconfig' then
        safe_dofile 'lakeconfig'
    end
    -- @doc [config] also try load ~/.lake/config
    local lconfig = exists(expanduser('~/.lake/config'))
    if lconfig then safe_dofile(lconfig) end
    if not PLAT then
        if not WINDOWS then
            PLAT = shell('uname -s')
        else
            PLAT='Windows'
        end
    end
    update_pwd()

    -- @doc [config] the environment variable LAKE_PARMS can be used to supply default global values,
    -- in the same <var>=<value> form as on the command-line; pairs are separated by semicolons.
    local parms = env 'LAKE_PARMS'
    if parms then
        for pair in list(split(parms,';')) do
            process_var_pair(pair)
        end
    end
    local no_synth_target
    local use_lakefile = true
    local i = 1
    while i <= #arg do
        local a = arg[i]
        local function getarg() local res = arg[i+1]; i = i + 1; return res end
        if process_var_pair(a) then
            -- @doc <name>=<val> pairs on command line for setting globals
        elseif a:sub(1,1) == '-' then
            local opt = a:sub(2)
            if opt == 'v' then
                verbose = true
            elseif opt == 'h' or opt == '-help' then
                print(usage)
                os.exit(0)
            elseif opt == 't' then
                TESTING = true
            elseif opt == 'n' then
                no_synth_target = true
            elseif opt == 'f' then
                lakefile = getarg()
            elseif opt == 'e' then
                lakefile = tmpcpy(getarg())
            elseif opt == 's' then
                STRICT = true
            elseif opt == 'g' then
                DEBUG = true
            elseif opt == 'd' then
                change_dir(getarg())
            elseif opt == 'p' then
                lakefile = tmpcpy(("tp,name = deduce_tool('%s'); tp.program(name)"):format(arg[i+1]))
                i = i + 1
            elseif opt == 'lua' or opt == 'l' then
                local name,lua = getarg(),'false'
                if opt=='lua' then lua = 'true' end
                lakefile,err = tmpcpy(("tp,name = deduce_tool('%s'); tp.shared{name,lua=%s}"):format(name,lua))
            end
        else
            if not no_synth_target and a:find('%.') and exists(a) then
                -- @doc 'synth-target' unless specifically switched off with '-t',
                -- see if we have a suitable rule for processing
                -- an existing file with this extension.
                local _,_,rule = deduce_tool(a,true)
                if _ then
                    set_flags()
                    use_lakefile = false
                    -- if there's no specific rule for this tool, we assume that there's
                    -- a program target for this file; we keep the target for later,
                    -- when we will try to execute its result.
                    if not rule then
                        synth_target = program (a)
                        synth_args_index = i + 1
                    else
                        rule.in_ext = extension_of(a)
                        rule(a)
                    end
                    break
                end
                -- otherwise, it has to be a target
            end
            append(specific_targets,a)
        end
        i = i + 1
    end
     set_flags()
    -- if we are called as a program, not as a library, then invoke the specified lakefile
    if arg[0] == 'lake.lua' or arg[0]:find '[/\\]lake%.lua$' then
        if use_lakefile then
            lakefile = lakefile or 'lakefile'
            if not exists(lakefile) then
                quit("'%s' does not exist",lakefile)
            end
            specfile = lakefile..'.spec'
            specfile = io.open(specfile,'r')
            outspec = io.open(TMPSPEC,'w')
            dofile(lakefile)
        end
        go()
        finalize()
    end
end

function finalize()
    if specfile then specfile:close() end
    if outspec then
        if pcall(outspec,close,outspec) then
            copyfile(TMPSPEC,lakefile..'.spec')
        end
    end
end

local dir_stack = {}
local push,pop = table.insert,table.remove

function change_dir (path)
    if path == '!' or path == '<' then
        lfs.currentdir(pop(dir_stack))
        print('restoring directory')
    else
        push(dir_stack,lfs.currentdir())
        local res,err = lfs.chdir(path)
        if not res then quit(err) end
        print('changing directory',path)
    end
    update_pwd()
end

-- recursively invoke lake at the given @path with the arguments @args
function lake(path,args)
    args = args or ''
    exec('lake -d '..path..'  '..args,true)
end


function go()
    if #all_targets_list == 0 then
        quit('no targets defined')
    end
    for tt in list(all_targets_list) do
        expand_dependencies(tt)
    end
    ALL_TARGETS = all_targets()
    if verbose then dump(ALL_TARGETS) end

    local synthesize_clean
    local targets = {}
    if #specific_targets > 0 then
        for tname in list(specific_targets) do
            t = target_from_file(tname)
            if not t then
                -- @doc 'all' is a synonym for the first target
                if tname == 'all' then
                    append(targets,all_targets_list[1])
                elseif tname ~= 'clean' then
                    quit ("no such target '%s'",tname)
                else --@doc there is no clean target, so we'll construct one later
                    synthesize_clean = true
                    append(targets,'clean')
                end
            end
            append(targets,t)
        end
    else
        -- @doc by default, we choose the first target, just like Make.
        -- (Program/library targets force themselves to the top)
        append(targets,all_targets_list[1])
    end
    -- if requested, generate a default clean target, using all the targets.
    if synthesize_clean then
        local t = new_target('clean',nil,function()
            remove(ALL_TARGETS)
            --remove_files '*.d *.spec'
        end)
        targets[index_list(targets,'clean')] = t
    end
    for t in list(targets) do
        t.time = filetime(t.target)
        check(t.time,t)
    end
    if nbuild == 0 then
        if not synth_target then print 'lake: up to date' end
    end
    -- @doc 'synth-target' a program target was implicitly created from the file on the command line;
    -- execute the target, passing the rest of the parms passed to Lake, unless we were
    -- explicitly asked to clean up.
    if synth_target and not synthesize_clean then
        run(synth_target.target,arg,synth_args_index)
    end
end

function run(prog,args,istart)
    local args = parm_list_concat(arg,istart)
    local ext = extension_of(prog)
    local runner = interpreters[ext]
    if runner then runner = runner..' '
    else runner = LOCAL_EXEC
    end
    exec(runner..prog..args)
end

function deduce_tool(fname,no_error)
    local name,ext,tp
    if type(fname) == 'table' then
        name,ext = fname, fname.ext
        if not ext then quit("need to specify 'ext' field for program()") end
    else
        name,ext = splitext(fname)
        if ext == '' then
            if no_error then return end
            quit('need to specify extension for input to program()')
        end
    end
    tp = extensions[ext]
    if not tp then
        if no_error then return end
        quit("unknown file extension '%s'",ext)
    end
    tp.ext = ext
    return tp,name,tp.rule
end

local flags_set

local function opt_flag (flag,opt)
    if opt then
        if opt == true then opt = OPTIMIZE
        elseif opt == false then return ''
        end
        return flag..opt
    else
        return ''
    end
end

--[[ -@doc [GLOBALS]
    These can be set on the command-line (like make) and in the environment variable LAKE_PARMS
    CC - the C compiler (gcc unless cl is available)
    CXX - the C++ compiler (g++ unless cl is available)
    FC - the Fortran compiler (gfortran)
    OPTIMIZE - (O1)
    STRICT - strict compile (also -s command-line flag)
    DEBUG - debug build (also -g command-line flag)
    PREFIX - (empty string. e.g. PREFIX=arm-linux makes CC become arm-linux-gcc etc)
    LUA_INCLUDE,LUA_LIB - (usually deduced from environment)
    WINDOWS - true for Windows
    PLAT - platform deduced from uname if not windows, 'Windows' otherwise
    MSVC - true if we're using cl
    EXE_EXT -  extension of programs on this platform
    DLL_EXT - extension of shared libraries on this platform
    DIRSEP - directory separator on this platform
    NO_COMBINE - don't allow the compiler to compile multiple files at once (if it is capable)
    NODEPS - don't do automatic dependency generation
]]


function set_flags(parms)
    if not parms then
        if not flags_set then flags_set = true else return end
    else
        for k,v in pairs(parms) do
            _G[k] = v
        end
    end
    -- @doc Microsft Visual C++ compiler prefered on Windows, if present
    if WINDOWS and which 'cl' and not CC then
        CC = 'cl'
        CXX = 'cl'
        PREFIX = ''
        WATCOM = os.getenv 'WATCOM'
        if WATCOM then
            NODEPS = true
        end
    else
        -- @doc if PREFIX is set, then we use PREFIX-gcc etc. For example,
        -- if PREFIX='arm-linux' then CC becomes 'arm-linux-gcc'
        if PREFIX and #PREFIX > 0 then
            PREFIX = PREFIX..'-'
            CC = PREFIX..'gcc'
            CXX = PREFIX..'g++'
            FC = PREFIX..'gfortran'
        else
            PREFIX = ''
            CC = CC or 'gcc'
        end
    end
    if not CXX and CC == 'gcc' then
        CXX = 'g++'
        FC = 'gfortran'
    end
    -- @doc The default value of OPTIMIZE is O1
    if not OPTIMIZE then
        OPTIMIZE = 'O1'
    end
    if CC ~= 'cl' then -- must be 'gcc' or something compatible
        c.init_flags = function(debug,opt,strict)
            local flags = choose(debug,'-g',opt_flag('-',opt))
            if strict then
                -- @doc 'strict compile' (-s) uses -pedantic -Wall for gcc; /WX for cl.
                flags = flags .. ' -pedantic -Wall'
            end
            return flags
        end
        c.auto_deps = '-MMD'
        AR = PREFIX..'ar'
        c.COMPILE = '$(CC) -c $(CFLAGS)  $(INPUT) -o $(TARGET)'
        c.COMPILE_COMBINE = '$(CC) -c $(CFLAGS)  $(INPUT)'
        c99.COMPILE = '$(CC) -std=c99 -c $(CFLAGS)  $(INPUT) -o $(TARGET)'
        c99.COMPILE_COMBINE = '$(CC) -std=c99 -c $(CFLAGS)  $(INPUT)'
        c.LINK = '$(CC) $(DEPENDS) $(LIBS) -o $(TARGET)'
        c99.LINK = c.LINK
        f.COMPILE = '$(FC) -c $(CFLAGS)  $(INPUT)'
        f.LINK = '$(FC) $(DEPENDS) $(LIBS) -o $(TARGET)'
        cpp.COMPILE = '$(CXX) -c $(CFLAGS)  $(INPUT) -o $(TARGET)'
        cpp.COMPILE_COMBINE = '$(CXX) -c $(CFLAGS)  $(INPUT)'
        cpp.LINK = '$(CXX) $(DEPENDS) $(LIBS) -o $(TARGET)'
        c.LIB = '$(AR) rcu $(TARGET) $(DEPENDS) && ranlib $(TARGET)'
        C_LIBPARM = '-l'
        C_LIBPOST = ' '
        C_LIBDIR = '-L'
        c.INCDIR = '-I'
        C_DEFDEF = '-D'
        if PLAT=='Darwin' then
            C_LINK_PREFIX = 'MACOSX_DEPLOYMENT_TARGET=10.3 '
            C_LINK_DLL = ' -bundle -undefined dynamic_lookup'
        else
            C_LINK_DLL = '-shared'
        end
        c.OBJ_EXT = '.o'
        LIB_PREFIX='lib'
        LIB_EXT='.a'
        SUBSYSTEM = '-Xlinker --subsystem -Xlinker  '  -- for mingw with Windows GUI
        if PLAT ~= 'Darwin' then
            C_EXE_EXPORT = ' -Wl,-E'
        else
            C_EXE_EXPORT = ''
        end
        C_STRIP = ' -Wl,-s'
        C_LIBSTATIC = ' -static'
        c.uses_dfile = 'slash'
        -- @doc under Windows, we use the .def file if provided when linking a DLL
        function c.massage_link (name,deps)
            local def = exists(name..'.def')
            if def and WINDOWS then
                deps = copy_list(deps)
                append(deps,def)
            end
            return deps
        end

		wresource.COMPILE = 'windres $(CFLAGS) $(INPUT) $(TARGET)'
		wresource.OBJ_EXT='.o'

    else -- Microsoft command-line compiler
        MSVC = true
        c.init_flags = function(debug,opt,strict)
            local flags = choose(debug,'/Zi',opt_flag('/',opt))
            if strict then -- 'warnings as errors' might be a wee bit overkill?
                flags = flags .. ' /WX'
            end
            return flags
        end
        c.COMPILE = 'cl /nologo -c $(CFLAGS)  $(INPUT) /Fo$(TARGET)'
        c.COMPILE_COMBINE = 'cl /nologo -c $(CFLAGS)  $(INPUT)'
        c.LINK = 'link /nologo $(DEPENDS) $(LIBS) /OUT:$(TARGET)'
        -- enabling exception unwinding is a good default...
        -- note: VC 6 still has this as '/GX'
        cpp.COMPILE = 'cl /nologo /EHsc -c $(CFLAGS)  $(INPUT) /Fo$(TARGET)'
        cpp.COMPILE_COMBINE = 'cl /nologo /EHsc -c $(CFLAGS) $(INPUT)'
        cpp.LINK = c.LINK
        c.LIB = 'lib /nologo $(DEPENDS) /OUT:$(TARGET)'
        c.auto_deps = '/showIncludes'
        function c.post_build(ptype,args)
            if not WATCOM and args and (args.static==false or args.dynamic) then
                local mtype = choose(ptype=='exe',1,2)
                return 'mt -nologo -manifest $(TARGET).manifest -outputresource:$(TARGET);'..mtype
            end
        end
        function c.massage_link (name,deps,t)
            local odeps = deps
            -- a hack needed because we have to link against the import library, not the DLL
            deps = {}
            for l in list(odeps) do
                if extension_of(l) == '.dll' then l = replace_extension(l,'.lib') end
                append(deps,l)
            end
            -- if there was an explicit .def file, use it
            local def = exists(name..'.def')
            if def then
                append(deps,'/DEF:'..def)
            elseif t.lua and t.ptype == 'dll' then
                -- somewhat ugly hack: if no .def and this is a Lua extension, then make sure
                -- the Lua extension entry point is visible.
                append(deps,' /EXPORT:luaopen_'..name)
            end
            return deps
        end
        -- @doc A language can define a filter which operates on the output of the
        -- compile tool. It is used so that Lake can parse the output of /showIncludes
        -- when using MSVC and create .d files in the same format as generated by GCC
        -- with the -MMD option.
        local rule,file_pat,dfile,target,ls
        local function write_deps()
            local outd = io.open(dfile,'w')
            outd:write(target,': ',concat(ls,' '),'\n')
            outd:close()
        end
        if not NODEPS then
        function c.filter(line,action)
          -- these are the three ways that the filter is called; initially with
          -- the input and the target, finally with the name, and otherwise
          -- with each line of output from the tool. This stage can filter the
          -- the output by returning some modified string.
          if action == 'start' then
            target,rule = line[1],line[3]
            file_pat = '.-%'..rule.in_ext..'$'
            dfile = nil
          elseif action == 'end' then
            write_deps()
          elseif line:match(file_pat) then
            local input
            -- the line containing the input file
            if dfile then write_deps() end
            dfile,input = rule:deps_filename(line)
            ls = {input}
          else
              local file = line:match('Note: including file:%s+(.+)')
              if file then
                if not isabs(file) then -- only relative paths are considered dependencies
                    append(ls,file)
                end
              else
                return line
              end
            end
        end
        end
        c.stdout = true
        C_LIBPARM = ''
        C_LIBPOST = '.lib '
        C_LIBDIR = '/LIBPATH:'
        c.INCDIR = '/I'
        C_DEFDEF = '/D'
        C_LINK_DLL = '/DLL'
        c.OBJ_EXT = '.obj'
        LIB_PREFIX=''
        C_STRIP = ''
        LIB_EXT='_static.lib'
        SUBSYSTEM = '/SUBSYSTEM:'
        C_LIBDYNAMIC = 'msvcrt.lib' -- /NODEFAULTLIB:libcmt.lib'
        c.uses_dfile = 'noslash'

		wresource.COMPILE = 'rc $(CFLAGS) /fo$(TARGET) $(INPUT) '
		wresource.OBJ_EXT='.res'
		wresource.INCDIR ='/i'

    end
end

function output_filter (lang,filter)
    local old_filter = lang.filter
    lang.filter = function(line,action)
        if not action then
            if old_filter then line = old_filter(line) end
            return filter(line)
        else
            if old_filter then old_filter(line,action) end
        end
    end
end

function concat_arg(pre,arg,sep,base)
    return ' '..concat_list(pre,deps_arg(arg,base),sep)
end

local function check_c99 (lang)
    if lang == c99 and CC == 'cl' then
        quit("C99 is not supported by CL")
    end
end

local function _compile(name,compile_deps,lang)
    local args = (type(name)=='table') and name or {}
    local cflags = ''
	if lang.init_flags then
		cflags = lang.init_flags(pick(args.debug,DEBUG), pick(args.optimize,OPTIMIZE), pick(args.strict,STRICT))
	end
    check_c99(lang)

    compile_deps = args.compile_deps or args.headers
    -- @doc 'defines' any preprocessor defines required
    if args.defines then
        cflags = cflags..concat_arg(C_DEFDEF,args.defines,' ')
    end
    -- @doc 'incdir' specifying the path for finding include files

    if args.incdir then
        cflags = cflags..concat_arg(lang.INCDIR,args.incdir,' ',args.base)
    end

    -- @doc 'flags' extra flags for compilation
    if args.flags then
        cflags = cflags..' '..args.flags
    end
    -- @doc 'nodeps' don't automatically generate dependencies
    if not args.nodeps and not NODEPS and lang.auto_deps then
        cflags = cflags .. ' ' .. lang.auto_deps
    end
    local can_combine = not args.odir and not NO_COMBINE and lang.COMPILE_COMBINE
    local compile_cmd = lang.COMPILE
    if can_combine then compile_cmd = lang.COMPILE_COMBINE end
    local compile_str = subst_all_but_basic(compile_cmd)
    local ext = args and args.ext or lang.ext

    local cr = rule(ext,lang.OBJ_EXT or ext,compile_str)

    -- @doc 'compile_deps' can provide a list of files which all members of the rule
    -- are dependent on.
    if compile_deps then cr:depends_on(compile_deps) end
    cr.cflags = cflags
    cr.can_combine = can_combine
    cr.uses_dfile = lang.uses_dfile
    return cr
end

function find_include (f)
    if not WINDOWS then
        return exists('/usr/include/'..f) or exists('/usr/share/include/'..f)
    else
       -- ??? no way to tell ???
    end
end

local extra_needs = {}

function define_need (name,callback)
    extra_needs[name] = callback
end

function define_pkg_need (name,package)
	if not package then package = name end
    define_need(name,function()
        local gflags = shell ('pkg-config --cflags '..package)
        if gflags:find ('pkg-config',1,true) then
            quit('pkgconfig problem:\n'..gflags)
        end
        local glibs = shell ('pkg-config --libs '..package)
        return {libflags=glibs,flags=gflags}
    end)
end

local function append_to_field (t,name,arg)
    if arg and #arg > 0 then
        if not t[name] then
            t[name] = {}
        elseif type(t[name]) == 'string' then
            t[name] = deps_arg(t[name])
        end
        append_list(t[name],deps_arg(arg))
    end
end

-- @doc [needs] these are currently the built-in needs supported by Lake
local builtin_needs = {math=true,readline=true,dl=true,sockets=true}

function update_needs(ptype,args)
    local needs = args.needs
    -- @doc [needs] extra needs for all compile targets can be set with the NEEDS global.
    if NEEDS then
        if needs then needs = needs .. ' ' .. NEEDS
        else needs = NEEDS
        end
    end
    needs = deps_arg(needs)
    local libs,incdir = {},{}
    for need in list(needs) do
        if not extra_needs[need] and not builtin_needs[need] then
            -- @doc [needs] unknown needs are assumed to be known by pkg-config
            define_pkg_need(need)
        end
        if extra_needs[need] then
            local res = extra_needs[need]()
            append_to_field(args,'libs',res.libs)
            append_to_field(args,'incdir',res.incdir)
            append_to_field(args,'defines',res.defines)
            append_to_field(args,'libdir',res.libdir)
            if res.libflags then args.libflags = concat_str(args.libflags,res.libflags,true) end
            if res.flags then args.flags = concat_str(args.flags,res.flags,true) end
        elseif not WINDOWS then
            if need == 'math' then append(libs,'m')
            elseif need == 'readline' then
                append(libs,'readline')
                if PLAT=='Linux' then
                    append_list(libs,{'ncurses','history'})
                end
            elseif need == 'dl' and PLAT=='Linux' then
                append(libs,'dl')
            end
        else
            if need == 'sockets' then append(libs,'wsock32') end
        end
    end
    append_to_field(args,'libs',libs)
    append_to_field(args,'incdir',incdir)
end

define_pkg_need('gtk','gtk+-2.0')
define_pkg_need('gthread','gthread-2.0')

define_need('windows',function()
    return { libs = 'user32 kernel32 gdi32 ole32 advapi32 shell32 imm32  uuid comctl32 comdlg32'}
end)

define_need('unicode',function()
    return { defines = 'UNICODE _UNICODE' }
end)


local lr_cfg

LUA_INCLUDE = nil
LUA_LIB = nil

-- the assumption here that the second item on your Lua paths is the 'canonical' location. Adjust accordingly!
function get_lua_path (p)
    return package.path:match(';(/.-)%?'):gsub('/lua/$','')
end

local function update_lua_flags (ptype,args)
    if LUA_INCLUDE == nil then
        -- if LuaRocks is available, we ask it where the Lua headers are found...
        if not IGNORE_LUAROCKS and not lr_cfg and pcall(require,'luarocks.cfg') then
            lr_cfg = luarocks.cfg
            LUA_INCLUDE = lr_cfg.variables.LUA_INCDIR
            LUA_LIBDIR = lr_cfg.variables.LUA_LIBDIR
        elseif WINDOWS then -- no standard place, have to deduce this ourselves!
            local lua_path = which(arg[-1])  -- usually lua, could be lua51, etc!
            if not lua_path then quit ("cannot find Lua on your path") end
            local path = dirname(lua_path)
            LUA_INCLUDE = exists(path,'include') or exists(path,'..\\include')
            if not LUA_INCLUDE then quit ("cannot find Lua include directory") end
            LUA_LIBDIR = exists(path,'lib') or exists(path,'..\\lib')
            if not LUA_INCLUDE or not LUA_LIBDIR then
                quit("cannot find Lua include and/or library files\nSpecify LUA_INCLUDE and LUA_LIBDIR")
            end
        else
            -- 'canonical' Lua install puts headers in sensible place
            if not find_include 'lua.h' then
                -- except for Debian, of course
                LUA_INCLUDE = find_include 'lua5.1/lua.h'
                if not LUA_INCLUDE then
                    quit ("cannot find Lua include files\nSpecify LUA_INCLUDE")
                end
            else
                LUA_INCLUDE = ''
                LUA_LIBDIR = ''
            end
        end
    end
    args.incdir = concat_str(args.incdir,LUA_INCLUDE)
    args.libdir = concat_str(args.libdir,LUA_LIBDIR or '')
    if WINDOWS then
        args.libs = concat_str(args.libs,'lua5.1')
    end
    if LUA_DEV then -- specifically, Lua for Windows
        if CC=='gcc' then
            args.libs = concat_str(args.libs,'msvcr80')
        else
            args.dynamic = true
        end
    end
end


local program_fields = {
    name=true, -- name of target (or first value of table)
    lua=true,  -- build against Lua libs
    needs=true, -- higher-level specification of target link requirements
    libdir=true, -- list of lib directories
    libs=true, -- list of libraries
    libflags=true, -- list of flags for linking
	subsystem=true, -- (Windows) GUi application
	strip=true,  -- strip symbols from output
    rules=true,inputs=true, -- explicit set of compile targets
    shared=true,dll=true, -- a DLL or .so (with lang.library)
    deps=true, -- explicit dependencies of a target (or subsequent values in table)
    export=true, -- this executable exports its symbols
    dynamic=true, -- link dynamically against runtime (default true for GCC, override for MSVC)
    static=true, -- statically link this target
    headers=true, -- explicit list of header files (not usually needed with auto deps)
    odir=true, -- output directory; if true then use 'debug' or 'release'; prepends PREFIX
    src=true, -- src files, may contain directories or wildcards (extension deduced from lang or `ext`)
    exclude=true,	-- a similar list that should be excluded from the source list (e.g. if src='*')
    ext=true, -- extension of source, if not the usual. E.g. ext='.cxx'
    defines=true, -- C preprocessor defines
    incdir=true, -- list of include directories
    flags=true,	 -- extra compile flags
    debug=true, -- override global default set by -g or DEBUG variable
    optimize=true, -- override global default set by OPTIMIZE variable
    strict=true, -- strict compilation of files
	base=true, -- base directory for source and includes
}

function check_options (args,fields,where)
	if not fields then
		fields = program_fields
		where = 'program'
	end
    for k,v in pairs(args) do
        if type(k) == 'string' and not fields[k] then
            quit("unknown %s option '%s'",where,k)
        end
    end
end

local function tail (t,istart)
    istart = istart or 2
    if #t < istart then return nil end
    return {select(istart,unpack(t))}
end

local function _program(ptype,name,deps,lang)
    local dependencies,src,except,cr,subsystem,args
    local libs = LIBS
    check_c99(lang)
    if type(name) == 'string' then name = { name } end
    if type(name) == 'table' then
        args = name
        check_options(args,program_fields,'program')
        append_table(args,lang.defaults)
        --- the name can be the first element of the args table
        name = args.name or args[1]
        deps = args.deps or tail(args)
        src = args.src
        except = args.exclude
        subsystem = args.subsystem
        -- special Lua support
        if args.lua then
            update_lua_flags(ptype,args)
        end
        -- @doc 'needs' specifying libraries etc by 'needs', not explicitly
        if args.needs or NEEDS then
            update_needs(ptype,args)
        end

        -- @doc 'libdir' specifying the path for finding libraries
        if args.libdir then
            libs = libs..concat_arg(C_LIBDIR,args.libdir,' ')
        end
        -- @doc 'static' this program is statically linked against the runtime
        -- By default, GCC doesn't do this, but CL does
        if args.static then
            if not MSVC then libs = libs..C_LIBSTATIC	end
        elseif args.static==false then
            if MSVC then libs = libs..C_LIBDYNAMIC	end
        end
        if args.dynamic then
            if MSVC and not WATCOM then libs = libs..C_LIBDYNAMIC	end
        end
        -- @doc 'libs' specifying the list of libraries to be linked against
        if args.libs then
            libs = libs..concat_arg(C_LIBPARM,args.libs,C_LIBPOST)
        end
        -- @doc 'libflags' explicitly providing command-line for link stage
        if args.libflags then
            libs = libs..args.libflags
            if not args.defines then args.defines = '' end
            args.defines = args.defines .. '_DLL'
        end
        if args.strip then
            libs = libs..C_STRIP
        end
        -- @doc 'rules' explicitly providing input targets! 'inputs' is a synonym
        if args.inputs then args.rules = args.inputs end
        if args.rules then
            cr = args.rules
            -- @doc 'rules' may be a .deps file
            if type(cr) == 'string' then
                cr = rules_from_deps(cr)
            elseif is_simple_list(cr) then
                cr = depends(cr)
            end
            if src then warning('providing src= with explicit rules= is useless') end
        else
            if not src then src = {name} end
        end
        -- @doc 'export' this program exports its symbols
        if args.export then
            libs = libs..C_EXE_EXPORT
        end
	else
		args = {}
    end
    -- we can now create a rule object to compile files of this type to object files,
    -- using the appropriate compile command.
    local odir = args.odir
	if odir then
        -- @doc 'odir' set means we want a separate output directory. If a boolean,
        -- then we make a reasonably intelligent guess.
		if odir == true then
			odir = PREFIX..choose(DEBUG,'debug','release')
			if not isdir(odir) then lfs.mkdir(odir) end
		end
	end
    if not cr then
        -- generally a good idea for Unix shared libraries
        if ptype == 'dll' and CC ~= 'cl' and not WINDOWS then
            args.flags = (args.flags or '')..' -fPIC'
        end
        cr = _compile(args,deps,lang)
		cr.output_dir = odir
    end


    -- can now generate a target for generating the executable or library, unless
    -- this is just a group of files
    local t
    if ptype ~= 'group' then
		if not name then quit('no name provided for program') end
        -- @doc we may have explicit dependencies, but we are always dependent on the files
        -- generated by the compile rule.
        dependencies = choose(deps,depends(cr,deps),cr)
        local tname
        local btype = 'LINK'
        local link_prefix = ''
        if args and (args.shared or args.dll) then ptype = 'dll' end
        if ptype == 'exe' then
            tname = name..EXE_EXT
        elseif ptype == 'dll' then
            tname = name..DLL_EXT
            libs = libs..' '..C_LINK_DLL
            if C_LINK_PREFIX then link_prefix = C_LINK_PREFIX end
        elseif ptype == 'lib' then
            tname = LIB_PREFIX..name..LIB_EXT
            btype = 'LIB'
        end
        -- @doc 'subsystem' with Windows, have to specify subsystem='windows' for pure GUI applications; ignored otherwise
        if subsystem and WINDOWS then
            libs = libs..' '..SUBSYSTEM..subsystem
        end
        local link_str = link_prefix..subst_all_but_basic(lang[btype])
        -- @doc conditional post-build step if a language defines a function 'post_build'
        -- that returns a string
        if btype == 'LINK' and lang.post_build then
            local post = lang.post_build(ptype,args)
            if post then link_str = link_str..' && '..post end
        end
        local target = tname
        if odir then target = join(odir,target) end
        t = new_target(target,dependencies,link_str,true)
        t.name = name
        t.libs = libs
        t.link = lang
        t.lua = args.lua
        t.ptype = ptype
        cr.parent = t
    end
    cr.filter = lang.filter
    cr.stdout = lang.stdout
    -- @doc  'src' we have been given a list of source files, without extension
    if src then
		local ext = args.ext or lang.ext
        src = expand_args(src,ext,args.recurse,args.base)
        if except then
            except = expand_args(except,ext,false,args.base)
            erase_list(src,except)
        end
        for f in list(src) do cr(f) end
    end
    return t,cr
end

function add_proglib (fname,lang,kind)
    lang[fname] = function (name,deps)
        return _program(kind,name,deps,lang)
    end
end

function add_prog (lang) add_proglib('program',lang,'exe') end
function add_shared (lang) add_proglib('shared',lang,'dll') end
function add_library (lang) add_proglib('library',lang,'lib') end

function add_group (lang)
    lang.group = function (name,deps)
        local _,cr = _program('group',name,deps,lang)
        return cr
    end
end

for lang in list {c,c99,cpp} do
	add_prog(lang)
	add_shared(lang)
	add_library(lang)
	add_group(lang)
end

add_prog(f)
add_group(wresource)

function program(fname,deps)
    local tp,name = deduce_tool(fname)
    return tp.program(name,deps)
end

function compile(args,deps)
    local tp,name = deduce_tool(args.ext or args[1])
    append_table(args,tp.defaults)
    local rule = _compile(args,deps,tp)
    rule:add_target(name)
    return rule
end

function shared(fname,deps)
    local tp,name = deduce_tool(fname)
    return tp.shared(name,deps)
end

--- patching text files ----

--- iterate over each line of @file, matching with the Lua string @pattern.
-- Any captures from @pattern are passed to a function @action, plus the line.
function foreach_line_matching (file,pattern,action)
	if not exists(file) then return nil end
	for line in io.lines(file) do
		local m = line:match(pattern)
		if m then action(m,line) end
	end
	return file
end

local function condition_arg (condition)
	if type(condition) == 'table' then
		condition = function(x) return condition[x] end
	end
	return condition
end

--- convert the file @src into @dest using the filter function or map @condition.
-- Any extra arguments will be passed to @condition after the line.
-- If the result is a string, it is written out; if a list, then each item is
-- written out. If the result is nil or false, then don't write.
-- If there is an error, returns nil and the error string, otherwise true
function generate_from (src,dest,condition,...)
	if not exists(src) then return nil,src.." cannot be read" end
	local out,err = io.open(dest,'w')
	if not out then return nil,err end
	condition = condition_arg(condition)
	for line in io.lines(src) do
		line = condition(line,...)
		if type(line) == 'table' then
			for _,l in ipairs(line) do	out:write(l,'\n') end
		elseif line then
			out:write(line,'\n')
		end
	end
	out:close()
	return true
end

--- like !generate_from, except that the conversion is done in-place by first making
-- a copy of @file. @condition again can be a function or a map
function filter (file,condition,...)
	local copyf = file..'.copy'
	if not exists(copyf) then --OUT-OF-DATE check needed!
		copyfile(file,copyf)
	end
	return generate_from(copyf,file,condition,...)
end

--- filter a file @file by matching each line against a @pattern.
-- Any capture from the pattern is passed to a function or map @condition;
-- if it returns true then prepend @comment to the line.
function comment_if(file,pattern,comment,condition)
	condition = condition_arg(condition)
	return filter(file,function(line)
		local name = line:match (pattern)
		if name and condition(name) then line = comment..line end
		return line
	end)
end

--- defines the default target for this lakefile
function default(args)
    new_target('default',args,'',true)
end

process_args()
