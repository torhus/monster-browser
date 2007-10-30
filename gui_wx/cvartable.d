module gui_wx.cvartable;

private {
	import wx.wx;

	import common;
	import serverlist;
	import main;
}

//CvarTable cvarTable;

class CvarTable
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

		foreach (i, header; ["Key", "Value"])
			listCtrl_.InsertColumn(i, header);
		
		foreach (i, w; [90, 90])
			listCtrl_.SetColumnWidth(i, w);
		
		listCtrl_.InsertItem(0, "item 1");
		listCtrl_.SetItem(0, 1, "1 col 2");
		listCtrl_.InsertItem(0, "item 2");
		listCtrl_.SetItem(0, 1, "2 col 2");		
		listCtrl_.InsertItem(3, "item 4");
		listCtrl_.SetItem(2, 1, "4 col 2");

	}

	Window getHandle() { return listCtrl_; }

	void setItems(char[][][] items)
	{
		assert (items && items.length);
		//table_.setItemCount(0);
		foreach (v; items) {
			//TableItem item = new TableItem(table_, DWT.NONE);
      		//item.setText(v);
      	}
  	}

	void clear()
	{
		//table_.removeAll();
	}

	/************************************************
	            PRIVATE STUFF
	 ************************************************/
private:
	Panel panel_;
	ListCtrl listCtrl_;
	Window parent_;
}
