/**
 * Windows API definitions needed for using the new Windows 7 taskbar features.
 */

module mswindows.taskbarlist;

import core.sys.windows.windows;
import core.sys.windows.com;


alias ulong ULONGLONG;  ///
alias IUnknown HIMAGELIST;  ///
private alias void* LPTHUMBBUTTON;  // just to make it compile

///
const IID IID_ITaskbarList3 = {0xea1afb91, 0x9e28, 0x4b86,
                             [0x90, 0xe9, 0x9e, 0x9f, 0x8a, 0x5e, 0xef, 0xaf]};


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
