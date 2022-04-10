
data = open("test.bin", "rb").read()

while (len(data) % 3) != 0:
    data += b"\x00"

codes = []
for i in range(0, len(data), 3):
    x = 0
    x |= (data[i + 0]) << 16 
    x |= (data[i + 1]) << 8
    x |= (data[i + 2]) << 0
    codes.append(x)

expected = -1

for line in open("packet.txt"):
    fields = line.split()
    if len(fields) < 4:
        continue

    code = int(fields[2], 16)
    try:
        i = codes.index(code)
    except Exception:
        i = -1

    if expected >= 0:
        if (i != expected) and (code != 0):
            print("error {:06x} {} {}".format(code, i, expected))

    expected = (i + 1) % len(codes)

print("OK")
