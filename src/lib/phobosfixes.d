/* Workarounds for various Phobos 2 issues */
module lib.phobosfixes;

import std.exception; // for assumeUnique
import std.functional; // for binaryFun
import std.range;  // for isRandomAccessRange
import std.utf;  // for decode


/* Using this instead of std.range.SortedRange, to avoid having to benchmark
 * to make sure there's no performance loss with the new version.  Phobos 2 is
 * as of April 2011 not tested and optimized much. Taken from DMD 2.046.
 */
Range upperBound(alias pred = "a < b", Range, V)(Range r, V value)
	if (isRandomAccessRange!(Range))
{
	size_t first = 0;
	size_t count = r.length;
	while (count > 0)
	{
		auto step = count / 2;
		auto it = first + step;
		if (!binaryFun!(pred)(value, r[it]))
		{
			first = it + 1;
			count -= step + 1;
		}
		else count = step;
	}
	return r[first .. r.length];
}


// From DMD 2.046, as the 2.052 version in std.array seems to be broken.
string join(in string[] words, string sep)
{
	if (!words.length) return null;
	immutable seplen = sep.length;
	size_t len = (words.length - 1) * seplen;
	
	foreach (i; 0 .. words.length)
		len += words[i].length;
	
	auto result = new char[len];
	
	size_t j;
	foreach (i; 0 .. words.length)
	{
		if (i > 0)
		{
			result[j .. j + seplen] = sep;
			j += seplen;
		}
		immutable wlen = words[i].length;
		result[j .. j + wlen] = words[i];
		j += wlen;
	}
	assert(j == len);
	return assumeUnique(result);
}
