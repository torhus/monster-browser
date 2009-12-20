module threadmanager;

import tango.core.Thread;
import tango.core.sync.Semaphore;

import dwt.dwthelper.Runnable;
import dwt.widgets.Display;

import runtools : killServerBrowser;


/// Global instance.
ThreadManager threadManager;


/**
 * Utility class for serialized execution of code in a secondary thread.
 *
 * The stored function or delegate will only be executed after the previously
 * started one has finished.  It will be executed in a thread controlled by
 * this class.
 */
class ThreadManager
{
	/**
	 * This can be checked by the function or delegate given to run to see if
	 * it should exit prematurely, to give the next function or delegate a
	 * chance to start sooner.
	 *
	 * The ThreadManager class does not read the value of this property, it
	 * only sets it.  The run method sets it to true, and it is set to false
	 * just before calling the stored function or delegate.  Using this
	 * property is purely optional.
	 */
	bool abort;


	///
	this()
	{
		thread_ = new Thread(&dispatch);
		thread_.name = "secondary";
		semaphore_ = new Semaphore;
		thread_.start();
	}


	/**
	 * Store a function or delegate to be called after the previous one has
	 * terminated.
	 *
	 * Only one function or delegate at a time can be stored, calling run again
	 * before the previous one has been started will replace it.
	 *
	 * These methods sets the abort property to true.
	 */
	synchronized void run(void function() fp)
	{
		abort = true;
		fp_ = fp;
		dg_ = null;
		semaphore_.notify();
	}


	/// ditto
	synchronized void run(void delegate() dg)
	{
		abort = true;
		dg_ = dg;
		fp_ = null;
		semaphore_.notify();
	}


	/**
	 * Tell the secondary thread to stop what it's doing and exit.
	 */
	void shutdown()
	{
		abort = true;
		shutdown_ = true;
		semaphore_.notify();
	}


	/// Is the secondary thread sleeping or working?
	bool sleeping() { return sleeping_; }


	private void dispatch()
	{
		void function() fpCopy;
		void delegate() dgCopy;

		while (true) {
			sleeping_ = true;
			semaphore_.wait();
			sleeping_ = false;
			if (shutdown_)
				break;

			synchronized (this) assert(fp_ !is null || dg_ !is null);

			killServerBrowser();

			synchronized (this) {
				fpCopy = fp_;
				fp_ = null;
				dgCopy = dg_;
				dg_ = null;
			}

			if (fpCopy !is null) {
				abort = false;
				fpCopy();
			}
			if (dgCopy !is null) {
				abort = false;
				dgCopy();
			}
		}
	}


	private {
		void function() fp_= null;
		void delegate() dg_= null;
		Thread thread_;
		Semaphore semaphore_;
		bool shutdown_ = false;
		bool sleeping_ = true;
	}
}
