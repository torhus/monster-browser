module playertable;

private {
	version (Tango) {
		import dwt.DWT;
		import dwt.widgets.Composite;
		import dwt.widgets.Event;
		import dwt.widgets.Listener;
		import dwt.widgets.Table;
		import dwt.widgets.TableColumn;
		import dwt.widgets.TableItem;
	}
	else import dwt.all;

	import common;
	import serverlist;
	import main;
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
	}

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
		}
	}

}
