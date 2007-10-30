module gui.playertable;


version (wx)
	public import gui_wx.playertable;
else
	public import gui_dwt.playertable;
