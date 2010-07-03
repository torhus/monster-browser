module playertable;

import std.string;

import org.eclipse.swt.SWT;
import org.eclipse.swt.events.MenuDetectEvent;
import org.eclipse.swt.events.MenuDetectListener;
import org.eclipse.swt.events.SelectionAdapter;
import org.eclipse.swt.events.SelectionEvent;
import org.eclipse.swt.graphics.Point;
import org.eclipse.swt.graphics.TextLayout;
import org.eclipse.swt.widgets.Composite;
import org.eclipse.swt.widgets.Display;
import org.eclipse.swt.widgets.Event;
import org.eclipse.swt.widgets.Listener;
import org.eclipse.swt.widgets.Menu;
import org.eclipse.swt.widgets.MenuItem;
import org.eclipse.swt.widgets.Table;
import org.eclipse.swt.widgets.TableColumn;
import org.eclipse.swt.widgets.TableItem;

import colorednames;
import common;
import serverdata;
import serverlist;
import servertable;
import settings;


__gshared PlayerTable playerTable;  ///

// should correspond to serverlist.PlayerColumn
enum playerHeaders = ["Name", "Score", "Ping"];


///
class PlayerTable
{
	///
	this(Composite parent)
	{
		parent_ = parent;
		table_ = new Table(parent, SWT.VIRTUAL | SWT.BORDER |
		                           SWT.FULL_SELECTION);
		table_.setHeaderVisible(true);
		table_.setLinesVisible(true);

		int[] widths = parseIntList(getSessionState("playerColumnWidths"),
		                                             playerHeaders.length, 50);

		// add columns
		foreach (int i, header; playerHeaders) {
			TableColumn column = new TableColumn(table_, SWT.NONE);
			column.setText(header);
			column.setWidth(widths[i]);
		}

		table_.addListener(SWT.SetData, new class Listener {
			public void handleEvent(Event e)
			{
				TableItem item = cast(TableItem) e.item;
				string[] data = players_[table_.indexOf(item)].data;
				item.setText(data[0 .. table_.getColumnCount()]);
			}
		});

		if (getSetting("coloredNames") == "true") {
			table_.addListener(SWT.EraseItem, new class Listener {
				void handleEvent(Event e) {
					if (e.index == PlayerColumn.NAME)
						e.detail &= ~SWT.FOREGROUND;
				}
			});

			table_.addListener(SWT.PaintItem, new class Listener {
				void handleEvent(Event e) {
					if (e.index != PlayerColumn.NAME)
						return;

					TableItem item = cast(TableItem) e.item;
					string[] data = players_[table_.indexOf(item)].data;
					scope tl = new TextLayout(Display.getDefault);

					tl.setText(data[PlayerColumn.NAME]);
					string rawName = data[PlayerColumn.RAWNAME];
					bool useEtColors = serverList_.useEtColors;
					foreach (r; parseColors(rawName, useEtColors).ranges)
						tl.setStyle(r.style, r.start, r.end);

					if (e.detail & SWT.SELECTED)
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
					dir = (dir == SWT.UP) ? SWT.DOWN : SWT.UP;
				} else {
					table_.setSortColumn(newColumn);
					dir = SWT.UP;
				}

				table_.setSortDirection(dir);
				sort();
				table_.clearAll();
			}
		};

		for (int i = 0; i < table_.getColumnCount(); i++) {
			TableColumn c = table_.getColumn(i);
			c.addListener(SWT.Selection, sortListener);
		}

		// restore sort order from previous session
		string s = getSessionState("playerSortOrder");
		uint ate;
		int sortCol = cast(int)Integer.convert(s, 10, &ate);
		bool reversed = (s.length > ate && s[ate] == 'r');
		if (sortCol >= playerHeaders.length)
			sortCol = 0;
		table_.setSortColumn(table_.getColumn(sortCol));
		table_.setSortDirection(reversed ? SWT.DOWN : SWT.UP);

		table_.addListener(SWT.MouseMove, new MouseMoveListener);

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
	bool sortReversed() { return (table_.getSortDirection() == SWT.DOWN); }

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

		sort();
		table_.setItemCount(players_.length);
		table_.clearAll();
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

			string text = null;
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

		MenuItem item = new MenuItem(menu, SWT.PUSH);
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
		bool reverse = (table_.getSortDirection() == SWT.DOWN) ^ isScore;

		bool lessOrEqual(Player a, Player b)
		{
			int result;

			if (numerical) {
				result = cast(int)Integer.parse(a.data[sortCol]) -
				         cast(int)Integer.parse(b.data[sortCol]);
			}
			else {
				result = icmp(a.data[sortCol], b.data[sortCol]);
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
	string[] data;    // Ordered according to the PlayerColumn enum.
	int serverIndex;  // Index into the filtered list of servers.
}
