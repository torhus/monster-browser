/*
	Copyright (C) 2004-2006 Christopher E. Miller

	This software is provided 'as-is', without any express or implied
	warranty.  In no event will the authors be held liable for any damages
	arising from the use of this software.

	Permission is granted to anyone to use this software for any purpose,
	including commercial applications, and to alter it and redistribute it
	freely, subject to the following restrictions:

	1. The origin of this software must not be misrepresented; you must not
	   claim that you wrote the original software. If you use this software
	   in a product, an acknowledgment in the product documentation would be
	   appreciated but is not required.
	2. Altered source versions must be plainly marked as such, and must not be
	   misrepresented as being the original software.
	3. This notice may not be removed or altered from any source distribution.
*/

/*

This file was modified 4 Feb 2009 by torhu (tango port).

Update:
The Ini object no longer saves in the destructor because if it is the
garbage collector deleting it, some value or section object could have
been destructed first, resulting in undefined behavior, such as an
access violation. Solution: save() before you exit the program.


Portable module for reading and writing INI files of the format:

[section]
key=value
...

Leading spaces and tabs are ignored.
Comments start with ; and should be on their own line.

If there are comments, spaces or keys above the first section, a nameless section is created for them.
This means there need not be any sections in the file to have keys.

Differences with Windows' profile (INI) functions:
* Windows 9x does not allow tabs in the value.
* Some versions do not allow the file to exceed 64 KB.
* If not a full file path, it's relative to the Windows directory.
* Windows 9x strips trailing spaces from the value.
* There might be a restriction on how long sections/keys/values may be.
* If there are double quotes around a value, Windows removes them.
* All key/value pairs must be in a named section.

*/



/// Module for reading and writing _INI files. _ini.d version 0.5
module ini;

import tango.io.device.File;
import tango.io.stream.TextFileStream;
import tango.stdc.stringz;
import tango.text.Ascii;
import tango.text.Util;

//debug = INI; //show file being parsed


debug(INI)
	import tango.io.Stdout;


private class IniLine
{
	~this()
	{
		debug(PRINT_DTORS)
			Stdout("~IniLine").newline;
	}


private:
	char[] data;
}


/// Key in an INI file.
class IniKey: IniLine
{
protected:
	//these are slices in data if unmodified
	//if modified, data is set to null
	char[] _name;
	char[] _value;


	this(char[] name)
	{
		_name = name;
	}


	~this()
	{
		debug(PRINT_DTORS)
			Stdout.formatln("~IniKey '{}'", _name);
	}


public:
	/// Property: get key _name.
	char[] name()
	{
		return _name;
	}


	/// Property: get key _value.
	char[] value()
	{
		return _value;
	}
}


/// Section of keys in an INI file.
class IniSection
{
protected:
	Ini _ini;
	char[] _name;
	IniLine[] lines;


	this(Ini ini, char[] name)
	{
		_ini = ini;
		_name = name;
	}


	~this()
	{
		debug(PRINT_DTORS)
			Stdout.formatln("~IniSection '{}'", _name);
	}


public:
	/// Property: get section _name.
	char[] name()
	{
		return _name;
	}


	/// Property: set section _name.
	void name(char[] newName)
	{
		_ini._modified = true;
		_name = newName;
	}


	/// foreach key.
	int opApply(int delegate(inout IniKey) dg)
	{
		int result = 0;
		uint i;
		IniKey ikey;
		for(i = 0; i != lines.length; i++)
		{
			ikey = cast(IniKey)lines[i];
			if(ikey)
			{
				result = dg(ikey);
				if(result)
					break;
			}
		}
		return result;
	}


	/// Property: get all _keys.
	//better to use foreach unless this array is needed
	IniKey[] keys()
	{
		IniKey[] ikeys = new IniKey[lines.length];
		uint i = 0;
		foreach(IniKey ikey; this)
		{
			ikeys[i++] = ikey;
		}
		return ikeys[0 .. i];
	}


	/// Returns: _key matching keyName, or null if not present.
	IniKey key(char[] keyName)
	{
		foreach(IniKey ikey; this)
		{
			if(_ini.match(ikey._name, keyName))
				return ikey;
		}
		return null; //didn't find it
	}


	/// Set an existing key's value.
	void setValue(IniKey ikey, char[] newValue)
	{
		ikey._value = newValue;
		_ini._modified = true;
		ikey.data = null;
	}


	/// Find or create key keyName and set its _value to newValue.
	void setValue(char[] keyName, char[] newValue)
	{
		IniKey ikey = key(keyName);
		if(!ikey)
		{
			ikey = new IniKey(keyName);
			lines ~= ikey;
			//_ini._modified = true; //next call does this
		}
		value(ikey, newValue);
	}


	/+
	///
	alias setValue value;
	+/


	/// Same as setValue(ikey, newValue).
	void value(IniKey ikey, char[] newValue)
	{
		return setValue(ikey, newValue);
	}


	/// Same as setValue(keyName, newValue).
	void value(char[] keyName, char[] newValue)
	{
		return setValue(keyName, newValue);
	}


	/// Returns: value of the existing key keyName, or defaultValue if not present.
	char[] getValue(char[] keyName, char[] defaultValue = null)
	{
		foreach(IniKey ikey; this)
		{
			if(_ini.match(ikey._name, keyName))
				return ikey.value;
		}
		return defaultValue; //didn't find it
	}


	// /// Returns: _value of the existing key keyName, or null if not present.
	/// Same as setValue(keyName, null).
	char[] value(char[] keyName)
	{
		return getValue(keyName, null);
	}


	/// Shortcut for getValue(keyName).
	char[] opIndex(char[] keyName)
	{
		return value(keyName);
	}


	/// Shortcut for setValue(keyName, newValue).
	void opIndexAssign(char[] newValue, char[] keyName)
	{
		value(keyName, newValue);
	}


	/// _Remove key keyName.
	void remove(char[] keyName)
	{
		uint i;
		IniKey ikey;
		for(i = 0; i != lines.length; i++)
		{
			ikey = cast(IniKey)lines[i];
			if(ikey && _ini.match(ikey._name, keyName))
			{
				if(i == lines.length - 1)
					lines = lines[0 .. i];
				else if(i == 0)
					lines = lines[1 .. lines.length];
				else
					lines = lines[0 .. i] ~ lines[i + 1 .. lines.length];
				_ini._modified = true;
				return;
			}
		}
	}
}


/// An INI file.
class Ini
{
protected:
	char[] _file;
	bool _modified = false;
	IniSection[] isecs;
	char secStart = '[', secEnd = ']';


	void parse()
	{
		debug(INI)
			Stdout.formatln("INI parsing file '{}'\n", _file);

		char[] data;
		int i = -1;
		IniSection isec;
		uint lineStartIndex = 0;

		try
		{
			data = cast(char[])File.get(_file);
			/+
			File f = new File(_file, FileMode.In);
			data = f.readString(f.size());
			delete f;
			+/
		}
		catch(Object o)
		{
			debug(INI)
				Stdout("INI no file to parse").newline;
			return;
		}
		if(!data.length)
		{
			debug(INI)
				Stdout("INI nothing to parse").newline;
			return;
		}


		char getc()
		{
			//also increment -i- past end so ungetc works properly
			if(++i >= data.length)
				return 0;
			return data[i];
		}


		void ungetc()
		{
			assert(i > 0);
			i--;
		}


		void reset()
		{
			lineStartIndex = i + 1;
		}


		void eol()
		{
			IniLine iline = new IniLine;
			iline.data = data[lineStartIndex .. i];
			debug(INI)
				Stdout.formatln("INI line: '{}'", substitute(substitute(substitute(iline.data, "\\", "\\\\"), "\r", "\\r"), "\n", "\\n"));
			isec.lines ~= iline;
		}


		char ch, ch2;
		int i2;
		isec = new IniSection(this, "");
		for(;;)
		{
			ch = getc();
			switch(ch)
			{
				case '\r':
					eol();
					ch2 = getc();
					if(ch2 != '\n')
						ungetc();
					reset();
					break;

				case '\n':
					eol();
					reset();
					break;

				case 0: //eof
					ini_eof:
					if(lineStartIndex < i)
					{
						eol();
						//reset();
					}
					isecs ~= isec;
					if(!isecs[0].lines)
						isecs = isecs[1 .. isecs.length];
					debug(INI)
						Stdout("INI done parsing").newline.newline;
					return;

				case ' ':
				case '\t':
				case '\v':
				case '\f':
					break;

				case ';': //comments
				case '#':
					done_comment:
					for(;;)
					{
						ch2 = getc();
						switch(ch2)
						{
							case '\r':
								eol();
								ch2 = getc();
								if(ch2 != '\n')
									ungetc();
								reset();
								break done_comment;

							case '\n':
								eol();
								reset();
								break done_comment;

							case 0: //eof
								goto ini_eof;

							default: ;
						}
					}
					break;

				default:
					if(ch == secStart) // '['
					{
						i2 = i + 1;
						done_sec:
						for(;;)
						{
							ch2 = getc();
							switch(ch2)
							{
								case '\r':
									eol();
									ch2 = getc();
									if(ch2 != '\n')
										ungetc();
									reset();
									break done_sec;

								case '\n':
									eol();
									reset();
									break done_sec;

								case 0: //eof
									goto ini_eof;

								default:
									if(ch2 == secEnd) // ']'
									{
										isecs ~= isec;
										isec = new IniSection(this, data[i2 .. i]);
										debug(INI)
											Stdout.formatln("INI section: '{}'", isec._name);
										for(;;)
										{
											ch2 = getc();
											switch(ch2)
											{
												case ' ':
												case '\t':
												case '\v':
												case '\f':
													//ignore whitespace
													break;

												case '\r':
													ch2 = getc();
													if(ch2 != '\n')
														ungetc();
													break done_sec;

												case '\n':
													break done_sec;

												default:
													//just treat junk after the ] as the next line
													ungetc();
													break done_sec;
											}
										}
										break done_sec;
									}
							}
						}
						reset();
						break;
					}
					else //must be beginning of key name
					{
						i2 = i;
						done_default:
						for(;;)
						{
							ch2 = getc();
							switch(ch2)
							{
								case '\r':
									eol();
									ch2 = getc();
									if(ch2 != '\n')
										ungetc();
									reset();
									break done_default;

								case '\n':
									eol();
									reset();
									break done_default;

								case 0: //eof
									goto ini_eof;

								case ' ':
								case '\t':
								case '\v':
								case '\f':
									break;

								case '=':
									IniKey ikey;


									void addKey()
									{
										ikey.data = data[lineStartIndex .. i];
										ikey._value = data[i2 .. i];
										isec.lines ~= ikey;
										debug(INI)
											Stdout.formatln("INI key: '{}' = '{}'", ikey._name, ikey._value);
									}


									ikey = new IniKey(data[i2 .. i]);
									i2 = i + 1; //after =
									for(;;) //get key value
									{
										ch2 = getc();
										switch(ch2)
										{
											case '\r':
												addKey();
												ch2 = getc();
												if(ch2 != '\n')
													ungetc();
												reset();
												break done_default;

											case '\n':
												addKey();
												reset();
												break done_default;

											case 0: //eof
												addKey();
												reset();
												goto ini_eof;

											default: ;
										}
									}
									break done_default;

								default: ;
							}
						}
					}
			}
		}
	}


	void firstOpen(char[] file)
	{
		//null terminated just to make it easier for the implementation
		_file = toStringz(file.dup)[0 .. file.length];
		parse();
	}


public:
	// Use different section name delimiters; not recommended.
	this(char[] file, char secStart, char secEnd)
	{
		this.secStart = secStart;
		this.secEnd = secEnd;

		firstOpen(file);
	}


	/// Construct a new INI _file.
	this(char[] file)
	{
		firstOpen(file);
	}


	~this()
	{
		debug(PRINT_DTORS)
			Stdout.formatln("~Ini '{}'", _file);

		// The reason this is commented is explained above.
		/+
		if(_modified)
			save();
		+/
	}


	/// Comparison function for section and key names. Override to change behavior.
	bool match(char[] s1, char[] s2)
	{
		return !icompare(s1, s2);
	}


	//reuse same object for another file
	/// Open an INI _file.
	void open(char[] file)
	{
		if(_modified)
			save();
		_modified = false;
		isecs = null;

		firstOpen(file);
	}


	/// Reload INI file; any unsaved changes are lost.
	void rehash()
	{
		_modified = false;
		isecs = null;
		parse();
	}


	/// Release memory without saving changes; contents become empty.
	void dump()
	{
		_modified = false;
		isecs = null;
	}


	/// Property: get whether or not the INI file was _modified since it was loaded or saved.
	bool modified()
	{
		return _modified;
	}


	/// Write contents to disk, even if no changes were made. It is common to do if(modified)save();
	void save()
	{
		_modified = false;

		if(!isecs.length)
			return;

		IniKey ikey;
		IniSection isec;
		uint i = 0, j;
		scope TextFileOutput f = new TextFileOutput(_file);
		scope (exit)
			f.flush.close;

		if(isecs[0]._name.length)
			goto write_name;
		else //first section doesn't have a name; just keys at start of file
			goto after_name;

		for(; i != isecs.length; i++)
		{
			write_name:
			f(secStart)(isecs[i]._name)(secEnd).newline;
			after_name:
			isec = isecs[i];
			for(j = 0; j != isec.lines.length; j++)
			{
				if(isec.lines[j].data is null)
				{
					ikey = cast(IniKey)isec.lines[j];
					if(ikey)
						ikey.data = ikey._name ~ "=" ~ ikey._value;
				}
				f(isec.lines[j].data).newline;
			}
		}
	}


	/// Finds a _section; returns null one named name does not exist.
	IniSection section(char[] name)
	{
		foreach(IniSection isec; isecs)
		{
			if(match(isec._name, name))
				return isec;
		}
		return null; //didn't find it
	}


	/// Shortcut for section(sectionName).
	IniSection opIndex(char[] sectionName)
	{
		return section(sectionName);
	}


	/// The section is created if one named name does not exist.
	/// Returns: Section named name.
	IniSection addSection(char[] name)
	{
		IniSection isec = section(name);
		if(!isec)
		{
			isec = new IniSection(this, name);
			_modified = true;
			isecs ~= isec;
		}
		return isec;
	}


	/// foreach section.
	int opApply(int delegate(inout IniSection) dg)
	{
		int result = 0;
		foreach(IniSection isec; isecs)
		{
			result = dg(isec);
			if(result)
				break;
		}
		return result;
	}


	/// Property: get all _sections.
	IniSection[] sections()
	{
		return isecs;
	}


	/// _Remove section named sectionName.
	void remove(char[] sectionName)
	{
		uint i;
		for(i = 0; i != isecs.length; i++)
		{
			if(match(sectionName, isecs[i]._name))
			{
				if(i == isecs.length - 1)
					isecs = isecs[0 .. i];
				else if(i == 0)
					isecs = isecs[1 .. isecs.length];
				else
					isecs = isecs[0 .. i] ~ isecs[i + 1 .. isecs.length];
				_modified = true;
				return;
			}
		}
	}
}


unittest
{
	char[] inifile = "unittest.ini";
	Ini ini;

	ini = new Ini(inifile);
	with(ini.addSection("foo"))
	{
		value("asdf", "jkl");
		value("bar", "wee!");
		value("hi", "hello");
	}
	ini.addSection("BAR");
	with(ini.addSection("fOO"))
	{
		value("yes", "no");
	}
	with(ini.addSection("Hello"))
	{
		value("world", "true");
	}
	with(ini.addSection("test"))
	{
		value("1", "2");
		value("3", "4");
	}
	ini["test"]["value"] = "true";
	assert(ini["Foo"]["yes"] == "no");
	ini.save();
	delete ini;

	ini = new Ini(inifile);
	assert(ini["FOO"]["Bar"] == "wee!");
	assert(ini["Foo"]["yes"] == "no");
	assert(ini["hello"]["world"] == "true");
	assert(ini["FOO"]["Bar"] == "wee!");
	assert(ini["55"] is null);
	assert(ini["hello"]["Yes"] is null);

	ini.open(inifile);
	ini["bar"].remove("notta");
	ini["foo"].remove("bar");
	ini.remove("bar");
	assert(ini["bar"] is null);
	assert(ini["foo"] !is null);
	assert(ini["foo"]["bar"] is null);
	ini.remove("foo");
	assert(ini["foo"] is null);
	ini.save();
	delete ini;
}

