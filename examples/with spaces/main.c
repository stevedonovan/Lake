#include <stdio.h>
#include <common.h>

#define xstr(s) str(s)
#define str(s) #s

int main()
{
    printf("answer is %d\n",one());
    printf("FOO is '%s'\n",xstr(FOO));
    return 0;
}
