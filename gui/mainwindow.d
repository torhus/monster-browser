module gui.mainwindow;


version (wx)
	public import gui_wx.mainwindow;
else
	public import gui_dwt.mainwindow;
