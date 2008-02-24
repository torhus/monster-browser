module serverlist;

private {
	debug import std.stdio;
	import std.c.string;

	import tango.text.Ascii;
	import tango.text.Util;
	import Integer = tango.text.convert.Integer;

	import dwt.DWT;
	import dwt.dwthelper.Runnable;
	import dwt.graphics.TextLayout;

	import common;
	import main;
	import servertable;
	import settings;
	import runtools;
	import qstat;
}


/// Bitflags.
enum Filter { NONE = 0, HAS_HUMANS = 1, NOT_EMPTY = 2 }

const char[][] defaultGameTypes = ["FFA", "1v1", "SP", "TDM", "CTF",
                                   /* "OFCTF", "Overload", "Harvester", */
                                  ];

char[][][char[]] gameTypes;

static this() {
	gameTypes["osp"] = split("FFA 1v1 SP TDM CTF CA", " ");
	gameTypes["q3ut3"] = split("FFA FFA FFA TDM TS FtL C&H CTF B&D", " ");
	gameTypes["q3ut4"] = split("FFA FFA FFA TDM TS FtL C&H CTF B&D", " ");
	gameTypes["westernq3"] = split("FFA Duel 2 TDM RTP BR", " ");
	gameTypes["wop"] = split("FFA 1v1 2 SyC LPS TDM 6 SyCT BB", " ");
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
	/// server name, with any color codes intact
	char[] rawName;
	/// name (without color codes), ping, playercount, map, etc.
	char[][] server;
	/// list of players, with name, score and ping for each
	char[][][] players;
	/// list of cvars, with key and value for each
	char[][][] cvars;

	TextLayout customData = null;

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
				result = Integer.toInt(server[ServerColumn.PING]) -
				         Integer.toInt(other.server[ServerColumn.PING]);
				break;

			default:
				result = icompare(server[activeServerList.sortColumn_],
				                  other.server[activeServerList.sortColumn_]);
		}

		return (activeServerList.reversed_ ? -result : result);
	}


	/// Extract some info about the server.
	int humanCount()
	{
		return Integer.convert(server[ServerColumn.PLAYERS]);
	}

	/// ditto
	int botCount()
	{
		char[] s = server[ServerColumn.PLAYERS];
		return Integer.convert(s[locate(s, '+')+1 .. $]);
	}

	/// ditto
	int maxClients()
	{
		char[] s = server[ServerColumn.PLAYERS];
		return Integer.convert(s[locate(s, '/')+1 .. $]);
	}

	/// ditto
	bool hasHumans() { return server[ServerColumn.PLAYERS][0] != '0'; }

	/// ditto
	bool hasBots()
	{
		char[] s = server[ServerColumn.PLAYERS];
		return (s[locate(s, '+')+1] != '0');
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
			//display.syncExec(new IntWrapper(index), &serverTable.refresh);
			display.syncExec(new class Runnable {
				void run() { serverTable.refresh(new IntWrapper(index)); }
			});
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
		if (getSetting("coloredNames") == "true") {
			foreach (ref sd; list) {
				if (sd.customData)
					sd.customData.dispose();
			}
		}
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


	/// Sets filters and updates the list accordingly.
	void setFilters(Filter newFilters)
	{
		if (newFilters == filters_)
			return;

		synchronized {
			filters_ = newFilters;
			updateFilteredList();
		}
		//display.asyncExec(null, &serverTable.reset);
		display.asyncExec(new class Runnable {
			void run() { serverTable.reset(); }
		});
	}

	Filter getFilters() { return filters_; }



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

	Filter filters_ = Filter.NONE;


	version (Windows)  // DMD bugzilla issue 235
	synchronized invariant()
	{
		if (filteredList.length > list.length) {
			error("filteredlist.length == ", filteredList.length,
			              "\nlist.length == ", list.length);
			assert(0);
		}
		if (!(filters_ || filteredList.length == list.length ||
		                  filteredList.length == (list.length - 1))) {
			error("ServerList invariant broken!\n",
			              "\nfilters_ & Filter.HAS_HUMANS: ", filters_ & Filter.HAS_HUMANS,
			              "\nfilters_ & Filter.NOT_EMPTY: ", filters_ & Filter.NOT_EMPTY,
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
		          Integer.toString(timer.millis) ~ " milliseconds.");
	}

	/**
	 * Insert a server in sorted order in the filtered list.
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

		size_t index;

		if (filteredList.length == 0) {
			index = filteredList.length;
			appendToFiltered(sd);
		}
		else {
			size_t i = filteredList.length / 2;
			size_t delta = i;
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
					if (i == filteredList.length - 1) {
						index = filteredList.length;
						appendToFiltered(sd);
						break;
					}
					else if (less(sd, filteredList[i+1])) {
							insertInFiltered(i+1, sd);
							index = i+1;
							break;
					}
					else {
						i += delta;
					}
				}
			}
		}

		debug {
			auto fL = filteredList;
			auto i = index;

			// Verify that the new element was inserted at the right location, by
			// comparing it to the elements before and after it.
			if (!((i == 0 || greaterOrEq(fL[i], fL[i-1])) &&
			      (i == (fL.length - 1)	 || less(fL[i], fL[i + 1])))) {

				db("_insertSorted, index = " ~ Integer.toString(i) ~ "\n" ~
				   "new: " ~ sd.server[ServerColumn.NAME] ~ "\n" ~
				   "i-1:" ~ (i > 0 ? fL[i-1].server[ServerColumn.NAME]  : "START") ~ "\n" ~
				   "i:  " ~ fL[i].server[ServerColumn.NAME] ~ "\n" ~
				   "i+1:" ~ (i < (fL.length - 1) ? fL[i+1].server[ServerColumn.NAME] : "END"));
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
		if (filters_ == 0)
			return false;
		if (filters_ & Filter.HAS_HUMANS && !sd.hasHumans)
			return true;
		if (filters_ & Filter.NOT_EMPTY && !(sd.hasHumans || sd.hasBots))
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
		if (filters_ & Filter.HAS_HUMANS) {
			for (size_t i = 0; i < list.length; i++) {
				if (list[i].hasHumans) {
					filteredList ~= &list[i];
				}
			}
		}
		else if (filters_ & Filter.NOT_EMPTY) {
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
	bool thereAlready;
	Filter savedFilters;

	// hack to get the correct filtering set up for the new list,
	// save the old one here for later use
	if (activeServerList !is null) {
		savedFilters = activeServerList.filters_;
	}

	if (ServerList* slist = modName in serverLists) {
		activeServerList = *slist;
		thereAlready = slist.complete;
	}
	else {
		activeServerList = new ServerList;
		serverLists[modName] = activeServerList;
		thereAlready = false;
	}

	activeServerList.filters_ = savedFilters;

	auto sortCol = serverTable.getTable.getSortColumn();
	synchronized (activeServerList) {
		activeServerList.setSort(serverTable.getTable.indexOf(sortCol),
	                      (serverTable.getTable.getSortDirection() == DWT.DOWN));
	}

	return thereAlready;
}

ServerList getActiveServerList() { return activeServerList; }
