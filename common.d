module common;

import tango.core.Array;
import tango.core.Thread;
import tango.core.Version;
import tango.io.device.File;
import Path = tango.io.Path;
import tango.stdc.ctype;
import tango.stdc.string;
import tango.stdc.time;
import tango.text.Ascii;
import tango.text.Util;
import tango.text.convert.Format;
import Integer = tango.text.convert.Integer;
import tango.io.stream.Iterator;
import tango.time.StopWatch;
import tango.time.Time;
import tango.util.log.Trace;

import dwt.DWT;
import dwt.dnd.Clipboard;
import dwt.dnd.TextTransfer;
import dwt.dwthelper.utils;
import dwt.widgets.Table;

import set;
import threadmanager;


version (allservers)  // useful for speed testing
	const bool MOD_ONLY = false;
else
	const bool MOD_ONLY = true;

struct arguments {  ///
static:
	bool dumplist  = false;  ///
	bool dumpqstat = false;  ///
	bool fromfile  = false;  ///
	bool norefresh = false;  ///
	bool quit      = false;  ///
}


char[] appDir;  /// Absolute path to where the application is installed.
char[] dataDir;  /// Absolute path to where settings and data is stored.
char[] logDir;  /// Absolute path to where the log file is.

bool haveGslist;  /// Will be true if gslist was found during startup.


const char[] APPNAME = "Monster Browser";

const char[] SVN = import("svnversion.txt");

const char[] FINAL_VERSION = "0.6";

debug {
	const char[] VERSION = __DATE__ ~
	                                 " (svnversion " ~ SVN ~ ") *DEBUG BUILD*";
}
else {
	version (Final)
		const char[] VERSION = FINAL_VERSION;
	else
		const char[] VERSION = __DATE__ ~  " (svnversion " ~ SVN ~ ")";
}

Clipboard clipboard;
StopWatch globalTimer;

///
bool userAbort = false;


// Add dispose() methods etc. to this array, and they will be called at
// shutdown.
void delegate()[] callAtShutdown;

// Custom file open modes, since Tango doesn't have sharing enabled by default
const File.Style WriteCreateShared =
                      { File.Access.Write, File.Open.Create, File.Share.Read };
const File.Style WriteAppendingShared =
                      { File.Access.Write, File.Open.Append, File.Share.Read };


private {
	const int MAX_LOG_SIZE = 100 * 1024;
	File logfile;
}


/**
 * Open a log file.
 *
 * Will write a startup message including the current date and time to it if it
 * was successfully opened.
 *
 * Throws: IOException.
 */
void initLogging(char[] name="LOG.TXT")
{
	const char[] sep =
	           "-------------------------------------------------------------";
	char[] error = null;
	assert(logDir);
	char[] path = logDir ~ name;

	if (Path.exists(path) && Path.fileSize(path) < MAX_LOG_SIZE)
		logfile = new File(path, WriteAppendingShared);
	else
		logfile = new File(path, WriteCreateShared);

	time_t t = time(null);
	char[] timestamp = ctime(&t)[0..24];
	logfile.write(newline ~ sep ~ newline ~ APPNAME ~ " " ~ VERSION ~
	                     " started at " ~ timestamp ~ newline ~ sep ~ newline);
}


/// Flush and close log file.
void shutDownLogging()
{
	if (logfile) {
		logfile.flush.close;
		logfile = null;
	}
}


/// Logging.
void log(char[] file, int line, char[] msg)
{
	log(file ~ "(" ~ Integer.toString(line) ~ "): " ~ msg);
}


/// ditto
void log(char[] s)
{
	version(redirect) {}
	else Trace.formatln("LOG: {}", s);

	assert(logfile !is null);
	if (logfile) {
		logfile.write(s);
		logfile.write(newline);
	}
}


/// ditto
void logx(char[] file, int line, Exception e)
{
	log(file, line, e.classinfo.name ~ ": " ~ e.toString());
	log(Format("{} threads, currently in '{}'.", Thread.getAll().length,
	                                                   Thread.getThis().name));
	log(Format("ThreadManager's thread is {}.",
	                         threadManager.sleeping ? "sleeping" : "working"));

	// output stack trace
	e.writeOut((char[] s) { logString(s); });

	version(redirect) {}
	else Trace.flush();
	if (logfile)
		logfile.flush();
}


// same as log(), but doesn't print newline
private void logString(char[] s)
{
	version(redirect) {}
	else Trace.format(s);

	assert(logfile !is null);
	if (logfile)
		logfile.write(s);
}


version (Windows)
	const char[] newline = "\r\n";
else
	const char[] newline = "\n";


/**
 * Transfer a string to the system clipboard.
 */
void copyToClipboard(char[] s)
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
	static Regex re = null;
	if (re is null)
		re = Regex(r"(\d{1,3}\.){3}\d{1,3}(:\d{1,5})?");

	return re.test(address) && (re.match(0).length == address.length);
}*/

// workaround, see http://dsource.org/projects/tango/ticket/956
bool isValidIpAddress(in char[] address)
{
	uint skipDigits(ref char[] s, uint maxDigits=uint.max) {
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
int findString(char[][] array, char[] str)
{
	foreach (int i, char[] s; array) {
		if (icompare(str, s) == 0)
			return i;
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
		if (icompare(str, s[column]) == 0)
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
void sortStringArray(char[][][] arr, int column=0, bool reverse=false,
                                                          bool numerical=false)
{
	bool less(char[][] a, char[][] b)
	{
		int result;

		if (numerical)
			result = Integer.parse(a[column]) - Integer.parse(b[column]);
		else
			result = icompare(a[column], b[column]);

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
		delete b;
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

	foreach (s; delimiters(str, ", \t")) {
		if (s.length > 0) {
			int val = Integer.parse(s);
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
char[] toCsv(T)(T[] a)
{
	char[] s = Format("{}", a);

	static if (Tango.Major == 0 && Tango.Minor < 997) {
		assert(s[0..2] == "[ " && s[$-2..$] == " ]");
		return s[2..$-2];
	}
	else {
		assert(s[0..1] == "[" && s[$-1..$] == "]");
		assert(!isspace(s[1]) && !isspace(s[$-2]));
		return s[1..$-1];
	}
}


/**
 * Get the widths of all columns in a DWT Table object.
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
 * Throws: Whatever iter's opApply throws.
 */
Set!(char[]) collectIpAddresses(Iterator!(char) iter, uint start=0)
{
	Set!(char[]) addresses;

	foreach (char[] line; iter) {
		if (start >= line.length)
			continue;

		line = line[start..$];
		if (isValidIpAddress(line))
			addresses.add(line.dup);
	}

	return addresses;
}


/// Sets the values of the common.arguments struct.
void parseCmdLine(char[][] args)
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
