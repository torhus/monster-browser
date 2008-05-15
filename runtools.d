/**
 * Functions for running qstat and gslist, while capturing their output
 */

module runtools;

import tango.core.Exception : IOException, ProcessException;
debug import tango.io.Console;
import tango.io.File;
import tango.io.FileConduit;
import Path = tango.io.Path;
import tango.io.stream.BufferStream;
import tango.io.stream.TextFileStream;
import tango.stdc.ctype : isdigit;
import tango.stdc.stdio : sscanf;
import tango.stdc.stringz;
import tango.sys.Process;
import Integer = tango.text.convert.Integer;
import tango.text.stream.LineIterator;

import common;
import main;
import qstat;
import serverlist;
import servertable;
import set;
import settings;


Process proc;

// True if parsing of the server list is to be aborted.  Set to true before
// calling a function to load/parse server lists.
bool abortParsing = false;

/// The name of the file that qstat reads addresses from when querying servers.
const char[] REFRESHFILE = "refreshlist.tmp";


/**
 * Run qstat or gslist (determined by the useGslist variable) to retrieve a
 * list of servers from the active mod's master server.
 *
 * Returns: A set containing the IP addresses of the servers.
 */
Set!(char[]) browserGetNewList()
{
	char[] cmdLine;
	size_t count = -1;
	Set!(char[]) addresses;

	if (common.useGslist)
		cmdLine = "gslist -n quake3 -o 5";
	else
		cmdLine = "qstat -q3m,68,outfile " ~ activeMod.masterServer ~ ",-";

	version (linux)
		cmdLine = "./" ~ cmdLine;

	if (common.useGslist && MOD_ONLY && activeMod.name!= "baseq3")
		cmdLine ~= " -f \"(gametype = \'" ~ activeMod.name ~ "\'\")";

	proc = new Process();
	//scope (exit) if (proc) proc.wait();

	try {
		log("Executing '" ~ cmdLine ~ "'.");
		proc.execute(cmdLine, null);
	}
	catch (ProcessException e) {
		char[] s = common.useGslist ? "gslist" : "qstat";
		error(s ~ " not found!\nPlease reinstall " ~ APPNAME ~ ".");
		logx(__FILE__, __LINE__, e);
		proc = null;
	}

	if (proc) {
		try {
			auto lineIter= new LineIterator!(char)(proc.stdout);
			size_t start = common.useGslist ? 0 : "q3s ".length;
			addresses = collectIpAddresses(lineIter, start);
			//proc.stdout.close();  FIXME: any point to this?
		}
		catch (IOException e) {
			//logx(__FILE__, __LINE__, e);
		}
		catch(Exception e) {
			logx(__FILE__, __LINE__,e);
			error(__FILE__ ~ Integer.toString(__LINE__) ~
			                 ": Unexpected exception: " ~ e.classinfo.name ~
			                 ": " ~ e.toString());
		}
	}

	return addresses;
}


/**
 * Loads the server list from activeMod.serverFile.
 *
 * callback will be called each time a new server has been added to serverList,
 * with the current number of servers as the argument.
 */
void browserLoadSavedList(void delegate(Object) callback)
{
	volatile abortParsing = false;

	if (!Path.exists(activeMod.serverFile)) {
		return;
	}

	try {
		scope input = new TextFileInput(activeMod.serverFile);
		getActiveServerList.clear();
		qstat.parseOutput(callback, input, null);
		getActiveServerList.complete = !abortParsing;
		input.close();
	}
	catch (IOException o) {
		warning("Unable to load the server list from disk,\n"
		      "press \'Get new list\' to download a new list.");
	}
}


/**
 * Queries all servers whose addresses are found in REFRESHFILE.
 *
 * The servers are added to serverList as they are received.
 *
 * Params:
 *     callback = Will be called each time a new server has been added to
 *                serverList, with the current number of servers as the
 *                argument.
 *     saveList = If true, qstat's raw output will be saved to disk.
 */
void browserRefreshList(void delegate(Object) callback, bool saveList=false)
{
	proc = new Process();
	//scope (exit) if (proc) proc.wait();

	try {
		char[] cmdLine = "qstat -f " ~ REFRESHFILE ~ " -raw,game " ~ FIELDSEP ~
		                  " -P -R -default q3s";
		if (getSetting("coloredNames") == "true")
			cmdLine ~= " -carets";
		version (linux)
			cmdLine = "./" ~ cmdLine;

		log("Executing '" ~ cmdLine ~ "'.");
		// FIXME: feed qstat through stdin (-f -)?
		proc.execute(cmdLine, null);
	}
	catch (ProcessException e) {
		error("qstat not found!\nPlease reinstall " ~ APPNAME ~ ".");
		return;
	}

	try {
		char[] tmpfile = saveList ? "servers.tmp" : null;
		scope iter = new LineIterator!(char)(proc.stdout);
		qstat.parseOutput(callback, iter, tmpfile);
		//proc.stdout.close();  FIXME: any point to this?

		getActiveServerList.complete = !abortParsing;

		if (saveList) {
			if (!abortParsing) {
				try {
					auto serverFile = activeMod.serverFile;
					if (Path.exists(serverFile))
						Path.remove(serverFile);
					Path.rename(tmpfile, serverFile);
				}
				catch (IOException e) {
					warning("Unable to save the server list to disk.");
				}
			}
			else {
				try {
					Path.remove(tmpfile);
				}
				catch (IOException e) {
					warning(e.toString());
				}
			}
		}
	}
	catch(Exception e) {
		db(__FILE__ ~ Integer.toString(__LINE__) ~ ": " ~ e.toString());
	}
}


/** Kill the command line server browser process
 *
 * Returns: true if the process was running, false if not.
 */
bool killServerBrowser()
{
	if (proc is null) {
		debug Cout("proc is null").newline;
		return false;
	}

	if (!proc.isRunning)
		return false;

	try {
		proc.kill();
		proc = null;
	}
	catch (ProcessException e) {
		// Since isRunning doesn't actually check if the process is still
		// running, this exception will happen all the time.
		//logx(__FILE__, __LINE__, e);
	}
	return true;
}
