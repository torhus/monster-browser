module threading;

import tango.core.Thread;
debug import tango.io.Console;

import runtools; // : abortParsing, killServerBrowser;


/// Global instance.
ThreadDispatcher threadDispatcher;


/**
 * Stores a pointer to a function or delegate and calls it only when
 * the previous has terminated.
 *
 * Note: Meant to be used as a singleton, but this is not enforced currently.
 */
final class ThreadDispatcher
{

	bool abort;  ///

	
	/**
	 * Store a function to be called after the current secondary thread has
	 * terminated.
	 *
	 * The return value of fp is a delegate that will be called in a new
	 * thread.  If fp returns null, no new thread is started.
	 *
	 * This method sets the abort property to true.
	 *
	 * Note: This will set the function pointer stored by runSecond to null.
	 */
	void run(void delegate() function() fp)
	{
		abort = true;
		fp_ = fp;
		fp2_ = null;
	}


	/**
	 * Stores a function to be called after the one given to run() has ended.
	 *
	 * If the secondary thread is running, fp is not called until after it is
	 * finished.
	 *
	 * This method does not change the abort property.
	 */
	void runSecond(void delegate() function() fp)  ///
	{
		fp2_ = fp;
	}


	void dispatch() ///
	{
		if (fp_ is null && fp2_ is null)
			return;

		if (thread_ !is null && thread_.isRunning) {
			// If we have fp2_, let fp_ run to completion first, otherwise
			// interrupt it.
			if (fp2_ is null)
				abort = true;
		}
		else {
			void delegate() function() fp;

			killServerBrowser();

			if (fp_ !is null) {
				fp = fp_;
				fp_ = null;
			}
			else {
				assert(fp2_ !is null);
				fp = fp2_;
				fp2_ = null;
			}

			abort = false;
			
			void delegate() startIt = fp();
			if (startIt !is null) {
				thread_ = new Thread(startIt);
				thread_.start();
			}
		}
	}


	private {
		void delegate() function() fp_= null;
		void delegate() function() fp2_= null;
		Thread thread_;
	}
}
