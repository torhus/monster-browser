/**
 * Functions for running qstat and gslist, while capturing their output
 */

module runtools;

import std.conv;
import std.file;
import std.stdio;

import lib.process;

import common;
import messageboxes;
import qstat;
import masterlist;
import serverdata;
import set;
import settings;


// workaround for process.d bug
__gshared extern(C) extern char **_environ;

__gshared private Process proc;


/**
 * Run qstat or gslist (determined by the haveGslist variable) to retrieve a
 * list of servers from the game's master server.
 *
 * Returns: A set containing the IP addresses of the servers.
 */
Set!(string) browserGetNewList(in GameConfig game)
{
	char[] cmdLine;
	Set!(string) addresses;
	bool gslist = common.haveGslist && game.useGslist;

	version (linux)
		cmdLine ~= "./";

	if (gslist)
		cmdLine ~= "gslist -n quake3 -o 5";
	else
		cmdLine ~= "qstat -q3m," ~ game.protocolVersion ~ ",outfile " ~
		                                              game.masterServer ~ ",-";

	// use gslist's server-sider filtering
	// Note: gslist returns no servers if filtering on "baseq3"
	if (gslist && MOD_ONLY && game.mod != "baseq3")
		cmdLine ~= " -f \"(gametype='" ~ game.mod ~ "')"
		           " AND (protocol=" ~ game.protocolVersion ~ ")\"";

	try {
		proc = new Process;
		// bug workaround
		for (int i = 0; _environ[i]; i++) {
			proc.addEnv(to!string(_environ[i]).dup);
		}
		//proc.workDir = appDir;
		//proc.gui = true;
		log("Executing '" ~ cmdLine ~ "'.");
		proc.execute(cmdLine);
	}
	catch (ProcessException e) {
		string s = gslist ? "gslist" : "qstat";
		error(s ~ " not found! Please reinstall " ~ APPNAME ~ ".");
		logx(__FILE__, __LINE__, e);
		proc = null;
	}

	if (proc) {
		try {
			size_t start = gslist ? 0 : "q3s ".length;
			addresses = collectIpAddresses(proc, start);
		}
		catch (PipeException e) {
			//logx(__FILE__, __LINE__, e);
		}
		catch(Exception e) {
			logx(__FILE__, __LINE__,e);
			error(__FILE__ ~ to!string(__LINE__) ~
			                 ": Unexpected exception: " ~ e.classinfo.name ~
			                 ": " ~ e.toString());
		}
	}

	return addresses;
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
		bool error = false;

		try {
			if (master_.length == 0 && !master_.load(game_.protocolVersion))
				error = true;
		}
		catch (FileException o) {
			error = true;
		}

		if (error) {
			warning("Unable to load the server list from disk, "
			                 "press \'Get new list\' to download a new list.");
		}

		return error ? 0 : master_.length;
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

			proc = new Process;
			//proc.workDir = appDir;
			//proc.gui = true;
			// bug workaround
			for (int i = 0; _environ[i]; i++) {
				proc.addEnv(to!string(_environ[i]).dup);
			}

			log("Executing '" ~ cmdLine ~ "'.");
			proc.execute(cmdLine.dup);

			if (arguments.dumplist)
				dumpFile.open("refreshlist.tmp", "w");

			foreach (address; addresses_) {
				proc.writeLine(address);
				if (dumpFile.isOpen) {
					dumpFile.writeln(address);
				}
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

		try {
			qstat.parseOutput(game_.mod, proc, &_deliver);
		}
		catch (PipeException e) {
			// exception probably means there was no more output
		}
	}


	private {
		Set!string addresses_;
		GameConfig game_;
		MasterList master_;
		bool replace_;
	}
}



/** Kill the command line server browser process
 *
 * Returns: true if the process was running, false if not.
 */
bool killServerBrowser()
{
	if (proc is null /*|| !proc.isRunning*/)
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
