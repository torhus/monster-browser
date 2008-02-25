module servertable;

private {
	import dwt.DWT;
	import dwt.events.SelectionAdapter;
	import dwt.events.SelectionEvent;
	import dwt.graphics.TextLayout;
	import dwt.widgets.Composite;
	import dwt.widgets.Event;
	import dwt.widgets.Listener;
	import dwt.widgets.Table;
	import dwt.widgets.TableColumn;
	import dwt.widgets.TableItem;

	import colorednames;
	import serverlist;
	import settings;
	import launch;
	import main;
	import common;
}

// should correspond to serverlist.ServerColumn
char[][] serverHeaders = ["Name", "PW", "Ping", "Players", "Game", "Map", "IP"];


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

		foreach (header; serverHeaders) {
			TableColumn column = new TableColumn(table_, DWT.NONE);
			column.setText(header);
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
			void handleEvent(Event e)
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

		/* Allow users to disable colored server names, since drawing them is so
		 * slow.
		 */
		if (getSetting("coloredNames") == "true") {
			table_.addListener(DWT.EraseItem, new class Listener {
				void handleEvent(Event e) {
					if (e.index == ServerColumn.NAME)
						e.detail &= ~DWT.FOREGROUND;
				}
			});

			table_.addListener(DWT.PaintItem, new class Listener {
				void handleEvent(Event e) {
					if (e.index != ServerColumn.NAME)
						return;

					TableItem item = cast(TableItem) e.item;
					auto i = table_.indexOf(item);
					ServerData* sd = getActiveServerList.getFiltered(i);
					TextLayout tl = sd.customData;

					if (tl is null) {
						auto parsed = parseColors(sd.rawName);
						tl = new TextLayout(display);
						tl.setText(parsed.cleanName);
						foreach (r; parsed.ranges)
							tl.setStyle(r.style, r.start, r.end);

						sd.customData = tl;  // cache it
					}
					tl.draw(e.gc, e.x, e.y);
				}
			});
		}

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
				joinServer(getActiveServerList.getFiltered(table_.getSelectionIndex()));
			}
		});

		Listener sortListener = new class Listener {
			void handleEvent(Event e)
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

		table_.setSortColumn(table_.getColumn(ServerColumn.NAME));
		table_.setSortDirection(DWT.UP);
	}


	/// Returns the server list's Table widget object.
	Table getTable() { return table_; };


	/*void update(Object dummy = null)
	{
		if (!table_.isDisposed)
			table_.setItemCount(getActiveServerList.filteredLength);
	}*/


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
	 * 2. Updates the cvar and player tables to show information for the selected
	 *    server, or clears them if there is no server selected.
	 * 3. Optionally sets the selection to the server specified by index.
	 *
	 * Params:
	 *     index = An IntWrapper object.  If not null, the server with the given
	 *             index is selected.
	 */
	void reset(Object index = null)
	{
		if(table_.isDisposed())
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
