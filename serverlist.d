module serverlist;

import tango.core.Array;
import tango.core.Exception : IOException;
import Path = tango.io.Path;
debug import tango.io.Stdout;
import tango.text.Ascii;
import tango.text.Util;
import tango.text.convert.Format;
import Integer = tango.text.convert.Integer;
import tango.stdc.string : memmove;
import tango.util.container.HashMap;

import dwt.graphics.TextLayout;

import common;
import geoip;
import masterlist;
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
	gameTypes["smokinguns"] = split("FFA Duel 2 TDM RTP BR", " ");
	gameTypes["westernq3"]  = split("FFA Duel 2 TDM RTP BR", " ");
	gameTypes["wop"] = split("FFA 1v1 2 SyC LPS TDM 6 SyCT BB", " ");
}

// should correspond to playertable.playerHeaders
enum PlayerColumn { NAME, SCORE, PING, RAWNAME };
// should correspond to servertable.serverHeaders
enum ServerColumn {
	COUNTRY, NAME, PASSWORDED, PING, PLAYERS, GAMETYPE, MAP, ADDRESS
};


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


/// Returns true if this server runs the correct mod.
bool matchMod(in ServerData* sd, in char[] mod)
{
	foreach (cvar; sd.cvars) {
		if ((cvar[0] == "game" || cvar[0] == "gamename") &&
		                                           icompare(cvar[1], mod) == 0)
			return true;
	}
	return false;
}


/**
 * A list of servers, with all necessary synchronization taken care of.
 *
 */
class ServerList
{
	/**
	 * true if list contains all servers for the mod, that replied when queried.
	 * Meaning that the server querying process was not interrupted.
	 */
	// FIXME: how does MasterList relate to this?
	bool complete = false;


	///
	this(in char[] gameName, MasterList master)
	{
		gameName_ = gameName;
		master_ = master;
		filteredIpHash_ = new HashMap!(char[], int);
	}


	///
	char[] gameName() { return gameName_; }


	///
	MasterList master() { return master_; }


	/// Returns false if the added server is filtered out.
	bool add(ServerHandle sh)
	{
		bool refresh = false;

		synchronized (this) {
			synchronized (master_) {
				ServerData sd = master_.getServerData(sh);
				sd.server[ServerColumn.COUNTRY] = getCountryCode(&sd);
				master_.setServerData(sh, sd);
			}
			list ~= sh;
			isSorted_ = false;
			if (!isFilteredOut(sh)) {
				insertSorted(list.length -1);
				refresh = true;
			}
		}

		return refresh;
	}


	/// Always returns true.
	bool replace(ServerHandle sh)
	{
		/*synchronized (this) {
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
				insertSorted(i);
		}*/

		return true;
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
	ServerData getFiltered(int i)
	{
		synchronized (this) {
			assert(i >= 0 && i < filteredList.length);
			synchronized (master_) {
				return master_.getServerData(list[filteredList[i]]);
			}
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

		synchronized (this) synchronized (master_)
		foreach (int i, ServerHandle sh; list) {
			ServerData sd = master_.getServerData(sh);
			if (sd.server[ServerColumn.ADDRESS] == ipAndPort)
				return i;
		}
		return -1;
	}


	/**
	 * Given the IP and port number, find a server in the filtered list.
	 *
	 * Returns: the server's index, or -1 if not found.
	 */
	int getFilteredIndex(char[] ipAndPort)
	{
		synchronized (this) {
			if (!filteredIpHashValid_)
				createFilteredIpHash();
			if (int* i = ipAndPort in filteredIpHash_) {
				assert(*i >= 0 && *i < filteredList.length);
				return *i;
			}
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
			filteredIpHash_.reset();
			complete = false;
		}

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
	 * sorting, until new values are given.  Set update to false if you don't
	 * want the actual sorting to be done, but only set the order.
	 */
	void sort(int column, bool reversed=false, bool update=true)
	{
		synchronized (this) {
			setSort(column, reversed);
			if (update) {
				_sort();
				updateFilteredList();
			}
		}
	}


	/**
	 * Sets filters and updates the list accordingly.
	 *
	 * Set update to false if you don't want the filters to be applied
	 * immediately.
	 */
	void setFilters(Filter newFilters, bool update=true)
	{
		if (newFilters == filters_)
			return;

		synchronized (this) {
			filters_ = newFilters;
			if (update)
				updateFilteredList();
		}
	}

	Filter getFilters() { return filters_; } ///


	/**
	 * Call customData.dispose() on each of the ServerData structs.
	 *
	 * Does nothing if "coloredNames" is not set to "true".
	 */
	void disposeCustomData()
	{
		if (getSetting("coloredNames") != "true")
			return;

		/*foreach (ref sd; list) {
			if (sd.customData)
				sd.customData.dispose();
		}*/
	}


/***********************************************************************
 *                                                                     *
 *                        PRIVATE SECTION                              *
 *                                                                     *
 ***********************************************************************/
private:
	ServerHandle[] list;
	size_t[] filteredList;
	// maps addresses to indices into the filtered list
	HashMap!(char[], int) filteredIpHash_;
	bool filteredIpHashValid_ = false;
	Set!(char[]) extraServers_;
	char[] gameName_;
	MasterList master_;

	int sortColumn_ = ServerColumn.NAME;
	int oldSortColumn_ = -1;
	bool reversed_ = false;
	bool isSorted_= false;

	Filter filters_ = Filter.NONE;


	invariant()
	{
		synchronized (this) {
			if (filteredList.length > list.length) {
				log(Format("filteredlist.length == {}\nlist.length == {}",
				                            filteredList.length, list.length));
				assert(0, "Details in log file.");
			}
			if (!(filters_ || filteredList.length == list.length ||
							  filteredList.length == (list.length - 1))) {
				log(Format("ServerList invariant broken!\n",
				           "\nfilters_ & Filter.HAS_HUMANS: {}"
				           "\nfilters_ & Filter.NOT_EMPTY: {}"
				           "\nlist.length: {}"
				           "\nfilteredList.length: {}",
				           filters_ & Filter.HAS_HUMANS,
				           filters_ & Filter.NOT_EMPTY,
				           list.length, filteredList.length));
				assert(0, "Details in log file.");
			}
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

		bool lessOrEqual(ServerHandle a, ServerHandle b)
		{
			ServerData sda = master_.getServerData(a);
			ServerData sdb = master_.getServerData(b);

			return compare(&sda, &sdb) <= 0;
		}

		if (!isSorted_ || sortColumn_ != oldSortColumn_) {
			synchronized (master_) {
				mergeSort(list, &lessOrEqual);
			}
			isSorted_ = true;
		}

		debug log("ServerList._sort() took " ~
		          Integer.toString(timer.millis) ~ " milliseconds.");
	}

	/**
	 * Insert a server in sorted order in the filtered list.
	 */
	void insertSorted(size_t listIndex)
	{
		bool less(size_t a, size_t b)
		{
			ServerData sda = master_.getServerData(list[a]);
			ServerData sdb = master_.getServerData(list[b]);

			return compare(&sda, &sdb) < 0;
		}

		size_t i;
		synchronized (master_) {
			i = ubound(filteredList, listIndex, &less);
		}
		insertInFiltered(i, listIndex);
	}

	/**
	 * Compares two ServerData instances according to the current sort order.
	 *
	 * Returns: >0 if a is smaller, <0 if b is smaller, 0 if they are equal.
	 */
	int compare(in ServerData* a, in ServerData* b)
	{
		int result;

		switch (sortColumn_) {
			case ServerColumn.PLAYERS:
				result = b.humanCount - a.humanCount;
				if (result)
					break;

				result = b.botCount - a.botCount;
				if (result)
					break;

				result = b.maxClients - a.maxClients;
				if (result)
					break;

				break;

			case ServerColumn.PING:
				result = Integer.toInt(a.server[ServerColumn.PING]) -
				         Integer.toInt(b.server[ServerColumn.PING]);
				break;

			default:
				result = icompare(a.server[sortColumn_],
				                  b.server[sortColumn_]);
		}

		return (reversed_ ? -result : result);
	}

	void insertInFiltered(size_t index, size_t listIndex)
	{
		assert(index <= filteredList.length);

		size_t oldLength = filteredList.length;
		filteredList.length = filteredList.length + 1;

		if (index < oldLength) {
			size_t* ptr = filteredList.ptr + index;
			size_t bytes = (oldLength - index) * filteredList[0].sizeof;
			memmove(ptr + 1, ptr, bytes);
		}
		filteredList[index] = listIndex;

		filteredIpHashValid_ = false;
	}

	void removeFromFiltered(ServerData* psd)
	{
		int i = getFilteredIndex(psd.server[ServerColumn.ADDRESS]);
		assert(i != -1);

		size_t* ptr = filteredList.ptr + i;
		size_t bytes = (filteredList.length - 1 - i) * filteredList[0].sizeof;
		memmove(ptr, ptr + 1, bytes);
		filteredList.length = filteredList.length - 1;

		filteredIpHash_.removeKey(psd.server[ServerColumn.ADDRESS]);
	}

	char[] getCountryCode(in ServerData* sd)
	{
		char[] address = sd.server[ServerColumn.ADDRESS];
		char[] code = countryCodeByAddr(address[0..locate(address, ':')]);

		return code;
	}

	void copyListToFilteredList()
	{
		filteredList.length = list.length;
		for (size_t i=0; i < list.length; i++)
			filteredList[i] = i;

		filteredIpHashValid_ = false;
	}

	bool isFilteredOut(ServerHandle sh)
	{
		if (filters_ == 0)
			return false;

		ServerData sd = master_.getServerData(sh);

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
		if (!isSorted_)
			_sort();

		filteredList.length = 0;
		if (filters_ & Filter.HAS_HUMANS) {
			foreach (i, sh; list) {
				ServerData sd = master_.getServerData(sh);
				if (sd.hasHumans)
					filteredList ~= i;
			}
			filteredIpHashValid_ = false;
		}
		else if (filters_ & Filter.NOT_EMPTY) {
			foreach (i, sh; list) {
				ServerData sd = master_.getServerData(sh);
				if (sd.hasBots || sd.hasHumans)
					filteredList ~= i;
			}
			filteredIpHashValid_ = false;
		}
		else {
			copyListToFilteredList();
		}
	}

	void createFilteredIpHash()
	{
		filteredIpHash_.clear();
		foreach (int i, listIndex; filteredList) {
			ServerData sd = master_.getServerData(list[listIndex]);
			filteredIpHash_[sd.server[ServerColumn.ADDRESS]] = i;
		}
		filteredIpHashValid_ = true;
	}

	/// Prints the filtered list and its length to stdout.
	debug void printFiltered()
	{
		Stdout.formatln("printFiltered(): {} elements in filteredList.",
		                filteredList.length);
		foreach (i, listIndex; filteredList) {
			ServerData sd = master_.getServerData(list[listIndex]);
			Stdout(/*i, ": ",*/ sd.server[ServerColumn.NAME]).newline;
		}
		Stdout.newline;
	}

	/// Prints the full list and its length to stdout.
	debug void printList()
	{
		Stdout.formatln("printList(): {} elements in full list.", list.length);
		int i = 0;
		foreach (sh; list) {
			ServerData sd = master_.getServerData(sh);
			Stdout(/*i++, ": ",*/ sd.server[ServerColumn.NAME]).newline;
		}
		Stdout.newline;
	}
}
