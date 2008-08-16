module serverlist;

import Path = tango.io.Path;
debug import tango.io.Stdout;
import tango.io.stream.TextFileStream;
import tango.text.Ascii;
import tango.text.Util;
import Integer = tango.text.convert.Integer;
import tango.stdc.string : memmove;

import dwt.DWT;
import dwt.dwthelper.Runnable;
import dwt.graphics.TextLayout;
import dwt.widgets.Display;

import common;
import dialogs;
import geoip;
import mainwindow;
import runtools;
import servertable;
import set;
import settings;


/// Server filter bitflags.
enum Filter {
	NONE = 0,  /// Value is zero.
	HAS_HUMANS = 1,  ///
	NOT_EMPTY = 2  ///
}

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
enum PlayerColumn { NAME, SCORE, PING, RAWNAME };
// should correspond to servertable.serverHeaders
enum ServerColumn {
	COUNTRY, NAME, PASSWORDED, PING, PLAYERS, GAMETYPE, MAP, ADDRESS
};

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
	/// list of players, with country, name, score, ping, and raw name (with color
	/// codes) for each.
	char[][][] players;
	/// list of cvars, with key and value for each
	char[][][] cvars;

	TextLayout customData = null;

	/// Compares according to activeServerList's settings.
	int opCmp(ServerData other)
	{
		int result;

		switch (activeServerList.sortColumn_) {
			case ServerColumn.PLAYERS:
				result = other.humanCount - humanCount;
				if (result)
					break;

				result = other.botCount - botCount;
				if (result)
					break;

				result = other.maxClients - maxClients;
				if (result)
					break;

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


	/// Extract some info about the server. Always returns >= 0.
	int humanCount()
	{
		auto r = Integer.convert(server[ServerColumn.PLAYERS]);
		assert(r >= 0 && r <= int.max);
		return r;
	}

	/// ditto
	int botCount()
	{
		char[] s = server[ServerColumn.PLAYERS];
		auto r = Integer.convert(s[locate(s, '+')+1 .. $]);
		assert(r >= 0 && r <= int.max);
		return r;
	}

	/// ditto
	int maxClients()
	{
		char[] s = server[ServerColumn.PLAYERS];
		auto r = Integer.convert(s[locate(s, '/')+1 .. $]);
		assert(r >= 0 && r <= int.max);
		return r;
	}

	/// Extract some info about the server.
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

		synchronized (this) {
			isSorted_ = false;
			sd.server[ServerColumn.COUNTRY] = getCountryCode(sd);
			list ~= *sd;
			if (!isFilteredOut(sd)) {
				index = _insertSorted(&list[$ - 1]);
				refresh = true;
			}
		}
		if (refresh && !arguments.norefresh)
			//display.syncExec(new IntWrapper(index), &serverTable.refresh);
			Display.getDefault.syncExec(new class Runnable {
				void run() { serverTable.refresh(new IntWrapper(index)); }
			});
	}


	///
	void replace(ServerData* sd)
	{
		int index = -1;

		synchronized (this) {
			isSorted_ = false;
			int i = getIndex(sd.server[ServerColumn.ADDRESS]);
			assert(i != -1);
			sd.server[ServerColumn.COUNTRY] =
			                              list[i].server[ServerColumn.COUNTRY];
			
			if (list[i].customData)
				list[i].customData.dispose();
			list[i] = *sd;
			removeFromFiltered(sd);
			if (!isFilteredOut(sd))
				index = _insertSorted(&list[i]);
		}

		if (!arguments.norefresh)
			//display.syncExec(new IntWrapper(index), &serverTable.refresh);
			Display.getDefault.syncExec(new class Runnable {
				void run()
				{
					serverTable.refresh();
				}
			});
	}


	 /// Iterate over the full list.
	/*int opApply(int delegate(ref ServerData) dg)
	{
		int result = 0;

		synchronized (this)
			foreach(ServerData sd; list) {
				result = dg(sd);
				if (result) {
					break;
				}
			}
		return result;
	}*/


	/// Return a server from the filtered list
	ServerData* getFiltered(int i)
	{
		synchronized (this) {
			assert(i >= 0 && i < filteredList.length);
			return filteredList[i];
		}
	}


	/**
	 * Given the IP and port number, find a server in the full list.
	 *
	 * Does a linear search.
	 *
	 * Returns: the server's index, or -1 if not found.
	 */
	int getIndex(char[] ipAndPort)
	{
		if (!ipAndPort.length)
			return -1;

		synchronized (this)
		foreach (int i, ref ServerData sd; list) {
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
	int getFilteredIndex(char[] ipAndPort)
	{
		if (!ipAndPort.length)
			return -1;

		synchronized (this)
		foreach (int i, ServerData* sd; filteredList) {
			if (sd.server[ServerColumn.ADDRESS] == ipAndPort)
				return i;
		}
		return -1;
	}


	///
	size_t filteredLength() { synchronized (this) return filteredList.length; }
	size_t length() { synchronized (this) return list.length; } /// ditto


	/**
	 * Clears the list and the filtered list.  Sets complete to false.
	 */
	ServerList clear()
	{
		synchronized (this) {
			disposeCustomData();

			//filteredList.length = 0;
			//list.length = 0;
			delete filteredList;
			delete list;
			complete = false;
		}

		return this;
	}


	///
	void disposeCustomData()
	{
		if (getSetting("coloredNames") == "true") {
			foreach (ref sd; list) {
				if (sd.customData)
					sd.customData.dispose();
			}
		}
	}


	///
	static void disposeAllCustomData()
	{
		foreach (slist; serverLists) {
			slist.disposeCustomData();
		}
	}


	/**
	 * Add an extra server to be included when doing a refresh.
	 *
	 * Useful for servers that are not on the master server's list.  Multiple
	 * servers can be added this way.
	 */
	void addExtraServer(in char[] address)
	{
		synchronized (this) extraServers_.add(address);
	}


	/// Returns the list of extra servers.
	Set!(char[]) extraServers() { synchronized (this) return extraServers_; }


	/**
	 * Sort the full list, then update the filtered list.
	 *
	 * Uses the previously selected _sort order, or the default
	 * if there is none.
	 */
	void sort()
	{
		synchronized (this) {
			_sort();
			updateFilteredList();
		}
	}


	/**
	 * Like sort(), but lets you spesify _sort _column and order.
	 *
	 * The given _sort _column and order will be used for all subsequent
	 * sorting, until new values are given.
	 */
	void sort(int column, bool reversed=false)
	{
		synchronized (this) {
			setSort(column, reversed);
			_sort();
			updateFilteredList();
		}
	}


	/// Sets filters and updates the list accordingly.
	void setFilters(Filter newFilters)
	{
		if (newFilters == filters_)
			return;

		synchronized (this) {
			filters_ = newFilters;
			updateFilteredList();
		}
		//display.asyncExec(null, &serverTable.reset);
		Display.getDefault.asyncExec(new class Runnable {
			void run() { serverTable.reset(); }
		});
	}

	Filter getFilters() { return filters_; } ///



/***********************************************************************
 *                                                                     *
 *                        PRIVATE SECTION                              *
 *                                                                     *
 ***********************************************************************/
private:
	ServerData[] list;
	ServerData*[] filteredList;
	Set!(char[]) extraServers_;

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

	void removeFromFiltered(ServerData* psd)
	{
		int i = getFilteredIndex(psd.server[ServerColumn.ADDRESS]);
		assert(i != -1);
		memmove(filteredList.ptr + i, filteredList.ptr + i + 1,
		               (filteredList.length - 1 - i) * filteredList[0].sizeof);
		filteredList.length = filteredList.length - 1;
	}

	char[] getCountryCode(ServerData* sd)
	{
		char[] address = sd.server[ServerColumn.ADDRESS];
		char[] code = countryCodeByAddr(address[0..locate(address, ':')]);

		// http://dsource.org/projects/dwt-win/ticket/6
		return code ? code : "";
	}

	void copyListToFilteredList()
	{
		filteredList.length = list.length;
		for (size_t i=0; i < list.length; i++) {
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
			foreach (ref sd; list) {
				if (sd.hasHumans) {
					filteredList ~= &sd;
				}
			}
		}
		else if (filters_ & Filter.NOT_EMPTY) {
			foreach (ref sd; list) {
				if (sd.hasBots || sd.hasHumans) {
					filteredList ~= &sd;
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
		Stdout.formatln("printFiltered(): {} elements in filteredList.",
		                filteredList.length);
		foreach (i, ServerData* sd; filteredList) {
			Stdout(/*i, ": ",*/ sd.server[ServerColumn.NAME]).newline;
		}
		Stdout.newline;
	}

	/// Prints the full list and its length to stdout.
	debug void printList()
	{
		Stdout.formatln("printList(): {} elements in full list.", list.length);
		int i = 0;
		foreach (ServerData sd; list) {
			Stdout(/*i++, ": ",*/ sd.server[ServerColumn.NAME]).newline;
		}
		Stdout.newline;
	}
}


/**
 * Sets the activeServerList global to refer to the ServerList object
 * for the mod given by modName.
 *
 * If there is no ServerList object for the given mod, one will be created,
 * and the corresponding list of extra servers will be loaded from disk.
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
	else {
		savedFilters = cast(Filter)Integer.convert(
		                                       getSessionState("filterState"));
	}

	if (ServerList* slist = modName in serverLists) {
		activeServerList = *slist;
		thereAlready = slist.complete;
	}
	else {
		activeServerList = new ServerList;
		serverLists[modName] = activeServerList;
		thereAlready = false;

		auto file = activeMod.extraServersFile;
		try {
			if (Path.exists(file)) {
				auto input = new TextFileInput(file);
				auto servers = collectIpAddresses(input);
				input.close;
				activeServerList.extraServers_ = servers;
			}
		}
		catch (IOException e) {
			log("Error when reading \"" ~ file ~ "\".");
		}
	}

	activeServerList.filters_ = savedFilters;

	auto sortCol = serverTable.getTable.getSortColumn();
	synchronized (activeServerList) {
		activeServerList.setSort(serverTable.getTable.indexOf(sortCol),
	                      (serverTable.getTable.getSortDirection() == DWT.DOWN));
	}

	return thereAlready;
}


/** Returns the active server list. */
ServerList getActiveServerList()
{
	return activeServerList;
}
