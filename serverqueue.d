module serverqueue;

import tango.core.Thread;
import tango.core.sync.Semaphore;
import tango.util.log.Trace;

import dwt.dwthelper.Runnable;
import dwt.widgets.Display;

import common;
import mainwindow;
import serverlist;


///
class ServerQueue
{
	///
	this(bool delegate(ServerData*) addDg)
	{
		addDg_ = addDg;
		semaphore_ = new Semaphore;
		adderThread_ = new Thread(&adder);
		adderThread_.isDaemon = true;
		adderThread_.start();
	}


	~this()
	{
		if (list_ !is null)
			delete list_;
	}


	///
	void add(ServerData* sd)
	{
		synchronized (this) list_ ~= *sd;
		semaphore_.notify();
	}


	///
	void addRemainingAndStop()
	{
		stop_ = true;
		semaphore_.notify();
		Trace.format("Waiting for adderThread_...").flush;
		while (adderThread_.isRunning) { }
		Trace.formatln("done.").flush;

		synchronized (this) {
			if (list_.length == 0)
				return;

			bool refresh = addAll();
			if (refresh) {
				Display.getDefault.syncExec(new class Runnable {
					void run() { serverTable.refresh(); }
				});
			}
		}
	
	}


	///
	private void adder()
	{
		while (!stop_) {
			do semaphore_.wait();
			while (!stop_ && list_.length == 0);

			synchronized (this) {
				bool refresh = addAll();
				if (refresh && !arguments.norefresh)
					Display.getDefault.asyncExec(new class Runnable {
						void run() { serverTable.refresh(); }
					});
			}
		}
	}


	/// Note: Doesn't synchronize.
	private bool addAll()
	{
		bool refresh = false;

		foreach (ref sd; list_) {
			if (addDg_(&sd))
				refresh = true;
		}
		list_.length = 0;

		return refresh;
	}


	private {
		ServerData[] list_;
		bool delegate(ServerData*) addDg_;
		Semaphore semaphore_;
		Thread adderThread_;
		bool stop_ = false;
	}
}
