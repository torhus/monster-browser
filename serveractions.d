module serveractions;

import tango.core.Memory;
import tango.core.Thread;
import tango.io.File;
import tango.io.FilePath;
debug import tango.io.Stdout;
import tango.text.convert.Integer;

import dwt.dwthelper.Runnable;

import common;
import main;
import qstat;
import runtools;
import serverlist;
import servertable;
import settings;


/**
 * Takes care of the serverList and activeMod side of switching mods.
 *
 * Makes sure that serverList and activeMod contains the data for the given
 * mod.  Calls switchToActiveMod, switchToActiveMod, or getNewList as needed.
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
			if (common.useGslist)
				getNewList();
			else if (FilePath(activeMod.serverFile).exists)
				refreshList();
			else
				getNewList();
		}
	}

	nameCopy = name;
	threadDispatcher.run(&f);

	/*if (setActiveServerList(activeMod.name)) {
		threadDispatcher.run(&switchToActiveMod);
	}
	else {
		if (common.useGslist)
			threadDispatcher.run(&getNewList);
		else if (exists(activeMod.serverFile))
			threadDispatcher.run(&refreshList);
		else
			threadDispatcher.run(&getNewList);
	}*/
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
	void f()
	{
		void callback(Object int_count)
		{
			statusBar.setLeft("Loading saved server list... " ~
			                  toString((cast(IntWrapper) int_count).value));
		}

		try {
			browserLoadSavedList(&callback);
			volatile if (!runtools.abortParsing) {
				version (Tango) {
					display.asyncExec(new class Runnable {
						void run() { serverTable.reset(); }
				    });
				}
				else {
					display.asyncExec(null, delegate void (Object o) {
					                            serverTable.reset();
					                        });
				}
			}
		}
		catch(Exception e) {
			logx(__FILE__, __LINE__, e);
		}
	}

	assert(serverThread is null || !serverThread.isRunning);

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

	void f()
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

			version (Tango) {
				volatile if (!runtools.abortParsing) {
					display.asyncExec(new class Runnable {
						void run() { done(null); }
					});
				}
			}
			else {
				volatile if (!runtools.abortParsing) {
					display.asyncExec(null, &done);
				}
			}

		}
		catch(Exception e) {
			logx(__FILE__, __LINE__, e);
		}
	}

	assert(serverThread is null || !serverThread.isRunning);

	File(REFRESHFILE).write(address ~ newline);

	addressCopy = address.dup;

	statusBar.setLeft("Querying server...");

	serverThread = new Thread(&f);
	serverThread.start();
}


/** Retrieves a new list from the master server. */
void getNewList()
{
	void f()
	{
		int serverCount = -1;
		static char[] total;

		void status(Object int_count)
		{
			statusBar.setLeft("Got " ~  total ~ " servers, querying..." ~
			                  toString((cast(IntWrapper)int_count).value));
		}

		try {
			serverCount = browserGetNewList();
			total = toString(serverCount);
			debug Stdout("serverCount = ")(total).newline;

			if (serverCount >= 0) {
				version (Tango) {
					display.asyncExec(new class Runnable {
						void run() { statusBar.setLeft("Got "  ~
					                          total ~ " servers, querying...");
				        }
				    });
				}
				else {
				    display.asyncExec(null, delegate void (Object o) {
					                        statusBar.setLeft("Got "  ~
					                              total ~ " servers, querying...");
				                        } );
				}

				browserRefreshList(&status, true, true);
				volatile if (!runtools.abortParsing) {
					version (Tango) {
						display.asyncExec(new class Runnable {
							void run() { serverTable.reset(); }
					    });
					}
					else {

					    display.asyncExec(null, delegate void (Object o) {
					                                serverTable.reset();
					                            });
					}
				}
			}
		}
		catch(Exception e) {
			logx(__FILE__, __LINE__, e);
		}

	}

	assert(serverThread is null || !serverThread.isRunning);

	getActiveServerList.clear();
	serverTable.refresh();

	GC.collect();
	statusBar.setLeft("Getting new server list...");
	serverThread = new Thread(&f);
	serverThread.start();
}


/** Refreshes the list. */
void refreshList()
{
	static uint total;
	static char[] totalStr;

	void f()
	{
		static char[] statusMsg;

		void status(Object int_count)
		{
			assert(statusMsg !is null);
			statusBar.setLeft(statusMsg ~
			                  toString((cast(IntWrapper)int_count).value));
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
			statusMsg = "Refreshing " ~  totalStr ~ " servers...";
			browserRefreshList(&status);
			version (Tango) {
				volatile if (!runtools.abortParsing) {
					display.asyncExec(new class Runnable {
						void run() { done(null); }
					});
				}
			}
			else {
				volatile if (!runtools.abortParsing) {
					display.asyncExec(null, &done);
				}
			}
		}
		catch(Exception e) {
			logx(__FILE__, __LINE__, e);
		}
	}

	assert(serverThread is null || !serverThread.isRunning);

	total = filterServerFile(activeMod.serverFile, REFRESHFILE).length;
	totalStr = toString(total);
	statusBar.setLeft("Refreshing " ~ totalStr ~ " servers...");
	getActiveServerList.clear();
	serverTable.refresh();

	GC.collect();
	serverThread = new Thread(&f);
	serverThread.start();
}
