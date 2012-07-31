#include <iostream>
#include <string>
#include <list>
#include <map>
using namespace std;

int foo(int i) { return i; }
double foo(double x) { return x; }

int main()
{
  string s;
  list<string> ls;
  map<string,int> mli;
  int i = 0;
  cout << i.x << endl;
  foo(s);
  cout.push(1);
  mli.put("alpha",0);
  ls.append("hello");
  cout << ls << endl;
  return 0;
}
