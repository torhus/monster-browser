module gui.cvartable;


version (wx)
	public import gui_wx.cvartable;
else
	public import gui_dwt.cvartable;
