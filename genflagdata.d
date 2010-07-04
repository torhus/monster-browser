#! /bin/rdmd
/**
 * Generate flagdata.d.
 */

import tango.io.Stdout;
import tango.io.stream.TextFile;
import tango.io.vfs.FileFolder;
import tango.text.Util : locatePrior;


const char[] DIR = "flags";
const char[] PATTERN = "*.png";
const char[] OUTPUT = "flagdata.d";

const char[] HEADER =
"/// Autogenerated by " __FILE__ " on " __TIMESTAMP__ ".

module flagdata;

ubyte[][char[]] flagFiles;

void initFlagFiles()
{
	flagFiles = [
";


int main()
{
	auto folder = new FileFolder(DIR);
	VfsFiles files = folder.self.catalog(PATTERN);

	Stdout.formatln("Found {} files in '{}'.", files.files, DIR);
	if (files.files < 100) {
		Stdout("ERROR: Suspiciously low number of files, aborting.");
		return 1;
	}

	auto f = new TextFileOutput(OUTPUT);
	scope (exit) f.flush.close;

	f.write(HEADER);
	size_t counter  = 0;
	foreach (path; files) {
		f.format("\t             \"{}\": cast(ubyte[])import(\"{}\")",
		                                    stripSuffix(path.name), path.name);
		if (counter < files.files - 1)
			f.write(",");
		f.newline;
		counter++;
	}
	f.formatln("\t            ];  // {} files\n}", files.files);

	Stdout.formatln("Successfully created {}.", OUTPUT);

	return 0;
}


char[] stripSuffix(char[] file)
{
	return file[0..locatePrior(file, '.')];
}
