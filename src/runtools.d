/**
 * Functions for running qstat and capturing its output
 */

module runtools;

import std.ascii : newline;
import std.conv;
import std.exception : ErrnoException;
import std.file;
import std.process;
import std.stdio;
import std.string;

import common;
import messageboxes;
import qstat;
import masterlist;
import serverdata;
import set;
import settings;


__gshared private ProcessPipes proc;
__gshared private Object procMutex;


/// Thrown if there's an error when communicating with a master server.
class MasterServerException : Exception {
	this(string msg) { super(msg); }
}


void runtoolsInit()
{
	procMutex = new Object();
}

/**
 * Run qstat to retrieve a list of servers from the game's master
 * server.
 *
 * Returns: A set containing the IP addresses of the servers.
 *
 * Throws: MasterServerException.
 */
Set!(string) browserGetNewList(in GameConfig game)
{
	char[] cmdLine;
	Set!(string) addresses;

	version (linux)
		cmdLine ~= "./";

	cmdLine ~= "qstat";
	// This has to be the first argument.
	if (game.qstatConfigFile)
		cmdLine ~= " -cfg " ~ game.qstatConfigFile;

	cmdLine ~= " -" ~ game.qstatMasterServerType ~
			   "," ~ game.protocolVersion ~ ",outfile " ~
			   game.masterServer ~ ",-";

	try {
		synchronized (procMutex) {
			log("Executing '" ~ cmdLine ~ "'.");
			proc = pipeProcess(
			       split(cmdLine), Redirect.all, null, Config.suppressConsole);
		}
	}
	catch (ProcessException e) {
		error("qstat not found! Please reinstall " ~ APPNAME ~ ".");
		logx(__FILE__, __LINE__, e);
	}

	if (proc != ProcessPipes.init && proc.pid.processID >= 0) {
		try {
			size_t start = "q3s ".length;
			auto lines = proc.stdout.byLine(KeepTerminator.no, newline);

			char[] firstLine = lines.front.dup;
			lines.popFront();
			throwIfQstatError(firstLine, lines.front, proc.stderr, game);

			addresses = collectIpAddresses(lines, start);
		}
		catch (StdioException e) {
			logx(__FILE__, __LINE__,e);
		}
		catch (Exception e) {
			error(__FILE__ ~ to!string(__LINE__) ~
			                 ": Unexpected exception: " ~ e.classinfo.name ~
			                 ": " ~ e.toString());
			logx(__FILE__, __LINE__,e);
		}
	}

	return addresses;
}


private void throwIfQstatError(in char[] line1, in char[] line2,
                               File stderr, in GameConfig game)
{
	if (!line1.startsWith("ADDRESS")) {
		char[] error = stderr.rawRead(new char[512]);
		if (error.length)
			throw new MasterServerException(strip(error).idup);
		else
			throw new MasterServerException("Unknown Qstat error");
	}

	size_t len = game.qstatMasterServerType.length;

	if (icmp(line2[0..len], game.qstatMasterServerType) == 0) {
		const(char)[][] parts = split(line2, " ");

		if (parts.length > 2) {
			const(char)[] s = strip(join(parts[1..$], " "));
			throw new MasterServerException(s.idup);
		}
		else {
			throw new MasterServerException(("Unrecognized error: \"" ~
			                                        strip(line2) ~ "\"").idup);
		}
	}
}


///
interface IServerRetriever
{
	/**
	 * Will be called after serverThread and qstat has terminated, but before
	 * the new thread is created.
	 *
	 * Use for doing initialization at this stage, if needed.
	 */
	void initialize();


	/**
	 * Will be called in the new thread, just before retrieve().
	 *
	 * Returns: The number of servers to be queried, for display in the GUI.
     *          Return 0 to abort the retrieval process.  Return -1 if the
	 *          number of servers is not known.  Returning -1 will not abort
	 *          the process.
	 */
	int prepare();


	/**
	 * Retrieves all servers, handing each one to the deliver delegate.
	 *
	 * If deliver returns false, the server retrieval process is aborted.
	 */
	void retrieve(bool delegate(ServerHandle, bool replied) deliver);

}


///
final class MasterListServerRetriever : IServerRetriever
{

	///
	this(in GameConfig game, MasterList master)
	{
		game_ = game;
		master_ = master;
	}


	///
	void initialize() { }


	///
	int prepare()
	{
		return master_.length;
	}


	///
	void retrieve(bool delegate(ServerHandle sh, bool replied) deliver)
	{
		foreach (sh; master_) {
			ServerData sd = master_.getServerData(sh);
			bool keep = matchGame(&sd, game_);
			static if (!MOD_ONLY)
				keep = true;
			if (keep)
				deliver(sh, true);
		}
	}


	private {
		const GameConfig game_;
		MasterList master_;
	}
}


///
final class QstatServerRetriever : IServerRetriever
{
	/**
	* Params:
	*    game      = Name of game.
	*    master    = MasterList object to add servers to.
	*    addresses = Addresses of servers to query.
	*    replace   = Try to replace servers in the master, instead of adding.
	*                Servers that are not present in the master will be added.
	*/
	this(string game, MasterList master, Set!string addresses,
	                                                        bool replace=false)
	{
		game_ = getGameConfig(game);
		master_ = master;
		addresses_ = addresses;
		replace_ = replace;
	}


	///
	void initialize() { }


	///
	int prepare()
	{
		try {
			string cmdLine = "qstat -f - -raw,game " ~ FIELDSEP ~ " -P -R" ~
			                                                   " -default q3s";
			File dumpFile;

			if (getSetting("coloredNames") == "true")
				cmdLine ~= " -carets";
			version (linux)
				cmdLine = "./" ~ cmdLine;

			cmdLine ~= " -maxsim " ~ getSetting("simultaneousQueries");

			synchronized (procMutex) {
				log("Executing '" ~ cmdLine ~ "'.");
				proc = pipeProcess(
				   split(cmdLine), Redirect.all, null, Config.suppressConsole);
			}

			if (arguments.dumplist)
				dumpFile.open("refreshlist.tmp", "w");

			synchronized (procMutex) {
				foreach (address; addresses_) {
					proc.stdin.writeln(address);
					if (dumpFile.isOpen) {
						dumpFile.writeln(address);
					}
				}
				proc.stdin.close();
			}
			log("Fed %s addresses to qstat.", addresses_.length);
		}
		catch (ProcessException e) {
			error("qstat not found! Please reinstall " ~ APPNAME ~ ".");
			return 0;
		}

		return addresses_.length;
	}


	///
	void retrieve(bool delegate(ServerHandle sh, bool replied) deliver)
	{
		bool _deliver(ServerData* sd, bool replied)
		{
			ServerHandle sh;

			if (replace_) {
				sh = master_.updateServer(*sd);
				if (sh == InvalidServerHandle)
					sh = master_.addServer(*sd);
			}
			else {
				sh = master_.addServer(*sd);
			}

			return deliver(sh, replied);
		}

		qstat.parseOutput(game_.mod, proc.stdout, &_deliver);
	}


	private {
		Set!string addresses_;
		GameConfig game_;
		MasterList master_;
		bool replace_;
	}
}


/**
 * Kill the command line server browser process.
 */
void killServerBrowser()
{
	if (proc == proc.init || proc.pid.processID < 0)
		return;

	try {
		kill(proc.pid);
		wait(proc.pid);
	}
	catch (ProcessException e) {
	}
	catch (ErrnoException e) {
	}
}
