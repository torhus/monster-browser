/**
 * Some utilites specific to the Windows platform.
 */

module mswindows.util;

import core.sys.windows.windows;


struct OSVERSIONINFO {
  DWORD dwOSVersionInfoSize;
  DWORD dwMajorVersion;
  DWORD dwMinorVersion;
  DWORD dwBuildNumber;
  DWORD dwPlatformId;
  CHAR szCSDVersion[128];  // ANSI version
}

extern (Windows) BOOL GetVersionExA(OSVERSIONINFO*);


///
OSVERSIONINFO getWindowsVersion()
{
	OSVERSIONINFO osvi = { OSVERSIONINFO.sizeof };

	GetVersionExA(&osvi);
	return osvi;
}


///
bool isWindows7OrLater()
{
	auto osvi = getWindowsVersion();
	return osvi.dwMajorVersion > 6 ||
	             osvi.dwMajorVersion == 6 && osvi.dwMinorVersion >= 1;
}
