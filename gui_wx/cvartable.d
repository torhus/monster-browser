module gui_wx.cvartable;

private {
	import wx.wx;

	import common;
	import serverlist;
	import main;
}


/*
 * Manages the cvars list control.
 */
class CvarTable
{
	this(Window parent)
	{
		listCtrl_ = new ListCtrl(parent, -1, ListCtrl.wxDefaultPosition,
                                 ListCtrl.wxDefaultSize,
                                 ListCtrl.wxLC_REPORT |
                                 ListCtrl.wxLC_SINGLE_SEL |
                                 ListCtrl.wxLC_HRULES |
                                 ListCtrl.wxLC_VRULES |
                                 ListCtrl.wxSUNKEN_BORDER);

		foreach (i, header; ["Key", "Value"])
			listCtrl_.InsertColumn(i, header);

		foreach (i, w; [90, 90])
			listCtrl_.SetColumnWidth(i, w);

		setItems([["item 1", "1 col 2"],
		          ["item 2", "2 col 2"]
		         ]);

	}


	Window getHandle() { return listCtrl_; }


	/**
	 * Set the contents of the list control.
	 */
	void setItems(char[][][] items)
	{
		assert (items && items.length);
		listCtrl_.DeleteAllItems();
		foreach (i, v; items) {
      		insertFullItem(i, v);
      	}
  	}

	/**
	 * Fill all columns in a line.
	 */
	void insertFullItem(int index, char[][] items)
	{
		assert(items.length == listCtrl_.ColumnCount);

		listCtrl_.InsertItem(index, items[0]);
		foreach (col, s; items[1..$])
			listCtrl_.SetItem(index, col+1, s);

	}

	/// Clear the list control.
	void clear()
	{
		listCtrl_.DeleteAllItems();
	}


	private {
		ListCtrl listCtrl_;
	}
}
