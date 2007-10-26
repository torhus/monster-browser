module gui.servertable;

private {
	import std.string;
	
	import wx.wx;

	import common;
	import launch;
	import main;
	import serverlist;
	import gui.cvartable;
	import gui.dialogs;
	import gui.mainwindow;
	import gui.playertable;
}


typedef int WindowID;

ServerTable serverTable;

// should correspond to serverlist.ServerColumn
char[][] serverHeaders = ["Name", "PW", "Ping", "Players", "Game", "Map", "IP"];


/**
 * GUI for displaying the server list.  Also controls what the cvar and
 * player tables displays.
 */
class ServerTable
{
	///
	this(Window parent)
	{
		parent_ = parent;

		listCtrl_ = new ServerListCtrl(parent_, -1, ListCtrl.wxDefaultPosition,
		                         ListCtrl.wxDefaultSize,
		                         ListCtrl.wxLC_REPORT |
		                         ListCtrl.wxLC_VIRTUAL |
		                         ListCtrl.wxLC_SINGLE_SEL |
		                         ListCtrl.wxLC_HRULES |
		                         ListCtrl.wxLC_VRULES |
		                         ListCtrl.wxSUNKEN_BORDER);

		foreach (i, header; serverHeaders)
			listCtrl_.InsertColumn(i, header);
/+
		listCtrl_.getColumn(ServerColumn.PASSWORDED).setAlignment(DWT.CENTER);
+/
		foreach (i, w; [250, 28, 32, 50, 40, 90, 130])
			listCtrl_.SetColumnWidth(i, w);

		/*listCtrl_.InsertItem(0, "item 1");
		listCtrl_.SetItem(0, 1, "1 col 2");
		listCtrl_.InsertItem(1, "item 2");
		listCtrl_.SetItem(1, 1, "2 col 2");*/

/+		
		listCtrl_.addSelectionListener(new class SelectionAdapter {
			void widgetSelected(SelectionEvent e)
			{
				int i = listCtrl_.getSelectionIndex();
				selectedIp_ = getActiveServerList.getFiltered(i).server[ServerColumn.ADDRESS];
				playerTable.setSelectedServer(i);
				cvarTable.setItems(getActiveServerList.getFiltered(i).cvars);
			}

			void widgetDefaultSelected(SelectionEvent e)
			{
				widgetSelected(e);
				JoinServer(getActiveServerList.getFiltered(listCtrl_.getSelectionIndex()));
			}
		});

		Listener sortListener = new class Listener {
			public void handleEvent(Event e)
			{
				// determine new sort column and direction
				TableColumn sortColumn, newColumn;
				int dir;

				sortColumn = listCtrl_.getSortColumn();
				newColumn = cast(TableColumn) e.widget;
				dir = listCtrl_.getSortDirection();

				if (sortColumn is newColumn) {
					dir = (dir == DWT.UP) ? DWT.DOWN : DWT.UP;
				} else {
					dir = DWT.UP;
					listCtrl_.setSortColumn(newColumn);
				}

				getActiveServerList.sort(listCtrl_.indexOf(newColumn), (dir == DWT.DOWN));

				listCtrl_.setSortDirection(dir);
				synchronized (getActiveServerList) {
					listCtrl_.clearAll();
					listCtrl_.setItemCount(getActiveServerList.filteredLength());
				}

				// keep the same server selected
				int i = getActiveServerList.getFilteredIndex(selectedIp_);
				if (i != -1)
					listCtrl_.setSelection(i);

			}
		};

		for (int i = 0; i < listCtrl_.getColumnCount(); i++) {
			TableColumn c = listCtrl_.getColumn(i);
			c.addListener(DWT.Selection, sortListener);
		}

		listCtrl_.setSortColumn(listCtrl_.getColumn(ServerColumn.NAME));
		listCtrl_.setSortDirection(DWT.UP);
+/
	}


	/// Returns the server list's Table widget object.
	ListCtrl getTable() { return listCtrl_; };


	/**
	 * Clears the table and refills it with updated data.  Keeps the same server
	 * selected, if there was one.
	 *
	 * Params:
	 *     index = An IntWrapper object.  Set this to the index of the last added
	 *             element.  If refilling the contents of the table would not
	 *             make this element visible, the table is not refilled.  If the
	 *             argument is null, the table is always refilled.
	 *
	 */
	void refresh(Object index = null)
	{/+
		if(listCtrl_.isDisposed())
			return;

		if (index) {
			int selected = listCtrl_.getSelectionIndex();
			int i = (cast(IntWrapper)index).value;

			if (i <= getBottomIndex() /*&& i >= listCtrl_.getTopIndex()*/) {
				listCtrl_.clearAll();
				listCtrl_.setItemCount(getActiveServerList.filteredLength);
			}

			if (selected != -1 && i <= selected) {
					listCtrl_.deselectAll();
					listCtrl_.select(selected + 1);
			}
		}
		else {
			listCtrl_.clearAll();
			listCtrl_.setItemCount(getActiveServerList.filteredLength);
		}+/
	}


	/**
	 * In addition to clearing the table and refilling it with updated data
	 * without losing the selection (like refresh()), it also:
	 *
	 * 1. Sets the status bar to the default status.
	 * 2. Updates the cvar and player tables to show information for the selected
	 *    server, or clears them if there is no server selected.
	 * 3. Optionally sets the selection to the server specified by index.
	 *
	 * Params:
	 *     index = An IntWrapper object.  If not null, the server with the given
	 *             index is selected.
	 */
	void reset(Object index = null)
	{/+
		if(listCtrl_.isDisposed())
			return;

		refresh();
		volatile if (!runtools.abortParsing && getActiveServerList.complete) {
			statusBar.setDefaultStatus(getActiveServerList.length,
			                           getActiveServerList.filteredLength);
		}

		int i;
		if (index !is null) {
			i = (cast(IntWrapper)index).value;
		}
		else {
			// Keep the same server selected.
			assert(selectedIp_);
			i = getActiveServerList.getFilteredIndex(selectedIp_);
		}

		if (i != -1) {
			listCtrl_.setSelection(i);
			playerTable.setSelectedServer(i);
			cvarTable.setItems(getActiveServerList.getFiltered(i).cvars);
		}
		else {
			listCtrl_.deselectAll();
			playerTable.clear();
			cvarTable.clear();
		}+/
	}


	int sortColumnIndex()
	{
		//return listCtrl_.indexOf(listCtrl_.getSortColumn());
		return 0;
	}


	bool reversedSortOrder()
	{
		//return (listCtrl_.getSortDirection() == DWT.DOWN);
		return false;
	}

	/************************************************
	            PRIVATE STUFF
	 ************************************************/
private:
	ListCtrl listCtrl_;
	Window parent_;
	char[] selectedIp_ = "";

	private int getBottomIndex()
	{
		/*return listCtrl_.getClientArea().height / listCtrl_.getItemHeight() +
		                                                  listCtrl_.getTopIndex();*/
		return int.max;
	}

}

class ServerListCtrl : ListCtrl
{
	this(Window parent, WindowID id, Point pos, Size size, long style) {
		super(parent, id, pos, size, style);
	}
	
	// FIXME: does it crash if args are long instead of int?
	// The wxD ListCtrl sample uses long instead of int, and crashes.
	string OnGetItem(int item, int column)
	{
/+
		listCtrl_.addListener(DWT.SetData, new class Listener {
			public void handleEvent(Event e)
			{
				TableItem item = cast(TableItem) e.item;
				int i = listCtrl_.indexOf(item);

				debug if (i >= getActiveServerList.filteredLength) {
					error(__FILE__, "(", __LINE__, "):\n",
					          "i >= getActiveServerList.filteredLength");
				}
				item.setText(getActiveServerList.getFiltered(i).server);
			}
		});
+/
		
		return .toString(item) ~ " " ~ .toString(column);
	}

}
