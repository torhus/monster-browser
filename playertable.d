module playertable;

private {
	version (Tango) {
		import dwt.DWT;
		import dwt.graphics.TextLayout;
		import dwt.widgets.Composite;
		import dwt.widgets.Event;
		import dwt.widgets.Listener;
		import dwt.widgets.Table;
		import dwt.widgets.TableColumn;
		import dwt.widgets.TableItem;
	}
	else import dwt.all;

	import colorednames;
	import common;
	import serverlist;
	import main;
	import settings;
}

// should correspond to serverlist.PlayerColumn
char[][] playerHeaders = ["Name", "Score", "Ping"];

class PlayerTable
{
	/*************************************************
	               PUBLIC METHODS
	*************************************************/
	this(Composite parent)
	{
		parent_ = parent;
		table_ = new Table(parent, DWT.VIRTUAL |  DWT.BORDER |
		                           DWT.HIDE_SELECTION);
		table_.setHeaderVisible(true);
		table_.setLinesVisible(true);

		foreach (header; playerHeaders) {
			TableColumn column = new TableColumn(table_, DWT.NONE);
			column.setText(header);
		}

		table_.getColumn(0).setWidth(100);
		table_.getColumn(1).setWidth(40);
		table_.getColumn(2).setWidth(40);

		table_.addListener(DWT.SetData, new class Listener {
			public void handleEvent(Event e)
			{
				TableItem item = cast(TableItem) e.item;
				auto sd = getActiveServerList.getFiltered(selectedServerIndex_);
				auto player = sd.players[table_.indexOf(item)];
				item.setText(player[0 .. table_.getColumnCount()]);
			}
		});

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
				auto sd = getActiveServerList.getFiltered(selectedServerIndex_);
				auto player = sd.players[table_.indexOf(item)];
				scope parsed = parseColors(player[PlayerColumn.RAWNAME]);
				scope tl = new TextLayout(display);

				tl.setText(player[PlayerColumn.NAME]);
				foreach (r; parsed.ranges)
					tl.setStyle(r.style, r.start, r.end);

				tl.draw(e.gc, e.x+2, e.y);
				tl.dispose();
			}
		});

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
	}

	/// The index of the currently active sort column.
	int sortColumn() { return table_.indexOf(table_.getSortColumn()); }

	/// Is the sort order reversed?
	bool sortReversed() { return (table_.getSortDirection() == DWT.DOWN); }

	/// Returns the player list's Table widget object.
	Table getTable() { return table_; };

	void reset()
	{
		table_.clearAll();
		sort();
		table_.setItemCount(getActiveServerList.getFiltered(
		                                 selectedServerIndex_).players.length);
	}

	/** Set which server to show the playerlist for
	 *
	 * Mainly for use by serverTable.
	 */
	void setSelectedServer(int i)
	{
		// FIXME: show players for all selected servers at once (like ASE)
		selectedServerIndex_ = i;
		auto sd = getActiveServerList.getFiltered(selectedServerIndex_);
		if (sd.players.length && sd.players[0][PlayerColumn.NAME] is null)
			addCleanPlayerNames(sd.players);
		reset();
	}

	void clear()
	{
		table_.removeAll();
	}

	/************************************************
	            PRIVATE STUFF
	 ************************************************/
private:
	Table table_;
	Composite parent_;
	int selectedServerIndex_;

	void sort()
	{
		auto sd = getActiveServerList.getFiltered(selectedServerIndex_);
		int sortCol = table_.indexOf(table_.getSortColumn());
		int dir = table_.getSortDirection();

		switch (sortCol) {
			case PlayerColumn.NAME:
				sortStringArrayStable(sd.players, sortCol,
		                              ((dir == DWT.UP) ? false : true));
				break;
			case PlayerColumn.SCORE:
				sortStringArrayStable(sd.players, sortCol,
		                          ((dir == DWT.DOWN) ? false : true), true);
				break;
			case PlayerColumn.PING:
				sortStringArrayStable(sd.players, sortCol,
		                          ((dir == DWT.UP) ? false : true), true);
				break;
			default:
				assert(0);
		}
	}


	void addCleanPlayerNames(char[][][] players)
	{
		foreach (p; players)
			p[PlayerColumn.NAME] = stripColorCodes(p[PlayerColumn.RAWNAME]);
	}

}
