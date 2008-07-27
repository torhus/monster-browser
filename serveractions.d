/**
 * Implements the main functionality of the program.  Querying servers, etc.
 */

module serveractions;

import tango.core.Memory;
import tango.core.Thread;
import tango.io.File;
import Path = tango.io.Path;
import tango.io.Stdout;
import tango.text.Util;
import tango.text.convert.Format;
import Integer = tango.text.convert.Integer;

import dwt.dwthelper.Runnable;
import dwt.widgets.Display;

import common;
import main; //: threadDispatcher;
import mainwindow;
import qstat;
import runtools;
import serverlist;
import servertable;
import set;
import settings;


/**
 * Switches the active mod.
 *
 * Takes care of everything, updating the GUI as necessary, querying servers or
 * a master server if there's no pre-existing data for the mod, etc.  Most of
 * the work is done in a new thread.
 */
void switchToMod(char[] name)
{
	static char[] nameCopy;

	static void f() {
		setActiveMod(nameCopy);

		if (setActiveServerList(activeMod.name)) {
			switchToActiveMod();
		}
		else {
			if (common.haveGslist && activeMod.useGslist)
				getNewList();
			else if (Path.exists(activeMod.serverFile))
				refreshList();
			else
				getNewList();
		}
	}

	nameCopy = name;
	threadDispatcher.run(&f);
}


/**
 * Make the serverTable display the server list contained by activeServerList.
 *
 * Useful for updating the display after calling setActiveServerList.
 */
private void switchToActiveMod()
{
	getActiveServerList.sort();

	serverTable.forgetSelection();
	serverTable.reset();
	statusBar.setDefaultStatus(getActiveServerList.length,
	                           getActiveServerList.filteredLength);
}


/** Loads the list from disk, using a new thread to do the work. */
void loadSavedList()
{
	void f()
	{
		scope status = new StatusBarUpdater;

		void counter(int count)
		{
			status.text = "Loading saved server list... " ~
			                                          Integer.toString(count);
			Display.getDefault.syncExec(status);
		}

		try {
			browserLoadSavedList(&counter);

			if (arguments.quit) { // for benchmarking
				Display.getDefault.syncExec(new class Runnable {
					void run()
					{
						Stdout.formatln("Time since startup: {} seconds.",
						                                  globalTimer.seconds);
						mainWindow.close;
					}
				});
			}

			Display.getDefault.asyncExec(new class Runnable {
				void run()
				{
					volatile if (!runtools.abortParsing)
						serverTable.reset;
					serverTable.notifyRefreshEnded;
				}
			});
		}
		catch(Exception e) {
			logx(__FILE__, __LINE__, e);
		}
	}

	assert(serverThread is null || !serverThread.isRunning);

	statusBar.setLeft("Loading saved server list...");
	serverThread = new Thread(&f);
	serverTable.notifyRefreshStarted;
	serverThread.start();
}


/**
 * Queries one or more servers, adds them to the active server list, and
 * refreshes the serverTable to make them show up.
 *
 * If replace is true, it will instead update servers with new data.
 *
 * The querying is done in a new thread.  The function does not verify that the
 * address is valid.
 *
 * Params:
 *     address = IP address and port of servers to query.
 *     replace = Update the servers instead of adding new ones.
 *     select  = Select the newly added or refreshed servers.
 */
void queryServers(in char[][] addresses, bool replace=false, bool select=false)
{
	if (!addresses.length)
		return;

	auto q = new ServerQuery(addresses, replace, select);
	threadDispatcher.run(&q.startQuery);
}


/** Refreshes the list, in a new thread. */
void refreshList()
{
	Set!(char[]) servers = filterServerFile(activeMod.serverFile);

	log("Refreshing server list for " ~ activeMod.name ~ "...");
	char[] tmp;
	char[] sfile = tail(activeMod.serverFile, "/", tmp);
	log(Format("Found {} servers in {}.", servers.length, sfile));

	// merge in the extra servers
	Set!(char[]) extraServers = getActiveServerList.extraServers;
	auto oldLength = servers.length;
	foreach (server; extraServers)
		servers.add(server);

	auto delta = servers.length - oldLength;
	log(Format("Added {} extra servers, skipping {} duplicates.",
	                                        delta, extraServers.length-delta));

	serverTable.clear();
	getActiveServerList.clear();

	if (servers.length) {
		auto q = new ServerQuery(servers.toArray, false, false);
		q.startMessage = Format("Refreshing {} servers...", servers.length);
		q.noReplyMessage = "None of the servers replied.";
		threadDispatcher.run(&q.startQuery);
	}
}


///
class ServerQuery
{
	char[] startMessage = "Querying server(s)...";
	char[] noReplyMessage = "There was no reply.";

	///
	this(in char[][] addresses, bool replace=false, bool select=false)
	{
		addresses_ = addresses;
		replace_ = replace;
		select_ = select;
		statusBarUpdater_ = new StatusBarUpdater;
	}

	~this()
	{
		if (statusBarUpdater_)
			delete statusBarUpdater_;

	}

	///
	void startQuery()
	{
		assert(serverThread is null || !serverThread.isRunning);

		if (Path.exists(REFRESHFILE))
			Path.remove(REFRESHFILE);
		auto written =
		            appendServersToFile(REFRESHFILE, Set!(char[])(addresses_));
		log(Format("Wrote {} addresses to {}.", written, REFRESHFILE));
		serverCount_ = written;

		statusBar.setLeft(startMessage);

		GC.collect;
		serverThread = new Thread(&run);
		serverTable.notifyRefreshStarted;
		serverThread.start();
	}

	private void run()
	{
		try {
			auto deliverDg = replace_ ? &getActiveServerList.replace :
			                            &getActiveServerList.add;
			browserRefreshList(deliverDg, &counter);

			Display.getDefault.asyncExec(new class Runnable {
				void run()
				{
					volatile if (!runtools.abortParsing)
						done;
					else
						serverTable.notifyRefreshEnded;
				}
			});
		}
		catch(Exception e) {
			logx(__FILE__, __LINE__, e);
		}
	}

	private void counter(int count)
	{
		statusBarUpdater_.text = startMessage ~ Integer.toString(count);
		Display.getDefault.syncExec(statusBarUpdater_);
	}

	private void done()
	{
		if (getActiveServerList.length() > 0) {
			IntWrapper index = null;
			if (select_)
				// FIXME: select them all, not just the first one
				index = new IntWrapper(
				          getActiveServerList.getFilteredIndex(addresses_[0]));
			long noReply = cast(long)serverCount_ - getActiveServerList.length;
			serverTable.reset(index, noReply > 0 ? cast(uint)noReply : 0);
		}
		else {
			statusBar.setLeft(noReplyMessage);
		}
		serverTable.notifyRefreshEnded;
	}

	private {
		char[][] addresses_;
		uint serverCount_;
		StatusBarUpdater statusBarUpdater_;
		bool replace_;
		bool select_;
	}
}


/**
 * Retrieves a new list from the master server.
 *
 * Uses a new thread to do the work.
 */
void getNewList()
{
	void f()
	{
		static char[] total;
		scope status = new StatusBarUpdater;

		void counter(int count)
		{
			status.text = "Got " ~  total ~
			                 " servers, querying..." ~ Integer.toString(count);
			Display.getDefault.syncExec(status);
		}

		try {
			auto addresses = browserGetNewList();
			log(Format("Got {} servers from {}.", addresses.length,
			                                          activeMod.masterServer));

			auto extraServers = getActiveServerList().extraServers;
			foreach (s; extraServers)
					addresses.add(s);
			log(Format("Added {} extra servers.", extraServers.length));

			if (Path.exists(REFRESHFILE))
				Path.remove(REFRESHFILE);
			auto written = appendServersToFile(REFRESHFILE, addresses);
			log(Format("Wrote {} addresses to {}.", written, REFRESHFILE));

			total = Integer.toString(written);


			if (addresses.length == 0) {
				// FIXME: what to do when there are no servers?
				Display.getDefault.asyncExec(new class Runnable {
					void run()
					{
						serverTable.reset();
						serverTable.notifyRefreshEnded;
					}
				});
			}
			else {
				Display display = Display.getDefault;
				display.asyncExec(new StatusBarUpdater("Got "  ~
				                             total ~ " servers, querying..."));

				browserRefreshList(&getActiveServerList.add, &counter, true);
				display.asyncExec(new class Runnable {
					void run()
					{
						volatile if (!runtools.abortParsing)
							serverTable.reset;
						serverTable.notifyRefreshEnded;
					}
				});
			}
		}
		catch(Exception e) {
			logx(__FILE__, __LINE__, e);
		}

	}

	assert(serverThread is null || !serverThread.isRunning);

	serverTable.clear();
	getActiveServerList.clear();

	GC.collect();
	statusBar.setLeft("Getting new server list...");
	log("Getting new server list for " ~ activeMod.name ~ "...");
	serverThread = new Thread(&f);
	serverTable.notifyRefreshStarted;
	serverThread.start();
}


private class StatusBarUpdater : Runnable {
	char[] text;

	this(char[] text=null) { this.text = text; }

	void run() { statusBar.setLeft(text); }
}
