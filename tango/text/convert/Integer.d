/*******************************************************************************

        copyright:      Copyright (c) 2004 Kris Bell. All rights reserved

        license:        BSD style: $(LICENSE)
        
        version:        Initial release: Nov 2005
        
        author:         Kris

        A set of functions for converting between string and integer 
        values. 

        Applying the D "import alias" mechanism to this module is highly
        recommended, in order to limit namespace pollution:
        ---
        import Integer = tango.text.convert.Integer;

        auto i = Integer.parse ("32767");
        ---
        
*******************************************************************************/

module tango.text.convert.Integer;

import std.conv: ConvException;
import std.traits;
alias ConvException IllegalArgumentException;
//private import tango.core.Exception;


long parse(T, U=uint) (T[] digits, U radix=0, uint* ate=null)
{return parse!(T)(digits, radix, ate);}

long parse(T) (T[] digits, uint radix=0, uint* ate=null)
{
        bool sign;

        auto eaten = trim (digits, sign, radix);
        auto value = convert (digits[eaten..$], radix, ate);

        // check *ate > 0 to make sure we don't parse "-" as 0.
        if (ate && *ate > 0)
            *ate += eaten;

        return cast(long) (sign ? -value : value);
}

/******************************************************************************

        Convert the provided 'digits' into an integer value,
        without checking for a sign or radix. The radix defaults
        to decimal (10).

        Returns the value and updates 'ate' with the number of
        characters consumed.

        Throws: none. The 'ate' param should be checked for valid input.

******************************************************************************/

ulong convert(T, U=uint) (T[] digits, U radix=10, uint* ate=null)
{return convert!(T)(digits, radix, ate);}

ulong convert(T) (T[] digits, uint radix=10, uint* ate=null)
{
        uint  eaten;
        ulong value;

        foreach (Unqual!T c; digits)
                {
                if (c >= '0' && c <= '9')
                   {}
                else
                   if (c >= 'a' && c <= 'z')
                       c -= 39;
                   else
                      if (c >= 'A' && c <= 'Z')
                          c -= 7;
                      else
                         break;

                if ((c -= '0') < radix)
                   {
                   value = value * radix + c;
                   ++eaten;
                   }
                else
                   break;
                }

        if (ate)
            *ate = eaten;

        return value;
}


/******************************************************************************

        Strip leading whitespace, extract an optional +/- sign,
        and an optional radix prefix. If the radix value matches
        an optional prefix, or the radix is zero, the prefix will
        be consumed and assigned. Where the radix is non zero and
        does not match an explicit prefix, the latter will remain 
        unconsumed. Otherwise, radix will default to 10.

        Returns the number of characters consumed.

******************************************************************************/

uint trim(T, U=uint) (T[] digits, ref bool sign, ref U radix)
{return trim!(T)(digits, sign, radix);}

uint trim(T) (T[] digits, ref bool sign, ref uint radix)
{
        Unqual!T c;
        T*      p = digits.ptr;
        int     len = digits.length;

        if (len)
           {
           // strip off whitespace and sign characters
           for (c = *p; len; c = *++p, --len)
                if (c is ' ' || c is '\t')
                   {}
                else
                   if (c is '-')
                       sign = true;
                   else
                      if (c is '+')
                          sign = false;
                   else
                      break;

           // strip off a radix specifier also?
           auto r = radix;
           if (c is '0' && len > 1)
               switch (*++p)
                      {
                      case 'x':
                      case 'X':
                           ++p;
                           r = 16;
                           break;
 
                      case 'b':
                      case 'B':
                           ++p;
                           r = 2;
                           break;
 
                      case 'o':
                      case 'O':
                           ++p;
                           r = 8;
                           break;
 
                      default: 
                           break;
                      } 

           // default the radix to 10
           if (r is 0)
               radix = 10;
           else
              // explicit radix must match (optional) prefix
              if (radix != r)
                  if (radix)
                      --p;
                  else
                     radix = r;
           }

        // return number of characters eaten
        return (p - digits.ptr);
}


/******************************************************************************

        quick & dirty text-to-unsigned int converter. Use only when you
        know what the content is, or use parse() or convert() instead.

        Return the parsed uint
        
******************************************************************************/

uint atoi(T) (T[] s, int radix = 10)
{
        uint value;

        foreach (c; s)
                 if (c >= '0' && c <= '9')
                     value = value * radix + (c - '0');
                 else
                    break;
        return value;
}


/******************************************************************************

        quick & dirty unsigned to text converter, where the provided output
        must be large enough to house the result (10 digits in the largest
        case). For mainstream use, consider utilizing format() instead.

        Returns a populated slice of the provided output
        
******************************************************************************/

T[] itoa(T, U=uint) (T[] output, U value, int radix = 10)
{return itoa!(T)(output, value, radix);}

T[] itoa(T) (T[] output, uint value, int radix = 10)
{
        T* p = output.ptr + output.length;

        do {
           *--p = cast(T)(value % radix + '0');
           } while (value /= radix);
        return output[p-output.ptr .. $];
}


/******************************************************************************

        Consume a number from the input without converting it. Argument
        'fp' enables floating-point consumption. Supports hex input for
        numbers which are prefixed appropriately

        Since version 0.99.9

******************************************************************************/

T[] consume(T) (T[] src, bool fp=false)
{
        T       c;
        bool    sign;
        uint    radix;

        // remove leading space, and sign
        auto e = src.ptr + src.length;
        auto p = src.ptr + trim (src, sign, radix);
        auto b = p;

        // bail out if the string is empty
        if (src.length is 0 || p > &src[$-1])
            return null;

        // read leading digits
        for (c=*p; p < e && ((c >= '0' && c <= '9') || 
            (radix is 16 && ((c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))));)
             c = *++p;

        if (fp)
           {
           // gobble up a point
           if (c is '.' && p < e)
               c = *++p;

           // read fractional digits
           while (c >= '0' && c <= '9' && p < e)
                  c = *++p;

           // did we consume anything?
           if (p > b)
              {
              // consume exponent?
              if ((c is 'e' || c is 'E') && p < e )
                 {
                 c = *++p;
                 if (c is '+' || c is '-')
                     c = *++p;
                 while (c >= '0' && c <= '9' && p < e)
                        c = *++p;
                 }
              }
           }
        return src [0 .. p-src.ptr];
}


/******************************************************************************

******************************************************************************/

debug (UnitTest)
{
        unittest
        {
        char[64] tmp;
        
        assert (toInt("1") is 1);
        assert (toLong("1") is 1);
        assert (toInt("1", 10) is 1);
        assert (toLong("1", 10) is 1);

        assert (atoi ("12345") is 12345);
        assert (itoa (tmp, 12345) == "12345");

        assert(parse( "0"w ) ==  0 );
        assert(parse( "1"w ) ==  1 );
        assert(parse( "-1"w ) ==  -1 );
        assert(parse( "+1"w ) ==  1 );

        // numerical limits
        assert(parse( "-2147483648" ) == int.min );
        assert(parse(  "2147483647" ) == int.max );
        assert(parse(  "4294967295" ) == uint.max );

        assert(parse( "-9223372036854775808" ) == long.min );
        assert(parse( "9223372036854775807" ) == long.max );
        assert(parse( "18446744073709551615" ) == ulong.max );

        // hex
        assert(parse( "a", 16) == 0x0A );
        assert(parse( "b", 16) == 0x0B );
        assert(parse( "c", 16) == 0x0C );
        assert(parse( "d", 16) == 0x0D );
        assert(parse( "e", 16) == 0x0E );
        assert(parse( "f", 16) == 0x0F );
        assert(parse( "A", 16) == 0x0A );
        assert(parse( "B", 16) == 0x0B );
        assert(parse( "C", 16) == 0x0C );
        assert(parse( "D", 16) == 0x0D );
        assert(parse( "E", 16) == 0x0E );
        assert(parse( "F", 16) == 0x0F );
        assert(parse( "FFFF", 16) == ushort.max );
        assert(parse( "ffffFFFF", 16) == uint.max );
        assert(parse( "ffffFFFFffffFFFF", 16u ) == ulong.max );
        // oct
        assert(parse( "55", 8) == 055 );
        assert(parse( "100", 8) == 0100 );
        // bin
        assert(parse( "10000", 2) == 0x10 );
        // trim
        assert(parse( "    \t20") == 20 );
        assert(parse( "    \t-20") == -20 );
        assert(parse( "-    \t 20") == -20 );
        // recognise radix prefix
        assert(parse( "0xFFFF" ) == ushort.max );
        assert(parse( "0XffffFFFF" ) == uint.max );
        assert(parse( "0o55") == 055 );
        assert(parse( "0O55" ) == 055 );
        assert(parse( "0b10000") == 0x10 );
        assert(parse( "0B10000") == 0x10 );

        // prefix tests
        char[] str = "0x";
        assert(parse( str[0..1] ) ==  0 );
        assert(parse("0x10", 10) == 0);
        assert(parse("0b10", 10) == 0);
        assert(parse("0o10", 10) == 0);
        assert(parse("0b10") == 0b10);
        assert(parse("0o10") == 010);
        assert(parse("0b10", 2) == 0b10);
        assert(parse("0o10", 8) == 010);

        // revised tests
        assert (format(tmp, 10, "d") == "10");
        assert (format(tmp, -10, "d") == "-10");

        assert (format(tmp, 10L, "u") == "10");
        assert (format(tmp, 10L, "U") == "10");
        assert (format(tmp, 10L, "g") == "10");
        assert (format(tmp, 10L, "G") == "10");
        assert (format(tmp, 10L, "o") == "12");
        assert (format(tmp, 10L, "O") == "12");
        assert (format(tmp, 10L, "b") == "1010");
        assert (format(tmp, 10L, "B") == "1010");
        assert (format(tmp, 10L, "x") == "a");
        assert (format(tmp, 10L, "X") == "A");

        assert (format(tmp, 10L, "d+") == "+10");
        assert (format(tmp, 10L, "d ") == " 10");
        assert (format(tmp, 10L, "d#") == "10");
        assert (format(tmp, 10L, "x#") == "0xa");
        assert (format(tmp, 10L, "X#") == "0XA");
        assert (format(tmp, 10L, "b#") == "0b1010");
        assert (format(tmp, 10L, "o#") == "0o12");

        assert (format(tmp, 10L, "d1") == "10");
        assert (format(tmp, 10L, "d8") == "00000010");
        assert (format(tmp, 10L, "x8") == "0000000a");
        assert (format(tmp, 10L, "X8") == "0000000A");
        assert (format(tmp, 10L, "b8") == "00001010");
        assert (format(tmp, 10L, "o8") == "00000012");

        assert (format(tmp, 10L, "d1#") == "10");
        assert (format(tmp, 10L, "d6#") == "000010");
        assert (format(tmp, 10L, "x6#") == "0x00000a");
        assert (format(tmp, 10L, "X6#") == "0X00000A");

        char[8] tmp1;
        assert (format(tmp1, 10L, "b12#") == "0b001010");
        assert (format(tmp1, 10L, "o12#") == "0o000012");
        }
}

/******************************************************************************

******************************************************************************/

/*debug (Integer)
{
        import tango.io.Stdout;

        void main()
        {
                char[8] tmp;

                Stdout.formatln ("d '{}'", format(tmp, 10));
                Stdout.formatln ("d '{}'", format(tmp, -10));

                Stdout.formatln ("u '{}'", format(tmp, 10L, "u"));
                Stdout.formatln ("U '{}'", format(tmp, 10L, "U"));
                Stdout.formatln ("g '{}'", format(tmp, 10L, "g"));
                Stdout.formatln ("G '{}'", format(tmp, 10L, "G"));
                Stdout.formatln ("o '{}'", format(tmp, 10L, "o"));
                Stdout.formatln ("O '{}'", format(tmp, 10L, "O"));
                Stdout.formatln ("b '{}'", format(tmp, 10L, "b"));
                Stdout.formatln ("B '{}'", format(tmp, 10L, "B"));
                Stdout.formatln ("x '{}'", format(tmp, 10L, "x"));
                Stdout.formatln ("X '{}'", format(tmp, 10L, "X"));

                Stdout.formatln ("d+ '{}'", format(tmp, 10L, "d+"));
                Stdout.formatln ("ds '{}'", format(tmp, 10L, "d "));
                Stdout.formatln ("d# '{}'", format(tmp, 10L, "d#"));
                Stdout.formatln ("x# '{}'", format(tmp, 10L, "x#"));
                Stdout.formatln ("X# '{}'", format(tmp, 10L, "X#"));
                Stdout.formatln ("b# '{}'", format(tmp, 10L, "b#"));
                Stdout.formatln ("o# '{}'", format(tmp, 10L, "o#"));

                Stdout.formatln ("d1 '{}'", format(tmp, 10L, "d1"));
                Stdout.formatln ("d8 '{}'", format(tmp, 10L, "d8"));
                Stdout.formatln ("x8 '{}'", format(tmp, 10L, "x8"));
                Stdout.formatln ("X8 '{}'", format(tmp, 10L, "X8"));
                Stdout.formatln ("b8 '{}'", format(tmp, 10L, "b8"));
                Stdout.formatln ("o8 '{}'", format(tmp, 10L, "o8"));

                Stdout.formatln ("d1# '{}'", format(tmp, 10L, "d1#"));
                Stdout.formatln ("d6# '{}'", format(tmp, 10L, "d6#"));
                Stdout.formatln ("x6# '{}'", format(tmp, 10L, "x6#"));
                Stdout.formatln ("X6# '{}'", format(tmp, 10L, "X6#"));

                Stdout.formatln ("b12# '{}'", format(tmp, 10L, "b12#"));
                Stdout.formatln ("o12# '{}'", format(tmp, 10L, "o12#")).newline;

                Stdout.formatln (consume("10"));
                Stdout.formatln (consume("0x1f"));
                Stdout.formatln (consume("0.123"));
                Stdout.formatln (consume("0.123", true));
                Stdout.formatln (consume("0.123e-10", true)).newline;

                Stdout.formatln (consume("10  s"));
                Stdout.formatln (consume("0x1f   s"));
                Stdout.formatln (consume("0.123  s"));
                Stdout.formatln (consume("0.123  s", true));
                Stdout.formatln (consume("0.123e-10  s", true)).newline;
        }
}*/



