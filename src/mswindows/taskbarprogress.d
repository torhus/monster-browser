module mswindows.taskbarprogress;

import core.sys.windows.windows;
import core.sys.windows.com;
public import mswindows.taskbarlist;

alias HWND = void*;
enum { NULL = null }

/**
 * Convenience wrapper for using the Windows 7 taskbar progress display feature.
 */
class TaskbarProgress
{
	/**
	 * Initialize COM, create and initialize a TaskbarList object.
	 *
	 * Throws: Exception if there is a problem creating or initializing the
	 *         COM object.
	 */
	this(HWND handle)
	{
		assert(handle);

		handle_ = handle;

		check(SUCCEEDED(CoInitialize(NULL)), "failed to initialize COM");
		scope (failure) CoUninitialize();

		check(SUCCEEDED(CoCreateInstance(&CLSID_TaskbarList,
		                              NULL,
		                              CLSCTX_INPROC_SERVER,
		                              &IID_ITaskbarList3,
		                              cast(void**)&taskbarList_)),
		                            "failed to create TaskbarList COM object");
		scope (failure) (taskbarList_.Release() == 0) || assert(0);

		check(taskbarList_.HrInit() == S_OK, "TaskbarList.HrInit() failed");
	}


	/// Wrapper around ITaskbarList3.SetProgressValue.
	void setProgressValue(ULONGLONG completed, ULONGLONG total)
	{
		taskbarList_.SetProgressValue(cast(HANDLE)handle_, completed, total);
	}


	/// Wrapper around ITaskbarList3.SetProgressState.
	void setProgressState(int flag)
	{
		taskbarList_.SetProgressState(cast(HANDLE)handle_, flag);
	}


	///  Call this to clean up when this object is no lenger needed.
	void dispose()
	{
		(taskbarList_.Release() == 0) || assert(0);
		CoUninitialize();
	}


	/// Check condition, throw exception if false.
	private void check(int condition, lazy string message)
	{
		if (!condition)
			throw new Exception("TaskbarProgress :: " ~ message);
	}


	private {
		ITaskbarList3 taskbarList_;
		HWND handle_;
	}
}
