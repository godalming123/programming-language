package main

// Custom arbitrary size number implementation
// TODO:
// - Implement exact fractions
// - Implement division
// - Implement modulo
// - Implement binary shifts
// - Free memory correctly

import "core:slice"

BigUint :: struct {
    // The further on in the array the chunk index is, the bigger the chunk is
    // chunk_multiplier = (2 ^ 32) ^ chunk_index
    chunks: []u64,
}

BigInt :: struct {
    is_negated:     bool,
    absolute_value: BigUint,
}

uint_zero :: BigUint{nil}
int_zero :: BigInt{false, uint_zero}

big_uint_from_u64 :: proc(num: u64) -> BigUint {
    if num == 0 {
        return uint_zero
    }
    chunks := make([]u64, 1)
    chunks[0] = num
    return BigUint{chunks}
}

big_int_from_i64 :: proc(num: i64) -> BigInt {
    if num < 0 {
        return BigInt{true, big_uint_from_u64(u64(-num))}
    }
    return BigInt{false, big_uint_from_u64(u64(num))}
}

LongerAndShorter :: struct {
    longer:  BigUint,
    shorter: BigUint,
}

get_longer_and_shorter :: proc(a: BigUint, b: BigUint) -> LongerAndShorter {
    if len(a.chunks) > len(b.chunks) {
        return LongerAndShorter{a, b}
    } else {
        return LongerAndShorter{b, a}
    }
}

plus_equal :: proc(longer: BigUint, shorter: BigUint, carry: bool) -> bool {
    if len(shorter.chunks) == 0 {
        return carry
    }
    a := longer.chunks[0]
    b := shorter.chunks[0]
    longer.chunks[0] = a + b + (carry ? 1 : 0)
    return plus_equal(BigUint{longer.chunks[1:]}, BigUint{shorter.chunks[1:]}, a > max(u64) - b)
}

minus_equal :: proc(longer: BigUint, shorter: BigUint, carry: bool) -> bool {
    if len(shorter.chunks) == 0 {
        return carry
    }
    a := longer.chunks[0]
    b := shorter.chunks[0]
    longer.chunks[0] = a - b - (carry ? 1 : 0)
    return minus_equal(BigUint{longer.chunks[1:]}, BigUint{shorter.chunks[1:]}, a < b)
}

add_uint :: proc(a: BigUint, b: BigUint) -> BigUint {
    result := get_longer_and_shorter(a, b)
    out := slice.clone_to_dynamic(result.longer.chunks)
    overflowed := plus_equal(BigUint{out[:]}, result.shorter, false)
    if overflowed {
        for i in len(result.shorter.chunks) ..< len(result.longer.chunks) {
            old := out[i]
            out[i] += 1
            if old < out[i] {
                return BigUint{out[:]}
            }
        }
        append_elem(&out, 1)
    }
    return BigUint{out[:]}
}

sub_uint :: proc(bigger: BigUint, smaller: BigUint) -> BigUint {
    out := make([dynamic]u64, len(bigger.chunks))
    copy_slice(out[:], bigger.chunks)
    negative := minus_equal(BigUint{out[:]}, smaller, false)
    if negative {
        for i in len(smaller.chunks) ..< len(bigger.chunks) {
            old := out[i]
            out[i] -= 1
            if old > out[i] {
                return BigUint{out[:]}
            }
        }
        panic("smaller > bigger")
    }
    return BigUint{out[:]}
}

CompareResult :: enum {
    FirstIsBigger,
    SecondIsBigger,
    Equal,
}

compare_uint :: proc(a: BigUint, b: BigUint) -> CompareResult {
    a_len := len(a.chunks)
    for a_len > len(b.chunks) {
        a_len -= 1
        if a.chunks[a_len] > 0 {
            return .FirstIsBigger
        }
    }
    b_len := len(b.chunks)
    for b_len > len(a.chunks) {
        b_len -= 1
        if b.chunks[b_len] > 0 {
            return .SecondIsBigger
        }
    }
    assert(a_len == b_len)
    pos := a_len - 1
    for pos >= 0 {
        if a.chunks[pos] > b.chunks[pos] {
            return .FirstIsBigger
        } else if a.chunks[pos] < b.chunks[pos] {
            return .SecondIsBigger
        }
        pos -= 1
    }
    return .Equal
}

add_int :: proc(a: BigInt, b: BigInt) -> BigInt {
    if a.is_negated == false && b.is_negated == false {
        return BigInt{false, add_uint(a.absolute_value, b.absolute_value)}
    } else if a.is_negated == true && b.is_negated == true {
        return BigInt{true, add_uint(a.absolute_value, b.absolute_value)}
    } else {
        result := compare_uint(a.absolute_value, b.absolute_value)
        switch result {
        case .Equal:
            return BigInt{false, BigUint{nil}}
        case .FirstIsBigger:
            return BigInt{a.is_negated, sub_uint(a.absolute_value, b.absolute_value)}
        case .SecondIsBigger:
            return BigInt{b.is_negated, sub_uint(b.absolute_value, a.absolute_value)}
        case:
            panic("unreachable")
        }
    }
}

negate :: proc(value: BigInt) -> BigInt {
    return BigInt{!value.is_negated, value.absolute_value}
}

sub_int :: proc(a: BigInt, b: BigInt) -> BigInt {
    return add_int(a, negate(b))
}

// TODO: Implement faster multiplication algorithm (karatsuba?)
mul_uint :: proc(a: BigUint, b: BigUint) -> BigUint {
    if len(a.chunks) == 0 || len(b.chunks) == 0 {
        return uint_zero
    }
    result := BigUint{make([]u64, len(a.chunks) + len(b.chunks) + 1)}
    for i := 0; i < len(a.chunks); i += 1 {
        carry: u128 = 0
        for j := 0; j < len(b.chunks); j += 1 {
            k := i + j
            prod := (u128(a.chunks[i]) * u128(b.chunks[j])) + u128(result.chunks[k]) + carry
            result.chunks[k] = u64(prod)
            carry = prod >> 64
        }
        result.chunks[i + len(b.chunks)] += u64(carry)
    }
    return result
}

mul_int :: proc(a: BigInt, b: BigInt) -> BigInt {
    if a.is_negated == b.is_negated {
        return BigInt{false, mul_uint(a.absolute_value, b.absolute_value)}
    } else {
        return BigInt{true, mul_uint(a.absolute_value, b.absolute_value)}
    }
}

// Returns the remainder
div_equal :: proc(a: BigUint, d: u64) -> u64 {
    if d == 0 {panic("division by zero")}
    rem: u128 = 0
    for i := len(a.chunks) - 1; i >= 0; i -= 1 {
        rem = (rem << 64) | u128(a.chunks[i])
        a.chunks[i] = u64(rem / u128(d))
        rem %= u128(d)
    }
    return u64(rem)
}

big_uint_from_string :: proc(s: string) -> BigUint {
    temp := BigUint{make([]u64, 1)}
    temp.chunks[0] = 10
    result := BigUint{make([]u64, 1)}
    for char in s {
        if char < '0' || char > '9' {
            panic("malformed input")
        }
        temp.chunks[0] = 10
        result = mul_uint(result, temp)
        temp.chunks[0] = u64(char - '0')
        result = add_uint(result, temp)
    }
    return result
}

big_uint_to_string :: proc(n: BigUint) -> string {
    if is_zero(n) {
        return "0"
    }

    temp := BigUint{make([]u64, len(n.chunks))}
    copy_slice(temp.chunks, n.chunks)

    out := make([]byte, 128)
    i := len(out)

    for {
        rem := div_equal(temp, 10)
        i -= 1
        if i < 0 {
            out_old := out
            out = make([]byte, len(out_old) * 2)
            i = len(out) - len(out_old)
            copy_slice(out[i:], out_old)
            delete(out_old)
            i -= 1
        }
        out[i] = byte('0' + rem)
        if is_zero(temp) {
            return string(out[i:])
        }
    }
}

is_zero :: proc(num: BigUint) -> bool {
    for chunk in num.chunks {
        if chunk != 0 {
            return false
        }
    }
    return true
}

big_uint_to_u64 :: proc(num: BigUint) -> (u64, bool) {
    if len(num.chunks) == 0 {
        return 0, true
    }
    for chunk in num.chunks[1:] {
        if chunk != 0 {
            return 0, true
        }
    }
    return num.chunks[0], true
}

big_uint_to_u32 :: proc(num: BigUint) -> (u32, bool) {
    as_u64, ok := big_uint_to_u64(num)
    if !ok {
        return 0, false
    }
    if as_u64 > u64(max(u32)) {
        return 0, false
    }
    return u32(as_u64), true
}

big_int_to_u32 :: proc(num: BigInt) -> (u32, bool) {
    if num.is_negated {
        return 0, false
    }
    return big_uint_to_u32(num.absolute_value)
}

