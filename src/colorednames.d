/**
 * Decoding of player and server name color codes.
 */

module colorednames;

import org.eclipse.swt.graphics.Color;
import org.eclipse.swt.graphics.TextStyle;
import org.eclipse.swt.widgets.Display;


// Extended set of color codes, like in RtCW: Enemy Territory.
// The first eight colors are the same as for Quake 3.
__gshared private TextStyle[32] etColors;

private enum Q3_DEFAULT_NAME = "UnnamedPlayer";


shared static this() {
	Display disp = Display.getDefault();

	// black
	etColors[0] = new TextStyle(null, new Color(disp,   0,   0,   0), null);
	// red
	etColors[1] = new TextStyle(null, new Color(disp, 220,   0,   0), null);
	// green
	etColors[2] = new TextStyle(null, new Color(disp,   0, 150,   0), null);
	// yellow
	etColors[3] = new TextStyle(null, new Color(disp, 198, 198,   0), null);
	// blue
	etColors[4] = new TextStyle(null, new Color(disp,   0,   0, 204), null);
	// cyan
	etColors[5] = new TextStyle(null, new Color(disp,   0, 204, 204), null);
	// magenta
	etColors[6] = new TextStyle(null, new Color(disp, 230,   0, 230), null);
	// for white color codes we use black
	etColors[7] = etColors[0];

	// EXTENDED COLORS
	// See http://wolfwiki.anime.net/index.php/Color_Codes

	// #ff7f00 (orange)
	etColors[ 8] = new TextStyle(null, new Color(disp, 255, 127,   0), null);
	// #7f7f7f (grey)
	etColors[ 9] = new TextStyle(null, new Color(disp, 127, 127, 127), null);
	// #bfbfbf (light grey)
	etColors[10] = new TextStyle(null, new Color(disp, 191, 191, 191), null);
	// duplicate of the above
	etColors[11] = etColors[10];
	// #007f00 (dark green)
	etColors[12] = new TextStyle(null, new Color(disp,   0, 127,   0), null);
	// #7f7f00
	etColors[13] = new TextStyle(null, new Color(disp, 127, 127,   0), null);
	// #00007f
	etColors[14] = new TextStyle(null, new Color(disp,   0,   0, 127), null);
	// #7f0000
	etColors[15] = new TextStyle(null, new Color(disp, 127,   0,   0), null);
	// #7f3f00
	etColors[16] = new TextStyle(null, new Color(disp, 127,  63,   0), null);
	// #ff9919
	etColors[17] = new TextStyle(null, new Color(disp, 255, 153,  25), null);
	// #007f7f
	etColors[18] = new TextStyle(null, new Color(disp,   0, 127, 127), null);
	// #7f007f
	etColors[19] = new TextStyle(null, new Color(disp, 127,   0, 127), null);
	// #007fff
	etColors[20] = new TextStyle(null, new Color(disp,   0, 127, 255), null);
	// #7f00ff
	etColors[21] = new TextStyle(null, new Color(disp, 127,   0, 255), null);
	// #3399cc
	etColors[22] = new TextStyle(null, new Color(disp,  51, 153, 204), null);
	// #ccffcc
	etColors[23] = new TextStyle(null, new Color(disp, 204, 255, 204), null);
	// #006633
	etColors[24] = new TextStyle(null, new Color(disp,   0, 102,  51), null);
	// #ff0033
	etColors[25] = new TextStyle(null, new Color(disp, 255,   0,  51), null);
	// #b21919
	etColors[26] = new TextStyle(null, new Color(disp, 178,  25,  25), null);
	// #993300
	etColors[27] = new TextStyle(null, new Color(disp, 153,  51,   0), null);
	// #cc9933
	etColors[28] = new TextStyle(null, new Color(disp, 204, 153,  51), null);
	// #999933
	etColors[29] = new TextStyle(null, new Color(disp, 153, 153,  51), null);
	// #ffffbf
	etColors[30] = new TextStyle(null, new Color(disp, 255, 255, 191), null);
	// #ffff7f
	etColors[31] = new TextStyle(null, new Color(disp, 255, 255, 127), null);
}


void disposeNameColors() {
	foreach (c; etColors) {
		if (!c.foreground.isDisposed())
			c.foreground.dispose();
	}
}


/** A parsed colored name. */
// FIXME: ColoredName.cleanName is not being used anywhere.
struct ColoredName {
	string cleanName;     ///  The string in question, stripped of color codes.
	ColorRange[] ranges;  ///
}


/** A color and a range to apply it to. */
struct ColorRange {
	TextStyle style;  /// Contains an SWT Color object set to the right color.
	int start;        /// The first character this ColorRange applies to.
	int end;          /// The last character this ColorRange applies to.
}


/**
 * Parse a string containing color codes.
 *
 */
ColoredName parseColors(in char[] s, bool useEtColors=false)
{
	ColoredName name;
	ColorRange range;
	int bitMask = useEtColors ? 31 : 7;

	for (int i=0; i < s.length; i++) {
		if (s[i] == '^' && (i == s.length-1 || s[i+1] != '^')) {
			// terminate the previous range
			if (name.ranges.length)
				name.ranges[$-1].end = name.cleanName.length - 1;
			if (i == s.length-1)
				break;

			i++;

			range.start = name.cleanName.length;

			/* The method of getting the index is straight from quake3 1.32b's
			 * q_shared.h.
			 */
			range.style = etColors[(s[i] - '0') & bitMask];

			name.ranges ~= range;
		}
		else {
			name.cleanName ~= s[i];
		}
	}

	// terminate the last range
	if (name.ranges.length)
		name.ranges[$-1].end = name.cleanName.length - 1;

	if (name.cleanName.length == 0)
		name.cleanName = Q3_DEFAULT_NAME;

	return name;
}


unittest {
	printf("colorednames.parseColors unit test starting...\n");

	assert(parseColors("mon^1S^7ter").cleanName == "monSter");
	assert(parseColors("^wwhite^0black").cleanName == "whiteblack");
	assert(parseColors("1a2b3c4^").cleanName == "1a2b3c4");
	assert(parseColors("^^0blackie").cleanName == "^blackie");
	assert(parseColors("^1").cleanName == "UnnamedPlayer");

	printf("colorednames.parseColors unit test succeeded.\n");
}


/**
 *  Strip the color codes from a string.
 */
string stripColorCodes(in char[] s)
{
	char[] name;

	for (int i=0; i < s.length; i++) {
		if (s[i] == '^' && (i == s.length-1 || s[i+1] != '^')) {
			i++;
			continue;
		}
		name ~= s[i];
	}

	return (name.length > 0) ? cast(string)name : Q3_DEFAULT_NAME;
}
