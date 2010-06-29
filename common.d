module common;

import core.Thread;
import core.stdc.ctype;
import core.stdc.string;
import core.stdc.time;
import std.conv;
import std.date;
import std.string;

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
static:
	bool dumplist  = false;  ///
	bool dumpqstat = false;  ///
	bool fromfile  = false;  ///
	bool norefresh = false;  ///
	bool quit      = false;  ///
	bool colortest = false;  ///
}


string appDir;  /// Absolute path to where the application is installed.
string dataDir;  /// Absolute path to where settings and data is stored.
string logDir;  /// Absolute path to where the log file is.

bool haveGslist;  /// Will be true if gslist was found during startup.


string APPNAME = "Monster Browser";

string SVN = import("svnversion.txt");

string FINAL_VERSION = "0.7";

debug {
	string VERSION = __DATE__ ~ " (svnversion " ~ SVN ~ ") *DEBUG BUILD*";
}
else {
	version (Final)
		string VERSION = FINAL_VERSION;
	else
		string VERSION = __DATE__ ~  " (svnversion " ~ SVN ~ ")";
}

Clipboard clipboard;
Timer globalTimer;

///
bool userAbort = false;

/// Is there a console available for output?
bool haveConsole;


// Add dispose() methods etc. to this array, and they will be called at
// shutdown.
void delegate()[] callAtShutdown;


private {
	File logFile;
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
	logFile.writeln(newline ~ sep ~ newline ~ APPNAME ~ " " ~ VERSION ~
	                     " started at " ~ timestamp ~ newline ~ sep);
}


/// Logging, with formatting support.
/*void log(in char[] file, int line, in char[] msg)
{
	log(file, "(", line, "): ", msg);
}*/


/// ditto
void log(T...)(T args)
{
	logFile.writefln(args);
}


/// ditto
void logx(in char[] file, int line, Exception e)
{
	log(file, line, e.classinfo.name ~ ": " ~ e.toString());
	log("%s threads, currently in '%s'.", Thread.getAll().length,
	                                                    Thread.getThis().name);
	log("ThreadManager's thread is %s.",
	                          threadManager.sleeping ? "sleeping" : "working");

	// output stack trace
	/*char[] buf;
	// FIXME: should probably avoid allocating memory here.
	e.writeOut((char[] s) { buf ~= s; });
	Log.root.info(buf);*/
}


/// Platform-specific _newline sequence
version (Windows)
	string newline = "\r\n";
else
	string newline = "\n";


///
struct Timer
{
	void start() { time_ = std.date.getUTCtime();	}  ///
	private d_time raw() { return std.date.getUTCtime() - time_; }  ///
	long millis() { return raw * (1000 / TicksPerSecond); }  ///
	double seconds() { return cast(double) raw / TicksPerSecond; }  ///
	private d_time time_;  ///
}


/**
 * Transfer a string to the system clipboard.
 */
void copyToClipboard(in char[] s)
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
	foreach (int i, char[][] s; array) {
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
void sortStringArray(in char[][][] arr, int column=0, bool reverse=false,
                                                          bool numerical=false)
{
	bool less(in char[][] a, in char[][] b)
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
string toCsv(T)(T[] a)
{
	return to!string(a, null, ", ", null);
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
 * Throws: Whatever iter's opApply throws.
 */
Set!(string) collectIpAddresses(Iterator!(char) iter, uint start=0)
{
	Set!(string) addresses;

	foreach (char[] line; iter) {
		if (start >= line.length)
			continue;

		line = line[start..$];
		if (isValidIpAddress(line))
			addresses.add(line.idup);
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
