module playertable;

private {
	import dejavu.lang.JObjectImpl;
	import dejavu.lang.String;

	import org.eclipse.swt.SWT;
	import org.eclipse.swt.widgets.Composite;
	import org.eclipse.swt.widgets.Event;
	import org.eclipse.swt.widgets.Listener;
	import org.eclipse.swt.widgets.Table;
	import org.eclipse.swt.widgets.TableColumn;
	import org.eclipse.swt.widgets.TableItem;

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
		table_ = new Table(parent, SWT.VIRTUAL |  SWT.BORDER |
		                           SWT.HIDE_SELECTION);
		table_.setHeaderVisible(true);
		table_.setLinesVisible(true);

		for (int i = 0; i < playerHeaders.length; i++) {
			TableColumn column = new TableColumn(table_, SWT.NONE);
			column.setText(String.fromUtf8(playerHeaders[i]));
		}

		table_.getColumn(0).setWidth(100);
		table_.getColumn(1).setWidth(40);
		table_.getColumn(2).setWidth(40);

		table_.addListener(SWT.SetData, new class JObjectImpl, Listener {
			public void handleEvent(Event e)
			{
				TableItem item = cast(TableItem) e.item;
				/*item.setText(serverList.getFiltered(
				          selectedServerIndex_).players[table_.indexOf(item)]);*/
				          
				ServerData* sd = serverList.getFiltered(selectedServerIndex_);
				foreach (i, s; sd.players[table_.indexOf(item)]) {
					item.setText(i, String.fromUtf8(s));
				}
			}
		});

		Listener sortListener = new class JObjectImpl, Listener {
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
					dir = dir == SWT.UP ? SWT.DOWN : SWT.UP;
				} else {
					table_.setSortColumn(currentColumn);
					dir = SWT.UP;
				}

				sortCol = table_.indexOf(table_.getSortColumn());

				switch (sortCol) {
					case PlayerColumn.NAME:
						sortStringArrayStable(serverList.getFiltered(
						                        selectedServerIndex_).players,
				                        sortCol,
				                        ((dir == SWT.UP) ? false : true));
				    	break;
					case PlayerColumn.SCORE:
				    sortStringArrayStable(serverList.getFiltered(
				                               selectedServerIndex_).players,
				                    sortCol,
				                    ((dir == SWT.DOWN) ? false : true), true);
						break;
					case PlayerColumn.PING:
				    sortStringArrayStable(serverList.getFiltered(
				                                selectedServerIndex_).players,
				                    sortCol,
				                    ((dir == SWT.UP) ? false : true), true);
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
			c.addListener(SWT.Selection, sortListener);
		}

		table_.setSortColumn(table_.getColumn(PlayerColumn.NAME));
		table_.setSortDirection(SWT.UP);
	}

	Table getTable() { return table_; };

	void reset()
	{
		table_.clearAll();
		sort();
		table_.setItemCount(serverList.getFiltered(
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
			            serverList.getFiltered(selectedServerIndex_).players,
		                sortCol, (dir == SWT.UP) ? false : true);
	    }
	    else {  // numerical sort
		    sortStringArrayStable(
		                  serverList.getFiltered(selectedServerIndex_).players,
		                  sortCol, (dir == SWT.UP) ? false : true, true);
		}
	}

}
