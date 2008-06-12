module link;

// used by the Bud and Rebuild tools
version(build) {
	pragma(link, "advapi32.lib");
	pragma(link, "comctl32.lib");
	pragma(link, "comdlg32.lib");
	pragma(link, "gdi32.lib");
	// Only needed for win 95/98 compatibility for SHGetSpecialFolderPath()
	pragma(link, "shfolder.lib");
	pragma(link, "shell32.lib");
	pragma(link, "ole32.lib");
	pragma(link, "oleaut32.lib");
	pragma(link, "oleacc.lib");
	pragma(link, "msimg32.lib");
	pragma(link, "usp10.lib");
}
