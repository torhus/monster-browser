/**
 * Functions for running qstat and capturing its output
 */

module runtools;

import tango.core.Exception : IOException, ProcessException;
import tango.io.device.File;
import tango.io.model.IConduit;
import tango.io.stream.Lines;
import tango.sys.Process;
import tango.text.Ascii;
import tango.text.Util;
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
private Object procMutex;


/// Thrown if there's an error when communicating with a master server.
class MasterServerException : Exception {
	this(char[] msg) { super(msg); }
}


void runtoolsInit()
{
	procMutex = new Object;
}


/**
 * Run qstat to retrieve a list of servers from the game's master
 * server.
 *
 * Returns: A set containing the IP addresses of the servers.
 *
 * Throws: MasterServerException.
 */
Set!(char[]) browserGetNewList(in GameConfig game)
{
	char[] cmdLine;
	Set!(char[]) addresses;
	InputStream stdout_copy, stderr_copy;

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
			proc = new Process(true, cmdLine);
			proc.workDir = appDir;
			proc.gui = true;
			log("Executing '" ~ cmdLine ~ "'.");
			proc.execute();
			// Copy these in case proc is null when we try to use them later.
			stdout_copy = proc.stdout;
			stderr_copy = proc.stderr;
		}
	}
	catch (ProcessException e) {
		error("qstat not found! Please reinstall " ~ APPNAME ~ ".");
		logx(__FILE__, __LINE__, e);
		synchronized (procMutex) {
			proc = null;
		}
	}

	if (proc) {
		try {
			auto lines = new Lines!(char)(stdout_copy);
			size_t start = "q3s ".length;

			lines.next();

			char[] line1 = lines.get().dup;
			char[] line2 = lines.next();
			throwIfQstatError(line1, line2, stderr_copy, game);

			do {
				char[] line = lines.get();
				if (start >= line.length)
					continue;

				line = line[start..$];
				if (isValidIpAddress(line))
					addresses.add(line.dup);
			} while (lines.next());
		}
		catch (IOException e) {
			//logx(__FILE__, __LINE__, e);
		}
	}

	return addresses;
}


private void throwIfQstatError(in char[] line1, in char[] line2,
                               InputStream stderr, in GameConfig game)
{
	if (!line1.startsWith("ADDRESS")) {
		char[] error = cast(char[])stderr.load();
		if (error.length)
			throw new MasterServerException(trim(error));
		else
			throw new MasterServerException("Unknown Qstat error");
	}

	if (line2.startsWithNoCase(game.qstatMasterServerType)) {
		char[][] parts = split(line2, " ");

		if (parts.length > 2) {
			char[] s = trim(join(parts[1..$], " "));
			throw new MasterServerException(s);
		}
		else {
			throw new MasterServerException("Unrecognized error: \"" ~
			                                        trim(line2) ~ "\"");
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

			cmdLine ~= " -maxsim " ~
			            Integer.toString(getSettingInt("simultaneousQueries"));

			synchronized (procMutex) {
				proc = new Process(true, cmdLine);
				proc.workDir = appDir;
				proc.gui = true;
				log("Executing '" ~ cmdLine ~ "'.");
				proc.execute();
				// Copy stdout in case proc is null when we try to access it
				// later.
				stdout_copy_ = proc.stdout;
			}

			if (arguments.dumplist)
				dumpFile = new File("refreshlist.tmp", File.WriteCreate);

			synchronized (procMutex) {
				if (proc) {
					foreach (address; addresses_) {
						proc.stdin.write(address);
						proc.stdin.write(newline);
						if (dumpFile) {
							dumpFile.write(address);
							dumpFile.write(newline);
						}
					}
					proc.stdin.flush.close;
				}
			}
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
		scope iter = new Lines!(char)(stdout_copy_);
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
		InputStream stdout_copy_;
	}
}



/** Kill the command line server browser process
 *
 * Returns: true if the process was running, false if not.
 */
bool killServerBrowser()
{
	synchronized (procMutex) {
		if (proc is null)
			return false;

		if (!proc.isRunning) {
			proc = null;
			return false;
		}

		try {
			proc.kill();
			proc = null;
		}
		catch (ProcessException e) {
			// Since isRunning doesn't actually check if the process is still
			// running, this exception will happen all the time.
			//logx(__FILE__, __LINE__, e);
		}
	}
	return true;
}
