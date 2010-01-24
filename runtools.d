/**
 * Functions for running qstat and gslist, while capturing their output
 */

module runtools;

import tango.core.Exception : IOException, ProcessException;
import tango.io.device.File;
import tango.io.stream.Lines;
import tango.sys.Process;
import tango.text.convert.Format;
import Integer = tango.text.convert.Integer;

import common;
import messageboxes;
import qstat;
import masterlist;
import serverdata;
import set;
import settings;


private Process proc;


/**
 * Run qstat or gslist (determined by the haveGslist variable) to retrieve a
 * list of servers from the game's master server.
 *
 * Returns: A set containing the IP addresses of the servers.
 */
Set!(char[]) browserGetNewList(in GameConfig game)
{
	char[] cmdLine;
	Set!(char[]) addresses;
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
		cmdLine ~= " -f \"(gametype = \'" ~ game.mod ~ "\'\")";

	try {
		proc = new Process(true, cmdLine);
		proc.workDir = appDir;
		proc.gui = true;
		log("Executing '" ~ cmdLine ~ "'.");
		proc.execute();
	}
	catch (ProcessException e) {
		char[] s = gslist ? "gslist" : "qstat";
		error(s ~ " not found! Please reinstall " ~ APPNAME ~ ".");
		logx(__FILE__, __LINE__, e);
		proc = null;
	}

	if (proc) {
		try {
			auto lineIter= new Lines!(char)(proc.stdout);
			size_t start = gslist ? 0 : "q3s ".length;
			addresses = collectIpAddresses(lineIter, start);
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
		catch (IOException o) {
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
		GameConfig game_;
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
	this(in char[] game, MasterList master, Set!(char[]) addresses,
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
			char[] cmdLine = "qstat -f - -raw,game " ~ FIELDSEP ~ " -P -R" ~
			                                                   " -default q3s";
			File dumpFile;

			if (getSetting("coloredNames") == "true")
				cmdLine ~= " -carets";
			version (linux)
				cmdLine = "./" ~ cmdLine;

			cmdLine ~= " -maxsim " ~ getSetting("simultaneousQueries");

			proc = new Process(true, cmdLine);
			proc.workDir = appDir;
			proc.gui = true;
			log("Executing '" ~ cmdLine ~ "'.");
			proc.execute();

			if (arguments.dumplist)
				dumpFile = new File("refreshlist.tmp", File.WriteCreate);

			foreach (address; addresses_) {
				proc.stdin.write(address);
				proc.stdin.write(newline);
				if (dumpFile) {
					dumpFile.write(address);
					dumpFile.write(newline);
				}
			}
			proc.stdin.flush.close;
			log(Format("Fed {} addresses to qstat.", addresses_.length));

			scope (exit) if (dumpFile)
				dumpFile.flush.close;
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
		scope iter = new Lines!(char)(proc.stdout);
		// FIXME: verify that everything is initialized correctly, and that
		// stdout is valid

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

		qstat.parseOutput(game_.mod, iter, &_deliver);
	}


	private {
		Set!(char[]) addresses_;
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
	if (proc is null || !proc.isRunning)
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
