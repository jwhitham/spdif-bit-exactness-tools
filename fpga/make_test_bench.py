
def main(csv_file_name: str, testbench_name: str,
                testbench_file_name: str) -> None:
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

    # times offset to zero
    offset = min(times)
    for i in range(len(times)):
        times[i] -= offset

    # generate test bench
    with open(testbench_file_name, "wt") as fd:
        fd.write(f"""
library ieee;
use ieee.std_logic_1164.all;

entity {testbench_name} is
    port (
        clock       : out std_logic;
        done        : out std_logic;
        data        : out std_logic
    );
end {testbench_name};

architecture structural of {testbench_name} is
begin
    process
    begin
""")
        fd.write("data <= '{:d}';\n".format(digital[0]))
        fd.write("done <= '0';\n")
        for i in range(1, len(times)):
            td = max(1, 1e9 * time_scale * (times[i] - times[i - 1]))
            fd.write("clock <= '1';\n")
            fd.write("wait for {:1.0f} ns;\n".format(td / 2))
            fd.write("clock <= '0';\n")
            fd.write("wait for {:1.0f} ns;\n".format(td / 2))
            fd.write("data <= '{:d}';\n".format(digital[i]))

        fd.write("""
        done <= '1';
        wait;
    end process;
end structural;
""")

if __name__ == "__main__":
    main("../examples/test_44100.csv", "test_signal_generator", "test_signal_generator.vhdl")

