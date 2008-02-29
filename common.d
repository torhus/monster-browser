module common;

private {
	import std.format;
	import std.regexp;
	import std.stdio;
	import std.utf;
	import std.c.stdio;
	import std.c.stdlib;

	import tango.io.FileConduit;
	import tango.io.FilePath;
	import tango.stdc.string;
	import tango.stdc.time;
	import tango.text.Ascii;
	import tango.text.Util;
	import Integer = tango.text.convert.Integer;
	import tango.time.Clock;
	import tango.time.Time;

	version (UseOldProcess) {
		import lib.process;
	}
	else {
		// FIXME: temporary, for readLine
		import tango.sys.Process;
		import tango.text.stream.LineIterator;

		class PipeException : Exception { this(char[] msg) { super(msg); } }
	}

	import dwt.DWT;
	import dwt.dwthelper.Runnable;
	import dwt.widgets.Display;
	import dwt.widgets.MessageBox;

	import main;
}


/* SETTINGS */
version (allservers)  // useful for speed testing
	const bool MOD_ONLY = false;
else
	const bool MOD_ONLY = true;

bool useGslist;


const char[] APPNAME = "Monster Browser";

const char[] SVN = import("svnversion.txt");

debug {
	const char[] VERSION = "- " ~ __DATE__ ~ " (svnversion " ~ SVN ~ ") *DEBUG BUILD*";
}
else {
	const char[] VERSION = "- " ~ __DATE__ ~  " (svnversion " ~ SVN ~ ")";
	//const char[] VERSION = "0.3e";
}

private {
	const char[] LOGFILE = "LOG.TXT";
	const int MAX_LOG_SIZE = 100 * 1024;
	FileConduit logfile;
}


static this()
{
	const char[] sep = "-------------------------------------------------------------";
	FileConduit.Style mode;

	with (FilePath(LOGFILE)) {
		if (exists && fileSize < MAX_LOG_SIZE)
			mode = FileConduit.WriteExisting;
		else
			mode = FileConduit.WriteCreate;
	}
	logfile = new FileConduit(LOGFILE, mode);
	logfile.seek(0, FileConduit.Anchor.End);
	auto t = time(null);
	char[] timestamp = ctime(&t)[0..24];
	logfile.write(newline ~ sep ~ newline ~ APPNAME ~ " started at " ~
	              timestamp ~ newline ~ sep ~ newline);
}


static ~this()
{
	logfile.close();
}


char[] readLineWrapper(Process newproc, bool returnNext=true)
{
	static Process proc = null;

	if (newproc)
		proc = newproc;

	version (UseOldProcess){
		return returnNext ? proc.readLine() : null;
	}
	else {
		static LineIterator!(char) iter;
		if (newproc)
			iter = new LineIterator!(char)(proc.stdout);
		if (returnNext) {
			if (iter.next)
				return iter.get.dup;  // FIXME: avoid duping?
			else
				throw new PipeException("iter.next returned null");
		}
		else {
			return null;
		}
	}
}


void messageBox(char[] title, int style, TypeInfo[] arguments, void* argptr)
{
/+
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
+/
	// only the gui thread can display message boxes
	Display.getDefault().syncExec(new class Runnable {
		void run() {
			char[] s;
			void f(dchar c) { std.utf.encode(s, c); }

			std.format.doFormat(&f, arguments, argptr);
			scope MessageBox mb = new MessageBox(mainWindow, style);
			mb.setText(title);
			mb.setMessage(s);
			log("messageBox (" ~ title ~ "): " ~ s);
			mb.open();
		}
	});

}


void _messageBox(char[] caption, int icon)(...)
{
	messageBox(caption, icon, _arguments, _argptr);
}

alias _messageBox!(APPNAME, DWT.ICON_INFORMATION) info;
alias _messageBox!("Warning", DWT.ICON_WARNING) warning;
alias _messageBox!("Error", DWT.ICON_ERROR) error;
alias _messageBox!("Debug", DWT.NONE) db;


void db(char[][] a)
{
	db(join(a, "\n"));
}


void log(char[] file, int line, char[] msg)
{
	log(file ~ "(" ~ Integer.toString(line) ~ "): " ~ msg);
}


void log(char[] s)
{
	version(NO_STDOUT) {}
	else debug writefln("LOG: " ~ s);

	logfile.write(s);
	logfile.write(newline);
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


version (Windows)
	const char[] newline = "\r\n";
else
	const char[] newline = "\n";


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
		if (toLower(str.dup) == toLower(s.dup)) {
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
		if (toLower(str.dup) == toLower(s[column].dup)) {
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
			result = Integer.toInt(first) - Integer.toInt(second);
		}
		else {
			result = icompare(first, second);
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
			result = Integer.toInt(a[sortColumn]) -
			         Integer.toInt(b[sortColumn]);
		}
		else {
			result = icompare(a[sortColumn], b[sortColumn]);
		}
		return (reverse ? -result <= 0 : result <= 0);
	}

	mergeSort(arr, &lessOrEqual);
}


class Timer
{
	this() { time_ = Clock.now(); }
	TimeSpan span() { return Clock.now() - time_; }
	long millis() { return span.millis(); }
	double secs() { return span.interval(); }
	void restart() { time_ = Clock.now(); }
	private Time time_;
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
