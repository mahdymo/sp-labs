"""
SP-Labs — 6G Channel Simulation with NVIDIA Sionna
====================================================

This script demonstrates key 6G PHY-layer concepts:
1. MIMO channel modeling (CDL models)
2. OFDM resource grid configuration
3. LDPC encoding/decoding
4. BER (Bit Error Rate) evaluation

Requirements: NVIDIA GPU with CUDA 12.0+, Sionna 0.19.1

Usage:
    python 6g_channel_sim.py
    # Or run interactively in Jupyter
"""

import os
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '3'

import numpy as np

try:
    import sionna
    print(f"Sionna version: {sionna.__version__}")
except ImportError:
    print("ERROR: Sionna not installed. Run: pip install sionna")
    exit(1)

import tensorflow as tf
from sionna.channel.tr38901 import CDL
from sionna.ofdm import ResourceGrid, ResourceGridMapper, LSChannelEstimator
from sionna.ofdm import LinearDetector
from sionna.fec.ldpc import LDPC5GEncoder, LDPC5GDecoder
from sionna.mapping import Mapper, Demapper
from sionna.utils import BinarySource, ebnodb2no, compute_ber

# ============================================================================
# Configuration — 6G-oriented parameters
# ============================================================================
NUM_TX_ANTENNAS = 4           # MIMO transmit antennas
NUM_RX_ANTENNAS = 4           # MIMO receive antennas
NUM_OFDM_SYMBOLS = 14         # Symbols per slot
FFT_SIZE = 256                # Subcarriers (scalable for 6G wideband)
SUBCARRIER_SPACING = 120e3    # 120 kHz SCS (FR2 / mmWave)
CARRIER_FREQUENCY = 28e9      # 28 GHz (mmWave band)
DELAY_SPREAD = 100e-9         # Channel delay spread
NUM_BITS_PER_SYMBOL = 4       # 16-QAM
CODERATE = 0.5                # LDPC code rate
BATCH_SIZE = 64
SNR_RANGE_DB = np.arange(-5, 25, 2.5)  # SNR sweep

print("=" * 60)
print("  SP-Labs — 6G Channel Simulation")
print("=" * 60)
print(f"  Carrier Frequency : {CARRIER_FREQUENCY/1e9:.1f} GHz")
print(f"  Subcarrier Spacing: {SUBCARRIER_SPACING/1e3:.0f} kHz")
print(f"  MIMO Config       : {NUM_TX_ANTENNAS}x{NUM_RX_ANTENNAS}")
print(f"  Modulation        : {2**NUM_BITS_PER_SYMBOL}-QAM")
print(f"  LDPC Code Rate    : {CODERATE}")
print(f"  FFT Size          : {FFT_SIZE}")
print("=" * 60)

# ============================================================================
# Build Simulation Components
# ============================================================================
print("\n[1/4] Initializing channel model (CDL-C)...")
cdl_model = CDL(
    model="C",
    delay_spread=DELAY_SPREAD,
    carrier_frequency=CARRIER_FREQUENCY,
    ut_array=sionna.channel.tr38901.Antenna("single", "V", 1, 1),
    bs_array=sionna.channel.tr38901.Antenna("single", "V", 1, 1),
    direction="uplink",
    min_speed=0.0
)

print("[2/4] Configuring OFDM resource grid...")
resource_grid = ResourceGrid(
    num_ofdm_symbols=NUM_OFDM_SYMBOLS,
    fft_size=FFT_SIZE,
    subcarrier_spacing=SUBCARRIER_SPACING,
    num_tx=1,
    num_streams_per_tx=1,
    pilot_pattern="kronecker",
    pilot_ofdm_symbol_indices=[2, 11]
)

print("[3/4] Setting up LDPC encoder/decoder...")
n = int(resource_grid.num_data_symbols * NUM_BITS_PER_SYMBOL)
k = int(n * CODERATE)
encoder = LDPC5GEncoder(k, n)
decoder = LDPC5GDecoder(encoder, hard_out=True)

mapper = Mapper("qam", NUM_BITS_PER_SYMBOL)
rg_mapper = ResourceGridMapper(resource_grid)

print("[4/4] Ready for simulation!")
print(f"  Code block: k={k} info bits -> n={n} coded bits")
print(f"  Resource grid: {NUM_OFDM_SYMBOLS} symbols x {FFT_SIZE} subcarriers")

# ============================================================================
# Run BER Simulation
# ============================================================================
print("\nRunning BER simulation across SNR range...")
print(f"  SNR range: {SNR_RANGE_DB[0]:.1f} to {SNR_RANGE_DB[-1]:.1f} dB")
print("-" * 40)

ber_results = []
source = BinarySource()

for snr_db in SNR_RANGE_DB:
    no = ebnodb2no(snr_db, NUM_BITS_PER_SYMBOL, CODERATE)
    bits = source([BATCH_SIZE, 1, 1, k])
    coded = encoder(bits)
    symbols = mapper(coded)
    x_rg = rg_mapper(symbols)

    # Simplified AWGN for demonstration (swap with CDL for full sim)
    noise = tf.complex(
        tf.random.normal(tf.shape(x_rg), stddev=tf.sqrt(no / 2)),
        tf.random.normal(tf.shape(x_rg), stddev=tf.sqrt(no / 2))
    )
    y_rg = x_rg + noise

    # Direct demapping (simplified)
    demapper = Demapper("app", "qam", NUM_BITS_PER_SYMBOL)
    llr = demapper([tf.reshape(y_rg[:, 0, 0, :resource_grid.num_data_symbols],
                               [BATCH_SIZE, 1, 1, -1]), no])
    bits_hat = decoder(llr)
    ber = compute_ber(bits, bits_hat).numpy()
    ber_results.append(ber)
    print(f"  SNR = {snr_db:6.1f} dB  |  BER = {ber:.6f}")

print("-" * 40)
print("\nSimulation complete!")
print(f"  Best BER  : {min(ber_results):.2e} at SNR = {SNR_RANGE_DB[np.argmin(ber_results)]:.1f} dB")
print(f"  Worst BER : {max(ber_results):.2e} at SNR = {SNR_RANGE_DB[np.argmax(ber_results)]:.1f} dB")
print("\n[OK] 6G channel simulation finished successfully")
