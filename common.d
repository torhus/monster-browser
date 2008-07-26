module common;

import tango.io.Console;
import tango.io.FileConduit;
import Path = tango.io.Path;
import tango.io.stream.BufferStream;
import tango.io.stream.TextFileStream;
import tango.stdc.ctype : isdigit;
import tango.stdc.stdlib : qsort;
import tango.stdc.string;
import tango.stdc.time;
import tango.text.Ascii;
import tango.text.Util;
import tango.text.convert.Format;
import Integer = tango.text.convert.Integer;
import tango.text.stream.StreamIterator;
import tango.time.Clock;
import tango.time.Time;

import dwt.DWT;
import dwt.dnd.Clipboard;
import dwt.dnd.TextTransfer;
import dwt.dwthelper.utils;
import dwt.widgets.Table;

import dialogs;
import set;


version (allservers)  // useful for speed testing
	const bool MOD_ONLY = false;
else
	const bool MOD_ONLY = true;

struct arguments {  ///
static:
	bool fromfile  = false;  ///
	bool norefresh = false;  ///
	bool quit      = false;  ///
}


char[] appDir;  /// Absolute path to where the application is installed.

bool haveGslist;  /// Will be true if gslist was found during startup.


const char[] APPNAME = "Monster Browser";

const char[] SVN = import("svnversion.txt");

const char[] FINAL_VERSION = "0.4a";

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
Timer globalTimer;


private {
	const int MAX_LOG_SIZE = 100 * 1024;
	FileConduit logfile;
}


/**
 * Open a log file.
 *
 * Will write a startup message including the current date and time to it if it
 * was successfully opened.
 *
 * Returns: null on success, an error message if there was a problem.
 *
 * Throws: IOException if there was a problem writing to the file after
 *         successfully opening it.
 */
char[] initLogging(char[] name="LOG.TXT")
{
	const char[] sep =
	           "-------------------------------------------------------------";
	FileConduit.Style mode;
	char[] error = null;
	assert(appDir);
	char[] path = appDir ~ name;

	if (Path.exists(path) && Path.fileSize(path) < MAX_LOG_SIZE)
		mode = FileConduit.WriteExisting;
	else
		mode = FileConduit.WriteCreate;

	try {
		logfile = new FileConduit(path, mode);
	}
	catch (IOException e) {
		error = e.toString;
	}

	if (logfile) {
		logfile.seek(0, FileConduit.Anchor.End);
		auto t = time(null);
		char[] timestamp = ctime(&t)[0..24];
		logfile.write(newline ~ sep ~ newline ~ APPNAME ~ " " ~ VERSION ~
		                 " started at " ~ timestamp ~ newline ~ sep ~ newline);
	}

	return error;
}


/// Flush and close log file.
void shutDownLogging()
{
	if (logfile) {
		logfile.flush.close;
		logfile = null;
	}
}


/// Display a debug message in a dialog box.
void db(in char[] fmt, ...)
{
	debug {
		char[] msg = Format.convert(_arguments, _argptr, fmt);
		messageBox(msg, "Debug", DWT.NONE);
	}
}


/// Display a multi-line debug message in a dialog box.
void db(char[][] array)
{
	debug db(join(array, "\n"));
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
	else debug Cout("LOG: ")(s).newline;

	if (logfile) {
		logfile.write(s);
		logfile.write(newline);
	}
}


/// ditto
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


/**
 * Sort a 2-dimensional string array.  Not a stable sort.
 *
 * Params:
 *     sortColumn = Column to sort on (the second dimension of arr).
 *     reverse    = Reversed order.
 *     numeric    = Set to true to get a numerical sort instead of an
 *                  alphabetical one.  The string in the column given by
 *                  sortColumn will be converted to an integer before
 *                  comparing.
 *
 * Throws: IllegalArgumentException if numeric is true, and the strings in
 *         sortColumn contains anything that doesn't parse as integers.
 */
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


/**
 * Sort a 2-dimensional string array.  This is a stable sort.
 *
 * Params:
 *     sortColumn = Column to sort on (the second dimension of arr).
 *     reverse    = Reversed order.
 *     numeric    = Set to true to get a numerical sort instead of an
 *                  alphabetical one.  The string in the column given by
 *                  sortColumn will be converted to an integer before
 *                  comparing.
 *
 * Throws: IllegalArgumentException if numeric is true, and the strings in
 *         sortColumn contains anything that doesn't parse as integers.
 */
void sortStringArrayStable(char[][][] arr, int sortColumn=0,
                           bool reverse=false, bool numeric=false)
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


/// A timer.
class Timer
{
	this() { time_ = Clock.now(); } ///
	long millis() { return span.millis(); } ///
	double seconds() { return span.interval(); } ///
	void restart() { time_ = Clock.now(); } ///

	private {
		TimeSpan span() { return Clock.now() - time_; } ///
		private Time time_;
	}
}


/**
 * In-place merge sort for arrays.  This is a stable sort.
 *
 * If lessOrEqual is null, the <= operator is used instead.
 *
 * Note: Allocates (a.length + 1) / 2 of heap memory, in order to speed up
         sorting.
 */
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


/**
 * Parse a sequence of comma-separated integers, skipping all whitespace.
 *
 * Signs (+ or -) are not allowed.
 */
int[] parseIntegerSequence(in char[] seq)
{
	uint ate;
	int[] r = null;

	while (seq.length) {
		seq = triml(seq);
		int val = Integer.convert(seq, 10, &ate);
		if (ate)
			r ~= val;
		else
			break;

		seq = seq[ate..$];
		seq = triml(seq);
		if (seq.length && seq[0] == ',')
			seq = seq[1..$];
	}

	return r;
}


/**
 * Turn an array into a string of a series of comma-separated values (1,2,3).
 */
char[] toCsv(T)(T[] a)
{
	char[] s = Format("{}", a);
	assert(s[0..2] == "[ " && s[$-2..$] == " ]");
	return s[2..$-2];
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
Set!(char[]) collectIpAddresses(StreamIterator!(char) iter, uint start=0)
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


/**
 * Append IP addresses to a file, skipping addresses in skipList.
 *
 * Returns: The number of servers that were written to the file.
 */
uint appendServersToFile(in char[] fileName, in Set!(char[]) servers,
                         in Set!(char[]) skipList=Set!(char[])())
{
	scope output = new BufferOutput(
	                    new FileConduit(fileName, FileConduit.WriteAppending));
	uint count = 0;

	foreach (address; servers) {
		if (!(address in skipList)) {
			output.write(address);
			output.write(newline);
			count++;
		}
	}

	output.flush.close;
	return count;
}


/// Sets the values of the common.arguments struct.
void parseCmdLine(char[][] args)
{
	foreach (arg; args[1..$]) {
		switch (arg) {
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
				break;
		}
	}
}
