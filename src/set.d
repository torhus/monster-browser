/**
 * A set container.
 */

module set;

import std.range;


/**
 * A set container.
 */
struct Set(T) {
	private bool[T] data_;

	///
	this(R)(R range)
		if (isInputRange!R && is(ElementType!R == T))
	{
		add(range);
	}

	void add(T val) { data_[val] = true; }  ///

	///
	void add(R)(R range)
		if (isInputRange!R && is(ElementType!R == T))
	{
		foreach (T val; range)
			add(val);
	}

	///
	void add(Set!(T) other)
	{
		add(other.data_.byKey());
	}

	void remove(T val) { data_.remove(val); } ///

	///
	bool opBinaryRight(string op : "in")(T val) const
	{
		return (val in data_) != null;
	}

	size_t length() const { return data_.length; } ///
	void rehash() { data_.rehash; } ///
	void clear() { data_.clear; } ///

	auto opSlice() const { return data_.byKey(); } ///

	///
	int opApply(int delegate(const ref T) dg) const
	{
		int result = 0;
		foreach (key, _; data_) {
			result = dg(key);
			if (result)
				break;
		}
		return result;
	}
}
