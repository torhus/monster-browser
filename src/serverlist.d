module serverlist;

import core.stdc.string : memmove;
import std.algorithm;
import std.conv;
import std.range;
import std.regex;
import std.string;
import std.uni : sicmp;

import common;
import gameconfig;
import geoip;
import masterlist;
import serverdata;
import set;


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
	bool complete = false;


	///
	this(string gameName, MasterList master, bool useEtColors)
	in {
		assert(gameName.length > 0);
		assert(master !is null);
	}
	do {
		gameName_ = gameName;
		master_ = master;
		useEtColors_ = useEtColors;
		searchDg_ = &filterServer;
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
	 * By default only servers previously added by calling add() or replace()
	 * will be considered, set checkForNew to true to include all servers.
	 */
	void refillFromMaster(bool checkForNew=false)
	{
		refill(checkForNew);
	}


	/**
	 * Return a server from the filtered list.
	 *
	 * Complexity is O(1).
	 */
	ServerData getFiltered(size_t i)
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
	size_t totalLength() const
	{
		synchronized (this) return ipHash_.length;
	}

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
			filteredList.length = 0;
			ipHash_ = null;
			isSorted_ = true;
			complete = false;
		}
	}


	/**
	 * Add extra servers to be included when doing a refresh.
	 *
	 * Useful for servers that are not on the master server's list.
	 */
	void addExtraServers(R)(R range)
		if (isInputRange!R && is(ElementType!R == string))
	{
		synchronized (this) extraServers_.add(range);
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
			refill(false);
		}
	}

	Filter getFilters() { return filters_; } ///

	bool setSearchString(string s, bool servers) ///
	{
		if (s == searchString_ && (servers && searchDg_ == &filterServer ||
		                            !servers && searchDg_ == &filterPlayer))
			return false;

		synchronized (this) {
			searchDg_ = servers ? &filterServer : &filterPlayer;
			if (searchString_.length == 0 && s.length == 0)
				return false;
			searchString_ = s;
			regex_ = regex(to!string(escaper(s)), "i");
			refill(false);
			return true;
		}
	}


	///
	void verifySorted()
	{
		if (filteredLength < 2)
			return;

		log("Verifying sorting...");

		auto servers = filteredList.map!(sh => master_.getServerData(sh));
		bool ok = true;

		synchronized (this) synchronized (master_)
		foreach (i, data; servers.slide(2).enumerate) {
			if (compare(data[0], data[1]) > 0) {
				ok = false;
				log("BAD SORTING at server index %s", i);
			}
		}
		assert(ok, "ServerList verifySorted() failed.");
		if (ok)
			log("Sorting OK.");
	}


/***********************************************************************
 *                                                                     *
 *                        PRIVATE SECTION                              *
 *                                                                     *
 ***********************************************************************/
private:
	ServerHandle[] filteredList;
	// maps addresses to indices into the filtered list
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

	string searchString_;
	bool delegate(ServerData*) searchDg_;
	Regex!char regex_;


	invariant
	{
		synchronized (this) {
			if (filteredList.length > ipHash_.length) {
				log("filteredlist.length == %s\nipHash_.length == %s",
				                   filteredList.length, ipHash_.length);
				assert(0);
			}
			if (!(filters_ || filteredList.length == ipHash_.length ||
			                  (filteredList.length + 1) == ipHash_.length ||
			                                           searchString_.length)) {
				log("ServerList invariant broken!" ~
				    "\nfilters_ & Filter.HAS_HUMANS: %s" ~
				    "\nfilters_ & Filter.NOT_EMPTY: %s" ~
				    "\nipHash_.length: %s" ~
				    "\nfilteredList.length: %s" ~
				    "\nsearchString_.length: %s",
				    filters_ & Filter.HAS_HUMANS,
				    filters_ & Filter.NOT_EMPTY,
				    ipHash_.length, filteredList.length, searchString_.length);
				assert(0);
			}
		}
	}


	/**
	* Add or replace a server in the list.
	*
	* Returns true if the filtered list was altered.
	*/
	bool addOrReplace(ServerHandle sh, bool replace=false)
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
				string ip = sd.server[ServerColumn.ADDRESS];
				GeoInfo geo = getGeoInfo(ip[0..findChar(ip, ':')]);

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
			Timer timer;
			timer.start();
		}

		bool less(ServerHandle a, ServerHandle b)
		{
			ServerData sda = master_.getServerData(a);
			ServerData sdb = master_.getServerData(b);

			return compare(sda, sdb) < 0;
		}

		if (!isSorted_) {
			synchronized (master_) {
				filteredList.sort!(less, SwapStrategy.stable);
			}
			isSorted_ = true;
			ipHashValid_ = false;
		}

		debug log("ServerList._sort() took %s milliseconds.", timer.millis);
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

		auto r = filteredList.assumeSorted!less.upperBound(sh);
		size_t i = filteredList.length - r.length;

		filteredList.insertInPlace(i, sh);
		ipHashValid_ = false;

		debug {
			ServerData newSd = master_.getServerData(sh);
			if (i > 0) {
				ServerData before = getFiltered(i - 1);
				assert(compare(newSd, before) >= 0);
			}
			if (filteredList.length > 0 && i + 1 < filteredList.length) {
				ServerData after = getFiltered(i + 1);
				assert(compare(newSd, after) < 0);
			}
		}
	}


	/// This is private to avoid triggering the invariant.
	void refill(bool checkForNew)
	{
		GameConfig game = getGameConfig(gameName_);
		typeof(ipHash_) newHash;

		filteredList.length = 0;

		synchronized (this) synchronized (master_) foreach (sh; master_) {
			ServerData sd = master_.getServerData(sh);
			string address = sd.server[ServerColumn.ADDRESS];

			if ((address in ipHash_ || checkForNew) && matchGame(&sd, game)) {
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
	 * Compares two ServerData instances according to the current sort order.
	 *
	 * Returns: >0 if a is smaller, <0 if b is smaller, 0 if they are equal.
	 */
	int compare(const ref ServerData a, const ref ServerData b)
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
			case ServerColumn.GAMETYPE_NUM:
				result = toIntOrDefault(a.server[sortColumn_]) -
				         toIntOrDefault(b.server[sortColumn_]);
				break;

			default:
				result = sicmp(a.server[sortColumn_], b.server[sortColumn_]);
		}

		return (reversed_ ? -result : result);
	}


	/// ditto
	/// FIXME: Use -preview=in instead of having this overload?
	int compare(const ServerData a, const ServerData b)
	{
		return compare(a, b);
	}


	bool removeFromFiltered(in char[] address)
	{
		int i = getFilteredIndex(address);
		if (i == -1)
			return false;

		filteredList = filteredList.remove(i);
		filteredList.assumeSafeAppend;

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

	bool isFilteredOut(ServerData* sd)
	{
		bool matched = searchString_.length == 0 ? true : searchDg_(sd);

		if (matched) {
			if (filters_ == Filter.NONE || sd.hasHumans)
				return false;
			else
				return filters_ & Filter.HAS_HUMANS || !sd.hasBots;
		}
		else {
			return true;
		}
	}

	bool filterServer(ServerData* sd)
	{
		string serverName = sd.server[ServerColumn.NAME];
		bool matched = false;

		if (serverName.matchFirst(regex_)) {
			matched = true;
		}
		else {
			string[] cvar = sd.cvars.getCvar("game");

			if (cvar && cvar[1].matchFirst(regex_)) {
				matched = true;
			}
			else {
				cvar = sd.cvars.getCvar("gamename");
				if (cvar && cvar[1].matchFirst(regex_)) {
					matched = true;
				}
			}
		}

		return matched;
	}

	bool filterPlayer(ServerData* sd)
	{
		if (sd.players.length == 0)
			return false;

		if (sd.players[0][PlayerColumn.NAME] is null)
		{
			addCleanPlayerNames(sd.players);
		}

		foreach (player; sd.players) {
			if (player[PlayerColumn.NAME].matchFirst(regex_))
				return true;
		}

		return false;
	}


	void updateIpHash(bool reset=true)
	{
		if (reset) {
			foreach (ref val; ipHash_)
				val = -1;
		}
		foreach (i, sh; filteredList) {
			ServerData sd = master_.getServerData(sh);
			ipHash_[sd.server[ServerColumn.ADDRESS]] = cast(int)i;
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
			log("%4d %-25s %4s", i, sd.server[ServerColumn.NAME],
			                                     sd.server[ServerColumn.PING]);
		}
		log("");
	}
}


/// Returns the total number of humans players in the filtered list of servers.
int countHumanPlayers(ServerList serverList)
{
	int players = 0;
	synchronized (serverList) {
		auto max = serverList.filteredLength;
		for (int i=0; i < max; i++)
			players += serverList.getFiltered(i).humanCount;
	}
	return players;
}
