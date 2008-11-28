/**
 * Decoding of Quake 3 style player and server name color codes.
 */
 
module colorednames;

import tango.stdc.ctype;
import tango.stdc.stdio;

import dwt.graphics.Color;
import dwt.graphics.TextStyle;
import dwt.widgets.Display;


private TextStyle[8] q3Colors;


static this() {
	Display display = Display.getDefault();

	// black
	q3Colors[0] = new TextStyle(null, new Color(display,   0,   0,   0), null);
	// red
	q3Colors[1] = new TextStyle(null, new Color(display, 240,   0,   0), null);
	// green
	q3Colors[2] = new TextStyle(null, new Color(display,   0, 190,   0), null);
	// yellow
	q3Colors[3] = new TextStyle(null, new Color(display, 220, 220,   0), null);
	// blue
	q3Colors[4] = new TextStyle(null, new Color(display,   0,   0, 240), null);
	// cyan
	q3Colors[5] = new TextStyle(null, new Color(display,   0, 225, 225), null);
	// magenta
	q3Colors[6] = new TextStyle(null, new Color(display, 230,   0, 230), null);
	// white
	//q3Colors[7] = new TextStyle(null, new Color(display, 255, 255, 255), null);
	q3Colors[7] = q3Colors[0];
}


void disposeNameColors() {
	foreach (c; q3Colors) {
		if (!c.foreground.isDisposed())
			c.foreground.dispose();
	}
}


/** A parsed colored name. */
// FIXME: ColoredName.cleanName is not being used anywhere.  ColoredName could
// also  be made a struct, to avoid some heap allocation.
class ColoredName {
	char[] cleanName;     ///  The string in question, stripped of color codes.
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
ColoredName parseColors(in char[] s)
{
	ColoredName name = new ColoredName;
	ColorRange range;

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
			range.style = q3Colors[(s[i] - '0') & 7];

			name.ranges ~= range;
		}
		else {
			name.cleanName ~= s[i];
		}
	}

	// terminate the last range
	if (name.ranges.length)
		name.ranges[$-1].end = name.cleanName.length - 1;

	return name;
}


unittest {
	printf("colorednames.parseColors unit test starting...\n");

	assert(parseColors("mon^1S^7ter").cleanName == "monSter");
	assert(parseColors("^wwhite^8black").cleanName == "whiteblack");
	assert(parseColors("1a2b3c4^").cleanName == "1a2b3c4");
	assert(parseColors("^^0blackie").cleanName == "^blackie");
	//assert(parseColors("^1").cleanName == "UnnamedPlayer");

	printf("colorednames.parseColors unit test succeeded.\n");
}


/**
 *  Strip the color codes from a string.
 */
char[] stripColorCodes(in char[] s)
{
	char[] name;

	for (int i=0; i < s.length; i++) {
		if (s[i] == '^' && (i == s.length-1 || s[i+1] != '^')) {
			i++;
			continue;
		}
		name ~= s[i];
	}

	return name;
}
