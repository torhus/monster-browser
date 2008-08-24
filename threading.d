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

	void run(void function() fp)  ///
	{
		abort = true;
		fp2_= null;
		fp_ = fp;
	}

	void run(void delegate() function() fp)  ///
	{
		abort = true;
		fp_ = null;
		fp2_ = fp;
	}

	void dispatch() ///
	{
		if (fp_ is null && fp2_ is null)
			return;

		if (thread_ !is null && thread_.isRunning) {
			abort = true;
		}
		else {
			debug Cout("ThreadDispatcher.dispatch: Killing server browser...")
			                                                          .newline;
			killServerBrowser();
			
			abort = false;

			if (fp_ !is null) {
				fp_();
				fp_ = null;
			}
			else {
				void delegate() startIt = fp2_();
				if (startIt !is null) {
					thread_ = new Thread(startIt);
					thread_.start();
				}
				fp2_= null;
			}
		}
	}

	private {
		void function() fp_ = null;
		void delegate() function() fp2_= null;
		Thread thread_;
	}
}
