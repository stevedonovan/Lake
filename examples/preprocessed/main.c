#include <stdio.h>

extern int answer();
extern double sqr(double);

int main()
{
   printf("answer %d and square %f\n",answer(),sqr(4));
   return 0;
}
