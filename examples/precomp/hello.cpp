#include "std.h"
using namespace std;


int main()
{
    list<string> ls;
    ls.push_back("one");
    ls.push_back("two");
    list<string>::iterator lsi;
    for (lsi = ls.begin(); lsi != ls.end(); ++lsi) {
        cout << "Hello " << *lsi << endl;
    }
	return 0;
}
