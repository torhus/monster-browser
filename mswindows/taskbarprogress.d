module mswindows.taskbarprogress;

import tango.sys.win32.Macros;
import tango.sys.win32.Types;
public import mswindows.taskbarlist;


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

		if (FAILED(CoInitialize(NULL)))
			throw new Exception("TaskbarProgress :: failed to initialize COM");

		HRESULT hr = CoCreateInstance(&CLSID_TaskbarList,
		                              NULL,
		                              CLSCTX_INPROC_SERVER,
		                              &IID_ITaskbarList3,
		                              cast(void**)&taskbarList_);
		if (FAILED(hr)) {
			CoUninitialize();
			throw new Exception(
			     "TaskbarProgress :: failed to create TaskbarList COM object");
		}
		if (taskbarList_.HrInit() != S_OK) {
			taskbarList_.Release() && assert(0);
			CoUninitialize();
			throw new Exception(
			                 "TaskbarProgress :: TaskbarList.HrInit() failed");
		}

	}


	/// Wrapper around ITaskbarList3.SetProgressValue.
	void setProgressValue(ULONGLONG completed, ULONGLONG total)
	{
		taskbarList_.SetProgressValue(handle_, completed, total);
	}


	/// Wrapper around ITaskbarList3.SetProgressState.
	void setProgressState(int flag)
	{
		taskbarList_.SetProgressState(handle_, flag);
	}


	///  Call this to clean up when this object is no lenger needed.
	void dispose()
	{
		taskbarList_.Release() && assert(0);
		CoUninitialize();
	}


	private {
		ITaskbarList3 taskbarList_;
		HWND handle_;
	}
}
