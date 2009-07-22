module serverlist;

import tango.core.Array;
import tango.core.Exception : IOException;
import Path = tango.io.Path;
import tango.text.Ascii;
import tango.text.Util;
import tango.text.convert.Format;
import Integer = tango.text.convert.Integer;
import tango.stdc.string : memmove;
import tango.util.container.HashMap;
debug import tango.util.log.Trace;

import common;
import geoip;
import masterlist;
import serverdata;
import set;
import settings;


/// Server filter bitflags.
enum Filter {
	NONE = 0,  /// Value is zero.
	HAS_HUMANS = 1,  ///
	NOT_EMPTY = 2  ///
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
	in {
		assert(gameName.length > 0);
		assert(master !is null);
	}
	body {
		gameName_ = gameName;
		master_ = master;
		ipHash_ = new HashMap!(char[], int);
	}


	///
	char[] gameName() { return gameName_; }


	///
	MasterList master() { return master_; }


	/// Returns false if the added server is filtered out.
	bool add(ServerHandle sh)
	{
		bool refresh = false;

		synchronized (this) synchronized (master_) {
			ServerData sd = master_.getServerData(sh);
			sd.server[ServerColumn.COUNTRY] = getCountryCode(&sd);
			ipHash_[sd.server[ServerColumn.ADDRESS]] = -1;
			if (!isFilteredOut(&sd)) {
				insertSorted(sh);
				refresh = true;
			}
		}

		return refresh;
	}


	/**
	* Replace a server in the list, or add it if it's missing.
	*
	* Returns true if the filtered list was altered.
	*/
	bool replace(ServerHandle sh)
	{
		synchronized (this) synchronized (master_) {
			ServerData sd = master_.getServerData(sh);
			bool removed = removeFromFiltered(sd.server[ServerColumn.ADDRESS]);

			if (sd.customData)
				sd.customData.dispose();

			if (!removed) {
				// adding as a new server
				ipHash_[sd.server[ServerColumn.ADDRESS]] = -1;
				sd.server[ServerColumn.COUNTRY] = getCountryCode(&sd);
			}
			if (!isFilteredOut(&sd)) {
				insertSorted(sh);
				return true;
			}
			else {
				return removed;
			}
		}
	}


	/**
	 * Clear the filtered list and refill it from the master list.
	 */
	synchronized void refillFromMaster()
	{
		char[] mod = getGameConfig(gameName_).mod;

		filteredList.length = 0;
		synchronized (master_) foreach (sh; master_) {
			ServerData sd = master_.getServerData(sh);
			char[] address = sd.server[ServerColumn.ADDRESS];
			if (address in ipHash_ && matchMod(&sd, mod) &&
			                                               !isFilteredOut(&sd))
				filteredList ~= sh;
		}
		ipHashValid_ = false;
		isSorted_ = false;
		_sort();
	}


	/**
	 * Return a server from the filtered list.
	 *
	 * Complexity is O(1).
	 */
	ServerData getFiltered(int i)
	{
		synchronized (this) {
			assert(i >= 0 && i < filteredList.length);
			synchronized (master_) {
				return master_.getServerData(filteredList[i]);
			}
		}
	}


	/**
	 * Given the IP and port number, find a server in the filtered list.
	 *
	 * Returns: the server's index, or -1 if unknown or not found.
	 */
	int getFilteredIndex(char[] ipAndPort, bool* found=null)
	{
		int result = -1;
		bool wasFound = false;

		synchronized (this) {
			if (!ipHashValid_)
				updateIpHash();

			if (int* i = ipAndPort in ipHash_) {
				assert(*i == -1 || *i < filteredList.length);
				result = *i;
				wasFound = true;
			}
		}
		if (found)
			*found = wasFound;
		return result;
	}


	/**
	 * Returns the server handle for a server in the filtered list.
	 *
	 * Complexity is O(1).
	 */
	ServerHandle getServerHandle(int i)
	{
		synchronized (this) {
			assert(i >= 0 && i < filteredList.length);
			return filteredList[i];
		}
	}


	///
	size_t filteredLength() { synchronized (this) return filteredList.length; }


	/**
	 * Clears the list and the filtered list.  Sets complete to false.
	 */
	void clear()
	{
		synchronized (this) {
			disposeCustomData();
			filteredList.length = 0;
			ipHash_.clear();
			isSorted_ = true;
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
	 * Sorts the filtered list.
	 *
	 * Uses the previously selected _sort order, or the default
	 * if there is none.
	 */
	void sort()
	{
		synchronized (this) {
			_sort();
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
			}
		}
	}


	/**
	 * Sets filters and updates the filtered list accordingly.
	 */
	void setFilters(Filter newFilters)
	{
		if (newFilters == filters_)
			return;

		synchronized (this) {
			filters_ = newFilters;
			refillFromMaster();
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
	ServerHandle[] filteredList;
	// maps addresses to indices into the filtered list
	HashMap!(char[], int) ipHash_;
	bool ipHashValid_ = false;  // true if the values (indices) are up to date
	Set!(char[]) extraServers_;
	char[] gameName_;
	MasterList master_;

	int sortColumn_ = ServerColumn.NAME;
	bool reversed_ = false;
	bool isSorted_= true;

	Filter filters_ = Filter.NONE;


	invariant()
	{
		synchronized (this) {
			/*if (filteredList.length > list.length) {
				log(Format("filteredlist.length == {}\nlist.length == {}",
				                            filteredList.length, list.length));
				assert(0, "Details in log file.");
			}*/
			/*if (!(filters_ || filteredList.length == list.length ||
			                       filteredList.length == (list.length - 1))) {
				log(Format("ServerList invariant broken!"
				           "\nfilters_ & Filter.HAS_HUMANS: {}"
				           "\nfilters_ & Filter.NOT_EMPTY: {}"
				           "\nlist.length: {}"
				           "\nfilteredList.length: {}",
				           filters_ & Filter.HAS_HUMANS,
				           filters_ & Filter.NOT_EMPTY,
				           list.length, filteredList.length));
				assert(0, "Details in log file.");
			}*/
		}
	}


	/// Updates sort column and order for the filtered list.
	void setSort(int column, bool reversed=false)
	{
		assert(column >= 0 && column <= ServerColumn.max);

		if (column != sortColumn_) {
			sortColumn_ = column;
			isSorted_ = false;
		}
		if (reversed != reversed_) {
			reversed_ = reversed;
			isSorted_ = false;
		}
	}


	/// Sorts the filtered list.
	void _sort()
	{
		debug scope timer = new Timer;

		bool lessOrEqual(ServerHandle a, ServerHandle b)
		{
			ServerData sda = master_.getServerData(a);
			ServerData sdb = master_.getServerData(b);

			return compare(&sda, &sdb) <= 0;
		}

		if (!isSorted_) {
			synchronized (master_) {
				mergeSort(filteredList, &lessOrEqual);
			}
			isSorted_ = true;
			ipHashValid_ = false;
		}

		debug log("ServerList._sort() took " ~
		          Integer.toString(timer.millis) ~ " milliseconds.");
	}

	/**
	 * Insert a server in sorted order in the filtered list.
	 */
	void insertSorted(ServerHandle sh)
	{
		assert(isSorted_);

		bool less(ServerHandle a, ServerHandle b)
		{
			ServerData sda = master_.getServerData(a);
			ServerData sdb = master_.getServerData(b);

			return compare(&sda, &sdb) < 0;
		}

		size_t i;
		synchronized (master_) {
			i = ubound(filteredList, sh, &less);
		}
		insertInFiltered(i, sh);
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
				result = Integer.parse(a.server[ServerColumn.PING]) -
				         Integer.parse(b.server[ServerColumn.PING]);
				break;

			default:
				result = icompare(a.server[sortColumn_],
				                  b.server[sortColumn_]);
		}

		return (reversed_ ? -result : result);
	}

	void insertInFiltered(size_t index, ServerHandle sh)
	{
		assert(index <= filteredList.length);

		size_t oldLength = filteredList.length;
		filteredList.length = filteredList.length + 1;

		if (index < oldLength) {
			ServerHandle* ptr = filteredList.ptr + index;
			size_t bytes = (oldLength - index) * filteredList[0].sizeof;
			memmove(ptr + 1, ptr, bytes);
		}
		filteredList[index] = sh;

		ipHashValid_ = false;
	}

	bool removeFromFiltered(in char[] address)
	{
		if (!ipHashValid_)
			updateIpHash();
		int i = getFilteredIndex(address);
		if (i == -1)
			return false;

		ServerHandle* ptr = filteredList.ptr + i;
		size_t bytes = (filteredList.length - 1 - i) * filteredList[0].sizeof;
		memmove(ptr, ptr + 1, bytes);
		filteredList.length = filteredList.length - 1;

		ipHashValid_ = false;
		return true;
	}

	char[] getCountryCode(in ServerData* sd)
	{
		char[] address = sd.server[ServerColumn.ADDRESS];
		char[] code = countryCodeByAddr(address[0..locate(address, ':')]);

		return code;
	}

	bool isFilteredOut(ServerHandle sh)
	{
		if (filters_ == 0)
			return false;

		ServerData sd = master_.getServerData(sh);
		return isFilteredOut(&sd);
	}

	bool isFilteredOut(in ServerData* sd)
	{
		if (filters_ == 0)
			return false;

		if (sd.hasHumans)
			return false;
		else
			return filters_ & Filter.HAS_HUMANS || !sd.hasBots;
	}

	void updateIpHash(bool reset=true)
	{
		if (reset) {
			foreach (ref val; ipHash_)
				val = -1;
		}
		foreach (int i, sh; filteredList) {
			ServerData sd = master_.getServerData(sh);
			ipHash_[sd.server[ServerColumn.ADDRESS]] = i;
		}
		ipHashValid_ = true;
	}

	/// Prints the filtered list and its length to stdout.
	debug void printFiltered()
	{
		Trace.formatln("printFiltered(): {} elements in filteredList.",
		                filteredList.length);
		foreach (i, sh; filteredList) {
			ServerData sd = master_.getServerData(sh);
			Trace.formatln(/*i, ": ",*/ sd.server[ServerColumn.NAME]);
		}
		Trace.formatln("");
	}
}


/// Returns the total number of humans players in the filtered list of servers.
int countHumanPlayers(in ServerList serverList)
{
	int players = 0;
	synchronized (serverList) {
		int max = serverList.filteredLength;
		for (int i=0; i < max; i++)
			players += serverList.getFiltered(i).humanCount;
	}
	return players;
}
