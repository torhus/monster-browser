module servertable;

import tango.text.Util;
import Integer = tango.text.convert.Integer;

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
import geoip;
import launch;
import mainwindow;
import serveractions;
import serverlist;
import settings;


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
	}


	///
	void disposeAll() { padlockImage_.dispose; }

	/// The index of the currently active sort column.
	int sortColumn() { return table_.indexOf(table_.getSortColumn()); }

	/// Is the sort order reversed?
	bool sortReversed() { return (table_.getSortDirection() == DWT.DOWN); }

	/// Returns the server list's Table widget object.
	Table getTable() { return table_; };

	///
	void notifyRefreshStarted(void delegate() stopServerRefresh=null)
	{
		stopServerRefresh_ = stopServerRefresh;
		if (!refreshSelected_.isDisposed)
			refreshSelected_.setEnabled(false);
	}

	///
	void notifyRefreshEnded()
	{
		stopServerRefresh_ = null;
		if (!refreshSelected_.isDisposed)
			refreshSelected_.setEnabled(true);
	}

	///
	bool stopRefresh()
	{
		if (stopServerRefresh_ !is null) {
			stopServerRefresh_();
			return true;
		}
		return false;
	}

	/*void update(Object dummy = null)
	{
		if (!table_.isDisposed)
			table_.setItemCount(getActiveServerList.filteredLength);
	}*/


	/**
	 * Clears the table and refills it with updated data.  Keeps the same
	 * selection if there was one, and if index is not null.
	 *
	 * Params:
	 *     index = An IntWrapper object.  Set this to the index of the last
	 *             added element.  If refilling the contents of the table would
	 *             not make this element visible, the table is not refilled.
	 *             If the argument is null, the table is always refilled.
	 *
	 */
	void refresh(Object index = null)
	{
		if(table_.isDisposed())
			return;

		if (index) {
			int[] selected = table_.getSelectionIndices;
			int i = (cast(IntWrapper)index).value;

			if (i <= getBottomIndex() /*&& i >= table_.getTopIndex()*/) {
				table_.clearAll();
				table_.setItemCount(getActiveServerList.filteredLength);
			}

			// not sure which way is the fastest...
			version (all) {
				if (selected.length) {
					// Restore selection, compensating for the newly inserted item.
					foreach (ref sel; selected) {
						if (i <= sel) {
							sel++;
							assert(sel < getActiveServerList.filteredLength);
						}
					}
					table_.setSelection(selected);
				}
			}
			else {
				// Move all selection markers below the new item down by one.
				foreach (sel; selected) {
					if (i <= sel) {
						table_.deselect(sel);
						table_.select(sel + 1);
					}
				}
			}
		}
		else {
			table_.clearAll();
			table_.setItemCount(getActiveServerList.filteredLength);
		}
	}

	/**
	 * In addition to clearing the table and refilling it with updated data
	 * without losing the selection (like refresh()), it also:
	 *
	 * 1. Updates the cvar and player tables to show information for the
	 *    selected server, or clears them if there is no server selected.
	 * 2. Optionally sets the selection to the server specified by index.
	 *
	 * Params:
	 *     index = An IntWrapper object.  If not null, the server with the
	 *             given index is selected.
	 */
	void reset(Object index=null)
	{
		if(table_.isDisposed())
			return;

		refresh();

		int[] indices;
		if (index && (cast(IntWrapper)index).value != -1) {
			indices ~= (cast(IntWrapper)index).value;
		}
		else {
			indices = getIndicesFromAddresses(selectedIps_);
		}

		if (indices.length) {
			table_.setSelection(indices);

			auto list = getActiveServerList;
			char[][][] allPlayers;
			foreach (i; indices)
				allPlayers ~= list.getFiltered(i).players;
			playerTable.setItems(allPlayers);

			auto sd = list.getFiltered(table_.getSelectionIndex);
			cvarTable.setItems(sd.cvars);
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
		delete selectedIps_;
	}
	

	/************************************************
	            PRIVATE MEMBERS
	 ************************************************/
private:
	Table table_;
	Composite parent_;
	char[][] selectedIps_;
	bool showFlags_, coloredNames_;
	Image padlockImage_;
	MenuItem refreshSelected_;
	void delegate() stopServerRefresh_;

	class SetDataListener : Listener {
		void handleEvent(Event e)
		{
			TableItem item = cast(TableItem) e.item;
			int index = table_.indexOf(item);
			assert(index < getActiveServerList.filteredLength);
			auto sd = getActiveServerList.getFiltered(index);
			
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
			delete selectedIps_;
			auto list = getActiveServerList;

			synchronized (list) {
				int[] indices = table_.getSelectionIndices;
				char[][][] allPlayers;
				if (indices.length) {
					foreach (i; indices) {
						auto sd = list.getFiltered(i);
						selectedIps_ ~= sd.server[ServerColumn.ADDRESS];
						allPlayers ~= sd.players;
					}

					auto sd = list.getFiltered(table_.getSelectionIndex);
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
			joinServer(getActiveServerList.getFiltered(index));
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

			getActiveServerList.sort(table_.indexOf(newColumn),
														(dir == DWT.DOWN));

			table_.setSortDirection(dir);
			synchronized (getActiveServerList) {
				table_.clearAll();
				table_.setItemCount(getActiveServerList.filteredLength());
				// keep the same servers selected
				table_.setSelection(getIndicesFromAddresses(selectedIps_));
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
			ServerData* sd = getActiveServerList.getFiltered(i);

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
				ServerData* sd = getActiveServerList.getFiltered(i);
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
				joinServer(getActiveServerList.getFiltered(
				                                  table_.getSelectionIndex()));
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
		char[] s = join(selectedIps_, newline);
		if (s.length) {
			s ~= newline;
			copyToClipboard(s);
		}
	}

	void onRefreshSelected()
	{
		if (selectedIps_.length)
			queryServers(selectedIps_, true);
	}
	
	void onSelectAll()
	{
		selectedIps_.length = 0;
		auto list = getActiveServerList;

		synchronized (list) {
			char[][][] allPlayers;

			for (size_t i=0; i < list.filteredLength; i++) {
				auto sd = list.getFiltered(i);
				selectedIps_ ~= sd.server[ServerColumn.ADDRESS];
				allPlayers ~= sd.players;
			}

			auto sd = list.getFiltered(table_.getSelectionIndex);
			cvarTable.setItems(sd.cvars);
			playerTable.setItems(allPlayers);
		}
	}

	int[] getIndicesFromAddresses(char[][] addresses)
	{
		int[] indices;
		auto list = getActiveServerList;
		
		foreach (char[] a; addresses) {
			int i = list.getFilteredIndex(a);
			if (i != -1)
				indices ~= i;
		}
		return indices;
	}

	int getBottomIndex()
	{
		return table_.getClientArea().height / table_.getItemHeight() +
		                                                  table_.getTopIndex();
	}
}
