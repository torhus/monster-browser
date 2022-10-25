/**
 * Miscellaneous Windows stuff.
 */
module mswindows.util;


public import core.sys.windows.shlobj;
import core.sys.windows.windows;
import std.conv;
import std.windows.syserror;


/**
 * Returns a special path, aka. known folder.
 *
 * Throws: WindowsException.
 */
string getSpecialPath(alias CSIDL)()
    if (CSIDL.stringof[0..6] == "CSIDL_")
{
    wchar[MAX_PATH] buf;
    DWORD type = SHGFP_TYPE.SHGFP_TYPE_CURRENT;

    wenforce(SHGetFolderPathW(null, CSIDL, null, type, buf.ptr) == S_OK);
    return to!string(buf.ptr);
}
