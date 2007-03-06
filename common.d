module common;


private {
	version (Tango) {
		import tango.core.Epoch;
	}
	else {
		import std.format;
		import std.date;
		import std.utf;
		import std.file;
		import std.stream;
		import std.c.stdlib;
		import std.c.stdio;
	}

	import dwt.all;
	import main;
}


/* SETTINGS */
const bool MOD_ONLY = true;
//debug const bool MOD_ONLY = false;

bool useGslist;


const char[] APPNAME = "Monster Browser";

debug {
	const char[] VERSION = "- " ~ __DATE__ ~ " *DEBUG BUILD*";
}
else {
	const char[] VERSION = "- " ~ __DATE__ ;
	//const char[] VERSION = "0.2" ;
}

private {
	const char[] LOGFILE = "LOG.TXT";
	const int MAX_LOG_SIZE = 100 * 1024;
	File logfile;
}


static this()
{
	const char[] sep = "-------------------------------------------------------------";

	if (std.file.exists(LOGFILE) && std.file.getSize(LOGFILE) > MAX_LOG_SIZE) {
		std.file.remove(LOGFILE);
	}
	logfile = new File(LOGFILE, FileMode.Append);
	logfile.writeLine("\n" ~ sep ~ "\n" ~ APPNAME ~ " started at " ~
	                  std.date.toString(getUTCtime()) ~ "\n" ~ sep);
}


void messageBox(char[] title, int style, TypeInfo[] arguments, void* argptr)
{
	void f(Object o) {
		char[] s;
		void f(dchar c) { std.utf.encode(s, c); }

		std.format.doFormat(&f, arguments, argptr);
		scope MessageBox mb = new MessageBox(mainWindow, style);
		mb.setText(title);
		mb.setMessage(s);
		log("messageBox (" ~ title ~ "): " ~ s);
		mb.open();
	}
	// only the gui thread can display message boxes
	Display.getDefault().syncExec(null, &f);
}


void warning(...)
{
	messageBox("Warning", DWT.ICON_WARNING, _arguments, _argptr);
}


void error(...)
{
	messageBox("Error", DWT.ICON_ERROR, _arguments, _argptr);
}


void db(...)
{
	messageBox("Debug", DWT.NONE, _arguments, _argptr);
}


void db(char[][] a)
{
	db(std.string.join(a, "\n"));
}


void log(char[] file, int line, char[] msg)
{
	log(file ~ "(" ~ std.string.toString(line) ~ "): " ~ msg);
}


void log(char[] s)
{
	logfile.writeLine(s);
	version(NO_STDOUT) {}
	else debug writefln("LOG: " ~ s);
}


void logx(char[] file, int line, Exception e)
{
	log(file, line, e.classinfo.name ~ ": " ~ e.toString());
}


/// Wrapper for an int.  Needed because std.boxer is broken, as of dmd 0.160.
class IntWrapper {
public:
	this(int v=0) { value = v; }
	int value;
}

/**
 * Find a string in an array of strings, ignoring case differences.
 *
 * Returns: the index where it was found, or -1 if it was not found.
 */
int findString(char[][] array, char[] str)
{
	foreach (int i, char[] s; array) {
		if (std.string.tolower(str) == std.string.tolower(s)) {
			return i;
		}
	}
	return -1;
}

/**
 * Like the above findString, but search in a given column of a
 * 3-dimensional array.
 */
int findString(char[][][] array, char[] str, int column)
{
	foreach (int i, char[][] s; array) {
		if (std.string.tolower(str) == std.string.tolower(s[column])) {
			return i;
		}
	}
	return -1;
}


void sortStringArray(char[][][] arr, int sortColumn=0, bool reverse=false,
                     bool numeric=false)
{
	static int _sortColumn;
	static bool _reverse, _numeric;

	static extern(C) int cmp(void* a, void* b)
	{
		char[] first = (*(cast(char[][]*) a))[_sortColumn];
		char[] second = (*(cast(char[][]*) b))[_sortColumn];
		int result;

		if (_numeric) {
			result = std.conv.toInt(first) - std.conv.toInt(second);
		}
		else {
			result = std.string.icmp(first, second);
		}
		return (_reverse ? -result : result);
	}

	_sortColumn = sortColumn;
	_reverse = reverse;
	_numeric = numeric;

	qsort(arr.ptr, arr.length, arr.sizeof, &cmp);
}


void sortStringArrayStable(char[][][] arr, int sortColumn=0, bool reverse=false,
                           bool numeric=false)
{

	bool lessOrEqual(char[][] a, char[][] b)
	{
		int result;

		if (numeric) {
			result = std.conv.toInt(a[sortColumn]) -
			                             std.conv.toInt(b[sortColumn]);
		}
		else {
			result = std.string.icmp(a[sortColumn], b[sortColumn]);
		}
		return (reverse ? -result <= 0 : result <= 0);
	}

	mergeSort(arr, &lessOrEqual);
}


class Timer
{
	this() { time_ = Epoch.utcMilli();	}
	ulong raw() { return Epoch.utcMilli() - time_; }
	ulong millis() { return raw; }
	double secs() { return cast(double) raw / 1000; }
	void restart() { time_ = Epoch.utcMilli(); }
	private ulong time_;
}


/// Pause console output and wait for <enter>
debug void pause()
{
	static char[80] s;
	fgets(s.ptr, s.sizeof, stdin);
}


void mergeSort(T)(T[] a, bool delegate(T a, T b) lessOrEqual=null)
{
	T[] b;

	void merge(size_t lo, size_t m, size_t hi)
	{
		size_t i, j, k;

		i = 0; j = lo;
		// copy first half of array a to auxiliary array b
		while (j <= m)
			b[i++] = a[j++];

		i = 0; k = lo;
		// copy back next-greatest element at each time
		while (k < j && j <= hi)
			if (lessOrEqual(b[i], a[j]))
				a[k++] = b[i++];
			else
				a[k++] = a[j++];

		// copy back remaining elements of first half, if any
		while (k < j)
			a[k++] = b[i++];
	}

	void _mergeSort(size_t lo, size_t hi)
	{
		if (lo < hi)
		{
			size_t m = (lo + hi) / 2;
			_mergeSort(lo, m);
			_mergeSort(m + 1, hi);
			merge(lo, m, hi);
		}
	}

	if (a.length > 0) {
		if (lessOrEqual is null)
			lessOrEqual = (T a, T b) { return a <= b; };
		b = new T[(a.length + 1) / 2];
		_mergeSort(0, a.length - 1);
		delete b;
	}
}
