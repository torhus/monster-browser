module common;

private {
	import std.date;
	import std.file;
	import std.format;
	import std.regexp;
	import std.stdio;
	import std.stream;
	import std.utf;
	import std.c.stdio;
	import std.c.stdlib;

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
	//const char[] VERSION = "- " ~ __DATE__ ;
	const char[] VERSION = "0.3d";
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


void log(char[] file, int line, char[] msg)
{
	log(file ~ "(" ~ std.string.toString(line) ~ "): " ~ msg);
}


void log(char[] s)
{
	version(NO_STDOUT) {}
	else debug writefln("LOG: " ~ s);

	logfile.writeLine(s);
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
 * Check if address is a valid IP _address, with or without a port number.
 *
 * No garbage at the beginning or end of the string is allowed.
 */
bool isValidIpAddress(in char[] address)
{
	RegExp re = new RegExp(r"(\d{1,3}\.){3}\d{1,3}(:\d{1,5})?");

	char[][] matches = re.exec(address);
	return (matches.length != 0 && matches[0].length == address.length);
}


/**
 * Find a string in an _array of strings, ignoring case differences.
 *
 * Does a linear search.
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
 * Like the above findString, but search in a given _column of a
 * 3-dimensional _array.
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

	qsort(arr.ptr, arr.length, arr[0].sizeof, &cmp);
}


void sortStringArrayStable(char[][][] arr, int sortColumn=0,
                           bool reverse=false,bool numeric=false)
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
	this() { time_ = std.date.getUTCtime();	}
	d_time raw() { return std.date.getUTCtime() - time_; }
	long millis() { return raw * (1000 / TicksPerSecond); }
	double secs() { return cast(double) raw / TicksPerSecond; }
	void restart() { time_ = std.date.getUTCtime(); }
	private d_time time_;
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
			size_t m = lo + ((hi - lo) / 2);
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
