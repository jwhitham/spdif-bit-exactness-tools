
import socket, argparse, typing, struct
from pathlib import Path

# These should match the bit positions in the "com_rot" block
# in app/compressor_main.vhdl
SET_MODE = (1 << 14) | 4
SET_ADJUST_1 = 2 << 14
SET_ADJUST_2 = 3 << 14
RESET_ERROR = (1 << 14) | 1
RESET_MODE = (1 << 14) | 2
SET_PREEMPH = (1 << 14) | (1 << 7)
UDP_PORT = 1967
UDP_TARGET = ("255.255.255.255", UDP_PORT)

CodeList = typing.List[int]

def set_adjust(codes: CodeList, command: int, value: typing.Optional[float]) -> None :
    if value is not None:
        top_of_range = (1 << 10) - 1
        codes.append(command | min(max(0, int(value * top_of_range)), top_of_range))

def set_mode(codes: CodeList, number: int, flag: bool) -> None:
    if flag:
        codes.append(SET_MODE | (number << 3))

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--adjust-1", type=float,
        help="set volume for C1 mode (0.0 .. 1.0)")
    parser.add_argument("--adjust-2", type=float,
        help="set volume for C2, A2, CV modes (0.0 .. 1.0)")
    parser.add_argument("--compress-max", "-cx", action="store_true",
        help="compress max -> maximum volume")
    parser.add_argument("--compress-2", "-c2", action="store_true",
        help="compress 2 -> volume set by adjust 2")
    parser.add_argument("--compress-1", "-c1", action="store_true",
        help="compress 1 -> volume set by adjust 1")
    parser.add_argument("--attenuate-2", "-a2", action="store_true",
        help="no compression, volume set by adjust 2")
    parser.add_argument("--compress-video", "-cv", action="store_true",
        help="compress for video -> volume set by adjust 2")
    parser.add_argument("--passthrough", "-p", action="store_true",
        help="passthrough")
    parser.add_argument("--dbg-spdif", action="store_true")
    parser.add_argument("--dbg-subcodes", action="store_true")
    parser.add_argument("--dbg-compress", action="store_true")
    parser.add_argument("--dbg-adcs", action="store_true")
    parser.add_argument("--dbg-version", action="store_true")
    parser.add_argument("--reset-error", action="store_true")
    parser.add_argument("--reset-mode", "-R", action="store_true",
        help="reset to default (set on the rotary control)")
    parser.add_argument("--pre-emphasis", type=bool)

    args = parser.parse_args()
    codes: CodeList = []

    set_adjust(codes, SET_ADJUST_1, args.adjust_1)
    set_adjust(codes, SET_ADJUST_2, args.adjust_2)

    # These should match mode_definitiions.vhdl
    set_mode(codes, 0, args.compress_max)
    set_mode(codes, 1, args.compress_2)
    set_mode(codes, 2, args.compress_1)
    set_mode(codes, 3, args.attenuate_2)
    set_mode(codes, 4, args.compress_video)
    set_mode(codes, 5, args.passthrough)
    set_mode(codes, 6, args.dbg_spdif)
    set_mode(codes, 7, args.dbg_subcodes)
    set_mode(codes, 8, args.dbg_compress)
    set_mode(codes, 9, args.dbg_adcs)
    set_mode(codes, 10, args.dbg_version)

    if args.pre_emphasis is not None:
        if args.pre_emphasis:
            codes.append(SET_PREEMPH | (1 << 6))
        else:
            codes.append(SET_PREEMPH)

    if args.reset_error:
        codes.append(RESET_ERROR)

    if args.reset_mode:
        codes.append(RESET_MODE)

    if len(codes) == 0:
        print("Use --help for instructions")
        return

    data = b"COM\n" + struct.pack(">" + str(len(codes)) + "H", *codes)
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    s.sendto(data, UDP_TARGET)

if __name__ == "__main__":
    main()
