/**
 * A synchronized wrapper for an associative array.
 */

module syncaa;

import std.traits : SharedOf;


synchronized final class SyncAA(K, V) ///
{
    // FIXME: Can initialize with new K[V] with DMD 2.101.
    this() { data_[K.init] = V.init; data_.remove(K.init); }

    ///
    V opIndex(K key) { return unshare[key]; }

    ///
    V opIndexAssign(V value, K key)
    {
        data_[key] = cast(SharedOf!V)value;
        return value;
    }

    ///
    K[] keys() { return unshare.keys; }

    ///
    V[] values() { return unshare.values; }

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
    V[K] unshare() inout { return cast(V[K])data_; }
}
