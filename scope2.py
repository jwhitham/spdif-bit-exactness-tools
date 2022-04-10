
import collections

# Read raw data
times = []
analogue = []
for line in open("signal.csv", "rt"):
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
state = False
for i in range(len(analogue)):
    if analogue[i] > threshold1:
        state = True
    elif analogue[i] < threshold0:
        state = False

    digital.append(state)

# Get pulse width
pulse = -len(digital)
pulse_histogram = collections.defaultdict(lambda: 0)
for i in range(1, len(digital)):
    if digital[i] == digital[i - 1]:
        pulse += 1
    else:
        pulse_histogram[pulse] += 1
        pulse = 1

width = 0
for (pulse, count) in sorted(pulse_histogram.items()):
    if pulse > 0:
        print("pulse width {} has count {}".format(pulse, count))
        if width == 0:
            width = pulse

print("base", width)
width1 = ((width * 2) - 1)
width2 = ((width * 3) - 1)
print("width1", width1)
print("width2", width2)

# Get binary data
pulse = -len(digital)
packets = [[]]
for i in range(1, len(digital)):
    if digital[i] == digital[i - 1]:
        pulse += 1
    else:
        if pulse >= width2:
            packets.append([])
        elif pulse >= width1:
            packets[-1].append(False)
        else:
            packets[-1].append(True)
        pulse = 1


with open("packet.txt", "wt") as fd:
    for packet in packets:
        for data in packet:
            if data:
                fd.write("1")
            else:
                fd.write("0")
        fd.write("\n")


