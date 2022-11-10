/**
 * A synchronized wrapper for an associative array.
 */

module syncaa;


synchronized final class SyncAA(K, V) ///
{
    ///
    V opIndex(K key) { return unshare[key]; }

    ///
    V opIndexAssign(V value, K key) { return unshare[key] = value; }

    ///
    K[] keys() { return unshare.keys; }

    ///
    void remove(K key) { data_.remove(key); }

    /// There is no `in` operator, it would not be thread-safe.
    V get(K key, lazy V defaultValue=V.init)
    {
        auto p = key in unshare;
        return p ? *p : defaultValue;
    }

    ///
    int opApply(scope int delegate(ref V) dg) const
    {
        int result = 0;
        foreach (value; unshare) {
            result = dg(value);
            if (result)
                break;
        }
        return result;
    }

    ///
    int opApply(scope int delegate(ref K, ref V) dg) const
    {
        int result = 0;
        foreach (key, value; unshare) {
            result = dg(key, value);
            if (result)
                break;
        }
        return result;
    }

private:
    V[K] data_;
    ref V[K] unshare() inout { return *cast(V[K]*)&data_; }
}
