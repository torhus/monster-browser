module monitor;

private {
	import std.date;
	import std.thread;

	//import dwt.all;
	import common;
	import dialogs;
	import main;
	import serveractions;
}

private Shell shell;


// test running something in another thread
void startMonitor(Shell shell)
{
	.shell = shell;

	void monitorDone(Object o)
	{
		//db("monitorDone");
		scope dialog = new MonitorNotify(mainWindow, "testing");
		//dialog.open();
	}

	int timerTest()
	{
		/*long start = getUTCtime()/TicksPerSecond;
		long now = getUTCtime()/TicksPerSecond;

		while (now < start + 2) {
			now = getUTCtime()/TicksPerSecond;
		}*/

		// only the gui thread can display message boxes
		Display.getDefault().syncExec(null, &monitorDone);
		threadDispatcher.run(&refreshList);
		return 0;
	}

	void f(Object shell)
	{
		try {
			Thread monitorThread = new Thread(&timerTest);
			monitorThread.start();
		}
		catch(Exception e) {
			logx(__FILE__, __LINE__, e);
			MessageBox.showMsg(e.classinfo.name ~ "\n" ~ e.toString());
		}

	}

	Display.getDefault().timerExec(shell, 2000, &f);
}
