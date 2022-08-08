module serverlist;

import tango.core.Array;
import tango.core.Exception : IOException;
import Path = tango.io.Path;
import tango.text.Ascii;
import tango.text.Util;
import tango.text.convert.Format;
import Integer = tango.text.convert.Integer;
import tango.stdc.string : memmove;
import tango.time.StopWatch;
import tango.util.container.HashMap;
debug import tango.util.log.Log;

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
final class ServerList
{
	/**
	 * true if list contains all servers for the mod, that replied when queried.
	 * Meaning that the server querying process was not interrupted.
	 */
	// FIXME: how does MasterList relate to this?
	bool complete = false;


	///
	this(in char[] gameName, MasterList master, bool useEtColors)
	in {
		assert(gameName.length > 0);
		assert(master !is null);
	}
	body {
		gameName_ = gameName;
		master_ = master;
		useEtColors_ = useEtColors;
		ipHash_ = new HashMap!(char[], int);
	}


	///
	char[] gameName() { return gameName_; }

	///
	MasterList master() { return master_; }

	///
	bool useEtColors() { return useEtColors_; }


	/**
	 * Add a server to the list.
	 *
	 * Returns true if the filtered list was altered.
	 */
	bool add(ServerHandle sh)
	{
		return addOrReplace(sh);
	}


	/**
	* Replace a server in the list, or add it if it's missing.
	*
	* Returns true if the filtered list was altered.
	*/
	bool replace(ServerHandle sh)
	{
		return addOrReplace(sh, true);
	}


	/**
	 * Clear the filtered list and refill it from the master list.
	 *
	 * Only servers previously added by calling add() or replace() will be
	 * considered.
	 */
	synchronized void refillFromMaster()
	{
		GameConfig game = getGameConfig(gameName_);
		auto newHash = new typeof(ipHash_);

		filteredList.length = 0;
		synchronized (master_) foreach (sh; master_) {
			ServerData sd = master_.getServerData(sh);
			char[] address = sd.server[ServerColumn.ADDRESS];

			if (address in ipHash_ && matchGame(&sd, game)) {
				newHash[address] = -1;
				sd.server[ServerColumn.GAMETYPE] =
				                     getGameTypeName(game, sd.numericGameType);
				if (!isFilteredOut(&sd))
					filteredList ~= sh;
			}
		}

		ipHash_ = newHash;
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
	synchronized size_t totalLength() { return ipHash_.size; }

	///
	synchronized size_t filteredLength() { return filteredList.length; }


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
	 *
	 * If autoRefill is true, calls refillFromMaster if the new filters differ
	 * from the old.
	 */
	void setFilters(Filter newFilters, bool autoRefill=true)
	{
		if (newFilters == filters_)
			return;

		synchronized (this) {
			filters_ = newFilters;
			if (autoRefill)
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
	bool useEtColors_;

	int sortColumn_ = ServerColumn.NAME;
	bool reversed_ = false;
	bool isSorted_ = true;

	Filter filters_ = Filter.NONE;


	// invariant + synchronized doesn't work with dmd on linux
	// see http://d.puremagic.com/issues/show_bug.cgi?id=235
	version (Windows) invariant()
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

	/**
	* Add or replace a server in the list.
	*
	* Returns true if the filtered list was altered.
	*/
	private bool addOrReplace(ServerHandle sh, bool replace=false)
	{
		synchronized (this) synchronized (master_) {
			ServerData sd = master_.getServerData(sh);
			GameConfig game = getGameConfig(gameName_);
			bool removed = false;

			if (replace) {
				removed = removeFromFiltered(sd.server[ServerColumn.ADDRESS]);
			}

			sd.server[ServerColumn.GAMETYPE] =
			                         getGameTypeName(game, sd.numericGameType);

			if (!removed) {
				// adding as a new server
				char[] ip = sd.server[ServerColumn.ADDRESS];
				GeoInfo geo = getGeoInfo(ip[0..locate(ip, ':')]);

				sd.server[ServerColumn.COUNTRY] = geo.countryCode;
				sd.countryName = geo.countryName;
				master_.setServerData(sh, sd);

				ipHash_[ip] = -1;
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


	/// Updates sort column and order for the filtered list.
	void setSort(int column, bool reversed=false)
	{
		assert(column >= 0 && column <= ServerColumn.max);

		if (column != sortColumn_) {
			sortColumn_ = column;
			isSorted_ = filteredList.length == 0;
		}
		if (reversed != reversed_) {
			reversed_ = reversed;
			isSorted_ = filteredList.length == 0;
		}
	}


	/// Sorts the filtered list.
	void _sort()
	{
		debug {
			StopWatch timer;
			timer.start();
		}

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
		          Integer.toString(timer.microsec / 1000) ~ " milliseconds.");
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

		size_t i = ubound(filteredList, sh, &less);
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
		Log.formatln("printFiltered(): {} elements in filteredList.",
		                filteredList.length);
		foreach (i, sh; filteredList) {
			ServerData sd = master_.getServerData(sh);
			Log.formatln(/*i, ": ",*/ sd.server[ServerColumn.NAME]);
		}
		Log.formatln("");
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
