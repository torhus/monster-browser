module serverlist;

private {
	import std.string;
	import std.stdio;
	import std.thread;
	import std.file;
	import std.conv;
	import std.gc;
	import std.c.string;

	import dwt.all;
	import common;
	import main;
	import servertable;
	import parselist;
	import qstat;
}


const char[][] defaultGameTypes = ["FFA", "1v1", "SP", "TDM", "CTF",
                                   /* "OFCTF", "Overload", "Harvester", */
                                  ];

char[][][char[]] gameTypes;

static this() {
	gameTypes["osp"] = split("FFA 1v1 SP TDM CTF CA");
	gameTypes["q3ut3"] = split("FFA FFA FFA TDM TS FtL C&H CTF B&D");
	gameTypes["q3ut4"] = split("FFA FFA FFA TDM TS FtL C&H CTF B&D");
	gameTypes["westernq3"] = split("FFA Duel 2 TDM RTP BR");
	gameTypes["wop"] = split("FFA 1v1 2 SyC LPS TDM 6 SyCT BB");
}

// should correspond to playertable.playerHeaders
enum PlayerColumn { NAME, SCORE, PING };
// should correspond to servertable.serverHeaders
enum ServerColumn { NAME, PASSWORDED, PING, PLAYERS, GAMETYPE, MAP, ADDRESS };

private {
	ServerList activeServerList;
	ServerList[char[]] serverLists;
}


/** Stores all data for a server. */
struct ServerData {
	/// name, ping, playercount, map, etc.
	char[][] server;
	/// list of players, with name, score and ping for each
	char[][][] players;
	/// list of cvars, with key and value for each
	char[][][] cvars;

	/// Compares according to activeServerList's settings.
	int opCmp(ServerData other)
	{
		int result = 0;

		switch (activeServerList.sortColumn_) {
			case ServerColumn.PLAYERS:
				int a, b;

				a = humanCount;
				b = other.humanCount;
				assert (a >= 0 && b >= 0);
				if (a || b) {
					result = b - a;
					break;
				}

				a = botCount;
				b = other.botCount;
				assert (a >= 0 && b >= 0);
				if (a || b) {
					result = b - a;
					break;
				}

				a = maxClients;
				b = other.maxClients;
				assert (a >= 0 && b >= 0);
				if (a || b) {
					result = b - a;
					break;
				}

				break;

			case ServerColumn.PING:
				result = std.conv.toInt(server[activeServerList.sortColumn_]) -
				          std.conv.toInt(other.server[activeServerList.sortColumn_]);
				break;

			default:
				result = std.string.icmp(server[activeServerList.sortColumn_],
				                       other.server[activeServerList.sortColumn_]);
		}

		return (activeServerList.reversed_ ? -result : result);
	}


	/// Extract some info about the server.
	int humanCount()
	{
		char[] s = server[ServerColumn.PLAYERS];
		return std.conv.toInt(s[0..find(s, '+')]);
	}

	/// ditto
	int botCount()
	{
		char[] s = server[ServerColumn.PLAYERS];
		return std.conv.toInt(s[find(s, '+')+1 .. find(s, "/")]);
	}

	/// ditto
	int maxClients()
	{
		char[] s = server[ServerColumn.PLAYERS];
		return std.conv.toInt(s[find(s, "/")+1 .. length]);
	}

	/// ditto
	bool hasHumans() { return server[ServerColumn.PLAYERS][0] != '0'; }

	/// ditto
	bool hasBots()
	{
		char[] s = server[ServerColumn.PLAYERS];
		return (s[find(s, '+')+1] != '0');
	}
}


/** A list of servers. */
class ServerList
{
	/**
	 * true if list contains all servers for the mod, that replied when queried.
	 * Meaning that the server querying process was not interrupted.
	 */
	bool complete = false;


	///
	void add(ServerData* sd)
	{
		bool refresh = false;
		int index;

		synchronized {
			isSorted_ = false;
			list ~= *sd;
			if (!isFilteredOut(sd)) {
				index = _insertSorted(&list[$ - 1]);
				refresh = true;
			}
		}
		if (refresh)
			display.syncExec(new IntWrapper(index), &serverTable.refresh);
	}


	/// Iterate over the full list.
	synchronized
	int opApply(int delegate(inout ServerData) dg)
	{
		int result = 0;

		foreach(ServerData sd; list) {
			result = dg(sd);
			if (result) {
				break;
			}
		}
		return result;
	}


	/// Return a server from the filtered list
	synchronized
	ServerData* getFiltered(int i)
	{
		return filteredList[i];
	}


	/**
	 * Given the IP and port number, find a server in the full list.
	 *
	 * Does a linear search.
	 *
	 * Returns: the server's index, or -1 if not found.
	 */
	synchronized
	int getIndex(char[] ipAndPort)
	{
		if (!ipAndPort)
			return -1;

		foreach (int i, inout ServerData sd; list) {
			if (sd.server[ServerColumn.ADDRESS] == ipAndPort)
				return i;
		}
		return -1;
	}


	/**
	 * Given the IP and port number, find a server in the filtered list.
	 *
	 * Does a linear search.
	 *
	 * Returns: the server's index, or -1 if not found.
	 */
	synchronized
	int getFilteredIndex(char[] ipAndPort)
	{
		if (!ipAndPort)
			return -1;

		foreach (int i, ServerData* sd; filteredList) {
			if (sd.server[ServerColumn.ADDRESS] == ipAndPort)
				return i;
		}
		return -1;
	}


	synchronized size_t filteredLength() { return filteredList.length; } ///
	synchronized size_t length() { return list.length; } /// ditto


	/**
	 * Clears the list and the filtered list.  Sets complete to false.
	 */
	synchronized
	ServerList clear()
	{
		//filteredList.length = 0;
		//list.length = 0;
		delete filteredList;
		delete list;
		complete = false;

		return this;
	}


	/**
	 * Add an extra server to be included when doing a refresh.
	 *
	 * Useful for servers that are not on the master server's list.  Multiple
	 * servers can be added this way.
	 */
	void addExtraServer(in char[] address)
	{
		// FIXME: avoid adding a server twice
		extraServers_ ~= address;
	}


	/// Returns the list of extra servers.  Please don't change it.
	// FIXME: This should probably return a const ref in D 2.0.
	char[][] extraServers() { return extraServers_; }


	/**
	 * Sort the full list, then update the filtered list.
	 *
	 * Uses the previously selected _sort order, or the default
	 * if there is none.
	 */
	synchronized
	void sort() { _sort(); updateFilteredList(); }


	/**
	 * Like sort(), but lets you spesify _sort _column and order.
	 *
	 * The given _sort _column and order will be used for all subsequent
	 * sorting, until new values are given.
	 */
	synchronized
	void sort(int column, bool reversed=false)
	{
		setSort(column, reversed);
		_sort();
		updateFilteredList();
	}


	/** Filter Controls */
	void filterNotEmpty(bool enable)
	{
		if (enable == filters_.notEmpty)
			return;

		synchronized {
			filters_.notEmpty = enable;
			updateFilteredList();
		}
		display.asyncExec(null, &serverTable.reset);
	}


	/// ditto
	void filterHasHumans(bool enable)
	{
		if (enable == filters_.hasHumans)
			return;

		synchronized {
			filters_.hasHumans = enable;
			updateFilteredList();
		}
		display.asyncExec(null, &serverTable.reset);
	}

/***********************************************************************
 *                                                                     *
 *                        PRIVATE SECTION                              *
 *                                                                     *
 ***********************************************************************/
private:
	ServerData[] list;
	ServerData*[] filteredList;
	char[][] extraServers_;

	int sortColumn_ = ServerColumn.NAME;
	int oldSortColumn_ = -1;
	bool reversed_ = false;
	bool isSorted_= false;

	struct Filters {
		bool notEmpty = false;
		bool hasHumans = false;
	};
	Filters filters_;

	synchronized invariant
	{
		if (filteredList.length > list.length) {
			error("filteredlist.length == ", filteredList.length,
			              "\nlist.length == ", list.length);
			assert(0);
		}
		if (!(filters_.hasHumans || filters_.notEmpty ||
		           filteredList.length == list.length ||
		           filteredList.length == (list.length - 1))) {
			error("ServerList invariant broken!\n",
			              "\nfilters_.hasHumans: ", filters_.hasHumans,
			              "\nfilters_.notEmpty: ", filters_.notEmpty,
			              "\nlist.length: ", list.length,
			              "\nfilteredList.length: ", filteredList.length);
			assert(0);
		}
	}


	/// Updates sort column and order for the main list.
	void setSort(int column, bool reversed=false)
	{
		assert(column >= 0 && column <= ServerColumn.max);
		oldSortColumn_ = sortColumn_;
		sortColumn_ = column;
		if (reversed != reversed_) {
			reversed_ = reversed;
			isSorted_ = false;
		}
	}


	/// Sorts the main list, doesn't touch the filtered list.
	void _sort()
	{
		debug scope timer = new Timer;

		if (!isSorted_ || sortColumn_ != oldSortColumn_) {
			mergeSort(list);
			isSorted_ = true;
		}

		debug log("ServerList._sort() took " ~
		          std.string.toString(timer.millis) ~ " milliseconds.");
	}

	/**
	 * Insert a server in sorted order in the filtered list.
	 *
	 *  FIXME: doesn't always sort right.
	 */
	int _insertSorted(ServerData* sd)
	{
		bool less(ServerData* a, ServerData* b)
		{
			return (*a < *b);
		}

		bool greaterOrEq(ServerData* a, ServerData* b)
		{
			return (*a >= *b);
		}

		int index;

		if (filteredList.length == 0) {
			index = filteredList.length;
			appendToFiltered(sd);
		}
		else if (filteredList.length == 1) {
			if (less(sd, filteredList[0])) {
				index = 0;
				insertInFiltered(0, sd);
			}
			else {
				index = filteredList.length;
				appendToFiltered(sd);
			}
		}
		else {
			int i = filteredList.length / 2;
			int delta = i;
			if (delta < 1) delta = 1;
			for (;;) {
				if (delta > 1) {
					delta /= 2;
				}
				if (less(sd, filteredList[i])) {
					if (i == 0) {
						index = 0;
						insertInFiltered(0, sd);
						break;
					}
					else if (greaterOrEq(sd, filteredList[i-1])) {
						index = i;
						insertInFiltered(i, sd);
						break;
					}
					else {
						i -= delta;
					}
				}
				else {
					assert(i <= filteredList.length);
					if (i == filteredList.length - 1) {
						index = filteredList.length;
						appendToFiltered(sd);
						break;
					}
					else if (i == filteredList.length - 2) {
						if (greaterOrEq(sd, filteredList[i])) {
							index = filteredList.length;
							appendToFiltered(sd);
						}
						else {
							index = i;
							insertInFiltered(i, sd);
						}
						break;
					}
					else {
						i += delta;
					}
				}
			}
		}

		return index;
	}

	void insertInFiltered(size_t index, ServerData* sd)
	{
		assert (index < filteredList.length);

		filteredList.length = filteredList.length + 1;
		memmove(filteredList.ptr + index + 1, filteredList.ptr + index,
		           (filteredList.length - 1 - index) * filteredList[0].sizeof);
		filteredList[index] = sd;
	}

	void appendToFiltered(ServerData* psd)
	{
		filteredList ~= psd;
	}

	void copyListToFilteredList()
	{
		filteredList.length = list.length;
		for (size_t i; i < list.length; i++) {
			filteredList[i] = &list[i];
		}
	}

	bool isFilteredOut(ServerData* sd)
	{
		if (!(filters_.hasHumans || filters_.notEmpty))
			return false;
		if (filters_.hasHumans && !sd.hasHumans)
			return true;
		if (filters_.notEmpty && !(sd.hasHumans || sd.hasBots))
			return true;

		return false;
	}

	/**
	 * Clear the filtered list and refill it with the contents of the full
	 * list, except servers that are filtered out.
	 *
	 * Will if necessary sort the full list before using it.
	 */
	void updateFilteredList()
	{
		if (!isSorted_) {
			_sort();
		}
		filteredList.length = 0;
		if (filters_.hasHumans) {
			for (size_t i = 0; i < list.length; i++) {
				if (list[i].hasHumans) {
					filteredList ~= &list[i];
				}
			}
		}
		else if (filters_.notEmpty) {
			for (size_t i = 0; i < list.length; i++) {
				if (list[i].hasBots || list[i].hasHumans) {
					filteredList ~= &list[i];
				}
			}
		}
		else {
			copyListToFilteredList();
		}
	}

	/// Prints the filtered list and its length to stdout.
	debug void printFiltered()
	{
		writefln("printFiltered(): ", filteredList.length,
		                              " elements in filteredList.");
		foreach (i, ServerData* sd; filteredList) {
			writefln(/*i, ": ",*/ sd.server[ServerColumn.NAME]);
		}
		writefln();
	}

	/// Prints the full list and its length to stdout.
	debug void printList()
	{
		writefln("printList(): ", list.length, " elements in full list.");
		int i = 0;
		foreach (ServerData sd; list) {
			writefln(/*i++, ": ",*/ sd.server[ServerColumn.NAME]);
		}
		writefln();
	}
}


/**
 * Sets the activeServerList global to refer to the ServerList object
 * for the mod given by modName.
 *
 * If there is no ServerList object for the given mod, one will be created.
 *
 * Returns:  true if the mod already had a ServerList object, false if a new
 *           one had to be created.  Also returns false if the object exists,
 *           but contains an incomplete list.
 *
 * Throws: OutOfMemoryError
 */
bool setActiveServerList(char[] modName)
{
	bool retval;
	bool saved_hasHumans = false, saved_notEmpty = false;

	// hack to get the correct filtering set up for the new list,
	// save the old one here for later use
	if (activeServerList !is null) {
		saved_hasHumans = activeServerList.filters_.hasHumans;
		saved_notEmpty = activeServerList.filters_.notEmpty;
	}

	if (ServerList* slist = modName in serverLists) {
		activeServerList = *slist;
		retval = slist.complete;
	}
	else {
		activeServerList = new ServerList;
		serverLists[modName] = activeServerList;
		retval = false;
	}

	activeServerList.filters_.notEmpty = saved_notEmpty;
	activeServerList.filters_.hasHumans = saved_hasHumans;

	// to avoid triggering the invariant later
	activeServerList.updateFilteredList();

	auto sortCol = serverTable.getTable.getSortColumn();
	synchronized (activeServerList) {
		activeServerList.setSort(serverTable.getTable.indexOf(sortCol),
	                      (serverTable.getTable.getSortDirection() == DWT.DOWN));
	}

	return retval;
}

ServerList getActiveServerList() { return activeServerList; }


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
			// FIXME: only needed because ServerList._insertSorted() is
			// unreliable
			getActiveServerList.sort();
			volatile if (!parselist.abortParsing) {
				display.asyncExec(null, delegate void (Object o) {
				                            serverTable.reset();
				                        } );
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
			// FIXME: only needed because ServerList._insertSorted() is unreliable
			getActiveServerList.sort();
			volatile if (!parselist.abortParsing) {
				display.asyncExec(null, &done);
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
				display.asyncExec(null, delegate void (Object o) {
				                        statusBar.setLeft("Got "  ~
				                              total ~ " servers, querying...");
			                        } );

				browserRefreshList(&status, true, true);
				// FIXME: only needed because ServerList._insertSorted() is unreliable
				getActiveServerList.sort();
				volatile if (!parselist.abortParsing) {
					display.asyncExec(null, delegate void (Object o) {
					                            serverTable.reset();
					                        } );
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
			// FIXME: only needed because ServerList._insertSorted() is unreliable
			getActiveServerList.sort();
			volatile if (!parselist.abortParsing) {
				display.asyncExec(null, &done);
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

/**
 * Make the serverTable display the server list contained by activeServerList.
 *
 * Useful for updating the display after calling setActiveServerList.
 */
void switchToActiveMod()
{
	//activeServerList.clear();
	//serverTable.refresh();

	//getActiveServerList.filters_.notEmpty = saved_notEmpty;
	//getActiveServerList.filters_.hasHumans = saved_hasHumans;

	// need to do this, to avoid asserting in the invariant
	// FIXME: find a way to avoid this, as the sort() call below also
	// calls updateFilteredList()
	//getActiveServerList.updateFilteredList();

	/*auto sortCol = serverTable.getTable.getSortColumn();
	getActiveServerList.sort(serverTable.getTable.indexOf(sortCol),
	                      (serverTable.getTable.getSortDirection() == DWT.DOWN));*/
	getActiveServerList.sort();

	serverTable.reset();
	statusBar.setDefaultStatus(getActiveServerList.length,
			                   getActiveServerList.filteredLength);
}
