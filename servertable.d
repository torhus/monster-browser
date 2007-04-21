module servertable;

private {
	//import dwt.all;

	import dejavu.lang.JObjectImpl;
	import dejavu.lang.String;

	import org.eclipse.swt.SWT;
	import org.eclipse.swt.events.SelectionAdapter;
	import org.eclipse.swt.events.SelectionEvent;
	import org.eclipse.swt.widgets.Composite;
	import org.eclipse.swt.widgets.Event;
	import org.eclipse.swt.widgets.Listener;
	import org.eclipse.swt.widgets.Table;
	import org.eclipse.swt.widgets.TableColumn;
	import org.eclipse.swt.widgets.TableItem;


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
		table_ = new Table(parent, SWT.VIRTUAL | SWT.FULL_SELECTION |
		                           SWT.BORDER);
		table_.setHeaderVisible(true);
		table_.setLinesVisible(true);

		for (int i = 0; i < serverHeaders.length; i++) {
			TableColumn column = new TableColumn(table_, SWT.NONE);
			column.setText(String.fromUtf8(serverHeaders[i]));
		}

		table_.getColumn(ServerColumn.PASSWORDED).setAlignment(SWT.CENTER);

		int col = 0;
		table_.getColumn(col++).setWidth(250);
		table_.getColumn(col++).setWidth(28);
		table_.getColumn(col++).setWidth(32);
		table_.getColumn(col++).setWidth(50);
		table_.getColumn(col++).setWidth(40);
		table_.getColumn(col++).setWidth(90);
		table_.getColumn(col++).setWidth(130);

		table_.addListener(SWT.SetData, new class JObjectImpl, Listener {
			public void handleEvent(Event e)
			{
				TableItem item = cast(TableItem) e.item;
				int index = table_.indexOf(item);

				debug if (index >= serverList.filteredLength) {
					error(__FILE__, "(", __LINE__, "):\n",
					          "index >= serverList.filteredLength");
				}
				//item.setText(serverList.getFiltered(index).server);
				foreach (i, s; serverList.getFiltered(index).server) {
					item.setText(i, String.fromUtf8(s));
				}
			}
		});

		table_.addSelectionListener(new class SelectionAdapter {
			void widgetSelected(SelectionEvent e)
			{
				int i = table_.getSelectionIndex();
				selectedIp_ = serverList.getFiltered(i).server[ServerColumn.ADDRESS];
				playerTable.setSelectedServer(i);
				cvarTable.setItems(serverList.getFiltered(i).cvars);

			}
			void widgetDefaultSelected(SelectionEvent e)
			{
				widgetSelected(e);
				JoinServer(serverList.getFiltered(table_.getSelectionIndex()));
			}
		});

		Listener sortListener = new class JObjectImpl, Listener {
			public void handleEvent(Event e)
			{
				// determine new sort column and direction
				TableColumn sortColumn, newColumn;
				int dir;

				sortColumn = table_.getSortColumn();
				newColumn = cast(TableColumn) e.widget;
				dir = table_.getSortDirection();

				if (sortColumn is newColumn) {
					dir = (dir == SWT.UP) ? SWT.DOWN : SWT.UP;
				} else {
					dir = SWT.UP;
					table_.setSortColumn(newColumn);
				}

				serverList.sort(table_.indexOf(newColumn), (dir == SWT.DOWN));

				table_.setSortDirection(dir);
				synchronized (serverList) {
					table_.clearAll();
					table_.setItemCount(serverList.filteredLength());
				}
			}
		};

		for (int i = 0; i < table_.getColumnCount(); i++) {
			TableColumn c = table_.getColumn(i);
			c.addListener(SWT.Selection, sortListener);
		}

		table_.setSortColumn(table_.getColumn(ServerColumn.NAME));
		table_.setSortDirection(SWT.UP);
	}

	Table getTable() { return table_; };

	/*void update(Object dummy = null)
	{
		if (!table_.isDisposed)
			table_.setItemCount(serverList.filteredLength);
	}*/

	void reset(Object dummy = null)
	{
		if(table_.isDisposed())
			return;

		refresh();
		volatile if (!parselist.abort) {
			statusBar.setDefaultStatus(serverList.length,
			                           serverList.filteredLength);
		}
		assert(selectedIp_);
		int i = serverList.getFilteredIndex(selectedIp_);
		if (i != -1) {
			table_.setSelection(i);
			playerTable.setSelectedServer(i);
			cvarTable.setItems(serverList.getFiltered(i).cvars);
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
				table_.setItemCount(serverList.filteredLength);
			}

			if (selected != -1 && i <= selected) {
					table_.deselectAll();
					table_.select(selected + 1);
			}
		}
		else {
			table_.clearAll();
			table_.setItemCount(serverList.filteredLength);
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
