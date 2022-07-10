
import sys
import math


def serial_0_sub(bottom_value, width):
    out = 0
    carry = 1
    check = -bottom_value

    assert 0 <= bottom_value < (1 << width)
    bottom_value &= (1 << width) - 1
    check &= (1 << width) - 1

    for i in range(width):
        new_bit = (bottom_value & 1) ^ 1
        bottom_value = bottom_value >> 1
        new_bit += carry
        out = out >> 1
        out |= (new_bit & 1) << (width - 1)
        carry = (new_bit >> 1) & 1
    #out -= 1 << width
    bottom_value = out
    assert check == out, (check, out)
    return bottom_value

# The divider will round towards 0 (unlike Python's // operator which rounds towards -inf)
# Unsigned division is easier

def div(top_value, bottom_value, width):
    assert bottom_value != 0
    top_value = conv_from_2s_complement(top_value, width)
    bottom_value = conv_from_2s_complement(bottom_value, width)

    top_negative = (top_value < 0)
    bottom_negative = (bottom_value < 0)
    bottom_value = bottom_value << (width - 1)

    if bottom_negative != top_negative:
        bottom_value = -bottom_value
    out = 0
    for i in range(width):
        out = out << 1
        subtract = top_value - bottom_value

        if subtract == 0 or (top_negative == (subtract < 0)):
            out |= 1
            top_value = subtract

        if bottom_negative != top_negative:
            out ^= 1

        bottom_value = bottom_value >> 1
 
    if bottom_negative != top_negative:
        out += 1

    out &= (1 << width) - 1
    return out

def conv_to_2s_complement(value, bits):
    return ((1 << bits) - 1) & value

def conv_from_2s_complement(value, bits):
    assert 0 <= value < (1 << bits)
    if value & (1 << (bits - 1)):
        value -= 1 << bits
    return value

print("test")
bits = 7
low = -(1 << (bits - 1)) + 1
high = (1 << (bits - 1))
for x in range(low, high):
    y = serial_0_sub(conv_to_2s_complement(x, bits), bits)
    assert (conv_to_2s_complement(-x, bits)) == y, (x, y)
    assert (conv_from_2s_complement(y, bits)) == -x, (x, y)
    assert (conv_from_2s_complement(conv_to_2s_complement(x, bits), bits) == x)

for x in range(low, high):
    for y in range(low, high):
        if y != 0:
            z = conv_from_2s_complement(
                    div(conv_to_2s_complement(x, bits),
                        conv_to_2s_complement(y, bits), bits), bits)
            ex = x / y
            if ex > 0:
                ex = math.floor(ex)
            else:
                ex = math.ceil(ex)

            if z != ex:
                print("divide {} by {}: got {} expected {}".format(x, y, z, ex))
                sys.exit(1)
            #else:
            #    print("divide {} by {}: got {} ok".format(x, y, z))

print("ok")


