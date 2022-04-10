
import collections

# Read raw data
times = []
analogue = []
for line in open("c:/temp/20220409-0002.csv", "rt"):
    fields = line.rstrip().split(",")
    try:
        t = float(fields[0])
        v = float(fields[1])
    except Exception:
        continue

    times.append(t)
    analogue.append(v)

period = 1e-6 * ((times[-1] - times[0]) / (len(times) - 1))
freq = 1.0 / period
print("period", period, "seconds")
print("frequency", freq, "Hz")

# Digitise
average = (sum(analogue) / len(analogue)) 
threshold1 = average * 1.1
threshold0 = average / 1.1
print("average", average)

digital = []
for i in range(len(analogue)):
    if analogue[i] > threshold1:
        state = True
    elif analogue[i] < threshold0:
        state = False

    digital.append(state)

# Get pulse width
pulse = 1
pulse_histogram = collections.defaultdict(lambda: 0)
for i in range(1, len(digital)):
    if digital[i] == digital[i - 1]:
        pulse += 1
    else:
        pulse_histogram[pulse] += 1
        pulse = 1

for (pulse, count) in sorted(pulse_histogram.items()):
    print("pulse width {} has count {}".format(pulse, count))

width = 8


# Detect the beginning of a packet
# Held high for a threshold time, then low for another threshold time
up = down = 0
up_max = down_max = 0

for i in range(len(digital)):
    if digital[i]:
        up += 1
        up_max = max(up, up_max)
        down = 0
    else:
        down += 1
        down_max = max(down, down_max)
        up = 0

print(up_max, down_max)
up_threshold = int(up_max / 1.1)

start = 0
down = up = 0
packet_start = []
for i in range(len(digital)):
    if digital[i]:
        up += 1
        down = 0
        trigger = (up >= up_threshold)
    elif trigger:
        up = 0
        down += 1
        if down == up_threshold:
            packet_start.append(start)
    else:
        up = down = 0
        start = i + 1

# Packets to files
with open("c:/temp/packet.txt", "wt") as fd:
    #   0...1...2...3...4...5...6...7...8...9...a...b...c...d...e...f
    #   0..1..2..3..4..5..6..7..8..9..a..b..c..d..e..f
    #   0.1.2.3.4.5.6.7.8.9.a.b.c.d.e.f.g.h.i.j.
    for i in range(len(packet_start) - 1):
        start = packet_start[i]
        finish = packet_start[i + 1]
        for j in range(start + (width // 2), finish, width):
            total = 0
            for k in range(-2, 2, 1):
                if digital[j + k]:
                    total += 1
            if total >= 2:
                fd.write("1")
            else:
                fd.write(" ")
        fd.write("\n")



