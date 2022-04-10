
import collections
import enum


# Read raw data
times = []
analogue = []
for line in open("signal4.csv", "rt"):
    fields = line.rstrip().split(",")
    try:
        t = float(fields[0])
        v = float(fields[1])
    except Exception:
        continue

    times.append(t)
    analogue.append(v)

osc_period = 1e-6 * ((times[-1] - times[0]) / (len(times) - 1))
osc_freq = 1.0 / osc_period
print("Oscilloscope clock period {:1.3f} microseconds".format(osc_period * 1e6))
print("Oscilloscope clock frequency {:1.3f} MHz".format(osc_freq / 1e6))

# Digitise
average = sum(analogue) / len(analogue)
threshold1 = average * 1.1
threshold0 = average / 1.1

digital = []
state = False
for i in range(len(analogue)):
    if analogue[i] > threshold1:
        state = True
    elif analogue[i] < threshold0:
        state = False

    digital.append(state)

# Get S/PDIF clock pulse width
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

#for (hold_time, count) in sorted(hold_time_histogram.items()):
#    if hold_time > 0:
#        print("hold_time width {} has count {}".format(hold_time, count))

best_score = -1
best_hold_time = 1
for hold_time in range(1, max_hold_time):
    peak0 = (hold_time_histogram.get(hold_time - 1, 0)
            + hold_time_histogram.get(hold_time, 0))
    peak1 = (hold_time_histogram.get(hold_time * 2 , 0)
            + hold_time_histogram.get(hold_time * 2 + 1, 0))

    score = peak0 + peak1
    #print("hold time {} has score {}".format(hold_time, score))
    if score > best_score:
        best_score = score
        best_hold_time = hold_time

# What's the S/PDIF bit rate? (Time to send a single bit)
spdif_period = best_hold_time * osc_period * 2
spdif_freq = 1.0 / spdif_period
print("S/PDIF clock frequency {:1.3f} MHz".format(spdif_freq / 1e6))

# Thresholds for longer pulses
width1 = ((best_hold_time * 2) - 1)
width2 = ((best_hold_time * 3) - 1)
print("width0", best_hold_time)
print("width1", width1)
print("width2", width2)

class SyncState(enum.Enum):
    NONE = enum.auto()
    START = enum.auto()
    B_HEADER = enum.auto()
    M_HEADER = enum.auto()
    W_HEADER = enum.auto()
    B_FOOTER = enum.auto()
    M_FOOTER = enum.auto()
    W_FOOTER = enum.auto()
    DESYNC = enum.auto()

B_PACKET = [True, False, False, False]
M_PACKET = [False, False, True, False]
W_PACKET = [False, True, False, False]

# Get binary data
pulse = -len(digital)
packets = [[]]
skip = False
inhibit = False
sync_state = SyncState.DESYNC

for i in range(1, len(digital)):
    if digital[i] == digital[i - 1]:
        pulse += 1
    else:
        if sync_state == SyncState.NONE:
            if pulse >= width2:
                # Synchronisation mark
                sync_state = SyncState.START
            elif pulse >= width1:
                # Ordinary data (0)
                packets[-1].append(False)
                skip = False
            else:
                # Ordinary data (1)
                if not skip:
                    packets[-1].append(True)
                    skip = True
                else:
                    skip = False

        elif sync_state == SyncState.START:
            if pulse >= width2:
                sync_state = SyncState.M_HEADER # 111000 received, 10 remaining
            elif pulse >= width1:
                sync_state = SyncState.W_HEADER # 11100 received, 100 remaining
            else:
                sync_state = SyncState.B_HEADER # 1110 received, 1000 remaining

        elif sync_state == SyncState.M_HEADER:
            if pulse >= width1:
                sync_state = SyncState.DESYNC   # expected 10
            else:
                sync_state = SyncState.M_FOOTER # 0 remaining

        elif sync_state == SyncState.W_HEADER:
            if pulse >= width1:
                sync_state = SyncState.DESYNC   # expected 100
            else:
                sync_state = SyncState.W_FOOTER # 00 remaining
            
        elif sync_state == SyncState.B_HEADER:
            if pulse >= width1:
                sync_state = SyncState.DESYNC   # expected 1000
            else:
                sync_state = SyncState.B_FOOTER # 000 remaining

        elif sync_state == SyncState.M_FOOTER:
            if pulse >= width1:
                sync_state = SyncState.DESYNC   # expected 0
            else:
                sync_state = SyncState.NONE
                packets.append(M_PACKET[:])

        elif sync_state == SyncState.W_FOOTER:
            if (pulse < width1) or (pulse >= width2):
                sync_state = SyncState.DESYNC   # expected 00
            else:
                sync_state = SyncState.NONE
                packets.append(W_PACKET[:])
            
        elif sync_state == SyncState.B_FOOTER:
            if pulse < width2:
                sync_state = SyncState.DESYNC   # expected 000
            else:
                sync_state = SyncState.NONE
                packets.append(B_PACKET[:])

        elif sync_state == SyncState.DESYNC:
            if pulse >= width2:
                # Synchronisation mark
                sync_state = SyncState.START
                print("resync at", times[i])

        pulse = 1

print("Packets", len(packets))

channel = 0

with open("packet.txt", "wt") as fd:
    j = 0
    for packet in packets:
        audio = 0
        if len(packet) < 32:
            fd.write("malformed\n")
            continue

        if packet[:4] == B_PACKET:
            fd.write("B ")
            channel = 0
        elif packet[:4] == M_PACKET:
            fd.write("M ")
            channel = 0
        elif packet[:4] == W_PACKET:
            fd.write("W ")
            channel += 1
        else:
            fd.write("? ")

        fd.write("ch{} ".format(channel))

        # Audio data here (24 bits)
        for data in reversed(packet[4:28]):
            audio = audio << 1
            if data:
                audio |= 1

        fd.write("{:06x} ".format(audio))

        # Validity
        if packet[28]:
            fd.write("?")
        else:
            fd.write(" ")

        # Subcode packet
        if packet[29]:
            fd.write("S")
        else:
            fd.write(" ")

        # Status
        if packet[30]:
            fd.write("C")
        else:
            fd.write(" ")

        # Parity
        count = 0
        for p in packet[4:32]:
            if p:
                count += 1

        if (count % 2) == 0:
            fd.write(" OK\n")
        else:
            fd.write(" ERR\n")



