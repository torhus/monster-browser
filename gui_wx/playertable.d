module gui_wx.playertable;

private {
	import wx.wx;

	import common;
	import main;
	import serverlist;
}


// should correspond to serverlist.PlayerColumn
char[][] playerHeaders = ["Name", "Score", "Ping"];


/*
 * Manages the players list control.
 */
class PlayerTable
{
	/*************************************************
	               PUBLIC METHODS
	*************************************************/
	this(Window parent)
	{
		parent_ = parent;

		listCtrl_ = new ListCtrl(parent, -1, ListCtrl.wxDefaultPosition,
	                                   ListCtrl.wxDefaultSize,
	                                   ListCtrl.wxLC_REPORT |
	                                   ListCtrl.wxLC_SINGLE_SEL |
	                                   ListCtrl.wxLC_HRULES |
	                                   ListCtrl.wxLC_VRULES |
	                                   ListCtrl.wxSUNKEN_BORDER);

		foreach (i, header; playerHeaders)
			listCtrl_.InsertColumn(i, header);

		foreach (i, w; [100, 40, 40])
			listCtrl_.SetColumnWidth(i, w);

		listCtrl_.InsertItem(0, "item 1");
		listCtrl_.SetItem(0, 1, "1 col 2");
		listCtrl_.InsertItem(0, "item 2");
		listCtrl_.SetItem(0, 1, "2 col 2");
		listCtrl_.InsertItem(3, "item 4");
		listCtrl_.SetItem(2, 1, "4 col 2");

/+
		table_.addListener(DWT.SetData, new class Listener {
			public void handleEvent(Event e)
			{
				TableItem item = cast(TableItem) e.item;
				item.setText(getActiveServerList.getFiltered(
				          selectedServerIndex_).players[table_.indexOf(item)]);
			}
		});

		Listener sortListener = new class Listener {
			public void handleEvent(Event e)
			{
				// determine new sort column and direction
				TableColumn sortColumn;
				TableColumn currentColumn;
				int dir, sortCol;

				sortColumn = table_.getSortColumn();
				currentColumn = cast(TableColumn) e.widget;
				dir = table_.getSortDirection();

				if (sortColumn is currentColumn) {
					dir = dir == DWT.UP ? DWT.DOWN : DWT.UP;
				} else {
					table_.setSortColumn(currentColumn);
					dir = DWT.UP;
				}

				sortCol = table_.indexOf(table_.getSortColumn());

				switch (sortCol) {
					case PlayerColumn.NAME:
						sortStringArrayStable(getActiveServerList.getFiltered(
						                        selectedServerIndex_).players,
				                        sortCol,
				                        ((dir == DWT.UP) ? false : true));
				    	break;
					case PlayerColumn.SCORE:
				    sortStringArrayStable(getActiveServerList.getFiltered(
				                               selectedServerIndex_).players,
				                    sortCol,
				                    ((dir == DWT.DOWN) ? false : true), true);
						break;
					case PlayerColumn.PING:
				    sortStringArrayStable(getActiveServerList.getFiltered(
				                                selectedServerIndex_).players,
				                    sortCol,
				                    ((dir == DWT.UP) ? false : true), true);
						break;
					default:
						assert(0);
				}

				table_.setSortDirection(dir);
				table_.clearAll();
			}
		};

		for (int i = 0; i < table_.getColumnCount(); i++) {
			TableColumn c = table_.getColumn(i);
			c.addListener(DWT.Selection, sortListener);
		}

		table_.setSortColumn(table_.getColumn(PlayerColumn.NAME));
		table_.setSortDirection(DWT.UP);
+/
	}

	Window getHandle() { return listCtrl_; };

	void reset()
	{
		//table_.clearAll();
		sort();
		/*table_.setItemCount(getActiveServerList.getFiltered(
		                                selectedServerIndex_).players.length);*/
	}

	/**
	 * Set which server to show the playerlist for
	 *
	 * Mainly for use by serverTable.
	 */
	void setSelectedServer(int i)
	{
		// FIXME: show players for all selected servers at once (like ASE)
		selectedServerIndex_ = i;
		reset();
	}

	void clear()
	{
		//table_.removeAll();
	}

	/************************************************
	            PRIVATE STUFF
	 ************************************************/
private:
	Window parent_;
	ListCtrl listCtrl_;
	int selectedServerIndex_;

	void sort()
	{/+
		int sortCol = table_.indexOf(table_.getSortColumn());
		int dir = table_.getSortDirection();

		if (sortCol== 0) {
			sortStringArrayStable(
			            getActiveServerList.getFiltered(selectedServerIndex_).players,
		                sortCol, (dir == DWT.UP) ? false : true);
	    }
	    else {  // numerical sort
		    sortStringArrayStable(
		                  getActiveServerList.getFiltered(selectedServerIndex_).players,
		                  sortCol, (dir == DWT.DOWN) ? false : true, true);
		}+/
	}

}
