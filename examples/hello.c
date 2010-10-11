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
