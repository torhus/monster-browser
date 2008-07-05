module servertable;

import tango.text.Util;
import Integer = tango.text.convert.Integer;

import dwt.DWT;
import dwt.events.SelectionAdapter;
import dwt.events.SelectionEvent;
import dwt.graphics.Image;
import dwt.graphics.ImageData;
import dwt.graphics.Rectangle;
import dwt.graphics.TextLayout;
import dwt.widgets.Composite;
import dwt.widgets.Display;
import dwt.widgets.Event;
import dwt.events.KeyAdapter;
import dwt.events.KeyEvent;
import dwt.widgets.Listener;
import dwt.widgets.Menu;
import dwt.widgets.MenuItem;
import dwt.widgets.Table;
import dwt.widgets.TableColumn;
import dwt.widgets.TableItem;
import dwt.dwthelper.ByteArrayInputStream;

import colorednames;
import common;
import geoip;
import launch;
import main;
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
		                           DWT.BORDER);
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

		table_.addListener(DWT.SetData, new class Listener {
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
				for (int i = ServerColumn.COUNTRY + 1; i <= ServerColumn.max;
				                                                         i++) {
					// http://dsource.org/projects/dwt-win/ticket/6
					item.setText(i, sd.server[i] ? sd.server[i] : "");
				}
			}
		});

		coloredNames_ = getSetting("coloredNames") == "true";
		showFlags_ = (getSetting("showFlags") == "true") && initGeoIp();

		if (showFlags_ || coloredNames_) {
			table_.addListener(DWT.EraseItem, new class Listener {
				void handleEvent(Event e) {
					if (e.index == ServerColumn.NAME && coloredNames_ ||
					           e.index == ServerColumn.COUNTRY && showFlags_ ||
					           e.index == ServerColumn.PASSWORDED)
						e.detail &= ~DWT.FOREGROUND;
				}
			});

			table_.addListener(DWT.PaintItem, new class Listener {
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
									e.gc.drawString(country, e.x + leftMargin,
									                                      e.y);
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
								e.gc.drawString(sd.server[ServerColumn.NAME],
								                                   textX, e.y);
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
			});

			table_.addListener(DWT.MouseMove, new class Listener {
				void handleEvent(Event event) {
					char[] text = null;
					scope point = new Point(event.x, event.y);
					TableItem item = table_.getItem(point);
					if (item && item.getBounds(ServerColumn.COUNTRY).
					                                         contains(point)) {
						int i = table_.indexOf(item);
						ServerData* sd = getActiveServerList.getFiltered(i);
						char[] ip = sd.server[ServerColumn.ADDRESS];
						auto colon = locate(ip, ':');
						text = countryNameByAddr(ip[0..colon]);
					}
					if (table_.getToolTipText() != text)
						table_.setToolTipText(text);
				}
			});
		}

		table_.addSelectionListener(new class SelectionAdapter {
			void widgetSelected(SelectionEvent e)
			{
				int i = table_.getSelectionIndex();
				if (i != -1) {
					auto sd = getActiveServerList.getFiltered(i);
					selectedIp_ = sd.server[ServerColumn.ADDRESS];
					cvarTable.setItems(sd.cvars);
					playerTable.setItems(sd.players);
				}
				else {
					selectedIp_ = null;
					cvarTable.clear;
					playerTable.clear;
				}
			}

			void widgetDefaultSelected(SelectionEvent e)
			{
				widgetSelected(e);
				joinServer(getActiveServerList.getFiltered(
				                                   table_.getSelectionIndex));
			}
		});
		
		table_.addKeyListener(new class KeyAdapter {
			public void keyPressed (KeyEvent e)
			{
				switch (e.keyCode) {
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
		});

		Listener sortListener = new class Listener {
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
				}

				// keep the same server selected
				int i = getActiveServerList.getFilteredIndex(selectedIp_);
				if (i != -1)
					table_.setSelection(i);

			}
		};

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

		// padlock image for passworded servers
		auto stream  = new ByteArrayInputStream(
		                                    cast(byte[])import("padlock.png"));
		auto data = new ImageData(stream);
		padlockImage_ = new Image(Display.getDefault, data.scaledTo(12, 12));
	}


	///
	~this() { padlockImage_.dispose; }

	/// The index of the currently active sort column.
	int sortColumn() { return table_.indexOf(table_.getSortColumn()); }

	/// Is the sort order reversed?
	bool sortReversed() { return (table_.getSortDirection() == DWT.DOWN); }

	/// Returns the server list's Table widget object.
	Table getTable() { return table_; };

	///
	void notifyRefreshStarted()
	{
		if (!refreshSelected_.isDisposed)
			refreshSelected_.setEnabled(false);
	}
	
	///
	void notifyRefreshEnded()
	{
		if (!refreshSelected_.isDisposed)
			refreshSelected_.setEnabled(true);
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
			int selected = table_.getSelectionIndex();
			int i = (cast(IntWrapper)index).value;

			if (i <= getBottomIndex() /*&& i >= table_.getTopIndex()*/) {
				table_.clearAll();
				table_.setItemCount(getActiveServerList.filteredLength);
			}

			if (selected != -1 && i <= selected) {
					table_.deselectAll();
					table_.select(selected + 1);
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
	 * 1. Sets the status bar to the default status.
	 * 2. Updates the cvar and player tables to show information for the
	 *    selected server, or clears them if there is no server selected.
	 * 3. Optionally sets the selection to the server specified by index.
	 *
	 * Params:
	 *     index   = An IntWrapper object.  If not null, the server with the
	 *               given index is selected.
	 *     noReply = If > 0, display in the status bar how many servers didn't
	 *               reply.
	 */
	void reset(Object index=null, uint noReply=0)
	{
		if(table_.isDisposed())
			return;

		refresh();
		volatile if (!runtools.abortParsing && getActiveServerList.complete) {
			statusBar.setDefaultStatus(getActiveServerList.length,
			                           getActiveServerList.filteredLength,
			                           noReply);
		}

		int i;
		if (index !is null) {
			i = (cast(IntWrapper)index).value;
		}
		else {
			// Keep the same server selected.
			i = getActiveServerList.getFilteredIndex(selectedIp_);
		}

		if (i != -1) {
			table_.setSelection(i);
			auto sd = getActiveServerList.getFiltered(i);
			playerTable.setItems(sd.players);
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


	/************************************************
	            PRIVATE MEMBERS
	 ************************************************/
private:
	Table table_;
	Composite parent_;
	char[] selectedIp_;
	bool showFlags_, coloredNames_;
	Image padlockImage_;
	MenuItem refreshSelected_;

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
		item.setText("Refresh this only\tCtrl+R");
		item.addSelectionListener(new class SelectionAdapter {
			void widgetSelected(SelectionEvent e) { onRefreshSelected(); }
		});
		refreshSelected_ = item;

		item = new MenuItem(menu, DWT.PUSH);
		item.setText("Copy address\tCtrl+C");
		item.addSelectionListener(new class SelectionAdapter {
			void widgetSelected(SelectionEvent e) { onCopyAddresses(); }
		});

		return menu;
	}

	void onCopyAddresses()
	{
		synchronized (getActiveServerList) {
			ServerData* sd = getActiveServerList.getFiltered(
			                                       table_.getSelectionIndex());
			copyToClipboard(sd.server[ServerColumn.ADDRESS]);
		}
	}

	void onRefreshSelected()
	{
		synchronized (getActiveServerList) {
			ServerData* sd = getActiveServerList.getFiltered(
			                                       table_.getSelectionIndex());
			querySingleServer(sd.server[ServerColumn.ADDRESS]);
		}
	}

	int getBottomIndex()
	{
		return table_.getClientArea().height / table_.getItemHeight() +
		                                                  table_.getTopIndex();
	}
}
