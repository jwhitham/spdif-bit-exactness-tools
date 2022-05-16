
import sys
import typing
from picoscope_decode import picoscope_decode
from spdif_decode import biphase_mark_decode, spdif_decode, AudioData


PAYLOAD = [
    0xc6, 0x4e, 0x65, 0x5e, 0x25, 0x76, 0x7d, 0x56, 0xf6, 0x69, 0x51, 0xf3,
    0xb6, 0x18, 0x1d, 0x76, 0x4d, 0xc1, 0xdb, 0x5e, 0x40, 0xd9, 0x9e, 0x0d,
    0x50, 0x8a, 0x48, 0xdd, 0xe3, 0xb3, 0x0d, 0x0c, 0x8f, 0xaf, 0xaf, 0xe6,
    0x5e, 0x41, 0x95, 0xb3, 0x66, 0x70, 0x01, 0x40, 0x81, 0x7f, 0x24, 0xda,
    0xf1, 0xeb, 0xf8, 0xc9, 0x5a, 0x20, 0xc9, 0x75, 0xc3, 0xea, 0xd0, 0x96,
    0x1c, 0x8d, 0xe3, 0xb3, 0x8f, 0xb4, 0x08, 0xcf, 0xb5, 0x55, 0xea, 0x6d,
    0x66, 0x3e, 0x48, 0x74, 0xec, 0x54, 0x5b, 0x0f, 0xf4, 0x01, 0x20, 0x3c,
    0x18, 0x52, 0x8c, 0xda, 0x9a, 0x00, 0x9a, 0xa2, 0x38, 0xbb, 0x69, 0x74,
    0xae, 0x80, 0x6a, 0xc5, 0x59, 0x62, 0xd1, 0x80, 0xc9, 0x1e, 0xd2, 0x5d,
    0x69, 0x35, 0x06, 0x4e, 0xae, 0x62, 0xb1, 0xab, 0x35, 0x35, 0xcc, 0x54,
    0x35, 0xb9, 0xff, 0x91, 0xa5, 0x58, 0x62, 0xf8
]

TRUE_MARKER_POSITION = 24
MARKER_VALUE = 0x654321
MARKER_MASK = 0xfff000
REPEAT_SIZE = 40
MASK_16 = 0xffff00

def int_conv(unsigned_data: int, bits: int) -> int:
    assert 0 <= unsigned_data < (1 << bits)
    if unsigned_data & ((1 << bits) >> 1):
        return unsigned_data - (1 << bits)
    else:
        return unsigned_data

def examine_walking_1s(samples: AudioData, bits: int) -> typing.Tuple[bool, int]:
    assert bits in (16, 24)
    shift = 24 - bits
    incorrect = -1
    small_error = False
    for i in range(24):
        left = 1 << i
        right = left ^ 0xffffff
        left_delta = abs(int_conv(left >> shift, bits) - int_conv(samples[i].left >> shift, bits))
        right_delta = abs(int_conv(right >> shift, bits) - int_conv(samples[i].right >> shift, bits))

        if (left_delta > 1) or (right_delta > 1):
            # Too much error
            print("at {} ({}-bit): expect {:06x} {:06x}  got {:06x} {:06x}".format(
                    i, bits, left, right, samples[i].left, samples[i].right))
            incorrect = i

        elif (left_delta == 1) or (right_delta == 1):
            # This small error could be due to rounding
            small_error = True

    return (small_error, incorrect)

def examine_audio_data(audio: AudioData) -> bool:
    # Find the marker
    marker_position = -1
    for i in range(len(audio)):
        if (audio[i].right & MARKER_MASK) == (MARKER_VALUE & MARKER_MASK):
            marker_position = i
            break

    if marker_position < 0:
        print("Unable to find the {:06x} marker within the audio data".format(
                MARKER_VALUE))

        for i in range(len(audio)):
            left = audio[i].left >> 8
            right = audio[i].right >> 8
            if ((left >= 300) and (left <= 960) # possible sample rate
                    and (right <= 0x6543) and (right >= 0x63b0)):
                scale = right / 0x6543
                print("Possible marker at position {} with volume level "
                        "reduced to {:1.3f}: sample rate {:1.0f} Hz ?".format(
                    i, scale, (left / scale) * 100))

        return False

    # Rearrange data
    samples: AudioData = []
    for i in range(REPEAT_SIZE):
        j = i + marker_position - TRUE_MARKER_POSITION
        if j < 0:
            j += REPEAT_SIZE
        if j >= len(audio):
            j -= REPEAT_SIZE
        assert 0 <= j < len(audio)

        samples.append(audio[j])

    assert (samples[TRUE_MARKER_POSITION].right & MARKER_MASK) == (MARKER_VALUE & MARKER_MASK)
    print("Sample rate of test data: {} Hz".format((samples[TRUE_MARKER_POSITION].left >> 8) * 100))

    # Check walking 1s (16 bit mode)
    (small_error, incorrect) = examine_walking_1s(samples, 16)

    if (incorrect < 0) and not small_error:
        print("Walking ones are perfectly correct for 16-bit")

        (small_error, incorrect) = examine_walking_1s(samples, 24)
        if (incorrect < 0) and not small_error:
            print("Walking ones are perfectly correct for 24-bit")
        elif incorrect < 0:
            print("Small error detected for 24-bit: not bit-exact")
        else:
            print("{} walking 1s are correct ({} exact bits)".format(23 - incorrect, 23 - incorrect))

    elif incorrect < 0:
        print("Walking ones are correct for 16-bit with at most +/- 1 bit error")

    else:
        print("{} walking 1s are correct ({} exact bits)".format(23 - incorrect, 23 - incorrect))

    # Check third part of the repeating block: 16 bit data (7 samples)
    j = 0
    for i in range(25, 32):
        left =  (PAYLOAD[j + 0] << 16) | (PAYLOAD[j + 1] << 8)
        right = (PAYLOAD[j + 2] << 16) | (PAYLOAD[j + 3] << 8)
        if (((samples[i].left & MASK_16) != left) or ((samples[i].right & MASK_16) != right)):
            print("at {} (16-bit): expect {:06x} {:06x}  got {:06x} {:06x}".format(
                    i, left, right, samples[i].left, samples[i].right))
            print("Error in 16-bit payload part, position {}: signal is not 16-bit clean".format(i))
            return False
        j += 4

    print("Correct 16-bit payload part: signal is 16-bit clean")

    # Final part of the repeating block: 24 bit data (8 samples)
    for i in range(32, REPEAT_SIZE):
        left =  (PAYLOAD[j + 0] << 16) | (PAYLOAD[j + 1] << 8) | (PAYLOAD[j + 2] << 0)
        right = (PAYLOAD[j + 3] << 16) | (PAYLOAD[j + 4] << 8) | (PAYLOAD[j + 5] << 0)
        if ((samples[i].left != left) or (samples[i].right != right)):
            print("at {} (24-bit): expect {:06x} {:06x}  got {:06x} {:06x}".format(
                    i, left, right, samples[i].left, samples[i].right))
            print("Error in 24-bit payload part, position {}: signal is not 24-bit clean".format(i))
            return False
        j += 6

    if incorrect < 0:
        print("Correct 24-bit payload part: signal is 24-bit clean")
    else:
        print("Correct 24-bit payload part but error in walking ones: signal is not 24-bit clean")

    return True

def main() -> None:
    if len(sys.argv) != 2:
        print("Usage: sigtest.py <input.csv>")
        sys.exit(1)

    (digital, osc_period) = picoscope_decode(sys.argv[1])
    packets = biphase_mark_decode(digital, osc_period)
    (audio, subcode_data) = spdif_decode(packets)


    print("Audio data received:")
    for sample in audio:
        print("{:06x} {:06x}".format(sample.left, sample.right))

    if len(audio) <= REPEAT_SIZE:
        print("Insufficient samples captured (need more than {})".format(REPEAT_SIZE))
        sys.exit(1)

    # remove final sample (may be incomplete)
    audio.pop()

    # analyse
    if not examine_audio_data(audio):
        sys.exit(1)


if __name__ == "__main__":
    main()
