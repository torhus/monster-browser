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
import servertable;
import set;
import settings;


Process proc;


/// The name of the file that qstat reads addresses from when querying servers.
char[] REFRESHFILE = "refreshlist.tmp";


/**
 * Run qstat or gslist (determined by the haveGslist variable) to retrieve a
 * list of servers from the active mod's master server.
 *
 * Returns: A set containing the IP addresses of the servers.
 */
Set!(char[]) browserGetNewList()
{
	char[] cmdLine;
	size_t count = -1;
	Set!(char[]) addresses;
	bool gslist = common.haveGslist && activeMod.useGslist;

	if (gslist)
		cmdLine = "gslist -n quake3 -o 5";
	else
		cmdLine = "qstat -q3m,68,outfile " ~ activeMod.masterServer ~ ",-";

	version (linux)
		cmdLine = "./" ~ cmdLine;

	if (gslist && MOD_ONLY && activeMod.name!= "baseq3")
		cmdLine ~= " -f \"(gametype = \'" ~ activeMod.name ~ "\'\")";

	proc = new Process();
	proc.workDir = appDir;
	//scope (exit) if (proc) proc.wait();

	try {
		log("Executing '" ~ cmdLine ~ "'.");
		proc.execute(cmdLine, null);
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


///
interface IServerRetriever
{
	/**
	 * Will be called after serverThread and qstat has terminated, but before
	 * the new thread is created.
	 *
	 * Use for doing initialization, if needed.
	 */
	void init();


	/**
	 * Will be called in the new thread, just before inputStream.
	 *
	 * Use for setting up the InputStream, etc.
	 *
	 * Returns: The number of servers to be queried, for display in the GUI.
     *          Return 0 to abort the retrieval process.  Return -1 if the
	 *          number of servers is not known.  Returning -1 will not abort
	 *          the process.
	 */
	int open();


	/**
	 * This will be handed to qstat.parseOutput as the source of input.
	 */
	InputStream inputStream();


	/**
	 * This will be handed to qstat.parseOutput as the optional output file.
	 */
	char[] outputFile();


	/**
	 * This will be called after qstat.parseOutput is done, still in the new
	 * thread.
	 */
	void close();
}


///
final class FromFileServerRetriever : IServerRetriever
{

	///
	this(in char[] fileName)
	{
		fileName_ = fileName;
	}

	///
	void init()	{ }


	///
	int open()
	{
		try {
			input_ = new TextFileInput(fileName_);
		}
		catch (IOException o) {
			warning("Unable to load the server list from disk,\n"
				  "press \'Get new list\' to download a new list.");
			return 0;
		}
		return -1;
	}


	///
	InputStream inputStream()
	{
		return input_;
	}


	///
	char[] outputFile() { return outputFile_; }


	///
	void close()
	{
		input_.close();
	}
	

	private {
		InputStream input_;
		char[] fileName_;
		char[] outputFile_;
	}
}


///
final class QstatServerRetriever : IServerRetriever
{
	///
	this(in char[][] addresses, bool saveList=false)
	{
		addresses_ = addresses;
		outputFile_ = saveList ? "servers.tmp" : null;
	}


	///
	void init()
	{
		// FIXME: check if this code could be moved into open()
		if (Path.exists(appDir ~ REFRESHFILE))
			Path.remove(appDir ~ REFRESHFILE);
		serverCount_ = appendServersToFile(appDir ~ REFRESHFILE,
		                                             Set!(char[])(addresses_));
		log(Format("Wrote {} addresses to {}.", serverCount_, REFRESHFILE));
	}


	///
	int open()
	{
		proc = new Process();
		proc.workDir = appDir;
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
			return 0;
		}
		
		//proc.stdout.close();  FIXME: any point to this?

		return serverCount_;
	}


	///
	InputStream inputStream()
	{
		// FIXME: verify that everything is initialized correctly, and that
		// stdout is valid
		return proc.stdout;
	}


	///
	char[] outputFile() { return outputFile_; }


	///
	void close()
	{
		if (!outputFile_.length)
			return;

		if (getActiveServerList.complete) {
			try {
				auto serverFile = activeMod.serverFile;
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
		char[][] addresses_;
		int serverCount_;
		char[] outputFile_;
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
