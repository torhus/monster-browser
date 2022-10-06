module common;

import core.thread;
import core.stdc.time;
import std.algorithm;
import std.ascii : newline;
import std.conv;
import std.datetime;
import std.file;
import std.range;
import std.regex;
import std.stdio;
import std.string;
import std.traits;

import java.lang.wrappers;
import org.eclipse.swt.SWT;
import org.eclipse.swt.dnd.Clipboard;
import org.eclipse.swt.dnd.TextTransfer;
import org.eclipse.swt.widgets.Table;

import set;
import threadmanager;


version (allservers)  // useful for speed testing
	const bool MOD_ONLY = false;
else
	const bool MOD_ONLY = true;

struct arguments {  ///
__gshared:
	bool dumplist  = false;  ///
	bool dumpqstat = false;  ///
	bool fromfile  = false;  ///
	bool norefresh = false;  ///
	bool quit      = false;  ///
}


shared string appDir;  /// Absolute path to where the application is installed.
shared string dataDir;  /// Absolute path to where settings and data is stored.
shared string logDir;  /// Absolute path to where the log file is.

enum APPNAME = "Monster Browser";
enum FINAL_VERSION = "0.9e";

__gshared Clipboard clipboard;
__gshared Timer globalTimer;

///
shared bool userAbort = false;

/// Is there a console available for output?
shared bool haveConsole = false;


// Add dispose() methods etc. to this array, and they will be called at
// shutdown.
__gshared void delegate()[] callAtShutdown;


private {
	__gshared File logFile;
}


///
string getVersionString()
{
	string revision = lineSplitter(import("revision.txt")).join(':');

	debug {
		return __DATE__ ~ " (" ~ revision ~ ") *DEBUG BUILD*";
	}
	else {
		version (Final)
			return FINAL_VERSION;
		else
			return __DATE__ ~  " (" ~ revision ~ ")";
	}
}


/**
 * Initialize logging.
 *
 * Throws: FileException, ErrnoException, and StdioException.
 */
void initLogging(string fileName="LOG.TXT")
{
	assert(logDir);
	string path = logDir ~ fileName;
	string bits = (void*).sizeof == 8 ? "64" : "32";
	version (Windows)
		string system = "Windows";
	else version (linux)
		string system = "Linux";
	else
		string system = "Unknown";

	// limit file size
	bool resetFile = exists(path) && getSize(path) > 1024 * 100;

	// open file and add a startup message
	auto time = cast(DateTime)Clock.currTime();
	logFile = File(path, resetFile ? "w" : "a");
	logFile.writeln();
	logFile.writeln(replicate("-", 65));
	logFile.writefln("%s %s started at %s", APPNAME, getVersionString(), time);
	logFile.writefln("%s-bit version running on %s", bits, system);
	logFile.writeln(replicate("-", 65));
}


/// Logging, with formatting support.
void log(Args...)(in char[] fmt, Args args)
{
	logFile.writefln(fmt, args);
	version (redirect) { }
	else {
		if (haveConsole) {
			write("LOG: ");
			writefln(fmt, args);
		}
	}
}


/// ditto
void logx(in char[] file, int line, Exception e)
{
	log("%s(%s): %s", file, line, e.toString());
	log("%s threads, currently in '%s'.", Thread.getAll().length,
	                                                   Thread.getThis().name);
	if (threadManager !is null) {
		log("ThreadManager's thread is %s.",
		                      threadManager.sleeping ? "sleeping" : "working");
	}
}


///
struct Timer
{
	void start() { time_ = clock(); }  ///
	private clock_t raw() { return clock() - time_; }  ///
	long millis() { return raw() * (1000 / CLOCKS_PER_SEC); }  ///
	double seconds() { return cast(double)raw() / CLOCKS_PER_SEC ; }  ///
	private clock_t time_;  ///
}


/**
 * Find c in s and return the index, or if not found return s.length.
 *
 * Made to behave like tango.text.Util.locate.  Only works when c is ASCII.
 */
size_t findChar(in char[] s, char c)
{
	assert(c <= 0x7f);
	
	// IIRC, pointers are faster with DMD
	const(char)* p = s.ptr;
	const(char)* end = s.ptr + s.length;
	for (; p != end; p++)
		if (*p == c)
			break;
	return p - s.ptr;
}


/**
 * Transfer a string to the system clipboard.
 */
void copyToClipboard(string s)
{
	Object obj = new ArrayWrapperString(s);
	TextTransfer textTransfer = TextTransfer.getInstance();
	clipboard.setContents([obj], [textTransfer]);
}


/**
 * Check if address is a valid IP _address, with or without a port number.
 *
 * No garbage at the beginning or end of the string is allowed.
 */
bool isValidIpAddress(in char[] address)
{
	__gshared auto re = ctRegex!(r"^(\d{1,3}\.){3}\d{1,3}(:\d{1,5})?$");

	return !!matchFirst(address, re);
}


/**
 * Find a string in an _array of strings, ignoring case differences.
 *
 * Does a linear search.
 *
 * Returns: the index where it was found, or -1 if it was not found.
 */
int findString(in char[][] array, in char[] str)
{
	foreach (i, s; array) {
		if (icmp(str, s) == 0)
			return cast(int)i;
	}
	return -1;
}


/**
 * Like the above findString, but search in a given _column of a
 * 3-dimensional _array.
 */
int findString(in char[][][] array, in char[] str, int column)
{
	foreach (i, s; array) {
		if (icmp(str, s[column]) == 0)
			return cast(int)i;
	}
	return -1;
}


/**
 * Sort a 2-dimensional string array.  Not a stable sort.
 *
 * Params:
 *     column     = Column to sort on (the second dimension of arr).
 *     reverse    = Reversed order.
 *     numerical  = Set to true to get a numerical sort instead of an
 *                  alphabetical one.
 */
void sortStringArray(string[][] arr, int column=0, bool reverse=false)
{
	bool less(in char[][] a, in char[][] b)
	{
		int result = icmp(a[column], b[column]);

		return reverse ? result >= 0 : result < 0;
	}

	arr.sort!(less);
}


/**
 * In-place merge sort for arrays.  This is a stable sort.
 *
 * Note: Allocates (a.length + 1) / 2 of heap memory, in order to speed up
 *       sorting.
 */
void mergeSort(T)(T[] a, bool delegate(T a, T b) lessOrEqual)
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
		b = new T[(a.length + 1) / 2];
		_mergeSort(0, a.length - 1);
	}
}


/**
 * Returns s as an int, or defaultVal if s did not parse as an int.
 */
int toIntOrDefault(in char[] s, int defaultVal=0)
{
	try {
		return to!int(s);
	}
	catch (ConvException) {
		return defaultVal;
	}
}

/**
 * Parse a sequence of integers, separated by any combination of commas,
 * spaces, or tabs.
 *
 * If forcedLength is > 0, the returned array will have been shortened or
 * extended as necessary to match that length.  If it needs to be extended,
 * the extra elements will have defaultVal as their value.
 */
int[] parseIntList(in char[] str, size_t forcedLength=0, int defaultVal=0)
{
	int[] r = str.splitter(regex(r"[, \t]"))
	             .filter!(x => x.length)
	             .map!(x => x.toIntOrDefault(defaultVal))
	             .array();

	if (forcedLength != 0 && r.length != forcedLength) {
		size_t oldLen = r.length;
		r.length = forcedLength;
		if (forcedLength > oldLen)
			r[oldLen .. $] = defaultVal;
	}

	return r;
}


/**
 * Turn an array into a string of a series of comma-separated values (1,2,3).
 */
string toCsv(T)(T[] a)
{
	return format("%s", a)[1..$-1];
}


/**
 * Get the widths of all columns in an SWT Table object.
 */
int[] getColumnWidths(Table table)
{
	int[] r;

	foreach (col; table.getColumns())
		r ~= col.getWidth();

	return r;
}



/**
 * Collect IP addresses into a set.
 *
 * The format of each address is IP:PORT, where the port number is
 * optional. Strings that are not valid IP addresses are skipped.
 *
 * Returns: A set of strings containing the IP and port of each server.
 */
Set!(string) collectIpAddresses(R)(R strings, size_t startColumn=0)
	if (isInputRange!R && isSomeString!(ElementType!R))
{
	Set!(string) addresses;

	foreach (s; strings) {
		if (startColumn >= s.length)
			continue;

		s = s[startColumn..$];
		if (isValidIpAddress(s))
			addresses.add(s.idup);
	}

	return addresses;
}

/**
 * See the above version, one address per line.
 *
 * Throws StdioException.
 */
Set!(string) collectIpAddresses(File stream, size_t startColumn=0)
{
	return collectIpAddresses(
			                    stream.byLine(KeepTerminator.no, newline), startColumn);
}


/// Sets the values of the common.arguments struct.
void parseCmdLine(in char[][] args)
{
	foreach (arg; args[1..$]) {
		switch (arg) {
			case "dumplist":
				arguments.dumplist = true;
				break;
			case "dumpqstat":
				arguments.dumpqstat = true;
				break;
			case "fromfile":
				arguments.fromfile = true;
				break;
			case "norefresh":
				arguments.norefresh = true;
				break;
			case "quit":
				arguments.quit = true;
				break;
			default:
				log("UNRECOGNIZED ARGUMENT: " ~ arg);
				break;
		}
	}
}
