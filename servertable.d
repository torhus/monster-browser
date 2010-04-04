module servertable;

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
import dwt.widgets.MessageBox;
import dwt.widgets.Table;
import dwt.widgets.TableColumn;
import dwt.widgets.TableItem;

import colorednames;
import common;
import cvartable;
import dialogs;
import geoip;
import launch;
import mainwindow;
import masterlist;
import playertable;
import rcon;
import serveractions;
import serverdata;
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

		int[] widths = parseIntList(getSessionState("serverColumnWidths"),
		                                             serverHeaders.length, 50);

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
	void disposeAll()
	{
		padlockImage_.dispose();
		disposeFlagImages();
	}


	///  Saves the session state.
	void saveState()
	{
		char[] serverOrder = Integer.toString(serverTable.sortColumn);
		if (serverTable.sortReversed)
			serverOrder ~= "r";
		setSessionState("serverSortOrder", serverOrder);

		char[] playerOrder = Integer.toString(playerTable.sortColumn);
		if (playerTable.sortReversed)
			playerOrder ~= "r";
		setSessionState("playerSortOrder", playerOrder);

		char[] cvarWidth = toCsv(getColumnWidths(cvarTable.getTable()));
		setSessionState("cvarColumnWidths", cvarWidth);

		char[] playerWidth = toCsv(getColumnWidths(playerTable.getTable()));
		setSessionState("playerColumnWidths", playerWidth);

		char[] serverWidth = toCsv(getColumnWidths(serverTable.getTable()));
		setSessionState("serverColumnWidths", serverWidth);
	}


	/**
	 * Sets the currently active ServerList.
	 *
	 * The new ServerList will be configured with the current sort order and
	 * filter settings.
	 */
	void setServerList(ServerList newList)
	{
		int sortCol = table_.indexOf(table_.getSortColumn());

		serverList_ = newList;

		synchronized (serverList_) {
			bool reversed = table_.getSortDirection() == DWT.DOWN;
			serverList_.sort(sortCol, reversed, false);
			serverList_.setFilters(filterBar.filterState, false);
		}
	}

	/// The ServerList currently being used.
	ServerList serverList() { return serverList_; }

	/// The index of the currently active sort column.
	int sortColumn() { return table_.indexOf(table_.getSortColumn()); }

	/// Is the sort order reversed?
	bool sortReversed() { return (table_.getSortDirection() == DWT.DOWN); }

	/// Returns the server list's Table widget object.
	Table getTable() { return table_; };

	///
	void notifyRefreshStarted(void delegate(bool) stopServerRefresh=null)
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
	bool stopRefresh(bool addRemaining)
	{
		if (!refreshInProgress_)
			return true;

		refreshInProgress_ = false;
		if (stopServerRefresh_ !is null) {
			stopServerRefresh_(addRemaining);
			return true;
		}
		return false;
	}

	/**
	 * If necessary clears the table and refills it with updated data.
	 *
	 * Keeps the same selection if there was one.  Updates the status bar main
	 * info.
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

		table_.setItemCount(serverList_.filteredLength);

		// Only refill the Table if visible items, or items further up have
		// moved.  Refilling every time is very slow.
		if (needRefresh || itemCount <= bottom)
			table_.clearAll();

		// Keep the same servers selected.
		table_.deselectAll();
		foreach (ip, v; selectedIps_) {
			int index = serverList_.getFilteredIndex(ip);
			selectedIps_[ip] = index;
			table_.select(index);
		}

		updateStatusBar();
	}

	/**
	 * In addition to clearing the table and refilling it with updated data
	 * without losing the selection (like quickRefresh(), only
	 * unconditionally), it also updates the cvar and player tables to show
	 * information for the selected servers, or clears them if there are no
	 * servers selected.
	 *
	 * Also updates the status bar main info.
	 */
	void fullRefresh()
	{
		if(table_.isDisposed())
			return;

		table_.setItemCount(serverList_.filteredLength);
		table_.clearAll();

		int[] indices;
		foreach (ip, v; selectedIps_) {
			auto i = serverList_.getFilteredIndex(ip);
			selectedIps_[ip] = i;
			if (i != -1)
				indices ~= i;
		}

		if (indices.length) {
			table_.setSelection(indices);
			playerTable.setItems(indices, serverList_);
			int cvarIndex = table_.getSelectionIndex();
			cvarTable.setItems(serverList_.getFiltered(cvarIndex).cvars);
		}
		else {
			table_.deselectAll();
			playerTable.clear();
			cvarTable.clear();
		}

		updateStatusBar();
	}

	/// Select one or more servers, replacing the current selection.
	void setSelection(int[] indices, bool takeFocus=false)
	{
		if (table_.isDisposed())
			return;

		assert(indices.length);

		selectedIps_.clear();
		int[] validIndices;
		foreach (i; indices) {
			if (i != -1) {
				validIndices ~= i;
				char[] address =
				       serverList_.getFiltered(i).server[ServerColumn.ADDRESS];
				selectedIps_[address] = i;
			}
		}
		table_.setSelection(validIndices);
		if (validIndices.length > 0) {
			playerTable.setItems(validIndices, serverList_);
			int cvarIndex = table_.getSelectionIndex();
			cvarTable.setItems(serverList_.getFiltered(cvarIndex).cvars);
		}
		else {
			playerTable.clear();
			cvarTable.clear();
		}

		if (takeFocus)
			table_.setFocus();
	}

	/**
	 * Updates the status main status bar info to show the current number of
	 * servers and players.
	 *
	 * Any method that alters the number of visible servers, or the number of
	 * players on those servers, should call this when it is done making
	 * changes.
	 *
	 * Note:
	 *     Changes to the player or cvar tables do not affect the status bar,
	 *     so it's not necessary to call this method in those cases.
	 */
	void updateStatusBar()
	{
		if (table_.isDisposed())
			return;

		int itemCount = table_.getItemCount();
		assert(itemCount == serverList_.filteredLength || itemCount == 0);
		statusBar.setDefaultStatus(serverList_.totalLength, itemCount, 0,
		                                       countHumanPlayers(serverList_));
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

		updateStatusBar();
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
	void delegate(bool) stopServerRefresh_;
	bool refreshInProgress_ = false;

	class SetDataListener : Listener {
		void handleEvent(Event e)
		{
			TableItem item = cast(TableItem) e.item;
			int index = table_.indexOf(item);
			assert(index < serverList_.filteredLength);
			auto sd = serverList_.getFiltered(index);

			// add text
			for (int i = ServerColumn.COUNTRY + 1; i <= ServerColumn.max; i++)
				item.setText(i, sd.server[i]);

			if (timedOut(&sd))
				item.setText(ServerColumn.PING, "\&infin;");
		}
	}

	class MySelectionListener : SelectionListener {
		void widgetSelected(SelectionEvent e)
		{
			selectedIps_.clear();

			synchronized (serverList_) {
				int[] indices = table_.getSelectionIndices;
				if (indices.length) {
					foreach (i; indices) {
						auto sd = serverList_.getFiltered(i);
						selectedIps_[sd.server[ServerColumn.ADDRESS]] = i;
					}

					auto sd =
					         serverList_.getFiltered(table_.getSelectionIndex);
					cvarTable.setItems(sd.cvars);
					playerTable.setItems(indices, serverList_);
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
				stopServerRefresh_(true);
			int index = table_.getSelectionIndex();
			joinServer(serverList_.gameName, serverList_.getFiltered(index));
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
				table_.setItemCount(serverList_.filteredLength());
				table_.clearAll();
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
			ServerData sd = serverList_.getFiltered(i);

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
						// FIXME: this caching is broken now
						TextLayout tl = sd.customData;
						if (tl is null) {
							tl = new TextLayout(Display.getDefault);
							tl.setText(sd.server[ServerColumn.NAME]);
							foreach (r; parseColors(sd.rawName).ranges)
								tl.setStyle(r.style, r.start, r.end);

							sd.customData = tl;  // cache it
						}

						tl.draw(e.gc, textX, e.y);
						// FIXME: don't dispose if caching it
						tl.dispose();
					}
					else {
						auto name = sd.server[ServerColumn.NAME];
						e.gc.drawString(name, textX, e.y);
					}
					break;
				case ServerColumn.PASSWORDED:
					if (sd.server[ServerColumn.PASSWORDED] == PASSWORD_YES)
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
				ServerData sd = serverList_.getFiltered(i);
				if (sd.server[ServerColumn.COUNTRY].length) {
					char[] ip = sd.server[ServerColumn.ADDRESS];
					auto colon = locate(ip, ':');
					text = countryNameByAddr(ip[0..colon]);
				}
			}
			if (table_.getToolTipText() != text)
				table_.setToolTipText(text);
		}
	}

	class MyKeyListener : KeyAdapter {
		public void keyPressed (KeyEvent e)
		{
			switch (e.keyCode) {
				case DWT.F9: case DWT.F10:
					// F10 is deprecated, as it is the standard key for opening
					// the menu on Windows.
					if ((e.stateMask & DWT.MODIFIER_MASK) == 0)
						onRemoteConsole();
					break;
				case DWT.DEL:
					if ((e.stateMask & DWT.MODIFIER_MASK) == 0)
						onRemoveSelected();
					break;
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
				if (stopServerRefresh_ !is null)
					stopServerRefresh_(true);
				joinServer(serverList_.gameName,
				          serverList_.getFiltered(table_.getSelectionIndex()));
			}
		});

		item = new MenuItem(menu, DWT.PUSH);
		item.setText("Set password");
		item.addSelectionListener(new class SelectionAdapter {
			void widgetSelected(SelectionEvent e) { onSetPassword(); }
		});


		new MenuItem(menu, DWT.SEPARATOR);

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

		item = new MenuItem(menu, DWT.PUSH);
		item.setText("Remove selected\tDel");
		item.addSelectionListener(new class SelectionAdapter {
			void widgetSelected(SelectionEvent e) { onRemoveSelected(); }
		});

		new MenuItem(menu, DWT.SEPARATOR);

		item = new MenuItem(menu, DWT.PUSH);
		item.setText("Remote console\tF9");
		item.addSelectionListener(new class SelectionAdapter {
			void widgetSelected(SelectionEvent e) { onRemoteConsole(); }
		});

		return menu;
	}

	void onCopyAddresses()
	{
		char[][] addresses;
		foreach (ip, v; selectedIps_)
			addresses ~= ip;
		if (addresses.length)
			copyToClipboard(join(addresses, newline));
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

	void onRemoveSelected()
	{
		MasterList master = serverList_.master;
		char[][] toRemove;

		// find all servers that are both selected and not filtered out
		foreach (ip, index; selectedIps_) {
			if (index != -1)
				toRemove ~= ip;
		}

		if (toRemove.length == 0)
			return;


		synchronized (serverList_) synchronized (master) {
			// ask user for confirmation
			int style = DWT.ICON_QUESTION | DWT.YES | DWT.NO;
			MessageBox mb = new MessageBox(mainWindow.handle, style);
			if (toRemove.length == 1) {
				mb.setText("Remove server");
				int index = selectedIps_[toRemove[0]];
				ServerData sd = serverList_.getFiltered(index);
				char[] name = sd.server[ServerColumn.NAME];
				mb.setMessage("Are you sure you want to remove \"" ~ name ~
				                                                        "\"?");
			}
			else {
				mb.setText("Remove servers");
				char[] count = Integer.toString(toRemove.length);
				mb.setMessage("Are you sure you want to remove these " ~
				                                          count ~ " servers?");
			}

			if (mb.open() == DWT.YES) {
				// do the actual removal
				foreach (char[] ip; toRemove) {
					int index = selectedIps_[ip];
					ServerHandle sh = serverList_.getServerHandle(index);
					ServerData sd = master.getServerData(sh);
					setEmpty(&sd);
					master.setServerData(sh, sd);
					selectedIps_.removeKey(ip);
				}

				// refresh filtered list and update GUI
				serverList_.refillFromMaster();
				fullRefresh();
			}
		}
	}


	void onSetPassword()
	{
		int index = table_.getSelectionIndex();
		if (index == -1)
			return;

		ServerData sd = serverList_.getFiltered(index);
		char[] address = sd.server[ServerColumn.ADDRESS];
		char[] message =
		            "Set the password to be used when joining the server.\n"
		            "The password will be saved on disk.\n\n"
		            "To delete the stored password, clear the password field\n"
		            "and press OK.";

		scope dialog = new ServerPasswordDialog(mainWindow.handle,
		                                     "Set Password", message, address);
		if (dialog.open() && !dialog.password.length)
			removePassword(address);
	}


	void onRemoteConsole()
	{
		int index = table_.getSelectionIndex();
		if (index == -1)
			return;

		ServerData sd = serverList_.getFiltered(index);
		char[] name = sd.server[ServerColumn.NAME];
		char[] address = sd.server[ServerColumn.ADDRESS];
		char[] pw = getRconPassword(address);

		if (pw.length > 0) {
			openRconWindow(name, address, pw);
		}
		else {
			auto dialog = new RconPasswordDialog(mainWindow.handle, name,
			                                                          address);
			if (dialog.open())
				openRconWindow(name, address, dialog.password);
		}
	}

	void onSelectAll()
	{
		selectedIps_.clear();

		synchronized (serverList_) {
			int[] indices;

			for (size_t i=0; i < serverList_.filteredLength; i++) {
				auto sd = serverList_.getFiltered(i);
				selectedIps_[sd.server[ServerColumn.ADDRESS]] = i;
				indices ~= i;
			}

			auto sd = serverList_.getFiltered(table_.getSelectionIndex);
			cvarTable.setItems(sd.cvars);
			playerTable.setItems(indices, serverList_);
		}
	}

	int getBottomIndex()
	{
		double q = cast(double)(table_.getClientArea().height -
		                    table_.getHeaderHeight()) / table_.getItemHeight();
		return cast(int)ceil(q) + table_.getTopIndex() - 1;
	}
}
