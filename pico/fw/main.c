#include "spdif.pio.h"

#include "pico/bootrom.h"
#include "pico/stdlib.h"
#include "hardware/pio.h"
#include "hardware/clocks.h"
#include "hardware/sync.h"
#include "hardware/watchdog.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// PIO
#define spdif_pio (pio0)
static uint32_t spdif_offset = ~0;
static uint32_t spdif_sm;
static pio_sm_config spdif_sm_config;

#define SPDIF_PIN 0

#define RAW_WORD_COUNT      10000
static uint32_t raw_block[RAW_WORD_COUNT];

typedef enum { START, STORE, DATA, DATA_SECOND_EDGE,
    PREAMBLE_1, PREAMBLE_2_X, PREAMBLE_2_Y, PREAMBLE_2_Z,
    PREAMBLE_3_X, PREAMBLE_3_Y, PREAMBLE_3_Z } wave_decoder_state_t;

typedef enum {
    ERROR_NONE = 0,
    ERROR_DATA_EXPECT_1,
    ERROR_DATA_EXPECT_1_OR_2,
    ERROR_WAVE_DATA_OVERFLOW,
    ERROR_UNKNOWN,
    ERROR_INVALID_LENGTH,
    ERROR_PREAMBLE_EXPECT_3,
    ERROR_PREAMBLE_2_X,
    ERROR_PREAMBLE_2_Y,
    ERROR_PREAMBLE_2_Z,
    ERROR_PREAMBLE_3_X,
    ERROR_PREAMBLE_3_Y,
    ERROR_PREAMBLE_3_Z,
} error_code_t;

typedef struct status_report_t {
    uint32_t raw_words;
    uint32_t raw_lengths;
    uint32_t wave_index;
    wave_decoder_state_t state;
    error_code_t error_code;
} status_report_t;

static uint8_t PAYLOAD[] = {
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
    0x35, 0xb9, 0xff, 0x91, 0xa5, 0x58, 0x62, 0xf8,
};

typedef struct audio_data_t {
    int32_t left, right;
} audio_data_t;

#define TRUE_MARKER_POSITION 24
#define MARKER_VALUE 0x654321
#define MARKER_MASK 0xfff000
#define REPEAT_SIZE 40
#define MASK_16 0xffff00

static int32_t int_conv(uint32_t unsigned_data, int32_t bits) {
    if (unsigned_data & ((1 << bits) >> 1)) {
        return (int32_t) unsigned_data - (1 << bits);
    } else {
        return (int32_t) unsigned_data;
    }
}

static void examine_walking_1s(audio_data_t* samples, int32_t bits, 
                               bool* small_error, int32_t* incorrect) {
    int32_t shift = 24 - bits;
    *incorrect = -1;
    *small_error = false;
    for (int32_t i = 23; i >= 0; i--) {
        int32_t left = 1 << i;
        int32_t right = left ^ 0xffffff;
        int32_t left_delta = abs(int_conv(left >> shift, bits) - int_conv(samples[i].left >> shift, bits));
        int32_t right_delta = abs(int_conv(right >> shift, bits) - int_conv(samples[i].right >> shift, bits));

        if ((left_delta > 1) || (right_delta > 1)) {
            // Too much error
            printf("at %u (%d-bit): expect %06x %06x  got %06x %06x\n",
                    i, bits, left, right, samples[i].left, samples[i].right);
            *incorrect = (int32_t) i;
            return;
        } else if ((left_delta == 1) || (right_delta == 1)) {
            // This small error could be due to rounding
            *small_error = true;
        }
    }
}

static void examine_wave_data(const uint32_t wave_size) {
    audio_data_t* audio = (audio_data_t*) raw_block;
    int32_t audio_length = wave_size / 2;
    int32_t i;

    // Find the marker
    int32_t marker_position = -1;
    for (i = REPEAT_SIZE * 2; i < audio_length; i++) {
        if (((audio[i].right & MARKER_MASK) == (MARKER_VALUE & MARKER_MASK))
        && ((audio[i - REPEAT_SIZE].right & MARKER_MASK) == (MARKER_VALUE & MARKER_MASK))
        && ((audio[i - (REPEAT_SIZE * 2)].right & MARKER_MASK) == (MARKER_VALUE & MARKER_MASK))) {
            marker_position = i - REPEAT_SIZE;
        }
    }

    if (marker_position < 0) {
        // draw peak meter
        int32_t peak = 0;
        for (i = 0; i < audio_length; i++) {
            int32_t left = abs(int_conv(audio[i].left, 24));
            int32_t right = abs(int_conv(audio[i].right, 24));
            if (left > peak) {
                peak = left;
            }
            if (right > peak) {
                peak = right;
            }
        }
        printf("\r");
        if (wave_size == 0) {
            printf("No signal");
        } else if (peak == 0) {
            printf("Silence");
        } else {
            peak = (peak >> 18) + 1;
            for (i = 0; i < peak; i++) {
                printf("#");
            }
        }
        printf("\x1b[K"); // clear to end of line
        fflush(stdout);
        return;
    }

    // Start at correct position
    audio_data_t* samples = &audio[marker_position - TRUE_MARKER_POSITION];
    printf("\nSample rate of test data: %u Hz\n", ((samples[TRUE_MARKER_POSITION].left >> 8) * 100));

    // Check walking 1s (16 bit mode)
    bool small_error = false;
    int32_t incorrect = -1;
    examine_walking_1s(samples, 16, &small_error, &incorrect);

    if ((incorrect < 0) && !small_error) {
        printf("Walking ones are perfectly correct for 16-bit\n");

        examine_walking_1s(samples, 24, &small_error, &incorrect);
        if ((incorrect < 0) && !small_error) {
            printf("Walking ones are perfectly correct for 24-bit\n");
        } else if (incorrect < 0) {
            printf("Small error detected for 24-bit: not bit-exact\n");
        } else {
            printf("For 24-bit, %d walking 1s are correct (%d exact bits)\n", 23 - incorrect, 23 - incorrect);
        }
    } else if (incorrect < 0) {
        printf("Walking ones are correct for 16-bit with at most +/- 1 bit error\n");
    } else {
        printf("For 16-bit, %d walking 1s are correct (%d exact bits)\n", 23 - incorrect, 23 - incorrect);
    }

    // Check third part of the repeating block: 16 bit data (7 samples)
    int32_t j = 0;
    for (i = 25; i < 32; i++) {
        int32_t left =  ((int32_t) PAYLOAD[j + 0] << 16) | ((int32_t) PAYLOAD[j + 1] << 8);
        int32_t right = ((int32_t) PAYLOAD[j + 2] << 16) | ((int32_t) PAYLOAD[j + 3] << 8);
        if (((samples[i].left & MASK_16) != left) || ((samples[i].right & MASK_16) != right)) {
            printf("at %d (16-bit): expect %06x %06x  got %06x %06x\n",
                    i, left, right, samples[i].left, samples[i].right);
            printf("Error in 16-bit payload part, position %d: signal is not 16-bit clean\n", i);
            return;
        }
        j += 4;
    }

    printf("Correct 16-bit payload part: signal is 16-bit clean\n");

    // Final part of the repeating block: 24 bit data (8 samples)
    for (i = 32; i < REPEAT_SIZE; i++) {
        int32_t left =  ((int32_t) PAYLOAD[j + 0] << 16) | ((int32_t) PAYLOAD[j + 1] << 8)
                            | ((int32_t) PAYLOAD[j + 2] << 0);
        int32_t right = ((int32_t) PAYLOAD[j + 3] << 16) | ((int32_t) PAYLOAD[j + 4] << 8)
                            | ((int32_t) PAYLOAD[j + 5] << 0);
        if ((samples[i].left != left) || (samples[i].right != right)) {
            printf("at %d (24-bit): expect %06x %06x  got %06x %06x\n",
                    i, left, right, samples[i].left, samples[i].right);
            printf("Error in 24-bit payload part, position %d: signal is not 24-bit clean\n", i);
            return;
        }
        j += 6;
    }

    if (incorrect < 0) {
        printf("Correct 24-bit payload part: signal is 24-bit clean\n");
    } else {
        printf("Correct 24-bit payload part but error in walking ones: signal is not 24-bit clean\n");
    }
}

void reboot_pico(bool reboot_into_boot_loader) {
    // Reboot Pico into either the boot loader or into the installed program
    if (reboot_into_boot_loader) {
        reset_usb_boot(0, 0);
    } else {
        watchdog_enable(1, 1);  // Watchdog triggered in 1ms
        while(1) {} // Wait for watchdog reset
    }
}

static void setup_pio() {
    // Install PIO program
    spdif_offset = pio_add_program(spdif_pio, &spdif_program);
    spdif_sm = pio_claim_unused_sm(spdif_pio, true);
    spdif_sm_config = spdif_program_get_default_config(spdif_offset);

    // Receive only, so FIFOs may be joined
    sm_config_set_fifo_join(&spdif_sm_config, PIO_FIFO_JOIN_RX);

    // 'jmp pin' will read from the SPDIF pin
    sm_config_set_jmp_pin(&spdif_sm_config, SPDIF_PIN);

    // 'wait' will read from SPDIF pin
    sm_config_set_in_pins(&spdif_sm_config, SPDIF_PIN);

    // shifter config - shift right, autopush 32
    sm_config_set_in_shift(&spdif_sm_config, true, true, 32);

    // PIO frequency is 125MHz
    sm_config_set_clkdiv(&spdif_sm_config, (float) clock_get_hz(clk_sys) / 125.0e6F);
}

static void pio_write(const uint32_t offset, const uint32_t value) {
    spdif_pio->instr_mem[offset] =
          0xe000    // SET
        | 0x0000    // no delay or side-set
        | 0x0020    // destination is X
        | value;    // data
}

static void set_pio_timings(const uint32_t t0, const uint32_t t1, const uint32_t t2) {
    pio_write(spdif_offset_t0_set_1, t0);
    pio_write(spdif_offset_t0_set_2, t0);
    pio_write(spdif_offset_t1_set_1, t1);
    pio_write(spdif_offset_t1_set_2, t1);
    pio_write(spdif_offset_t2_set_1, t2);
    pio_write(spdif_offset_t2_set_2, t2);
}

static void capture_raw_data() {
    // Reset PIO
    pio_sm_init(spdif_pio, spdif_sm, spdif_offset, &spdif_sm_config);

    uint32_t int_flags = save_and_disable_interrupts();

    // Start PIO
    pio_sm_set_enabled(spdif_pio, spdif_sm, true);

    // Read data
    for (uint32_t i = 0; i < RAW_WORD_COUNT; i++) {
        raw_block[i] = pio_sm_get_blocking(spdif_pio, spdif_sm);
    }

    // Stop
    pio_sm_set_enabled(spdif_pio, spdif_sm, false);

    restore_interrupts(int_flags);
}

static status_report_t convert_raw_to_wave() {
    uint8_t channel_count = 0;
    uint8_t bit_count = 0;
    uint32_t bit_data = 0;
    uint32_t bit_data_channel_0 = 0;
    status_report_t sr = {0, 0, 0, START, ERROR_NONE};

    for (sr.raw_words = 0; sr.raw_words < RAW_WORD_COUNT; sr.raw_words++) {
        uint32_t word = raw_block[sr.raw_words];
        for (sr.raw_lengths = 0; sr.raw_lengths < 16; sr.raw_lengths++) {
            const uint32_t length = (word & 3) + 1;
            word = word >> 2;
            switch (sr.state) {
                case STORE:
                    switch (channel_count) {
                        case 0: // left
                            bit_data_channel_0 = bit_data;
                            break;
                        case 1: // right
                            // There will always be less wave data than raw data, as wave data
                            // is more compact, so we can reuse the space like this
                            raw_block[sr.wave_index++] = bit_data_channel_0 & 0xffffffU;
                            raw_block[sr.wave_index++] = bit_data & 0xffffffU;
                            if (sr.wave_index > sr.raw_words) {
                                sr.error_code = ERROR_WAVE_DATA_OVERFLOW;
                                return sr;
                            }
                            break;
                        default:
                            // additional channel - ignore
                            break;
                    }
                    switch (length) {
                        case 3:
                            sr.state = PREAMBLE_1;
                            break;
                        case 1:
                        case 2:
                            sr.error_code = ERROR_PREAMBLE_EXPECT_3;
                            return sr;
                        default:
                            sr.error_code = ERROR_INVALID_LENGTH;
                            return sr;
                    }
                    break;
                case START:
                    // Await length 3 code
                    switch (length) {
                        case 3:
                            sr.state = PREAMBLE_1;
                            break;
                        default:
                            sr.state = START;
                            break;
                    }
                    break;
                case DATA:
                    switch (length) {
                        case 2:
                            bit_data = bit_data >> 1;
                            bit_count --;
                            if (bit_count == 0) {
                                sr.state = STORE;
                            }
                            break;
                        case 1:
                            bit_data = bit_data >> 1;
                            bit_data |= 1U << 27U;
                            bit_count --;
                            sr.state = DATA_SECOND_EDGE;
                            break;
                        case 3:
                            sr.error_code = ERROR_DATA_EXPECT_1_OR_2;
                            return sr;
                        default:
                            sr.error_code = ERROR_INVALID_LENGTH;
                            return sr;
                    }
                    break;
                case DATA_SECOND_EDGE:
                    switch (length) {
                        case 1:
                            if (bit_count == 0) {
                                sr.state = STORE;
                            } else {
                                sr.state = DATA;
                            }
                            break;
                        case 2:
                        case 3:
                            sr.error_code = ERROR_DATA_EXPECT_1;
                            return sr;
                        default:
                            sr.error_code = ERROR_INVALID_LENGTH;
                            return sr;
                    }
                    break;
                case PREAMBLE_1:
                    bit_count = 28;
                    switch (length) {
                        case 3:
                            // X preamble
                            sr.state = PREAMBLE_2_X;
                            channel_count = 0;
                            break;
                        case 2:
                            // Y preamble
                            sr.state = PREAMBLE_2_Y;
                            channel_count++;
                            break;
                        case 1:
                            // Z preamble
                            sr.state = PREAMBLE_2_Z;
                            channel_count = 0;
                            break;
                        default:
                            sr.error_code = ERROR_INVALID_LENGTH;
                            return sr;
                    }
                    break;
                case PREAMBLE_2_X:
                    switch (length) {
                        case 1:
                            sr.state = PREAMBLE_3_X;
                            break;
                        case 2:
                        case 3:
                            if (sr.wave_index > 0) {
                                sr.error_code = ERROR_PREAMBLE_2_X;
                                return sr;
                            }
                            sr.state = START;
                            break;
                        default:
                            sr.error_code = ERROR_INVALID_LENGTH;
                            return sr;
                    }
                    break;
                case PREAMBLE_2_Y:
                    switch (length) {
                        case 1:
                            sr.state = PREAMBLE_3_Y;
                            break;
                        case 2:
                        case 3:
                            if (sr.wave_index > 0) {
                                sr.error_code = ERROR_PREAMBLE_2_Y;
                                return sr;
                            }
                            sr.state = START;
                            break;
                        default:
                            sr.error_code = ERROR_INVALID_LENGTH;
                            return sr;
                    }
                    break;
                case PREAMBLE_2_Z:
                    switch (length) {
                        case 1:
                            sr.state = PREAMBLE_3_Z;
                            break;
                        case 2:
                        case 3:
                            if (sr.wave_index > 0) {
                                sr.error_code = ERROR_PREAMBLE_2_Z;
                                return sr;
                            }
                            sr.state = START;
                            break;
                        default:
                            sr.error_code = ERROR_INVALID_LENGTH;
                            return sr;
                    }
                    break;
                case PREAMBLE_3_X:
                    switch (length) {
                        case 1:
                            sr.state = DATA;
                            break;
                        case 2:
                        case 3:
                            if (sr.wave_index > 0) {
                                sr.error_code = ERROR_PREAMBLE_3_X;
                                return sr;
                            }
                            sr.state = START;
                            break;
                        default:
                            sr.error_code = ERROR_INVALID_LENGTH;
                            return sr;
                    }
                    break;
                case PREAMBLE_3_Y:
                    switch (length) {
                        case 2:
                            sr.state = DATA;
                            break;
                        case 1:
                        case 3:
                            if (sr.wave_index > 0) {
                                sr.error_code = ERROR_PREAMBLE_3_Y;
                                return sr;
                            }
                            sr.state = START;
                            break;
                        default:
                            sr.error_code = ERROR_INVALID_LENGTH;
                            return sr;
                    }
                    break;
                case PREAMBLE_3_Z:
                    switch (length) {
                        case 3:
                            sr.state = DATA;
                            break;
                        case 1:
                        case 2:
                            if (sr.wave_index > 0) {
                                sr.error_code = ERROR_PREAMBLE_3_Z;
                                return sr;
                            }
                            sr.state = START;
                            break;
                        default:
                            sr.error_code = ERROR_INVALID_LENGTH;
                            return sr;
                    }
                    break;
                default:
                    sr.error_code = ERROR_UNKNOWN;
                    return sr;
            }
        }
    }
    sr.error_code = ERROR_NONE;
    return sr;
}

static uint32_t convert_raw_to_wave_and_halt_on_error() {
    status_report_t sr = convert_raw_to_wave();

    if (sr.error_code == ERROR_NONE) {
        // number of words converted
        return sr.wave_index;
    }
    if (sr.error_code == ERROR_INVALID_LENGTH) {
        // No signal? Just try again
        return 0;
    }
    printf("\nsr.error code = %d\n"
           "sr.raw_words = %u (of %u)\n"
           "sr.raw_lengths = %u\n"
           "sr.wave_index = %u\n"
           "sr.state = %d\n",
           sr.error_code, sr.raw_words, RAW_WORD_COUNT,
           sr.raw_lengths, sr.wave_index, sr.state);
    const uint32_t pre_window = 8;
    const uint32_t post_window = 8;
    uint32_t i = sr.raw_words;
    if (i > pre_window) {
        i -= pre_window;
    } else {
        i = 0;
    }
    for (uint32_t k = 0; (k < (pre_window + post_window)) && (i < RAW_WORD_COUNT); i++, k++) {
        printf("raw_block[%u] = %08x -> ", i, raw_block[i]);
        uint32_t word = raw_block[i];
        for (uint32_t j = 0; j < 16; j++) {
            const uint32_t length = (word & 3) + 1;
            word = word >> 2;
            if ((sr.raw_words == i) && (sr.raw_lengths == j)) {
                printf("<%d>", length);
            } else {
                printf(" %d ", length);
            }
        }
        printf("\n");
    }
    printf("Stopped by error\n\n\n");
    reboot_pico(false);
    return 0;
}

int main() {
    stdio_init_all();

    setup_pio();
    while (true) {
        printf("\rReady - press 'x' key to start, or 'r' to return to bootloader:");
        fflush(stdout);
        int ch = getchar_timeout_us(1000000);
        if (ch == 'x') {
            break;
        }
        if (ch == 'k') {
            printf("\nSet T0 and T1: t0 = ");
            int t0 = getchar() - '0';
            printf("%d\nt1 = ", t0);
            int t1 = getchar() - '0';
            printf("%d\nok = ", t1);
            if (getchar() == 'y') {
                printf("set\n");
                set_pio_timings(t0, t1, 8);
                break;
            } else {
                printf("not set\n");
            }
        }
        if (ch == 'r') {
            reboot_pico(true);
        }
    }
    printf("\nConnect SPDIF to pin %d - use 44.1kHz or 48kHz stereo\n", SPDIF_PIN);
    
    while (getchar_timeout_us(10000) < 0) {
        capture_raw_data();
        const uint32_t wave_size = convert_raw_to_wave_and_halt_on_error();
        examine_wave_data(wave_size);
    }
    printf("\nStopped by key press\n\n\n");
    reboot_pico(false);
}
