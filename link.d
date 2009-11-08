module link;

version(all) {
	pragma(lib, "advapi32.lib");
	pragma(lib, "comctl32.lib");
	pragma(lib, "comdlg32.lib");
	pragma(lib, "gdi32.lib");
	// Only needed for win 95/98 compatibility for SHGetSpecialFolderPath()
	pragma(lib, "shfolder.lib");
	pragma(lib, "shell32.lib");
	pragma(lib, "shlwapi.lib");
	pragma(lib, "ole32.lib");
	pragma(lib, "oleaut32.lib");
	pragma(lib, "olepro32.lib");
	pragma(lib, "oleacc.lib");
	pragma(lib, "msimg32.lib");
	pragma(lib, "usp10.lib");
	pragma(lib, "zlib.lib");
}
