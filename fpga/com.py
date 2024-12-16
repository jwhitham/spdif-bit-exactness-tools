
import sys, subprocess, argparse
from pathlib import Path

SET_MODE = 1 << 14
SET_ADJUST_1 = 2 << 14
SET_ADJUST_2 = 3 << 14
COMFILTER_GENERATE_DIR = Path("j:/comfilter/generated")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--adjust-1", type=float)
    parser.add_argument("--adjust-2", type=float)
    parser.add_argument("--compress-max", action="store_true")
    parser.add_argument("--compress-2", action="store_true")
    parser.add_argument("--compress-1", action="store_true")
    parser.add_argument("--attenuate-2", action="store_true")
    parser.add_argument("--compress-video", action="store_true")
    parser.add_argument("--passthrough", action="store_true")
    parser.add_argument("--dbg-spdif", action="store_true")
    parser.add_argument("--dbg-subcodes", action="store_true")
    parser.add_argument("--dbg-compress", action="store_true")
    parser.add_argument("--dbg-adcs", action="store_true")
    parser.add_argument("--dbg-version", action="store_true")
    parser.add_argument("--reset-error", action="store_true")
    parser.add_argument("--pre-emphasis", type=bool)

    args = parser.parse_args()
    codes = []

    def set_adjust(command, value):
        if value is not None:
            top_of_range = (1 << 10) - 1
            codes.append(command | min(max(0, int(value * top_of_range)), top_of_range))

    set_adjust(SET_ADJUST_1, args.adjust_1)
    set_adjust(SET_ADJUST_2, args.adjust_2)

    def set_mode(number, flag):
        if flag:
            codes.append(SET_MODE | (number << 3) | (1 << 2))

    set_mode(0, args.compress_max)
    set_mode(1, args.compress_2)
    set_mode(2, args.compress_1)
    set_mode(3, args.attenuate_2)
    set_mode(4, args.compress_video)
    set_mode(5, args.passthrough)
    set_mode(6, args.dbg_spdif)
    set_mode(7, args.dbg_subcodes)
    set_mode(8, args.dbg_compress)
    set_mode(9, args.dbg_adcs)
    set_mode(10, args.dbg_version)

    if args.pre_emphasis is not None:
        codes.append(SET_MODE | (number << 3) | (1 << 2))

    if args.reset_error is not None:
        codes.append(SET_MODE | 1)

    sys.exit(subprocess.call([str(COMFILTER_GENERATE_DIR / "packetgen.exe"), "wav",
                    str(COMFILTER_GENERATE_DIR / "packet.wav")] +
                    [str(c) for c in codes]))

if __name__ == "__main__":
    main()
