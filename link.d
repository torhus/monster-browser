module link;

// used by the Build tool
version(build) {
	debug {
		pragma(link, "dwtd.lib");
	}
	else {
		pragma(link, "dwt.lib");
	}

	pragma(link, "advapi32.lib");
	pragma(link, "comctl32.lib");
	pragma(link, "gdi32.lib");
	pragma(link, "shell32.lib");
	pragma(link, "comdlg32.lib");
	pragma(link, "ole32.lib");
	pragma(link, "uuid.lib");
	pragma(link, "phobos.lib");

	pragma(link, "user32_dwt.lib");
	pragma(link, "imm32_dwt.lib");
	pragma(link, "shell32_dwt.lib");
	pragma(link, "msimg32_dwt.lib");
	pragma(link, "gdi32_dwt.lib");
	pragma(link, "kernel32_dwt.lib");
	pragma(link, "usp10_dwt.lib");
	pragma(link, "olepro32_dwt.lib");
	pragma(link, "oleaut32_dwt.lib");
	pragma(link, "oleacc_dwt.lib");
}
