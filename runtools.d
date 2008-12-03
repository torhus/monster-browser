/**
 * Functions for running qstat and gslist, while capturing their output
 */

module runtools;

import tango.core.Exception : IOException, ProcessException;
debug import tango.io.Console;
import Path = tango.io.Path;
import tango.io.model.IConduit : InputStream;
import tango.io.stream.TextFileStream;
import tango.sys.Process;
import tango.text.convert.Format;
import Integer = tango.text.convert.Integer;
import tango.text.stream.LineIterator;

import common;
import dialogs;
import qstat;
import serverlist;
import set;
import settings;


private Process proc;


/**
 * Run qstat or gslist (determined by the haveGslist variable) to retrieve a
 * list of servers from the active mod's master server.
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
	if (gslist && MOD_ONLY && game.mod != "baseq3")
		cmdLine ~= " -f \"(gametype = \'" ~ game.mod ~ "\'\")";

	try {
		proc = new Process(cmdLine);
		proc.workDir = appDir;
		log("Executing '" ~ cmdLine ~ "'.");
		proc.execute();
	}
	catch (ProcessException e) {
		char[] s = gslist ? "gslist" : "qstat";
		error(s ~ " not found!\nPlease reinstall " ~ APPNAME ~ ".");
		logx(__FILE__, __LINE__, e);
		proc = null;
	}

	if (proc) {
		try {
			auto lineIter= new LineIterator!(char)(proc.stdout);
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
	 * If deliver's argument is null the server is ignored.  Useful for servers
	 * that timed out.  deliver should still be called, since it's also used
	 * for updating the progress counter.
	 *
	 * If deliver returns false, the server retrieval process is aborted.
	 */
	void retrieve(bool delegate(ServerData*) deliver);

}


///
final class FromFileServerRetriever : IServerRetriever
{

	///
	this(in char[] game)
	{
		GameConfig game_ = getGameConfig(game);
	}


	///
	void initialize() { }


	///
	int prepare()
	{
		try {
			input_ = new TextFileInput(game_.serverFile);
		}
		catch (IOException o) {
			warning("Unable to load the server list from disk,\n"
				  "press \'Get new list\' to download a new list.");
			return 0;
		}
		return -1;
	}


	///
	void retrieve(bool delegate(ServerData*) deliver)
	{
		scope iter = new LineIterator!(char)(input_);
		qstat.parseOutput(game_.name, iter, deliver);
		input_.close();
	}


	private {
		InputStream input_;
		GameConfig game_;
	}
}


///
final class QstatServerRetriever : IServerRetriever
{
	///
	this(in char[] game, Set!(char[]) addresses, bool saveList=false)
	{
		game_ = getGameConfig(game);
		addresses_ = addresses;
		outputFile_ = saveList ? "servers.tmp" : null;
	}


	///
	void initialize()
	{
		// FIXME: check if this code could be moved into prepare()
		if (Path.exists(appDir ~ REFRESHFILE))
			Path.remove(appDir ~ REFRESHFILE);
		serverCount_ = appendServersToFile(appDir ~ REFRESHFILE, addresses_);
		log(Format("Wrote {} addresses to {}.", serverCount_, REFRESHFILE));
	}


	///
	int prepare()
	{
		try {
			char[] cmdLine = "qstat -f " ~ REFRESHFILE ~ " -raw,game " ~ FIELDSEP ~
							  " -P -R -default q3s";
			if (getSetting("coloredNames") == "true")
				cmdLine ~= " -carets";
			version (linux)
				cmdLine = "./" ~ cmdLine;

			proc = new Process(cmdLine);
			proc.workDir = appDir;
			log("Executing '" ~ cmdLine ~ "'.");
			// FIXME: feed qstat through stdin (-f -)?
			proc.execute();
		}
		catch (ProcessException e) {
			error("qstat not found!\nPlease reinstall " ~ APPNAME ~ ".");
			return 0;
		}

		return serverCount_;
	}


	///
	void retrieve(bool delegate(ServerData*) deliver)
	{
		scope iter = new LineIterator!(char)(proc.stdout);
		// FIXME: verify that everything is initialized correctly, and that
		// stdout is valid
		completed_ = qstat.parseOutput(game_.mod, iter, deliver, outputFile_);

		if (outputFile_.length)
			renameOutputFile();
	}


	private void renameOutputFile()
	{
		if (completed_ ) {
			try {
				char[] serverFile = game_.serverFile;
				if (Path.exists(serverFile))
					Path.remove(serverFile);
				Path.rename(outputFile_, serverFile);
			}
			catch (IOException e) {
				warning("Unable to save the server list to disk.");
			}
		}
		else {
			try {
				Path.remove(outputFile_);
			}
			catch (IOException e) {
				warning(e.toString());
			}
		}
	}


	private {
		static const char[] REFRESHFILE = "refreshlist.tmp";

		Set!(char[]) addresses_;
		GameConfig game_;
		int serverCount_;
		char[] outputFile_;
		bool completed_;
	}
}



/** Kill the command line server browser process
 *
 * Returns: true if the process was running, false if not.
 */
bool killServerBrowser()
{
	log("Killing server browser...");

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
