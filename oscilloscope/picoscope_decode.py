
import typing
from spdif_decode import RawDigitalSignal


def picoscope_decode(csv_file_name: str) -> typing.Tuple[RawDigitalSignal, float]:
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

    return (digital, osc_period)

