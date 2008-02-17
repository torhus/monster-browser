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
	q3Colors[1] = new TextStyle(null, new Color(display, 255,   0,   0), null);
	// green
	q3Colors[2] = new TextStyle(null, new Color(display,   0, 255,   0), null);
	// yellow
	q3Colors[3] = new TextStyle(null, new Color(display, 255, 255,   0), null);
	// blue
	q3Colors[4] = new TextStyle(null, new Color(display,   0,   0, 255), null);
	// cyan
	q3Colors[5] = new TextStyle(null, new Color(display,   0, 255, 255), null);
	// magenta
	q3Colors[6] = new TextStyle(null, new Color(display, 255,   0, 255), null);
	// white
	//q3Colors[7] = new TextStyle(null, new Color(display, 255, 255, 255), null);
	q3Colors[7] = q3Colors[0];
}


static ~this() {
	foreach (c; q3Colors) {
		if (!c.foreground.isDisposed())
			c.foreground.dispose();
	}
}


/** A parsed colored name. */
class ColoredName {
	char[] cleanName;
	ColorRange[] ranges;
}


/** A color and a range to apply it to. */
struct ColorRange {
	TextStyle style;
	int start;
	int end;
}


/**
 * Parse colored names.
 *
 */
ColoredName parseColors(char[] s)
{
	ColoredName cname = new ColoredName;
	ColorRange crange;

	for (int i=0; i < s.length; i++) {
		if (s[i] == '^' && (i == s.length-1 || s[i+1] != '^')) {
			// terminate the previous range
			if (cname.ranges.length)
				cname.ranges[$-1].end = cname.cleanName.length - 1;
			if (i == s.length-1)
				break;

			i++;

			crange.start = cname.cleanName.length;

			/* The method of getting the index is straight from quake3 1.32b's
			 * q_shared.h.
			 */
			crange.style = q3Colors[(s[i] - '0') & 7];

			cname.ranges ~= crange;
		}
		else {
			cname.cleanName ~= s[i];
		}
	}

	// terminate the last range
	if (cname.ranges.length)
		cname.ranges[$-1].end = cname.cleanName.length - 1;

	return cname;
}


unittest {
	printf("colorednames unit test starting...\n");

	assert(parseColors("mon^1S^7ter").cleanName == "monSter");
	assert(parseColors("^wwhite^8black").cleanName == "whiteblack");
	assert(parseColors("1a2b3c4^").cleanName == "1a2b3c4");
	assert(parseColors("^^0blackie").cleanName == "^blackie");
	//assert(parseColors("^1").cleanName == "UnnamedPlayer");

	printf("colorednames unit test succeeded.\n");
}
