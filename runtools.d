module runtools;

private {
	import std.file;
	import std.string;
	import std.stream;
	import std.stdio;

	version (Tango)
		import tango.sys.Process;
	else
		import lib.process;

	import common;
	import serverlist;
	import qstat;
	import main;
	import servertable;
	import settings;
}

// workaround for process.d bug
extern(C) extern char **_environ;

Process proc;

// True if parsing of the server list is to be aborted.  Set to true before
// calling a function to load/parse server lists.
bool abortParsing = false;

// Note: gslist only outputs to a file called quake3.gsl
const char[] REFRESHFILE = "quake3.gsl";


int browserGetNewList()
{
	char[] cmdLine;
	int count = -1;

	if (common.useGslist) {
		cmdLine = "gslist -n quake3 -o 1";
	}
	else {
		cmdLine = "qstat -q3m,68,outfile " ~ activeMod.masterServer ~ "," ~
		          REFRESHFILE;
	}

	//log("browserGetNewList():");
	if (common.useGslist && MOD_ONLY && activeMod.name!= "baseq3") {
		cmdLine ~= " -f \"(gametype = \'" ~ activeMod.name ~ "\'\")";
	}

	proc = new Process();

	version (Windows) { }
	else scope (exit) if (proc) proc.wait();

	// bug workaround
	version (Tango) { }
	else for (int i = 0; _environ[i]; i++) {
		proc.addEnv(std.string.toString(_environ[i]).dup);
	}

	try {
		log("Executing '" ~ cmdLine ~ "'.");
		proc.execute(cmdLine);
	}
	catch (Exception e) {
		char[] s = common.useGslist ? "gslist" : "qstat";
		error(s ~ " not found!\nPlease reinstall " ~ APPNAME ~ ".");
		logx(__FILE__, __LINE__, e);
		proc = null;
	}

	if (proc) {
		try {
			readLineWrapper(proc, false);

			// Just swallow gslist or qstat's output, but get the server count.
			// The IPs are written to a file.
			if (common.useGslist) {
				for (;;) {
					char[] s = readLineWrapper(null);
					if (s.length > 0 && std.ctype.isdigit(s[0])) {
						count = std.conv.toInt(s[0..find(s, ' ')]);
						log("gslist retrieving " ~ std.string.toString(count) ~
						               " servers.");
					}
				}
			}
			else {
				char[] s;
				int r;

				readLineWrapper(null);
				s = readLineWrapper(null);
				r = sscanf(toStringz(s), "%*s %*s %d", &count);
				log("qstat retrieving " ~ std.string.toString(count) ~
				                              " servers.");
			}
		}
		catch (PipeException e) {
			//logx(__FILE__, __LINE__, e);
		}
		catch(Exception e) {
			logx(__FILE__, __LINE__,e);
			error(__FILE__ ~ std.string.toString(__LINE__) ~
			                 ": Unkown exception: " ~ e.classinfo.name ~ ": " ~
			                 e.toString());
		}
	}

	debug if (count < 0) {
		log(__FILE__, __LINE__, "browserGetNewList(): count < 0");
		if (proc) {
			log("    proc is not null.");
		}
		else {
			log("    proc is null.");
		}
	}

	return count;
}


void browserLoadSavedList(void delegate(Object) callback)
{
	BufferedFile f;

	volatile abortParsing = false;

	//log("browserLoadSavedList():");
	if (!std.file.exists(activeMod.serverFile)) {
		return;
	}

	try {
		f = new BufferedFile(activeMod.serverFile);
		getActiveServerList.clear();
		qstat.parseOutput(callback, &f.readLine, &f.eof, null);
		getActiveServerList.complete = !abortParsing;
		f.close();
	}
	catch (OpenException o) {
		warning("Unable to load the server list from disk,\n"
		      "press \'Get new list\' to download a new list.");
	}
}


void browserRefreshList(void delegate(Object) callback,
                        bool extraServers=true, bool saveList=false)
{
	if (extraServers) {
		scope BufferedFile f = new BufferedFile(REFRESHFILE, FileMode.Append);

		foreach (address; getActiveServerList.extraServers)
			f.writeLine(address);

		f.close();

		char[] extraServersFile = activeMod.extraServersFile();
		if (exists(extraServersFile))
			append(REFRESHFILE, read(extraServersFile));
	}

	//log("browserRefreshList():");
	proc = new Process();

	version (Windows) { }
	else scope (exit) if (proc) proc.wait();

	// bug workaround
	version (Tango) { }
	else for (int i = 0; _environ[i]; i++) {
		proc.addEnv(std.string.toString(_environ[i]).dup);
	}

	try {
		char[] cmdLine = "qstat -f " ~ REFRESHFILE ~ " -raw,game " ~ FIELDSEP ~
		                  " -P -R -default q3s" /*-carets";*/;

		log("Executing '" ~ cmdLine ~ "'.");
		// FIXME: feed qstat through stdin (-f -)?
		proc.execute(cmdLine);
	}
	catch (Exception e) {
		error("qstat not found!\nPlease reinstall " ~ APPNAME ~ ".");
		return;
	}

	try {
		char[] tmpfile = saveList ? "servers.tmp" : null;
		readLineWrapper(proc, false);
		char[] readLine() { return readLineWrapper(null); }
		qstat.parseOutput(callback, &readLine, null, tmpfile);
	}
	catch(PipeException e) {
		getActiveServerList.complete = !abortParsing;

		if (saveList) {
			if (!abortParsing) {
				try {
					if (exists(activeMod.serverFile))
						std.file.remove(activeMod.serverFile);
					std.file.rename("servers.tmp", activeMod.serverFile);
				}
				catch (FileException e) {
					warning("Unable to save the server list to disk.");
				}
			}
			else {
				try {
					std.file.remove("servers.tmp");
				}
				catch (FileException e) {
					warning(e.toString());
				}
			}
		}
	}
	catch(Exception e) {
		db(__FILE__ ~ std.string.toString(__LINE__) ~ ": " ~ e.toString());
	}
}


/** Kill the command line server browser process
 *
 * Returns: true if succeeded, false if not.
 */
bool killServerBrowser()
{
	if (proc is null) {
		debug writefln("proc is null");
		return true;
	}

	try {
		proc.kill();
		proc = null;
	}
	catch (Exception e) {
		logx(__FILE__, __LINE__, e);
		return false;
	}
	return true;
}
