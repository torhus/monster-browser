module servertable;

import std.ascii : newline;
import std.conv;
import std.math;
import std.string;

import java.io.ByteArrayInputStream;
import org.eclipse.swt.SWT;
import org.eclipse.swt.events.KeyAdapter;
import org.eclipse.swt.events.KeyEvent;
import org.eclipse.swt.events.MenuDetectEvent;
import org.eclipse.swt.events.MenuDetectListener;
import org.eclipse.swt.events.SelectionAdapter;
import org.eclipse.swt.events.SelectionListener;
import org.eclipse.swt.events.SelectionEvent;
import org.eclipse.swt.graphics.Image;
import org.eclipse.swt.graphics.Color;
import org.eclipse.swt.graphics.ImageData;
import org.eclipse.swt.graphics.Rectangle;
import org.eclipse.swt.graphics.TextLayout;
import org.eclipse.swt.widgets.Composite;
import org.eclipse.swt.widgets.Display;
import org.eclipse.swt.widgets.Event;
import org.eclipse.swt.widgets.Listener;
import org.eclipse.swt.widgets.Menu;
import org.eclipse.swt.widgets.MenuItem;
import org.eclipse.swt.widgets.MessageBox;
import org.eclipse.swt.widgets.Table;
import org.eclipse.swt.widgets.TableColumn;
import org.eclipse.swt.widgets.TableItem;

import colorednames;
import common;
import cvartable;
import dialogs;
import geoip;
import launch;
import mainwindow;
import masterlist;
import messageboxes;
import playertable;
import rcon;
import serveractions;
import serverdata;
import serverlist;
import settings;


__gshared ServerTable serverTable;  ///

// should correspond to serverlist.ServerColumn
immutable serverHeaders = [" ", "Name", "PW", "Ping", "Players", "Game type",
                           "Map", "IP"];


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
		table_ = new Table(parent, SWT.VIRTUAL | SWT.FULL_SELECTION |
		                           SWT.MULTI | SWT.BORDER);
		table_.setHeaderVisible(true);
		table_.setLinesVisible(true);

		int[] widths = parseIntList(getSessionState("serverColumnWidths"),
		                                             serverHeaders.length, 50);

		// add columns
		foreach (i, header; serverHeaders) {
			TableColumn column = new TableColumn(table_, SWT.NONE);
			column.setText(header);
			column.setWidth(widths[i]);
		}

		table_.getColumn(ServerColumn.PASSWORDED).setAlignment(SWT.CENTER);

		table_.addListener(SWT.SetData, new SetDataListener);
		table_.addSelectionListener(new MySelectionListener);
		table_.addKeyListener(new MyKeyListener);

		coloredNames_ = getSetting("coloredNames") == "true";
		showFlags_ = initGeoIp() && (getSetting("showFlags") == "true");

		if (coloredNames_) {
			table_.addListener(SWT.EraseItem, new EraseItemListener);
			table_.addListener(SWT.PaintItem, new PaintItemListener);
		}


		Listener sortListener = new SortListener;

		for (int i = 0; i < table_.getColumnCount(); i++) {
			TableColumn c = table_.getColumn(i);
			c.addListener(SWT.Selection, sortListener);
		}

		// restore sort order from previous session
		int sortCol = 0;
		bool reversed = false;
		try {
			string s = getSessionState("serverSortOrder");
			sortCol = parse!int(s);
			reversed = s.startsWith('r');
			if (sortCol >= serverHeaders.length)
				sortCol = 0;

		}
		catch (ConvException) { }

		table_.setSortColumn(table_.getColumn(sortCol));
		table_.setSortDirection(reversed ? SWT.DOWN : SWT.UP);

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

		timeOutColor_ = Display.getDefault().getSystemColor(SWT.COLOR_RED);
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
		string serverOrder = to!string(serverTable.sortColumn);
		if (serverTable.sortReversed)
			serverOrder ~= "r";
		setSessionState("serverSortOrder", serverOrder);

		string playerOrder = to!string(playerTable.sortColumn);
		if (playerTable.sortReversed)
			playerOrder ~= "r";
		setSessionState("playerSortOrder", playerOrder);

		string cvarWidth = toCsv(getColumnWidths(cvarTable.getTable()));
		setSessionState("cvarColumnWidths", cvarWidth);

		string playerWidth = toCsv(getColumnWidths(playerTable.getTable()));
		setSessionState("playerColumnWidths", playerWidth);

		string serverWidth = toCsv(getColumnWidths(serverTable.getTable()));
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
			bool reversed = table_.getSortDirection() == SWT.DOWN;
			serverList_.sort(sortCol, reversed, false);
			serverList_.setFilters(filterBar.filterState);
		}
	}

	/// The ServerList currently being used.
	ServerList serverList() { return serverList_; }

	/// The index of the currently active sort column.
	int sortColumn() { return table_.indexOf(table_.getSortColumn()); }

	/// Is the sort order reversed?
	bool sortReversed() { return (table_.getSortDirection() == SWT.DOWN); }

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

		table_.setItemCount(cast(int)serverList_.filteredLength);

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

		table_.setItemCount(cast(int)serverList_.filteredLength);
		table_.clearAll();

		int[] indices;
		foreach (ip, v; selectedIps_) {
			auto i = serverList_.getFilteredIndex(ip);
			selectedIps_[ip] = i;
			if (i != -1)
				indices ~= i;
		}

		table_.setSelection(indices);
		setPlayersAndCvars(indices);

		updateStatusBar();
	}

	/// Select one or more servers, replacing the current selection.
	void setSelection(int[] indices, bool takeFocus=false)
	{
		if (table_.isDisposed())
			return;

		assert(indices.length);

		selectedIps_ = null;
		int[] validIndices;
		foreach (i; indices) {
			if (i != -1) {
				validIndices ~= i;
				string address =
				       serverList_.getFiltered(i).server[ServerColumn.ADDRESS];
				selectedIps_[address] = i;
			}
		}
		table_.setSelection(validIndices);
		setPlayersAndCvars(validIndices);

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
		statusBar.setDefaultStatus(cast(uint)serverList_.totalLength,
		                         itemCount, 0, countHumanPlayers(serverList_));
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
		selectedIps_ = null;
	}


	/************************************************
	            PRIVATE MEMBERS
	 ************************************************/
private:
	Table table_;
	Composite parent_;
	ServerList serverList_;
	int[string] selectedIps_;
	bool showFlags_, coloredNames_;
	Image padlockImage_;
	MenuItem refreshSelected_;
	void delegate(bool) stopServerRefresh_;
	bool refreshInProgress_ = false;
	Color timeOutColor_;

	class SetDataListener : Listener {
		void handleEvent(Event e)
		{
			TableItem item = cast(TableItem) e.item;
			int index = table_.indexOf(item);
			assert(index < serverList_.filteredLength);
			auto sd = serverList_.getFiltered(index);

			for (int i = ServerColumn.NAME; i <= ServerColumn.max; i++) {
				item.setText(i, sd.server[i]);
			}

			string countryCode = sd.server[ServerColumn.COUNTRY];
			string ip = sd.server[ServerColumn.ADDRESS];

			if (sd.countryName.length)
				item.setText(ServerColumn.COUNTRY, sd.countryName);
			else if (countryCode.length)
				item.setText(ServerColumn.COUNTRY, countryCode);

			if (showFlags_ && countryCode.length)
				item.setImage(ServerColumn.COUNTRY, getFlagImage(countryCode));

			if (timedOut(&sd)) {
				item.setText(ServerColumn.PING, "\&infin;");
				item.setForeground(ServerColumn.PING, timeOutColor_);
			}
		}
	}

	class MySelectionListener : SelectionListener {
		void widgetSelected(SelectionEvent e)
		{
			selectedIps_ = null;

			synchronized (serverList_) {
				int[] indices = table_.getSelectionIndices;
				if (indices.length) {
					foreach (i; indices) {
						auto sd = serverList_.getFiltered(i);
						selectedIps_[sd.server[ServerColumn.ADDRESS]] = i;
					}
				}
				setPlayersAndCvars(indices);
			}
		}

		void widgetDefaultSelected(SelectionEvent e)
		{
			int index = table_.getSelectionIndex();

			if (index < 0)
				return;

			widgetSelected(e);
			if (stopServerRefresh_ !is null)
				stopServerRefresh_(true);
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
				dir = (dir == SWT.UP) ? SWT.DOWN : SWT.UP;
			} else {
				dir = SWT.UP;
				table_.setSortColumn(newColumn);
			}

			serverList_.sort(table_.indexOf(newColumn), (dir == SWT.DOWN));

			table_.setSortDirection(dir);
			synchronized (serverList_) {
				table_.setItemCount(cast(int)serverList_.filteredLength());
				table_.clearAll();
				// keep the same servers selected
				foreach (ip, v; selectedIps_)
					selectedIps_[ip] = serverList_.getFilteredIndex(ip);
				table_.setSelection(selectedIps_.values);
			}
		}
	}

	class EraseItemListener : Listener {
		void handleEvent(Event e) {
			if (e.index == ServerColumn.NAME && coloredNames_ ||
			                   e.index == ServerColumn.PASSWORDED)
				e.detail &= ~SWT.FOREGROUND;
		}
	}

	class PaintItemListener : Listener {
		void handleEvent(Event e) {
			if (!((e.index == ServerColumn.NAME && coloredNames_) ||
					 e.index == ServerColumn.PASSWORDED))
				return;

			TableItem item = cast(TableItem) e.item;
			auto i = table_.indexOf(item);
			ServerData sd = serverList_.getFiltered(i);

			enum { leftMargin = 2 }

			switch (e.index) {
				case ServerColumn.NAME:
					auto textX = e.x + leftMargin;
					if (!(e.detail & SWT.SELECTED)) {
						TextLayout tl = new TextLayout(Display.getDefault);
						tl.setText(sd.server[ServerColumn.NAME]);

						bool useEtColors = serverList_.useEtColors;
						auto name = parseColors(sd.rawName, useEtColors);
						foreach (r; name.ranges)
							tl.setStyle(r.style, r.start, r.end);

						tl.draw(e.gc, textX, e.y);
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

	class MyKeyListener : KeyAdapter {
		public override void keyPressed (KeyEvent e)
		{
			switch (e.keyCode) {
				case SWT.F9:
					if ((e.stateMask & SWT.MODIFIER_MASK) == 0)
						onRemoteConsole();
					break;
				case SWT.F12:
					// print raw (with color codes) server and player names
					if ((e.stateMask & SWT.MODIFIER_MASK) == 0) {
						int i = table_.getSelectionIndex();
						if (i != -1) {
							string[] s;
							auto sd = serverList_.getFiltered(i);

							log("-------------------------------------------");
							log(sd.rawName);
							log("");
							s ~= sd.rawName;
							s ~= "";
							foreach (p; sd.players) {
								log(p[PlayerColumn.RAWNAME]);
								s ~= p[PlayerColumn.RAWNAME];
							}
							log("-------------------------------------------");

							if (!haveConsole)
								db(s);
						}
					}
					break;
				case SWT.DEL:
					if ((e.stateMask & SWT.MODIFIER_MASK) == 0)
						onRemoveSelected();
					break;
				case 'a':
					if (e.stateMask == SWT.MOD1) {
						// SWT bug? CTRL+A works by default in SWT.
						// In SWT, it marks all items, and fires the
						// widgetSelected event, neither of which happens
						// here.
						onSelectAll();
						e.doit = false;
					}
					break;
				case 'c':
					if (e.stateMask == SWT.MOD1) {
						onCopyAddresses();
						e.doit = false;
					}
					break;
				case 'r':
					if (e.stateMask == SWT.MOD1) {
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

		MenuItem item = new MenuItem(menu, SWT.PUSH);
		item.setText("Join\tEnter");
		menu.setDefaultItem(item);
		item.addSelectionListener(new class SelectionAdapter {
			override void widgetSelected(SelectionEvent e) {
				if (stopServerRefresh_ !is null)
					stopServerRefresh_(true);
				joinServer(serverList_.gameName,
				          serverList_.getFiltered(table_.getSelectionIndex()));
			}
		});

		item = new MenuItem(menu, SWT.PUSH);
		item.setText("Set password");
		item.addSelectionListener(new class SelectionAdapter {
			override void widgetSelected(SelectionEvent e) { onSetPassword(); }
		});


		new MenuItem(menu, SWT.SEPARATOR);

		item = new MenuItem(menu, SWT.PUSH);
		item.setText("Refresh selected\tCtrl+R");
		item.addSelectionListener(new class SelectionAdapter {
			override void widgetSelected(SelectionEvent e)
			{
				onRefreshSelected();
			}
		});
		refreshSelected_ = item;

		item = new MenuItem(menu, SWT.PUSH);
		item.setText("Copy addresses\tCtrl+C");
		item.addSelectionListener(new class SelectionAdapter {
			override void widgetSelected(SelectionEvent e)
			{
				onCopyAddresses();
			}
		});

		item = new MenuItem(menu, SWT.PUSH);
		item.setText("Remove selected\tDel");
		item.addSelectionListener(new class SelectionAdapter {
			override void widgetSelected(SelectionEvent e)
			{
				onRemoveSelected();
			}
		});

		new MenuItem(menu, SWT.SEPARATOR);

		item = new MenuItem(menu, SWT.PUSH);
		item.setText("Remote console\tF9");
		item.addSelectionListener(new class SelectionAdapter {
			override void widgetSelected(SelectionEvent e)
			{
				onRemoteConsole();
			}
		});

		item = new MenuItem(menu, SWT.PUSH);
		item.setText("Remove selected\tDel");
		item.addSelectionListener(new class SelectionAdapter {
			override void widgetSelected(SelectionEvent e)
			{
				onRemoveSelected();
			}
		});

		new MenuItem(menu, SWT.SEPARATOR);

		item = new MenuItem(menu, SWT.PUSH);
		item.setText("Remote console\tF9");
		item.addSelectionListener(new class SelectionAdapter {
			override void widgetSelected(SelectionEvent e)
			{
				onRemoteConsole();
			}
		});

		return menu;
	}

	void onCopyAddresses()
	{
		string[] addresses;
		foreach (ip, v; selectedIps_)
			addresses ~= ip;
		if (addresses.length)
			copyToClipboard(join(addresses, newline));
	}

	void onRefreshSelected()
	{
		string[] addresses;

		if (selectedIps_.length == 0)
			return;

		foreach (ip, v; selectedIps_)
			addresses ~= ip;
		queryServers(addresses, true);
	}

	void onRemoveSelected()
	{
		MasterList master = serverList_.master;
		string[] toRemove;

		// find all servers that are both selected and not filtered out
		foreach (ip, index; selectedIps_) {
			if (index != -1)
				toRemove ~= ip;
		}

		if (toRemove.length == 0)
			return;


		synchronized (serverList_) synchronized (master) {
			// ask user for confirmation
			int style = SWT.ICON_QUESTION | SWT.YES | SWT.NO;
			MessageBox mb = new MessageBox(mainWindow.handle, style);
			if (toRemove.length == 1) {
				mb.setText("Remove server");
				int index = selectedIps_[toRemove[0]];
				ServerData sd = serverList_.getFiltered(index);
				string name = sd.server[ServerColumn.NAME];
				mb.setMessage("Are you sure you want to remove \"" ~ name ~
				                                                        "\"?");
			}
			else {
				mb.setText("Remove servers");
				string count = to!string(toRemove.length);
				mb.setMessage("Are you sure you want to remove these " ~
				                                          count ~ " servers?");
			}

			if (mb.open() == SWT.YES) {
				// do the actual removal
				foreach (string ip; toRemove) {
					int index = selectedIps_[ip];
					ServerHandle sh = serverList_.getServerHandle(index);
					ServerData sd = master.getServerData(sh);
					setEmpty(&sd);
					master.setServerData(sh, sd);
					selectedIps_.remove(ip);
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
		string address = sd.server[ServerColumn.ADDRESS];
		string message =
		          "Set the password to be used when joining the server.\n" ~
		          "The password will be saved on disk.\n\n" ~
		          "To delete the stored password, clear the password field\n" ~
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
		string name = sd.server[ServerColumn.NAME];
		string address = sd.server[ServerColumn.ADDRESS];
		string pw = getRconPassword(address);

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
		table_.selectAll();
		selectedIps_ = null;

		synchronized (serverList_) {
			int[] indices;

			for (size_t i=0; i < serverList_.filteredLength; i++) {
				auto sd = serverList_.getFiltered(i);
				selectedIps_[sd.server[ServerColumn.ADDRESS]] = cast(int)i;
				indices ~= cast(int)i;
			}
			setPlayersAndCvars(indices);
		}
	}

	void setPlayersAndCvars(int[] selectedServers)
	{
		playerTable.setItems(selectedServers, serverList_);
		if (table_.getSelectionCount() == 1) {
			auto sd = serverList_.getFiltered(table_.getSelectionIndex());
			cvarTable.setItems(sd.cvars);
		}
		else {
			cvarTable.clear();
		}
	}

	int getBottomIndex()
	{
		double q = cast(double)(table_.getClientArea().height -
		                    table_.getHeaderHeight()) / table_.getItemHeight();
		return cast(int)ceil(q) + table_.getTopIndex() - 1;
	}
}
