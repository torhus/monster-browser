/**
 * Some utilites specific to the Windows platform.
 */

module mswindows.util;

import tango.sys.win32.Types;
import tango.sys.win32.UserGdi;


///
OSVERSIONINFO getWindowsVersion()
{
	OSVERSIONINFO osvi = { OSVERSIONINFO.sizeof };
	alias GetVersionExW GetVersionEx;  // Missing from Tango

	GetVersionEx(&osvi);
	return osvi;
}


///
bool isWindows7OrLater()
{
	auto osvi = getWindowsVersion();
	return osvi.dwMajorVersion > 6 ||
	             osvi.dwMajorVersion == 6 && osvi.dwMinorVersion >= 1;
}
