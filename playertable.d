module playertable;

import tango.text.Ascii;

import dwt.DWT;
import dwt.events.MenuDetectEvent;
import dwt.events.MenuDetectListener;
import dwt.events.SelectionAdapter;
import dwt.events.SelectionEvent;
import dwt.graphics.Point;
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
import serverdata;
import serverlist;
import servertable;
import settings;


PlayerTable playerTable;  ///

// should correspond to serverlist.PlayerColumn
char[][] playerHeaders = ["Name", "Score", "Ping"];


///
class PlayerTable
{
	///
	this(Composite parent)
	{
		parent_ = parent;
		table_ = new Table(parent, DWT.VIRTUAL | DWT.BORDER |
		                           DWT.FULL_SELECTION);
		table_.setHeaderVisible(true);
		table_.setLinesVisible(true);

		int[] widths = parseIntList(getSessionState("playerColumnWidths"),
		                                             playerHeaders.length, 50);

		// add columns
		foreach (int i, header; playerHeaders) {
			TableColumn column = new TableColumn(table_, DWT.NONE);
			column.setText(header);
			column.setWidth(widths[i]);
		}

		table_.addListener(DWT.SetData, new class Listener {
			public void handleEvent(Event e)
			{
				TableItem item = cast(TableItem) e.item;
				char[][] data = players_[table_.indexOf(item)].data;
				item.setText(data[0 .. table_.getColumnCount()]);
			}
		});

		if (getSetting("coloredNames") == "true") {
			table_.addListener(DWT.EraseItem, new class Listener {
				void handleEvent(Event e) {
					if (e.index == PlayerColumn.NAME)
						e.detail &= ~DWT.FOREGROUND;
				}
			});

			table_.addListener(DWT.PaintItem, new class Listener {
				void handleEvent(Event e) {
					if (e.index != PlayerColumn.NAME)
						return;

					TableItem item = cast(TableItem) e.item;
					char[][] data = players_[table_.indexOf(item)].data;
					scope tl = new TextLayout(Display.getDefault);

					tl.setText(data[PlayerColumn.NAME]);
					foreach (r; parseColors(data[PlayerColumn.RAWNAME]).ranges)
						tl.setStyle(r.style, r.start, r.end);

					if (e.detail & DWT.SELECTED)
						e.gc.drawString(tl.getText, e.x+2, e.y);
					else
						tl.draw(e.gc, e.x+2, e.y);
					tl.dispose();
				}
			});
		}

		Listener sortListener = new class Listener {
			public void handleEvent(Event e)
			{
				auto oldColumn = table_.getSortColumn();
				auto newColumn = cast(TableColumn)e.widget;
				int dir = table_.getSortDirection();

				if (newColumn is oldColumn) {
					dir = (dir == DWT.UP) ? DWT.DOWN : DWT.UP;
				} else {
					table_.setSortColumn(newColumn);
					dir = DWT.UP;
				}

				table_.setSortDirection(dir);
				sort();
				table_.clearAll();
			}
		};

		for (int i = 0; i < table_.getColumnCount(); i++) {
			TableColumn c = table_.getColumn(i);
			c.addListener(DWT.Selection, sortListener);
		}

		// restore sort order from previous session
		char[] s = getSessionState("playerSortOrder");
		uint ate;
		int sortCol = Integer.convert(s, 10, &ate);
		bool reversed = (s.length > ate && s[ate] == 'r');
		if (sortCol >= playerHeaders.length)
			sortCol = 0;
		table_.setSortColumn(table_.getColumn(sortCol));
		table_.setSortDirection(reversed ? DWT.DOWN : DWT.UP);

		table_.addListener(DWT.MouseMove, new MouseMoveListener);

		table_.addSelectionListener(new class SelectionAdapter {
			void widgetDefaultSelected(SelectionEvent e)
			{
				TableItem item = cast(TableItem)e.item;
				int serverIndex = players_[table_.indexOf(item)].serverIndex;
				serverTable.setSelection([serverIndex], true);
			}
		});

		table_.setMenu(createContextMenu());
		table_.addMenuDetectListener(new class MenuDetectListener {
			void menuDetected(MenuDetectEvent e)
			{
				if (table_.getSelectionCount() == 0)
					e.doit = false;
			}
		});
	}

	/// The index of the currently active sort column.
	int sortColumn() { return table_.indexOf(table_.getSortColumn()); }

	/// Is the sort order reversed?
	bool sortReversed() { return (table_.getSortDirection() == DWT.DOWN); }

	/// Returns the player list's Table widget object.
	Table getTable() { return table_; };

	/**
	 * Set the contents of this table.
	 *
	 * Params:
	 *     serverIndices = Indices into the filtered list of servers.
	 *     serverList    = The ServerList instances that the indices are for.
	 */
	void setItems(int[] serverIndices, ServerList serverList)
	{
		assert(serverIndices.length > 0 && serverList !is null);

		moreThanOneServer_ = serverIndices.length > 1;

		players_.length = 0;
		foreach (serverIndex; serverIndices) {
			auto sd = serverList.getFiltered(serverIndex);
			foreach (player; sd.players)
				players_ ~= Player(player, serverIndex);
		}

		serverList_ = serverList;
		addCleanPlayerNames();

		table_.setItemCount(players_.length);
		table_.clearAll();
		sort();
	}

	///
	void clear()
	{
		table_.removeAll();
		players_.length = 0;
	}

	/************************************************
	            PRIVATE MEMBERS
	 ************************************************/
private:
	Table table_;
	Composite parent_;
	ServerList serverList_;
	Player[] players_;
	bool moreThanOneServer_;


	class MouseMoveListener : Listener {
		void handleEvent(Event event) {
			if (!moreThanOneServer_) {
				table_.setToolTipText(null);
				return;
			}

			char[] text = null;
			scope point = new Point(event.x, event.y);
			TableItem item = table_.getItem(point);

			if (item && item.getBounds(PlayerColumn.NAME).contains(point)) {
				int serverIndex = players_[table_.indexOf(item)].serverIndex;
				ServerData sd = serverList_.getFiltered(serverIndex);
				text = sd.server[ServerColumn.NAME];
			}

			if (table_.getToolTipText() != text)
				table_.setToolTipText(text);
		}
	}


	Menu createContextMenu()
	{
		Menu menu = new Menu(table_);

		MenuItem item = new MenuItem(menu, DWT.PUSH);
		item.setText("Select server\tEnter");
		menu.setDefaultItem(item);
		item.addSelectionListener(new class SelectionAdapter {
			void widgetSelected(SelectionEvent e) {
				int index = players_[table_.getSelectionIndex()].serverIndex;
				serverTable.setSelection([index], true);
			}
		});

		return menu;
	}


	void sort()
	{
		int sortCol = table_.indexOf(table_.getSortColumn());
		bool isScore = sortCol == PlayerColumn.SCORE;
		bool isPing = sortCol == PlayerColumn.PING;
		bool numerical = isScore || isPing;
		bool reverse = (table_.getSortDirection() == DWT.DOWN) ^ isScore;

		bool lessOrEqual(Player a, Player b)
		{
			int result;

			if (numerical) {
				result = Integer.parse(a.data[sortCol]) -
				         Integer.parse(b.data[sortCol]);
			}
			else {
				result = icompare(a.data[sortCol], b.data[sortCol]);
			}
			return (reverse ? -result <= 0 : result <= 0);
		}

		mergeSort(players_, &lessOrEqual);
	}


	void addCleanPlayerNames()
	{
		foreach (p; players_)
			if (p.data[PlayerColumn.NAME] is null)
				p.data[PlayerColumn.NAME] =
				                 stripColorCodes(p.data[PlayerColumn.RAWNAME]);
	}

}


private struct Player {
	char[][] data;    // Ordered according to the PlayerColumn enum.
	int serverIndex;  // Index into the filtered list of servers.
}
