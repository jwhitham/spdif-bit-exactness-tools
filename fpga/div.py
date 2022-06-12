
import sys
import math

# The divider will round towards 0 (unlike Python's // operator which rounds towards -inf)
# Unsigned division is easier

def div(top_value, bottom_value, width):
    assert bottom_value != 0
    assert abs(top_value) < (1 << width)
    assert abs(bottom_value) < (1 << width)
    inv = False
    if bottom_value < 0 and top_value < 0:
        bottom_value = -bottom_value
        top_value = -top_value
    elif bottom_value < 0:
        bottom_value = -bottom_value
        inv = True
    elif top_value < 0:
        top_value = -top_value
        inv = True

    bottom_value = bottom_value << (width - 1)
    out = 0
    for i in range(width):
        out = out << 1
        if top_value >= bottom_value:
            out |= 1
            top_value -= bottom_value
        bottom_value = bottom_value >> 1
 
    if inv:
        out = -out
    return out

print("test")
bits = 7
test_size = (1 << bits) - 1
for x in range(-test_size, test_size + 1):
    for y in range(-test_size, test_size + 1):
        if y != 0:
            z = div(x, y, bits)
            ex = x / y
            if ex > 0:
                ex = math.floor(ex)
            else:
                ex = math.ceil(ex)
            if z != ex:
                print("divide {} by {}: got {} expected {}".format(x, y, z, ex))
                sys.exit(1)

print("ok")


