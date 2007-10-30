module gui.dialogs;


version (wx)
	public import gui_wx.dialogs;
else
	public import gui_dwt.dialogs;
