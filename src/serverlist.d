module serverlist;

import core.stdc.string : memmove;
import lib.phobosfixes; // upperBound, icmp
import std.algorithm;
import std.conv;
import std.string;

import Integer = tango.text.convert.Integer;

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
	this(string gameName, MasterList master, bool useEtColors)
	in {
		assert(gameName.length > 0);
		assert(master !is null);
	}
	body {
		gameName_ = gameName;
		master_ = master;
		useEtColors_ = useEtColors;
	}


	///
	string gameName() { return gameName_; }

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
	 *
	 * Only servers previously added by calling add() or replace() will be
	 * considered.
	 */
	void refillFromMaster()
	{
		synchronized (this) {
			GameConfig game = getGameConfig(gameName_);
			typeof(ipHash_) newHash;

			filteredList.length = 0;
			synchronized (master_) foreach (sh; master_) {
				ServerData sd = master_.getServerData(sh);
				string address = sd.server[ServerColumn.ADDRESS];

				if (address in ipHash_ && matchGame(&sd, game)) {
					newHash[address] = -1;
					if (!isFilteredOut(&sd))
						filteredList ~= sh;
				}
			}

			ipHash_ = newHash;
			ipHashValid_ = false;
			isSorted_ = false;
			_sort();
		}
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
	int getFilteredIndex(in char[] ipAndPort, bool* found=null)
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
	size_t totalLength() { synchronized (this) return ipHash_.length; }

	///
	size_t filteredLength() const
	{
		synchronized (this) return filteredList.length;
	}


	/**
	 * Clears the list and the filtered list.  Sets complete to false.
	 */
	void clear()
	{
		synchronized (this) {
			disposeCustomData();
			filteredList.length = 0;
			//ipHash_.clear();
			ipHash_ = null;
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
	void addExtraServer(string address)
	{
		synchronized (this) extraServers_.add(address);
	}


	/// Returns the list of extra servers.
	Set!(string) extraServers() { synchronized (this) return extraServers_; }


	/**
	 * Sorts the filtered list.
	 *
	 * Uses the previously selected _sort order, or the default
	 * if there is none.
	 */
	void sort()
	{
		synchronized (this) _sort();
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
	//HashMap!(char[], int) ipHash_;
	int[string] ipHash_;
	bool ipHashValid_ = false;  // true if the values (indices) are up to date
	Set!(string) extraServers_;
	string gameName_;
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
				log("filteredlist.length == %s\nlist.length == %s",
				                             filteredList.length, list.length);
				assert(0, "Details in log file.");
			}*/
			/*if (!(filters_ || filteredList.length == list.length ||
			                       filteredList.length == (list.length - 1))) {
				log("ServerList invariant broken!"
				    "\nfilters_ & Filter.HAS_HUMANS: %s"
				    "\nfilters_ & Filter.NOT_EMPTY: %s"
				    "\nlist.length: %s"
				    "\nfilteredList.length: %s",
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
			Timer timer;
			timer.start();
		}

		bool lessOrEqual(ServerHandle a, ServerHandle b)
		{
			ServerData sda = master_.getServerData(a);
			ServerData sdb = master_.getServerData(b);

			return compare(sda, sdb) <= 0;
		}

		if (!isSorted_) {
			synchronized (master_) {
				mergeSort(filteredList, &lessOrEqual);
			}
			isSorted_ = true;
			ipHashValid_ = false;
		}

		debug log("ServerList._sort() took ", timer.millis, " milliseconds.");
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

			return compare(sda, sdb) < 0;
		}

		auto r = lib.phobosfixes.upperBound!(less)(filteredList, sh);
		size_t i = filteredList.length - r.length;

		// tried std.array.insert, but got a 30% slowdown
		insertInFiltered(i, sh);

		debug {
			ServerData newSd = master_.getServerData(sh);
			if (i > 0) {
				ServerData before = getFiltered(i - 1);
				assert(compare(newSd, before) >= 0);
			}
			if (filteredList.length > 0 && i < filteredList.length - 1) {
				ServerData after = getFiltered(i + 1);
				assert(compare(newSd, after) < 0);
			}
		}
	}

	/**
	 * Compares two ServerData instances according to the current sort order.
	 *
	 * Returns: >0 if a is smaller, <0 if b is smaller, 0 if they are equal.
	 */
	int compare(ref const ServerData a, ref const ServerData b)
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
				result = cast(int)Integer.parse(a.server[ServerColumn.PING]) -
				         cast(int)Integer.parse(b.server[ServerColumn.PING]);
				break;

			default:
				result = lib.phobosfixes.icmp(a.server[sortColumn_], b.server[sortColumn_]);
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

	string getCountryCode(in ServerData* sd)
	{
		string address = sd.server[ServerColumn.ADDRESS];
		string code = countryCodeByAddr(address[0..findChar(address, ':')]);

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
		log("printFiltered(): %s elements in filteredList.",
		                                                  filteredList.length);
		foreach (i, sh; filteredList) {
			ServerData sd = master_.getServerData(sh);
			log(/*i, ": ",*/ sd.server[ServerColumn.NAME]);
		}
		log("");
	}
}


/// Returns the total number of humans players in the filtered list of servers.
int countHumanPlayers(ServerList serverList)
{
	int players = 0;
	synchronized (serverList) {
		int max = serverList.filteredLength;
		for (int i=0; i < max; i++)
			players += serverList.getFiltered(i).humanCount;
	}
	return players;
}
