// a simple extension which exports the Lua API lua_createtable function
#include <string.h>
#include <math.h>
//#define LUA_BUILD_AS_DLL
//#define LUA_LIB
// includes for Lua
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

// createtable takes two integer arguments, the number of initial array slots
// and the initial number of hash slots - both default to 0.
static int l_createtable (lua_State *L) {
  int narr = luaL_optint(L,1,0);         // initial array slots, default 0
  int nrec = luaL_optint(L,2,0);   // intial hash slots, default 0
  lua_createtable(L,narr,nrec);
  return 1;
}

static const luaL_reg mylib[] = {
    {"createtable",l_createtable},
    {NULL,NULL}
};

LUALIB_API int luaopen_mylib(lua_State *L)
{
    luaL_register (L, "mylib", mylib);
    return 1;
}
