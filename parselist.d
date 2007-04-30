module parselist;

private {
	import std.string;
	import std.stream;
	import std.stdio;

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

// True if loading of server list is to be aborted.  Set to true before
// calling a function to load/parse server lists.
bool abort = false;

// Note: gslist only outputs to a file called quake3.gsl
const char[] REFRESHFILE = "quake3.gsl";
const char[] SERVERFILE = "servers.lst";


int browserGetNewList()
{
	char[] cmdLine;
	int count = -1;

	if (common.useGslist) {
		cmdLine = "gslist -n quake3 -o 1";
	}
	else {
		cmdLine = "qstat -q3m,68,outfile master3.idsoftware.com," ~
		          REFRESHFILE;
	}

	//log("browserGetNewList():");
	if (common.useGslist && MOD_ONLY && modName != "baseq3") {
		cmdLine ~= " -f \"(gametype = \'" ~ modName ~ "\'\")";
	}

	proc = new Process();

	// bug workaround
	for(int i = 0; _environ[i]; i++) {
		proc.addEnv(std.string.toString(_environ[i]).dup);
	}

	try {
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
			// Just swallow gslist or qstat's output, but get the server count.
			// The IPs are written to a file.
			if (common.useGslist) {
				for (;;) {
					char[] s = proc.readLine();
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

				proc.readLine();
				s = proc.readLine();
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

	volatile abort = false;

	//log("browserLoadSavedList():");
	if (!std.file.exists(SERVERFILE)) {
		return;
	}

	try {
		f = new BufferedFile(SERVERFILE);
		activeServerList.clear();
		qstat.parseOutput(callback, &f.readLine, &f.eof, null);
		f.close();
	}
	catch (OpenException o) {
		warning("Unable to load the server list from disk,\n"
		      "press \'Get new list\' to download a new list.");
	}
}


void browserRefreshList(void delegate(Object) callback, bool saveList=false)
{
	//log("browserRefreshList():");
	proc = new Process();

	// bug workaround
	for(int i = 0; _environ[i]; i++) {
		proc.addEnv(std.string.toString(_environ[i]).dup);
	}

	try {
		// FIXME: feed qstat through stdin (-f -)?
		proc.execute("qstat -f " ~ REFRESHFILE ~ " -raw,game " ~ FIELDSEP ~
		             " -P -R -default q3s" /*-carets";*/);


	}
	catch (Exception e) {
		logx(__FILE__, __LINE__, e);
		error("qstat not found!\nPlease reinstall " ~ APPNAME ~ ".");
		return;
	}

	try {
		char[] s = saveList ? SERVERFILE : null;
		qstat.parseOutput(callback, &proc.readLine, null, s);
	}
	catch(PipeException e) {
		//logx(__FILE__, __LINE__, e);
	}
	catch(Exception e) {
		logx(__FILE__, __LINE__, e);
		error(__FILE__ ~ std.string.toString(__LINE__) ~ ": " ~ e.toString());
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
