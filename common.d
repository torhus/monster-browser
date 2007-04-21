module common;

//import std.date;
//import std.stdio;
//import std.format;
//import std.utf;
//import std.file;
//import std.stream;
//import std.c.stdlib;
//import std.c.stdio;

public import tango.core.Type : Time;
import tango.io.Console;
import tango.io.FilePath;
import tango.stdc.stdio;
import tango.stdc.stdlib;
import tango.stdc.stringz;
import tango.text.Ascii;
import Integer = tango.text.convert.Integer;
import tango.text.convert.Sprint;
import TimeStamp = tango.text.convert.TimeStamp;
import Util = tango.text.Util;
import tango.util.time.Utc;

import dejavu.lang.JObjectImpl;
import dejavu.lang.Runnable;
import dejavu.lang.String;

import org.eclipse.swt.SWT;
import org.eclipse.swt.widgets.Display;
import org.eclipse.swt.widgets.MessageBox;

//import dwt.all;
import main;


/* SETTINGS */
const bool MOD_ONLY = true;
//debug const bool MOD_ONLY = false;

bool useGslist;


const char[] APPNAME = "Monster Browser";

debug {
	const char[] VERSION = "- " ~ __DATE__ ~ " *DEBUG BUILD*";
}
else {
	const char[] VERSION = "- " ~ __DATE__;
	//const char[] VERSION = "0.2" ;
}

private {
	const char[] LOGFILE = "LOG.TXT";
	const int MAX_LOG_SIZE = 100 * 1024;
	FILE* logfile;
	Sprint!(char) logFormatter;
}


static this()
{
	const char[] sep = "-------------------------------------------------------------";

	auto f = new FilePath(LOGFILE);

	if (f.exists && f.fileSize > MAX_LOG_SIZE) {
		f.remove();
	}

	logfile = fopen(toUtf8z(LOGFILE), "a".ptr);

	char[] s = "\n" ~ sep ~ "\n" ~ APPNAME ~ " started at " ~
	           TimeStamp.toUtf8(Utc.local()) ~ "\n" ~ sep ~ "\n";

	fwrite(s.ptr, s[0].sizeof, s.length, logfile);

	logFormatter = new Sprint!(char);
}


static ~this()
{
	fclose(logfile);
}


void messageBox(char[] title, int style, char[] fmt,
                                    TypeInfo[] arguments, void* argptr)
{
	// only the gui thread can display message boxes
	Display.getDefault().syncExec(new class JObjectImpl, Runnable {
		void run() {
			char[] s = logFormatter.format(fmt, arguments, argptr);
			scope MessageBox mb = new MessageBox(mainWindow, style);
			mb.setText(String.fromUtf8(title));
			mb.setMessage(String.fromUtf8(s));
			log("messageBox (" ~ title ~ "): " ~ s);
			mb.open();
		}
	});
}


void warning(char[] fmt, ...)
{
	messageBox("Warning", SWT.ICON_WARNING, fmt,  _arguments, _argptr);
}


void error(char[] fmt, ...)
{
	messageBox("Error", SWT.ICON_ERROR,fmt, _arguments, _argptr);
}


void db(char[] fmt, ...)
{
	messageBox("Debug", SWT.NONE,fmt, _arguments, _argptr);
}


void db(char[][] a)
{
	db(Util.join(a, "\n"));
}


void log(char[] file, int line, char[] msg)
{
	log(file ~ "(" ~ Integer.toUtf8(line) ~ "): " ~ msg);
}


void log(char[] s)
{
	fwrite((s ~= '\n').ptr, s[0].sizeof, s.length + 1, logfile);
	version(NO_STDOUT) {}
	else debug Cout("LOG: " ~ s);
}


void logx(char[] file, int line, Exception e)
{
	log(file ~ Integer.toUtf8(line) ~ e.classinfo.name ~ ": " ~ e.toUtf8());
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
 * Does a linear search.
 *
 * Returns: the index where it was found, or -1 if it was not found.
 */
int findString(char[][] array, char[] str)
{
	foreach (int i, char[] s; array) {
		if (toLower(str) == toLower(s)) {
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
		if (toLower(str) == toLower(s[column])) {
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

	qsort(arr.ptr, arr.length, arr.sizeof, &cmp);
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
	this() { time_ = Utc.local();	}
	Time raw() { return Utc.local() - time_; }
	long millis() { return raw * (1000 / Time.TicksPerSecond); }
	double secs() { return cast(double) raw / Time.TicksPerSecond; }
	void restart() { time_ = Utc.local(); }
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
