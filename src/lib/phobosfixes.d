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
	auto first = 0;
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


// From DMD 2.046, as the 2.052 version seems to be broken.
int icmp(in char[] s1, in char[] s2)
{
	size_t i1, i2;
	for (;;)
	{
		if (i1 == s1.length) return i2 - s2.length;
		if (i2 == s2.length) return s1.length - i1;
		auto c1 = std.utf.decode(s1, i1),
			c2 = std.utf.decode(s2, i2);
		if (c1 >= 'A' && c1 <= 'Z')
			c1 += cast(int)'a' - cast(int)'A';
		if (c2 >= 'A' && c2 <= 'Z')
			c2 += cast(int)'a' - cast(int)'A';
		if (c1 != c2) return cast(int) c1 - cast(int) c2;
	}
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
