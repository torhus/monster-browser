module gui.servertable;


version (wx)
	public import gui_wx.servertable;
else
	public import gui_dwt.servertable;
