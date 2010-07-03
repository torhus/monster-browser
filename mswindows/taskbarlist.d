/**
 * Windows API definitions needed for using the new Windows 7 taskbar features.
 */

module mswindows.taskbarlist;

import tango.sys.win32.IUnknown;
import tango.sys.win32.Types;


alias DWORDLONG ULONGLONG;  ///
alias GUID CLSID;  ///
private alias void* LPTHUMBBUTTON;  // just to make it compile

///
const CLSID CLSID_TaskbarList = {0x56FDF344, 0xFD6D, 0x11D0,
                             [0x95, 0x8A, 0x00, 0x60, 0x97, 0xC9, 0xA0, 0x90]};

///
const IID IID_ITaskbarList3 = {0xea1afb91, 0x9e28, 0x4b86,
                             [0x90, 0xe9, 0x9e, 0x9f, 0x8a, 0x5e, 0xef, 0xaf]};

enum
{
	CLSCTX_INPROC_SERVER     = 0x1,
	CLSCTX_INPROC_HANDLER    = 0x2,
	CLSCTX_LOCAL_SERVER      = 0x4,
	CLSCTX_INPROC_SERVER16   = 0x8,
	CLSCTX_REMOTE_SERVER     = 0x10,
	CLSCTX_INPROC_HANDLER16  = 0x20,
	CLSCTX_INPROC_SERVERX86  = 0x40,
	CLSCTX_INPROC_HANDLERX86 = 0x80,

	CLSCTX_INPROC = (CLSCTX_INPROC_SERVER|CLSCTX_INPROC_HANDLER),
	CLSCTX_ALL = (CLSCTX_INPROC_SERVER| CLSCTX_INPROC_HANDLER| CLSCTX_LOCAL_SERVER),
	CLSCTX_SERVER = (CLSCTX_INPROC_SERVER|CLSCTX_LOCAL_SERVER),
}


extern (Windows) {
	HRESULT CoInitialize(LPVOID pvReserved);  ///
	void    CoUninitialize();  ///
	HRESULT CoCreateInstance(const CLSID *rclsid, IUnknown UnkOuter,
	                      DWORD dwClsContext, const IID* riid, void* ppv);  ///
}


///
interface ITaskbarList : IUnknown
{
	HRESULT HrInit();

	HRESULT AddTab(HWND hwnd);

	HRESULT DeleteTab(HWND hwnd);

	HRESULT ActivateTab(HWND hwnd);

	HRESULT SetActiveAlt(HWND hwnd);
}


///
interface ITaskbarList2 : ITaskbarList
{
	HRESULT MarkFullscreenWindow(
		HWND hwnd,
		BOOL fFullscreen);
}


///
interface ITaskbarList3 : ITaskbarList2
{
	HRESULT SetProgressValue(
		HWND hwnd,
		ULONGLONG ullCompleted,
		ULONGLONG ullTotal);

	HRESULT SetProgressState(
		HWND hwnd,
		/*TBPFLAG*/ int tbpFlags);

	HRESULT RegisterTab(
		HWND hwndTab,
		HWND hwndMDI);

	HRESULT UnregisterTab(
		HWND hwndTab);

	HRESULT SetTabOrder(
		HWND hwndTab,
		HWND hwndInsertBefore);

	HRESULT SetTabActive(
		HWND hwndTab,
		HWND hwndMDI,
		DWORD dwReserved);

	HRESULT ThumbBarAddButtons(
		HWND hwnd,
		UINT cButtons,
		/*[in, size_is(cButtons)]*/ LPTHUMBBUTTON pButton);

	HRESULT ThumbBarUpdateButtons(
		HWND hwnd,
		UINT cButtons,
		/*[in, size_is(cButtons)]*/ LPTHUMBBUTTON pButton);

	HRESULT ThumbBarSetImageList(
		HWND hwnd,
		HIMAGELIST himl);

	HRESULT SetOverlayIcon(
		HWND hwnd,
		HICON hIcon,
		/*[in, unique, string]*/ LPCWSTR pszDescription);

	HRESULT SetThumbnailTooltip(
		HWND hwnd,
		/*[in, unique, string]*/ LPCWSTR pszTip);

	HRESULT SetThumbnailClip(
		HWND hwnd,
		RECT *prcClip);
}


enum /*TBPFLAG*/
{
	/// Flags for setting the taskbar progress state.
	TBPF_NOPROGRESS     = 0x00000000,
	TBPF_INDETERMINATE  = 0x00000001,  /// ditto
	TBPF_NORMAL         = 0x00000002,  /// ditto
	TBPF_ERROR          = 0x00000004,  /// ditto
	TBPF_PAUSED         = 0x00000008,  /// ditto
}
