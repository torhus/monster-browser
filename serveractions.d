module serveractions;

import std.file;
import std.gc;
import std.stdio;
import std.string;
import std.thread;

version (Windows) { }
else
	import dwt.dwthelper.Runnable;


import common;
import main;
import qstat;
import runtools;
import serverlist;
import servertable;
import settings : setActiveMod, activeMod;


/**
 * Takes care of the serverList and activeMod side of switching mods.
 *
 * Makes sure that serverList and activeMod contains the data for the given
 * mod.  Calls switchToActiveMod, switchToActiveMod, or getNewList as needed.
 */
void switchToMod(char[] name)
{
	// FIXME: race condition if qstat.Parseoutput calls Serverlist.add
	// between the call to setActiveServerList and that threadDispatcher
	// calls its argument?  What about setActiveMod?

	setActiveMod(name);

	if (setActiveServerList(activeMod.name)) {
		threadDispatcher.run(&switchToActiveMod);
	}
	else {
		if (common.useGslist)
			threadDispatcher.run(&getNewList);
		else if (exists(activeMod.serverFile))
			threadDispatcher.run(&refreshList);
		else
			threadDispatcher.run(&getNewList);
	}
}


/**
 * Make the serverTable display the server list contained by activeServerList.
 *
 * Useful for updating the display after calling setActiveServerList.
 */
private void switchToActiveMod()
{
	getActiveServerList.sort();

	serverTable.reset();
	statusBar.setDefaultStatus(getActiveServerList.length,
			                   getActiveServerList.filteredLength);
}


/** Loads the list from disk. */
void loadSavedList()
{
	int f()
	{
		void callback(Object int_count)
		{
			statusBar.setLeft("Loading saved server list... " ~
			          std.string.toString((cast(IntWrapper) int_count).value));
		}

		try {
			browserLoadSavedList(&callback);
			volatile if (!runtools.abortParsing) {
				version (Windows) {
					display.asyncExec(null, delegate void (Object o) {
					                            serverTable.reset();
					                        });
				}
				else {				
					display.asyncExec(new class Runnable {
						void run() { serverTable.reset(); }
				    });
				}
			}
		}
		catch(Exception e) {
			logx(__FILE__, __LINE__, e);
		}
		return 0;
	}

	assert(serverThread is null ||
	                   serverThread.getState() == Thread.TS.TERMINATED);

	statusBar.setLeft("Loading saved server list...");
	serverThread = new Thread(&f);
	serverThread.start();
}


/**
 * Queries a single server, adds it to the active server list, and refreshes
 * the serverTable to make it show up.
 *
 * The querying is done in a new thread.  The function does not verify that the
 * address is valid.
 */
void queryAndAddServer(in char[] address)
{
	static char[] addressCopy;

	int f()
	{
		void done(Object)
		{
			if (getActiveServerList.length() > 0) {
				serverTable.reset(new IntWrapper(
				                       getActiveServerList.getFilteredIndex(addressCopy)));
			}
			else {
				statusBar.setLeft("Nothing to refresh");
			}
		}

		try {
			browserRefreshList(delegate void(Object) { }, false);

			version (Windows) {
				volatile if (!runtools.abortParsing) {
					display.asyncExec(null, &done);
				}
			}
			else {
				volatile if (!runtools.abortParsing) {
					display.asyncExec(new class Runnable {
						void run() { done(null); }
					});
				}
			}

		}
		catch(Exception e) {
			logx(__FILE__, __LINE__, e);
		}
		return 0;
	}

	assert(serverThread is null ||
	                   serverThread.getState() == Thread.TS.TERMINATED);

	write(REFRESHFILE, address ~ newline);

	addressCopy = address.dup;

	statusBar.setLeft("Querying server...");

	serverThread = new Thread(&f);
	serverThread.start();
}


/** Retrieves a new list from the master server. */
void getNewList()
{
	int f()
	{
		int serverCount = -1;
		static char[] total;

		void status(Object int_count)
		{
			statusBar.setLeft("Got " ~  total ~ " servers, querying..." ~
			          std.string.toString((cast(IntWrapper) int_count).value));
		}

		try {
			serverCount = browserGetNewList();
			total = std.string.toString(serverCount);
			debug writefln("serverCount = ", total);

			if (serverCount >= 0) {
				version (Windows) {
					display.asyncExec(null, delegate void (Object o) {
					                        statusBar.setLeft("Got "  ~
					                              total ~ " servers, querying...");
				                        } );
				}
				else {
					display.asyncExec(new class Runnable {
						void run() { statusBar.setLeft("Got "  ~
					                          total ~ " servers, querying...");
				        }
				    });
				        
				}

				browserRefreshList(&status, true, true);
				volatile if (!runtools.abortParsing) {
					version (Windows) {
						display.asyncExec(null, delegate void (Object o) {
					                                serverTable.reset();
					                            });
					}
					else {				
						display.asyncExec(new class Runnable {
							void run() { serverTable.reset(); }
					    });
					}
				}
			}
		}
		catch(Exception e) {
			logx(__FILE__, __LINE__, e);
		}

		return 0;
	}

	assert(serverThread is null ||
	                   serverThread.getState() == Thread.TS.TERMINATED);

	getActiveServerList.clear();
	serverTable.refresh();

	fullCollect();
	statusBar.setLeft("Getting new server list...");
	serverThread = new Thread(&f);
	serverThread.start();
}


/** Refreshes the list. */
void refreshList()
{
	int f()
	{
		static char[] total;

		void status(Object int_count)
		{
			statusBar.setLeft("Refreshing " ~  total ~ " servers..." ~
			          std.string.toString((cast(IntWrapper) int_count).value));
		}

		void done(Object o)
		{
			if (getActiveServerList.length() > 0) {
				serverTable.reset();
			}
			else {
				statusBar.setLeft("Nothing to refresh");
			}
		}

		try {
			total = std.string.toString(countServersInRefreshList());
			browserRefreshList(&status);
			version (Windows) {
				volatile if (!runtools.abortParsing) {
					display.asyncExec(null, &done);
				}
			}
			else {
				volatile if (!runtools.abortParsing) {
					display.asyncExec(new class Runnable {
						void run() { done(null); }
					});
				}
			}
		}
		catch(Exception e) {
			logx(__FILE__, __LINE__, e);
		}
		return 0;
	}

	assert(serverThread is null ||
	                   serverThread.getState() == Thread.TS.TERMINATED);

	//if (!exists(REFRESHFILE)) {
		qstat.saveRefreshList();
	//}
	statusBar.setLeft("Refreshing " ~
	         std.string.toString(countServersInRefreshList()) ~ " servers...");
	getActiveServerList.clear();
	serverTable.refresh();

	fullCollect();
	serverThread = new Thread(&f);
	serverThread.start();
}
