
import collections
import enum
import typing


RawDigitalSignal = typing.List[bool]
RawSPDIFPackets = typing.List[typing.List[bool]] 
RawSubcodeData = typing.List[bool]

class Sample:
    left = 0
    right = 0

AudioData = typing.List[Sample]

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

def main(csv_file_name: str) -> None:
    # Read raw data
    times = []
    analogue = []
    time_scale = 1e-6
    for line in open(csv_file_name, "rt"):
        fields = line.rstrip().split(",")
        try:
            t = float(fields[0])
            v = float(fields[1])
        except Exception:
            if line.startswith("(ms)"):
                time_scale = 1e-3
            elif line.startswith("(us)"):
                time_scale = 1e-6
            elif line.startswith("(ns)"):
                time_scale = 1e-9

            continue

        times.append(t)
        analogue.append(v)

    osc_period = time_scale * ((times[-1] - times[0]) / (len(times) - 1))
    osc_freq = 1.0 / osc_period
    print("Oscilloscope clock period {:1.3f} microseconds".format(osc_period * 1e6))
    print("Oscilloscope clock frequency {:1.3f} MHz".format(osc_freq / 1e6))
    print("Signal peak-to-peak: {:1.3f} to {:1.3f}".format(min(analogue), max(analogue)))

    # Digitise
    average = sum(analogue) / len(analogue)
    threshold1 = average * 1.1
    threshold0 = average / 1.1
    print("Signal midpoint: {:1.3f}".format(average))

    digital: RawDigitalSignal = []
    state = False
    for i in range(len(analogue)):
        if analogue[i] > threshold1:
            state = True
        elif analogue[i] < threshold0:
            state = False

        digital.append(state)

    # Get S/PDIF clock pulse width
    hold_time = -len(digital)
    hold_time_histogram: typing.Dict[int, int] = collections.defaultdict(lambda: 0)
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
        #print("hold time {} has score {}".format(hold_time, score))
        if score > best_score:
            best_score = score
            best_hold_time = hold_time

    # What's the S/PDIF bit rate? (Time to send a single bit)
    spdif_period = best_hold_time * osc_period * 2
    spdif_freq = 1.0 / spdif_period
    print("S/PDIF clock frequency {:1.3f} MHz".format(spdif_freq / 1e6))

    # Thresholds for longer pulses
    width1 = ((best_hold_time * 2) - 0)
    width2 = ((best_hold_time * 3) - 0)
    print("width0", best_hold_time)
    print("width1", width1)
    print("width2", width2)

    # Get binary data
    pulse = -len(digital)
    packets: RawSPDIFPackets = [[]]
    skip = False
    inhibit = False
    sync_state = SyncState.DESYNC

    for i in range(1, len(digital)):
        if digital[i] == digital[i - 1]:
            pulse += 1
        else:
            if pulse >= width2:
                print("triple")
            elif pulse >= width1:
                print("double")
            else:
                print("single")
            pulse = 0

if __name__ == "__main__":
    main("../examples/test_44100.csv")
