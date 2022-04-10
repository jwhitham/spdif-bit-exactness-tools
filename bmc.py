

import collections

data = "10011010010"
bmc = "1011001010110100110100"
bmc = ''.join([bmc[min(int(i / 3), len(bmc) - 1)] for i in range(len(bmc) * 4)])


def bmc_encoder(data, hold_time):
    data2 = ""
    current = True
    for i in range(len(data)):
        for j in range(hold_time):
            data2 += ("1" if current else "0")
        if data[i] == "1":
            current = not current
        for j in range(hold_time):
            data2 += ("1" if current else "0")
        current = not current

    return data2

def bmc_decoder(bmc):

    # Get short pulse length
    hold_time = -len(bmc)
    hold_time_histogram = collections.defaultdict(lambda: 0)
    max_hold_time = 0
    for i in range(1, len(bmc)):
        if bmc[i] == bmc[i - 1]:
            hold_time += 1
        else:
            hold_time_histogram[hold_time] += 1
            max_hold_time = max(hold_time, max_hold_time)
            hold_time = 1

    for (hold_time, count) in sorted(hold_time_histogram.items()):
        if hold_time > 0:
            print("hold time {} has count {}".format(hold_time, count))

    # What's the pulse length
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

    threshold_time = ((best_hold_time * 2) - 1)
    print("best hold time", best_hold_time, threshold_time)

    hold_time = 0
    data2 = ""
    skip = False
    for i in range(1, len(bmc)):
        if bmc[i - 1] == bmc[i]:
            hold_time += 1
        else:
            if hold_time <= threshold_time:
                if not skip:
                    data2 += "1"
                    skip = True
                else:
                    skip = False
            else:
                data2 += "0"
                skip = False
            hold_time = 1

    return data2

print(bmc_encoder(data, 3))
print(bmc)
print(bmc_decoder(bmc))
print(data)
