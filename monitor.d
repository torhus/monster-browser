module monitor;

private {
	import std.date;
	import std.thread;

	import dwt.all;
	import common;
}

private Shell shell;


// test running something in another thread
void startMonitor(Shell shell)
{
	.shell = shell;

	void monitorDone(Object o)
	{
		warning("monitorDone");
	}

	int timerTest()
	{
		long start = getUTCtime()/TicksPerSecond;
		long now = getUTCtime()/TicksPerSecond;

		while (now < start + 3) {
			now = getUTCtime()/TicksPerSecond;
		}

		// only the gui thread can display message boxes
		Display.getDefault().syncExec(null, &monitorDone);
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

	Display.getDefault().timerExec(shell, 1000, &f);
}
