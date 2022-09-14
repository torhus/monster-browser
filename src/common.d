module common;

import core.thread;
import core.stdc.ctype;
import core.stdc.string;
import core.stdc.time;
import std.file;
import std.stdio;
import undead.stream : InputStream;
import std.string;
import tango.core.Array;
import Integer = tango.text.convert.Integer;
import tango.text.Util : delimiters;

import lib.process;

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
	bool colortest = false;  ///
}


shared string appDir;  /// Absolute path to where the application is installed.
shared string dataDir;  /// Absolute path to where settings and data is stored.
shared string logDir;  /// Absolute path to where the log file is.

shared bool haveGslist;  /// Will be true if gslist was found during startup.


enum APPNAME = "Monster Browser";

enum SVN = import("svnversion.txt");

enum FINAL_VERSION = "0.7";

debug {
	enum VERSION = __DATE__ ~ " (svnversion " ~ SVN ~ ") *DEBUG BUILD*";
}
else {
	version (Final)
		enum VERSION = FINAL_VERSION;
	else
		enum VERSION = __DATE__ ~  " (svnversion " ~ SVN ~ ")";
}

__gshared Clipboard clipboard;
__gshared Timer globalTimer;

///
shared bool userAbort = false;

/// Is there a console available for output?
shared bool haveConsole;


// Add dispose() methods etc. to this array, and they will be called at
// shutdown.
__gshared void delegate()[] callAtShutdown;


private {
	__gshared File logFile;
}


/**
 * Initialize logging.
 *
 * Throws: StdioException.
 */
void initLogging(string fileName="LOG.TXT")
{
	const string sep =
	           "-------------------------------------------------------------";
	assert(logDir);
	string path = logDir ~ fileName;

	// limit file size
	if (exists(path) && getSize(path) > 1024 * 100)
		remove(path);

	// open file and add a startup message
	time_t t = time(null);
	char[] timestamp = ctime(&t)[0..24];
	logFile = File(path, "a");
	logFile.writeln('\n' ~ sep ~ '\n' ~ APPNAME ~ " " ~ VERSION ~
	                     " started at " ~ timestamp ~ '\n' ~ sep);
}


/// Logging, with formatting support.
void log(T...)(T args)
{
	logFile.writefln(args);
	version (redirect) { }
	else {
		write("LOG: ");
		writefln(args);
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

	// output stack trace
	/*char[] buf;
	// FIXME: should probably avoid allocating memory here.
	e.writeOut((char[] s) { buf ~= s; });
	Log.root.info(buf);*/
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
/*bool isValidIpAddress(in char[] address)
{
	__gshared Regex re = null;
	if (re is null)
		re = Regex(r"(\d{1,3}\.){3}\d{1,3}(:\d{1,5})?");

	return re.test(address) && (re.match(0).length == address.length);
}*/

// workaround, see http://dsource.org/projects/tango/ticket/956
bool isValidIpAddress(const(char)[] address)
{
	uint skipDigits(ref const(char)[] s, uint maxDigits=uint.max) {
		size_t i = 0;
		while (i < s.length && isdigit(s[i]) && i < maxDigits)
			i++;
		s = s[i..$];
		return i;
	}

	for (int i=0; i < 3; i++) {
		if (address.length == 0 || !isdigit(address[0]))
			return false;
		if (skipDigits(address, 3) == 0)
			return false;
		if (address.length == 0 || address[0] != '.')
			return false;
		address = address[1..$];
	}

	if (address.length == 0 || !isdigit(address[0]))
		return false;
	if (skipDigits(address, 3) == 0)
		return false;

	if (address.length == 0)
		return true;

	if (address[0] == ':' && address.length >= 2) {
		address = address[1..$];
		if (isdigit(address[0]) && skipDigits(address) <= 5 &&
		                                                   address.length == 0)
			return true;
	}

	return false;
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
	foreach (int i, s; array) {
		if (icmp(str, s) == 0)
			return i;
	}
	return -1;
}


/**
 * Like the above findString, but search in a given _column of a
 * 3-dimensional _array.
 */
int findString(in char[][][] array, in char[] str, int column)
{
	foreach (int i, const(char[][]) s; array) {
		if (icmp(str, s[column]) == 0)
			return i;
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
void sortStringArray(string[][] arr, int column=0, bool reverse=false,
                                                          bool numerical=false)
{
	bool less(in char[][] a, in char[][] b)
	{
		int result;

		if (numerical)
			result = cast(int)Integer.parse(a[column]) -
			         cast(int)Integer.parse(b[column]);
		else
			result = icmp(a[column], b[column]);

		return reverse ? result >= 0 : result < 0;
	}

	sort(arr, &less);
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
 * Parse a sequence of integers, separated by any combination of commas,
 * spaces, or tabs.
 *
 * If forcedLength is > 0, the returned array will have been shortened or
 * extended as necessary to match that length.  If it needs to be extended,
 * the extra elements will have defaultVal as their value.
 */
int[] parseIntList(in char[] str, size_t forcedLength=0, int defaultVal=0)
{
	int[] r = null;

	foreach (s; delimiters(str, cast(const(char[]))", \t")) {
		if (s.length > 0) {
			int val = cast(int)Integer.parse(s);
			r ~= val;
		}
	}

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
 * optional.  One address each token. If no valid address is found, the token
 * is ignored.
 *
 * Returns: A set of strings containing the IP and port of each server.
 *
 * Throws: Whatever stream's opApply throws.
 */
Set!(string) collectIpAddresses(InputStream stream, uint start=0)
{
	Set!(string) addresses;

	foreach (char[] line; stream) {
		if (start >= line.length)
			continue;

		line = line[start..$];
		if (isValidIpAddress(line))
			addresses.add(line.idup);
	}

	return addresses;
}


/// ditto
Set!(string) collectIpAddresses(Process stream, uint start=0)
{
	Set!(string) addresses;

	try {
		for (;;) {
			char[] line = stream.readLine();
			if (start >= line.length)
				continue;

			line = line[start..$];
			if (isValidIpAddress(line))
				addresses.add(line.idup);
		}
	}
	catch (PipeException e) {
		// ignore the exception
	}	

	return addresses;
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
			case "colortest":
				arguments.colortest = true;
				break;
			default:
				log("UNRECOGNIZED ARGUMENT: " ~ arg);
				break;
		}
	}
}
