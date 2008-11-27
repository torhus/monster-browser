module servertable;

import tango.io.stream.TextFileStream;
import tango.stdc.math : ceil;
import tango.text.Util;
import Integer = tango.text.convert.Integer;
import tango.util.container.HashMap;

import dwt.DWT;
import dwt.dwthelper.ByteArrayInputStream;
import dwt.events.KeyAdapter;
import dwt.events.KeyEvent;
import dwt.events.MenuDetectEvent;
import dwt.events.MenuDetectListener;
import dwt.events.SelectionAdapter;
import dwt.events.SelectionListener;
import dwt.events.SelectionEvent;
import dwt.graphics.Image;
import dwt.graphics.ImageData;
import dwt.graphics.Rectangle;
import dwt.graphics.TextLayout;
import dwt.widgets.Composite;
import dwt.widgets.Display;
import dwt.widgets.Event;
import dwt.widgets.Listener;
import dwt.widgets.Menu;
import dwt.widgets.MenuItem;
import dwt.widgets.Table;
import dwt.widgets.TableColumn;
import dwt.widgets.TableItem;

import colorednames;
import common;
import cvartable;
import geoip;
import launch;
import playertable;
import serveractions;
import serverlist;
import settings;


ServerTable serverTable;  ///

// should correspond to serverlist.ServerColumn
char[][] serverHeaders =
                   [" ", "Name", "PW", "Ping", "Players", "Game", "Map", "IP"];


/**
 * GUI for displaying the server list.  Also controls what the cvar and
 * player tables displays.
 */
class ServerTable
{
	///
	this(Composite parent)
	{
		parent_ = parent;
		table_ = new Table(parent, DWT.VIRTUAL | DWT.FULL_SELECTION |
		                           DWT.MULTI | DWT.BORDER);
		table_.setHeaderVisible(true);
		table_.setLinesVisible(true);

		int[] widths = parseIntegerSequence(
		                                getSessionState("serverColumnWidths"));
		// FIXME use defaults if wrong length?
		widths.length = serverHeaders.length;

		// add columns
		foreach (int i, header; serverHeaders) {
			TableColumn column = new TableColumn(table_, DWT.NONE);
			column.setText(header);
			column.setWidth(widths[i]);
		}

		table_.getColumn(ServerColumn.PASSWORDED).setAlignment(DWT.CENTER);

		table_.addListener(DWT.SetData, new SetDataListener);
		table_.addSelectionListener(new MySelectionListener);
		table_.addKeyListener(new MyKeyListener);

		coloredNames_ = getSetting("coloredNames") == "true";
		showFlags_ = (getSetting("showFlags") == "true") && initGeoIp();

		if (showFlags_ || coloredNames_) {
			table_.addListener(DWT.EraseItem, new EraseItemListener);
			table_.addListener(DWT.PaintItem, new PaintItemListener);
		}

		if (showFlags_)
			table_.addListener(DWT.MouseMove, new MouseMoveListener);

		Listener sortListener = new SortListener;

		for (int i = 0; i < table_.getColumnCount(); i++) {
			TableColumn c = table_.getColumn(i);
			c.addListener(DWT.Selection, sortListener);
		}

		// restore sort order from previous session
		char[] s = getSessionState("serverSortOrder");
		uint ate;
		int sortCol = Integer.convert(s, 10, &ate);
		bool reversed = (s.length > ate && s[ate] == 'r');
		if (sortCol >= serverHeaders.length)
			sortCol = 0;
		table_.setSortColumn(table_.getColumn(sortCol));
		table_.setSortDirection(reversed ? DWT.DOWN : DWT.UP);

		// right-click menu for servers
		table_.setMenu(createContextMenu);
		table_.addMenuDetectListener(new class MenuDetectListener {
			void menuDetected(MenuDetectEvent e)
			{
				if (table_.getSelectionCount == 0)
					e.doit = false;
			}
		});

		// padlock image for passworded servers
		auto stream  = new ByteArrayInputStream(
		                                    cast(byte[])import("padlock.png"));
		auto data = new ImageData(stream);
		padlockImage_ = new Image(Display.getDefault, data.scaledTo(12, 12));

		selectedIps_ = new HashMap!(char[], int);
	}


	///
	void disposeAll() { padlockImage_.dispose; }

	/**
	 * Sets the currently active ServerList.
	 *
	 * If there is no ServerList object for the given mod, one will be created,
	 * and the corresponding list of extra servers will be loaded from disk.
	 *
	 * Returns:  true if the mod already had a ServerList object, false if a
	 *           new one had to be created.  Also returns false if the object
	 *           exists, but contains an incomplete list.
	 *
	 * Throws: OutOfMemoryError
	 */
	bool setServerList(in char[] modName)
	{
		bool thereAlready;
		Filter savedFilters;

		// hack to get the correct filtering set up for the new list,
		// save the old one here for later use
		if (serverList_ !is null) {
			savedFilters = serverList_.getFilters();
		}
		else {
			savedFilters = cast(Filter)Integer.convert(
			                                   getSessionState("filterState"));
		}

		if (ServerList* list = modName in serverLists) {
			serverList_ = *list;
			thereAlready = serverList_.complete;
		}
		else {
			serverList_ = new ServerList(modName);
			serverLists[modName] = serverList_;
			thereAlready = false;

			auto file = getModConfig(modName).extraServersFile;
			try {
				if (Path.exists(file)) {
					auto input = new TextFileInput(file);
					auto servers = collectIpAddresses(input);
					input.close;
					foreach (s; servers)
						serverList_.addExtraServer(s);
				}
			}
			catch (IOException e) {
				log("Error when reading \"" ~ file ~ "\".");
			}
		}

		serverList_.setFilters(savedFilters, false);

		auto sortCol = table_.getSortColumn();
		synchronized (serverList_) {
			serverList_.sort(table_.indexOf(sortCol),
			                   (table_.getSortDirection() == DWT.DOWN), false);
		}

		return thereAlready;
	}

	///
	ServerList getServerList() { return serverList_; }

	/// The index of the currently active sort column.
	int sortColumn() { return table_.indexOf(table_.getSortColumn()); }

	/// Is the sort order reversed?
	bool sortReversed() { return (table_.getSortDirection() == DWT.DOWN); }

	/// Returns the server list's Table widget object.
	Table getTable() { return table_; };

	///
	void notifyRefreshStarted(void delegate() stopServerRefresh=null)
	{
		refreshInProgress_ = true;
		stopServerRefresh_ = stopServerRefresh;
		if (!refreshSelected_.isDisposed)
			refreshSelected_.setEnabled(false);
	}

	///
	void notifyRefreshEnded()
	{
		refreshInProgress_ = false;
		stopServerRefresh_ = null;
		if (!refreshSelected_.isDisposed)
			refreshSelected_.setEnabled(true);
	}

	///
	bool stopRefresh()
	{
		refreshInProgress_ = false;
		if (stopServerRefresh_ !is null) {
			stopServerRefresh_();
			return true;
		}
		return false;
	}

	///
	bool refreshInProgress() { return refreshInProgress_ ; }

	/*void update(Object dummy = null)
	{
		if (!table_.isDisposed)
			table_.setItemCount(serverList_.filteredLength);
	}*/


	/**
	 * If necessary clears the table and refills it with updated data.
	 *
	 * Keeps the same selection if there was one.
	 */
	void quickRefresh()
	{
		if(table_.isDisposed())
			return;

		int itemCount = table_.getItemCount();
		int bottom = getBottomIndex();
		bool needRefresh = false;

		// Check to see if the bottommost visible item has moved or not.
		if (bottom < serverList_.filteredLength && bottom < itemCount) {
			TableItem bottomItem = table_.getItem(bottom);
			enum { col = ServerColumn.ADDRESS }
			if (bottomItem.getText(col) !=
		                           serverList_.getFiltered(bottom).server[col])
				needRefresh = true;
		}

		// Only refill the Table if visible items, or items further up have
		// moved.  Refilling every time is very, very slow.
		if (needRefresh || itemCount <= bottom) {
			table_.setItemCount(serverList_.filteredLength);
			table_.clearAll();
		}

		// Keep the same servers selected.
		table_.deselectAll();
		foreach (ip, v; selectedIps_) {
			int index = serverList_.getFilteredIndex(ip);
			selectedIps_[ip] = index;
			table_.select(index);
		}
	}

	/**
	 * In addition to clearing the table and refilling it with updated data
	 * without losing the selection (like quickRefresh(), only
	 * unconditionally), it also:
	 *
	 * 1. Updates the cvar and player tables to show information for the
	 *    selected server, or clears them if there is no server selected.
	 * 2. Optionally sets the selection to the server specified by index.
	 *
	 * Params:
	 *     index = If not equal to -1, the server with the given index is
	 *             selected.
	 */
	void fullRefresh(int index=-1)
	{
		if(table_.isDisposed())
			return;

		table_.clearAll();
		table_.setItemCount(serverList_.filteredLength);

		int[] indices;
		if (index != -1) {
			indices ~= index;
		}
		else {
			foreach (ip, v; selectedIps_)
				selectedIps_[ip] = serverList_.getFilteredIndex(ip);
			indices = selectedIps_.toArray();
		}

		if (indices.length) {
			table_.setSelection(indices);
			
			char[][][] allPlayers;
			foreach (i; indices) {
				if (i < serverList_.filteredLength)
					allPlayers ~= serverList_.getFiltered(i).players;
			}
			playerTable.setItems(allPlayers);

			cvarTable.clear();
			int i = table_.getSelectionIndex();
			if (i >= 0 && i < serverList_.filteredLength)
				cvarTable.setItems(serverList_.getFiltered(i).cvars);
		}
		else {
			table_.deselectAll();
			playerTable.clear();
			cvarTable.clear();
		}
	}

	/// Empty the server, player, and cvar tables.
	void clear()
	{
		if (table_.isDisposed)
			return;

		table_.setItemCount(0);
		table_.clearAll;

		cvarTable.clear;
		playerTable.clear;
	}

	///
	void forgetSelection()
	{
		selectedIps_.reset();
	}
	

	/************************************************
	            PRIVATE MEMBERS
	 ************************************************/
private:
	Table table_;
	Composite parent_;
	ServerList serverList_;
	HashMap!(char[], int) selectedIps_;
	bool showFlags_, coloredNames_;
	Image padlockImage_;
	MenuItem refreshSelected_;
	void delegate() stopServerRefresh_;
	bool refreshInProgress_ = false;

	class SetDataListener : Listener {
		void handleEvent(Event e)
		{
			TableItem item = cast(TableItem) e.item;
			int index = table_.indexOf(item);
			assert(index < serverList_.filteredLength);
			auto sd = serverList_.getFiltered(index);
			
			// Find and store country code.
			/*if (sd.server[ServerColumn.COUNTRY].length == 0) {
				char[] ip = sd.server[ServerColumn.ADDRESS];
				auto colon = locate(ip, ':');
				char[] country = countryCodeByAddr(ip[0..colon]);
				sd.server[ServerColumn.COUNTRY] = country;
			}*/

			// add text
			for (int i = ServerColumn.COUNTRY + 1; i <= ServerColumn.max; i++)
				// http://dsource.org/projects/dwt-win/ticket/6
				item.setText(i, sd.server[i] ? sd.server[i] : "");
		}
	}

	class MySelectionListener : SelectionListener {
		void widgetSelected(SelectionEvent e)
		{
			selectedIps_.clear();

			synchronized (serverList_) {
				int[] indices = table_.getSelectionIndices;
				char[][][] allPlayers;
				if (indices.length) {
					foreach (i; indices) {
						auto sd = serverList_.getFiltered(i);
						selectedIps_[sd.server[ServerColumn.ADDRESS]] = i;
						allPlayers ~= sd.players;
					}

					auto sd =
					         serverList_.getFiltered(table_.getSelectionIndex);
					cvarTable.setItems(sd.cvars);
					playerTable.setItems(allPlayers);
				}
				else {
					cvarTable.clear;
					playerTable.clear;
				}
			}
		}

		void widgetDefaultSelected(SelectionEvent e)
		{
			widgetSelected(e);
			if (stopServerRefresh_ !is null)
				stopServerRefresh_();
			int index = table_.getSelectionIndex();
			joinServer(serverList_.modName, serverList_.getFiltered(index));
		}
	}

	class SortListener : Listener {
		void handleEvent(Event e)
		{
			// determine new sort column and direction
			auto sortColumn = table_.getSortColumn;
			auto newColumn = cast(TableColumn)e.widget;
			int dir = table_.getSortDirection;

			if (sortColumn is newColumn) {
				dir = (dir == DWT.UP) ? DWT.DOWN : DWT.UP;
			} else {
				dir = DWT.UP;
				table_.setSortColumn(newColumn);
			}

			serverList_.sort(table_.indexOf(newColumn), (dir == DWT.DOWN));

			table_.setSortDirection(dir);
			synchronized (serverList_) {
				table_.clearAll();
				table_.setItemCount(serverList_.filteredLength());
				// keep the same servers selected
				foreach (ip, v; selectedIps_)
					selectedIps_[ip] = serverList_.getFilteredIndex(ip);
				table_.setSelection(selectedIps_.toArray());
			}
		}
	}

	class EraseItemListener : Listener {
		void handleEvent(Event e) {
			if (e.index == ServerColumn.NAME && coloredNames_ ||
			                   e.index == ServerColumn.COUNTRY && showFlags_ ||
			                   e.index == ServerColumn.PASSWORDED)
				e.detail &= ~DWT.FOREGROUND;
		}
	}

	class PaintItemListener : Listener {
		void handleEvent(Event e) {
			if (!((e.index == ServerColumn.NAME && coloredNames_) ||
					(e.index == ServerColumn.COUNTRY && showFlags_) ||
					 e.index == ServerColumn.PASSWORDED))
				return;

			TableItem item = cast(TableItem) e.item;
			auto i = table_.indexOf(item);
			ServerData* sd = serverList_.getFiltered(i);

			enum { leftMargin = 2 }

			switch (e.index) {
				case ServerColumn.COUNTRY:
					char[] country = sd.server[ServerColumn.COUNTRY];
					if (showFlags_ && country.length) {
						if (Image flag = getFlagImage(country))
							// could cache the flag Image here
							e.gc.drawImage(flag, e.x+1, e.y+1);
						else
							e.gc.drawString(country, e.x + leftMargin, e.y);
					}
					break;
				case ServerColumn.NAME:
					auto textX = e.x + leftMargin;
					if (!(e.detail & DWT.SELECTED)) {
						TextLayout tl = sd.customData;
						if (tl is null) {
							auto parsed = parseColors(sd.rawName);
							tl = new TextLayout(Display.getDefault);
							tl.setText(sd.server[ServerColumn.NAME]);
							foreach (r; parsed.ranges)
								tl.setStyle(r.style, r.start, r.end);

							sd.customData = tl;  // cache it
						}

						tl.draw(e.gc, textX, e.y);
					}
					else {
						auto name = sd.server[ServerColumn.NAME];
						e.gc.drawString(name, textX, e.y);
					}
					break;
				case ServerColumn.PASSWORDED:
					if (sd.server[ServerColumn.PASSWORDED].length)
						e.gc.drawImage(padlockImage_, e.x+4, e.y+1);
					break;
				default:
					assert(0);
			}
		}
	}

	class MouseMoveListener : Listener {
		void handleEvent(Event event) {
			char[] text = null;
			scope point = new Point(event.x, event.y);
			TableItem item = table_.getItem(point);
			if (item && item.getBounds(ServerColumn.COUNTRY).contains(point)) {
				int i = table_.indexOf(item);
				ServerData* sd = serverList_.getFiltered(i);
				char[] ip = sd.server[ServerColumn.ADDRESS];
				auto colon = locate(ip, ':');
				text = countryNameByAddr(ip[0..colon]);
			}
			if (table_.getToolTipText() != text)
				table_.setToolTipText(text);
		}
	}

	class MyKeyListener : KeyAdapter {
		public void keyPressed (KeyEvent e)
		{
			switch (e.keyCode) {
				case 'a':
					if (e.stateMask == DWT.MOD1) {
						// DWT bug? CTRL+A works by default in SWT.
						// In SWT, it marks all items, and fires the
						// widgetSelected event, neither of which happens
						// here.
						table_.selectAll();
						onSelectAll();
						e.doit = false;
					}
					break;
				case 'c':
					if (e.stateMask == DWT.MOD1) {
						onCopyAddresses();
						e.doit = false;
					}
					break;
				case 'r':
					if (e.stateMask == DWT.MOD1) {
						if (refreshSelected_.getEnabled)
							onRefreshSelected();
						e.doit = false;
					}
					break;
				default:
					break;
			}
		}
	}

	Menu createContextMenu()
	{
		Menu menu = new Menu(table_);

		MenuItem item = new MenuItem(menu, DWT.PUSH);
		item.setText("Join\tEnter");
		menu.setDefaultItem(item);
		item.addSelectionListener(new class SelectionAdapter {
			void widgetSelected(SelectionEvent e) {
				joinServer(serverList_.modName,
				          serverList_.getFiltered(table_.getSelectionIndex()));
			}
		});

		item = new MenuItem(menu, DWT.PUSH);
		item.setText("Refresh selected\tCtrl+R");
		item.addSelectionListener(new class SelectionAdapter {
			void widgetSelected(SelectionEvent e) { onRefreshSelected(); }
		});
		refreshSelected_ = item;

		item = new MenuItem(menu, DWT.PUSH);
		item.setText("Copy addresses\tCtrl+C");
		item.addSelectionListener(new class SelectionAdapter {
			void widgetSelected(SelectionEvent e) { onCopyAddresses(); }
		});

		return menu;
	}

	void onCopyAddresses()
	{		
		char[][] addresses;
		foreach (ip, v; selectedIps_)
			addresses ~= ip;
		char[] s = join(addresses, newline);
		if (s.length) {
			s ~= newline;
			copyToClipboard(s);
		}
	}

	void onRefreshSelected()
	{
		char[][] addresses;

		if (selectedIps_.size == 0)
			return;

		foreach (ip, v; selectedIps_)
			addresses ~= ip;
		queryServers(addresses, true);
	}
	
	void onSelectAll()
	{
		selectedIps_.clear();

		synchronized (serverList_) {
			char[][][] allPlayers;

			for (size_t i=0; i < serverList_.filteredLength; i++) {
				auto sd = serverList_.getFiltered(i);
				selectedIps_[sd.server[ServerColumn.ADDRESS]] = i;
				allPlayers ~= sd.players;
			}

			auto sd = serverList_.getFiltered(table_.getSelectionIndex);
			cvarTable.setItems(sd.cvars);
			playerTable.setItems(allPlayers);
		}
	}

	int[] getIndicesFromAddresses(char[][] addresses)
	{
		int[] indices;

		foreach (char[] a; addresses) {
			int i = serverList_.getFilteredIndex(a);
			if (i != -1)
				indices ~= i;
		}
		return indices;
	}

	int getBottomIndex()
	{
		double q = cast(double)(table_.getClientArea().height -
		                    table_.getHeaderHeight()) / table_.getItemHeight();
		return cast(int)ceil(q) + table_.getTopIndex() - 1;
	}
}
