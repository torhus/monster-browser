/**
 * A set container.
 */

module set;


/**
 * A set container.
 *
 * Currently it's just a thin wrapper around an associative array, ignoring
 * the values.
 */
struct Set(T) {
	private bool[T] data_;

	void add(T val) { data_[val] = true; }  ///
	void remove(T val) { data_.remove(val); } ///
	bool opIn_r(T val) { return (val in data_) != null; } ///
	size_t length() { return data_.length; } ///
	void rehash() { data_.rehash; } ///
	T[] toArray() { return data_.keys; } ///

	///
	static Set!(T) opCall(T[] values=null)
	{
		Set!(T) set;
		foreach (T val; values)
			set.add(val);
		return set;
	}

	///
	int opApply(int delegate(ref T) dg)
    {
	    int result = 0;
		foreach (key, val; data_) {
			result = dg(key);
			if (result)
				break;
		}
		return result;
	}
}
