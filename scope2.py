
import collections

# Read raw data
times = []
analogue = []
for line in open("left24khz.csv", "rt"):
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
threshold1 = 20
threshold0 = 10

digital = []
state = False
for i in range(len(analogue)):
    if analogue[i] > threshold1:
        state = True
    elif analogue[i] < threshold0:
        state = False

    digital.append(state)

# Get pulse width
hold_time = -len(digital)
hold_time_histogram = collections.defaultdict(lambda: 0)
max_hold_time = 0
for i in range(1, len(digital)):
    if digital[i] == digital[i - 1]:
        hold_time += 1
    else:
        hold_time_histogram[hold_time] += 1
        max_hold_time = max(hold_time, max_hold_time)
        hold_time = 1

for (hold_time, count) in sorted(hold_time_histogram.items()):
    if hold_time > 0:
        print("hold_time width {} has count {}".format(hold_time, count))

best_score = -1
best_hold_time = 1
for hold_time in range(1, max_hold_time):
    peak0 = (hold_time_histogram.get(hold_time - 1, 0)
            + hold_time_histogram.get(hold_time, 0))
    peak1 = (hold_time_histogram.get(hold_time * 2 , 0)
            + hold_time_histogram.get(hold_time * 2 + 1, 0))

    score = peak0 + peak1
    print("hold time {} has score {}".format(hold_time, score))
    if score > best_score:
        best_score = score
        best_hold_time = hold_time

width1 = ((best_hold_time * 2) - 1)
width2 = ((best_hold_time * 3) - 1)
print("width1", width1)
print("width2", width2)

# Get binary data
pulse = -len(digital)
packets = [[]]
skip = False
for i in range(1, len(digital)):
    if digital[i] == digital[i - 1]:
        pulse += 1
    else:
        if pulse >= width2:
            packets.append([])
            skip = False
        elif pulse >= width1:
            packets[-1].append(False)
            skip = False
        else:
            if not skip:
                packets[-1].append(True)
                skip = True
            else:
                skip = False
        pulse = 1


with open("packet.txt", "wt") as fd:
    j = 0
    for packet in packets:
        fd.write("({:1.3f} -> {:-3d}) ".format(j * period * 1e6, len(packet)))
        audio = 0
        if len(packet) > 28:
            for data in packet[0:24]:
                audio = audio << 1
                if data:
                    audio |= 1

        fd.write("{:06x} ".format(audio))
        for data in packet:
            j += 1
            if data:
                fd.write("1")
            else:
                fd.write("0")
        fd.write("\n")


