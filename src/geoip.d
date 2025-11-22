/**
 * GeoIP stuff.
 */

module geoip;

import core.stdc.stdarg;
import core.stdc.stdint;
import core.stdc.string;
import core.stdc.time;
import std.algorithm.iteration : map;
import std.ascii;
import std.conv;
import std.string;

import java.io.ByteArrayInputStream;
import lib.loader;  // Replacement for std.loader
import org.eclipse.swt.SWTException;
import org.eclipse.swt.graphics.Image;
import org.eclipse.swt.widgets.Display;

import common;
import flagdata;
import maxminddb;

/** The result of a GeoIp lookup */
struct GeoInfo {
	string countryCode;
	string locationName;
}

private __gshared {
	MMDB_s mmdb;
	bool geoIpReady = false;
	Display display;
	Image[string] flagCache;
}

private void bindFuncOrThrow(alias funcPtr)(ExeModule lib)
{
	funcPtr = cast(typeof(funcPtr))lib.getSymbol(funcPtr.stringof);
}

private void bindFunc(alias funcPtr)(ExeModule lib)
{
	funcPtr = cast(typeof(funcPtr))lib.findSymbol(funcPtr.stringof);
}


///
bool initGeoIp(in char[] dbName)
{
	version (Win32)
		string libName = "libmaxminddb.dll";
	else version (Win64)
		string libName = "maxminddb.dll";
	else
		string libName = "libmaxminddb.so.0";

	shared static bool firstTime = true;
	ExeModule geoIpLib;
	c_int result;

	assert(firstTime, "Can't call initGeoIp() more than once.");
	if (!firstTime)
		return false;
	firstTime = false;

	try {
		geoIpLib = new ExeModule(libName);
		bindFuncOrThrow!(MMDB_lib_version)(geoIpLib);
		bindFuncOrThrow!(MMDB_open)(geoIpLib);
		bindFuncOrThrow!(MMDB_close)(geoIpLib);
		bindFuncOrThrow!(MMDB_lookup_string)(geoIpLib);
		bindFuncOrThrow!(MMDB_aget_value)(geoIpLib);
		bindFuncOrThrow!(MMDB_get_metadata_as_entry_data_list)(geoIpLib);
		bindFuncOrThrow!(MMDB_get_entry_data_list)(geoIpLib);
		bindFuncOrThrow!(MMDB_free_entry_data_list)(geoIpLib);
		bindFuncOrThrow!(MMDB_strerror)(geoIpLib);
	}
	catch (ExeModuleException e) {
		log("Unable to load the GeoIP library (" ~ libName ~ "), server " ~
			"locations will not be shown.");
		return false;
	}
	log("Loaded GeoIP2 library (" ~ libName ~ ") version " ~
	    fromStringz(MMDB_lib_version()) ~ ".");

	result = MMDB_open(toStringz(appDir ~ dbName), 0, &mmdb);
	if (result != MMDB_SUCCESS) {
		log("GeoIP: " ~ to!string(MMDB_strerror(result)));
		geoIpLib.close();
	}
	else {
		time_t build_epoch = cast(time_t)mmdb.metadata.build_epoch;

		log("Loaded GeoIP2 database: " ~
		    to!string(mmdb.metadata.database_type) ~ ", " ~
		    strip(to!string(asctime(gmtime(&build_epoch)))) ~ ".");

		initFlagFiles;
		geoIpReady = true;
	}

	return geoIpReady;
}


///
GeoInfo getGeoInfo(in char[] addr)
{
	if (!geoIpReady)
		return GeoInfo(null, null);

	c_int gai_error = 0, mmdb_error;
	bool error = false;

	MMDB_lookup_result_s result = MMDB_lookup_string(&mmdb,
	                                                 toStringz(addr),
	                                                 &gai_error,
	                                                 &mmdb_error);

	if (gai_error != 0) {
		log("GeoIP: " ~ to!string(gai_strerror(gai_error)));
		error = true;
	}
	if (mmdb_error != MMDB_SUCCESS) {
		log("GeoIP: " ~ to!string(MMDB_strerror(mmdb_error)));
		error = true;
	}
	if (!result.found_entry) {
		error = true;
	}
	if (error) {
		log("GeoIp: No info for address " ~ addr ~ ".");
		return GeoInfo(null, null);
	}
	else {
		string code = getString(&result.entry, "country", "iso_code", null);
		assert(code.length == 2);
		string name = getString(&result.entry, "country", "names", "en", null);
		string city = getString(&result.entry, "city", "names", "en", null);
		return GeoInfo(toLower(code), city ? text(city, ", ", name) : name);
	}
}


private string getString(MMDB_entry_s* start, in char*[] args ...)
{
	assert(args.length && args[$-1] is null);

	MMDB_entry_data_s entry_data;
	c_int result = MMDB_aget_value(start, &entry_data, args.ptr);

	if (result == MMDB_SUCCESS && entry_data.has_data) {
		return cast(string)entry_data.utf8_string[0..entry_data.data_size];
	}
	else {
		return null;
	}
}


/**
 * Get a flag image for the given two-letter lower case country code.
 *
 * Returns null when no flag was found for the given country code, or if there
 * was a problem reading the image file, etc.  Only one attempt will be made at
 * loading each flag, calling this function again will not cause more attempts
 * to be made.
 */
Image getFlagImage(in char[] countryCode)
{
	Image* image;

	image = countryCode in flagCache;
	if (!image) {
		Image tmp = null;
		ubyte[]* data = countryCode in flagFiles;

		if (data) {
			try {
				auto stream  = new ByteArrayInputStream(cast(byte[])*data);
				tmp = new Image(display, stream);
			}
			catch (SWTException e) {
				log("Error when decoding flag for '" ~ countryCode ~ "', " ~
				                                     "possibly corrupt file.");
			}
		}
		else {
			log("No flag found for country code '" ~ countryCode ~ "'.");
		}

		flagCache[countryCode] = tmp;
		image = &tmp;
	}

	return image ? *image : null;
}


/// To be called before program exit.
void disposeFlagImages()
{
	if (geoIpReady) {
		geoIpReady = false;
		MMDB_close(&mmdb);
	}

	foreach (key, val; flagCache)
		if (val)
			val.dispose;

}


extern (C) __gshared {
	c_int function(in char */*const*/ filename, uint32_t flags,
	               MMDB_s */*const*/ mmdb)
	    MMDB_open;
	void function(MMDB_s */*const*/ mmdb) MMDB_close;
	MMDB_lookup_result_s function(MMDB_s */*const*/ mmdb,
	                              in char */*const*/ ipstr,
	                              c_int */*const*/ gai_error,
	                              c_int */*const*/ mmdb_error)
	    MMDB_lookup_string;
	c_int function(MMDB_entry_s */*const*/ start,
	                     MMDB_entry_data_s */*const*/ entry_data, ...)
	    MMDB_get_value;
	c_int function(MMDB_entry_s */*const*/ start,
	                     MMDB_entry_data_s */*const*/ entry_data,
	                     va_list va_path)
	    MMDB_vget_value;
	c_int function(MMDB_entry_s */*const*/ start,
	               MMDB_entry_data_s */*const*/ entry_data,
	               in /*const*/ char */*const*/ */*const*/ path)
	    MMDB_aget_value;
	c_int function(MMDB_s */*const*/ mmdb,
	               MMDB_entry_data_list_s **/*const*/ entry_data_list)
	    MMDB_get_metadata_as_entry_data_list;
	c_int function(MMDB_entry_s *start, MMDB_entry_data_list_s
	                               **/*const*/ entry_data_list)
	    MMDB_get_entry_data_list;
	void function(MMDB_entry_data_list_s */*const*/ entry_data_list)
	    MMDB_free_entry_data_list;
	/*const*/ char *function() MMDB_lib_version;
	/*const*/ char *function(c_int error_code) MMDB_strerror;
}
