module servertable;

private {
	import dwt.all;
	import serverlist;
	import launch;
	import main;
	import common;
}

// should correspond to serverlist.ServerColumn
char[][] serverHeaders = ["Name", "PW", "Ping", "Players", "Game", "Map", "IP"];

class ServerTable
{
	/*************************************************
	               PUBLIC METHODS
	*************************************************/
	this(Composite parent)
	{
		parent_ = parent;
		table_ = new Table(parent, DWT.VIRTUAL | DWT.FULL_SELECTION |
		                           DWT.BORDER);
		table_.setHeaderVisible(true);
		table_.setLinesVisible(true);

		for (int i = 0; i < serverHeaders.length; i++) {
			TableColumn column = new TableColumn(table_, DWT.NONE);
			column.setText(serverHeaders[i]);
		}

		table_.getColumn(ServerColumn.PASSWORDED).setAlignment(DWT.CENTER);

		int col = 0;
		table_.getColumn(col++).setWidth(250);
		table_.getColumn(col++).setWidth(28);
		table_.getColumn(col++).setWidth(32);
		table_.getColumn(col++).setWidth(50);
		table_.getColumn(col++).setWidth(40);
		table_.getColumn(col++).setWidth(90);
		table_.getColumn(col++).setWidth(130);

		table_.addListener(DWT.SetData, new class Listener {
			public void handleEvent(Event e)
			{
				TableItem item = cast(TableItem) e.item;
				int i = table_.indexOf(item);

				debug if (i >= getActiveServerList.filteredLength) {
					error(__FILE__, "(", __LINE__, "):\n",
					          "i >= getActiveServerList.filteredLength");
				}
				item.setText(getActiveServerList.getFiltered(i).server);
			}
		});

		table_.addSelectionListener(new class SelectionAdapter {
			void widgetSelected(SelectionEvent e)
			{
				int i = table_.getSelectionIndex();
				selectedIp_ = getActiveServerList.getFiltered(i).server[ServerColumn.ADDRESS];
				playerTable.setSelectedServer(i);
				cvarTable.setItems(getActiveServerList.getFiltered(i).cvars);

			}
			void widgetDefaultSelected(SelectionEvent e)
			{
				widgetSelected(e);
				JoinServer(getActiveServerList.getFiltered(table_.getSelectionIndex()));
			}
		});

		Listener sortListener = new class Listener {
			public void handleEvent(Event e)
			{
				// determine new sort column and direction
				TableColumn sortColumn, newColumn;
				int dir;

				sortColumn = table_.getSortColumn();
				newColumn = cast(TableColumn) e.widget;
				dir = table_.getSortDirection();

				if (sortColumn is newColumn) {
					dir = (dir == DWT.UP) ? DWT.DOWN : DWT.UP;
				} else {
					dir = DWT.UP;
					table_.setSortColumn(newColumn);
				}

				getActiveServerList.sort(table_.indexOf(newColumn), (dir == DWT.DOWN));

				table_.setSortDirection(dir);
				synchronized (getActiveServerList) {
					table_.clearAll();
					table_.setItemCount(getActiveServerList.filteredLength());
				}
			}
		};

		for (int i = 0; i < table_.getColumnCount(); i++) {
			TableColumn c = table_.getColumn(i);
			c.addListener(DWT.Selection, sortListener);
		}

		table_.setSortColumn(table_.getColumn(ServerColumn.NAME));
		table_.setSortDirection(DWT.UP);
	}

	Table getTable() { return table_; };

	/*void update(Object dummy = null)
	{
		if (!table_.isDisposed)
			table_.setItemCount(getActiveServerList.filteredLength);
	}*/

	void reset(Object dummy = null)
	{
		if(table_.isDisposed())
			return;

		refresh();
		volatile if (!parselist.abortParsing) {
			statusBar.setDefaultStatus(getActiveServerList.length,
			                           getActiveServerList.filteredLength);
		}
		assert(selectedIp_);
		int i = getActiveServerList.getFilteredIndex(selectedIp_);
		if (i != -1) {
			table_.setSelection(i);
			playerTable.setSelectedServer(i);
			cvarTable.setItems(getActiveServerList.getFiltered(i).cvars);
		}
		else {
			table_.deselectAll();
			playerTable.clear();
			cvarTable.clear();
		}
	}

	void refresh(Object index = null)
	{
		if(table_.isDisposed())
			return;

		if (index) {
			int selected = table_.getSelectionIndex();
			int i = (cast(IntWrapper) index).value;

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

	/************************************************
	            PRIVATE STUFF
	 ************************************************/
private:
	Table table_;
	Composite parent_;
	char[] selectedIp_ = "";

	private int getBottomIndex()
	{
		return table_.getClientArea().height / table_.getItemHeight() +
		                                                  table_.getTopIndex();
	}
}
