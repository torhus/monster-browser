/**
 * GeoIP stuff.
 */

module geoip;

import Path = tango.io.Path;
debug import tango.io.Stdout;
import tango.stdc.stringz;
import tango.sys.SharedLib;
import tango.text.Ascii;

import dwt.graphics.Image;
import dwt.widgets.Display;

import common;


private GeoIP* gi = null;
private Display display;
private Image[char[]] flagCache;


private void bindFunc(alias funcPtr)(SharedLib lib)
{
	funcPtr = cast(typeof(funcPtr))lib.getSymbol(funcPtr.stringof.ptr);
}


///
bool initGeoIp()
{
	SharedLib geoIpLib;

	assert(gi is null, "Can't call initGeoIp() more than once.");

	try {
		geoIpLib = SharedLib.load("GeoIP.dll");
		bindFunc!(GeoIP_open)(geoIpLib);
		bindFunc!(GeoIP_delete)(geoIpLib);
		bindFunc!(GeoIP_country_code_by_addr)(geoIpLib);
	}
	catch (SharedLibException e) {
		log("Unable to load GeoIP.dll, flags will not be shown.");
		return false;
	}

	gi = GeoIP_open("GeoIP.dat", GEOIP_MEMORY_CACHE);
	if (gi is null) {
		warning("GeoIP.dat was not found, flags will not be shown.");
		geoIpLib.unload;
	}
	else {
		display = Display.getDefault;
	}

	return gi !is null;
}


///
char[] countryCodeByAddr(in char[] addr)
{
	assert(gi);

	char* code = GeoIP_country_code_by_addr(gi, toStringz(addr));
	if (code is null) {
		log("GeoIP: no country found for " ~ addr ~ ".");
		return null;
	}
	else {
		return toLower(fromStringz(code).dup);
	}
}


///
Image getFlagImage(in char[] countryCode)
{
	Image* image;

	image = countryCode in flagCache;
	if (image is null) {
		char[] file = "flags/" ~ countryCode ~ ".gif";
		if (Path.exists(file)) {
			auto tmp = new Image(display, file);
			flagCache[countryCode] = tmp;
			image = &tmp;
		}
		else {
			log("No flag found for country code '" ~ countryCode ~ "'.");
		}
	}

	return image ? *image : null;
}


static ~this()
{
	foreach (key, val; flagCache)
		val.dispose;

	if (gi)
		GeoIP_delete(gi);
}


struct GeoIP { }

enum /*GeoIPOptions*/ {
	GEOIP_STANDARD = 0,
	GEOIP_MEMORY_CACHE = 1,
	GEOIP_CHECK_CACHE = 2,
	GEOIP_INDEX_CACHE = 4,
	GEOIP_MMAP_CACHE = 8,
}

extern (C) {
	GeoIP* function(in char *filename, int flags) GeoIP_open;
	void function(GeoIP* gi) GeoIP_delete;
	char* function(GeoIP* gi, in char *addr) GeoIP_country_code_by_addr;
}
