
import typing

def read_csv_file(csv_file_name: str,
                digital: typing.List[bool],
                times: typing.List[float]) -> None:

    # Read raw data
    analogue = []
    time_scale = 1e-6
    td = t = t0 = 0.0
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

        td = max(1.0, (t - t0) * time_scale * 1e9)
        times.append(td)
        analogue.append(v)
        t0 = t


    # Digitise
    average = sum(analogue) / len(analogue)
    threshold1 = average * 1.1
    threshold0 = average / 1.1
    state = False
    for i in range(len(analogue)):
        if analogue[i] > threshold1:
            state = True
        elif analogue[i] < threshold0:
            state = False

        digital.append(state)

def main() -> None:
    # read input files
    times = []
    digital = []
    read_csv_file("20220502-32k.csv", digital, times)
    read_csv_file("20220502-44k.csv", digital, times)
    read_csv_file("20220502-48k.csv", digital, times)
    read_csv_file("../examples/test_48000.csv", digital, times)
    read_csv_file("../examples/test_44100.csv", digital, times)

    # generate test bench
    with open("test_signal_generator.vhdl", "wt") as fd:
        fd.write(f"""
library ieee;
use ieee.std_logic_1164.all;

entity test_signal_generator is
    port (
        done_out        : out std_logic;
        clock_out       : out std_logic;
        raw_data_out    : out std_logic
    );
end test_signal_generator;

architecture structural of test_signal_generator is
    signal done     : std_logic := '0';
    signal raw_data : std_logic := '0';
    signal clock    : std_logic := '0';
begin
    done_out <= done;
    raw_data_out <= raw_data;
    clock_out <= clock;

    process
    begin
        raw_data <= '0';
        done <= '0';
        clock <= '0';
""")
        for (data, td) in zip(digital, times):
            fd.write("wait for {:1.0f} ns; ".format(td / 2))
            fd.write("clock <= '0'; ")
            fd.write("raw_data <= '{:d}'; ".format(data))
            fd.write("wait for {:1.0f} ns; ".format(td / 2))
            fd.write("clock <= '1'; \n")

        fd.write("""
        wait for 1 us;
        clock <= '0';
        raw_data <= '1';
        wait for 1 us;
        clock <= '1';
        raw_data <= '0';
        wait for 1 us;
        done <= '1';
        wait;
    end process;
end structural;
""")

if __name__ == "__main__":
    main()

