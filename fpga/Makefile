
RFLAGS = --assert-level=note

VHDL =  \
		lib/subtractor.vhdl \
		lib/divider.vhdl \
		lib/multiplier.vhdl \
		lib/fifo.vhdl \
		lib/led_scan.vhdl \
		lib/convert_from_sign_magnitude.vhdl \
		lib/convert_to_sign_magnitude.vhdl \
		lib/pulse_gen.vhdl \
		lib/uart.vhdl \
		lib/delay1.vhdl \
		lib/delay.vhdl \
		app/mode_definitions.vhdl \
		app/adc_driver.vhdl \
		app/rotary_switch.vhdl \
		app/compressor.vhdl \
		app/generated/version_rom.vhdl \
		app/generated/match_rom.vhdl \
		app/matcher.vhdl \
		app/vu_meter.vhdl \
		app/mode_display.vhdl \
		spdif/channel_decoder.vhdl \
		spdif/clock_regenerator.vhdl \
		spdif/input_decoder.vhdl \
		spdif/packet_decoder.vhdl \
		spdif/combined_encoder.vhdl \
		app/compressor_main.vhdl

TEST_VHDL = \
		test/sb_ram40_4k.vhdl \
		test/generated/test_signal_generator.vhdl \
		test/test_delay2.vhdl \
		test/test_delay.vhdl \
		test/test_encoder2.vhdl \
		test/test_encoder.vhdl \
		test/test_disable_compressor.vhdl \
		test/test_clock_regenerator.vhdl \
		test/test_volume.vhdl \
		test/test_compressor.vhdl \
		test/test_compressor2.vhdl \
		test/test_compressor_main.vhdl \
		test/test_divider.vhdl \
		test/test_multiplier.vhdl \
		test/test_subtractor.vhdl \
		test/test_sign_magnitude.vhdl \
		test/test_fifo.vhdl \
		test/test_input_decoder.vhdl \
		test/test_measure.vhdl \
		test/test_uart.vhdl \
		test/test_top_level.vhdl

all: run_tests

clean:
	ghdl --remove

run_tests:
	ghdl --remove
	python app/make_match_rom.py
	python app/make_version_rom.py
	python test/make_test_bench.py
	ghdl -a --work=work $(VHDL) $(TEST_VHDL)
	ghdl -r test_delay2 $(RFLAGS)
	ghdl -r test_delay $(RFLAGS)
	ghdl -r test_compressor2 $(RFLAGS)
	ghdl -r test_compressor $(RFLAGS)
	ghdl -r test_sign_magnitude $(RFLAGS)
	ghdl -r test_compressor_main $(RFLAGS)
	ghdl -r test_encoder2 $(RFLAGS)
	ghdl -r test_encoder $(RFLAGS)
	ghdl -r test_clock_regenerator $(RFLAGS)
	ghdl -r test_input_decoder $(RFLAGS)
	ghdl -r test_volume $(RFLAGS)
	ghdl -r test_disable_compressor $(RFLAGS)
	ghdl -r test_measure $(RFLAGS)
	ghdl -r test_subtractor $(RFLAGS)
	ghdl -r test_multiplier $(RFLAGS)
	ghdl -r test_divider $(RFLAGS)
	ghdl -r test_uart $(RFLAGS)
	ghdl -r test_fifo $(RFLAGS)
	ghdl -r test_top_level $(RFLAGS) > tmp.txt
	diff -q tmp.txt test/test_top_level_out.txt
	echo "tests ok"
