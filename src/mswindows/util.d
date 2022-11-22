/**
 * Miscellaneous Windows stuff.
 */
module mswindows.util;


public import core.sys.windows.shlobj;
import core.sys.windows.windows;
import std.conv;
import std.string;
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


/**
 * Get the default program files directory, or an educated guess if not
 * found.
 *
 * Sample return: "C:\Program Files".
 */
string getProgramFilesDirectory()
{
    try {
        return getSpecialPath!CSIDL_PROGRAM_FILES;
    }
    catch (WindowsException _) {
        return "C:\\Program Files";
    }
}


/**
 * Returns the value of a registry key, or null if there was an error.
 *
 * Throws: Exception if the argument is not a valid key.
 */
string getRegistryStringValue(in char[] key)
{
    HKEY hKey;
    DWORD dwType = REG_SZ;
    BYTE[255] buf = void;
    LPBYTE lpData = buf.ptr;
    DWORD dwSize = buf.length;
    LONG status;
    string retval = null;

    wstring[] parts = split(to!wstring(key), "\\");
    if (parts.length < 3)
        throw new Exception("Invalid registry key: " ~ cast(string)key);

    HKEY keyConst = hkeyFromString(parts[0]);
    wchar* subKey = join(parts[1..$-1], "\\").dup.ptr;
    status = RegOpenKeyExW(keyConst, subKey, 0, KEY_ALL_ACCESS, &hKey);

    if (status == ERROR_SUCCESS) {
        wchar* name = parts[$-1].dup.ptr;
        status = RegQueryValueExW(hKey, name, null, &dwType, lpData, &dwSize);

        if (status == ERROR_MORE_DATA) {
            lpData = (new BYTE[dwSize]).ptr;
            status = RegQueryValueExW(hKey, name, null,
                                                     &dwType, lpData, &dwSize);
        }

        if (status == ERROR_SUCCESS)
            retval = to!string(cast(wchar*)lpData);

        RegCloseKey(hKey);
    }

    return retval;
}


/// Throws: Exception.
private HKEY hkeyFromString(in wchar[] s)
{
    if (icmp(s, "HKEY_CLASSES_ROOT") == 0)
        return HKEY_CLASSES_ROOT;
    if (icmp(s, "HKEY_CURRENT_USER") == 0)
        return HKEY_CURRENT_USER;
    if (icmp(s, "HKEY_LOCAL_MACHINE") == 0)
        return HKEY_LOCAL_MACHINE;

    throw new Exception("Invalid HKEY: " ~ to!string(s));
}
