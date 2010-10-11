#include <iostream>
#include <string>
#include <list>
using namespace std;

int main()
{
  list<string> ls;
  ls.append("hello");
  cout << ls << endl;
  return 0;
}
