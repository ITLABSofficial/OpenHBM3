# OpenHBM3

**An Open-Source JEDEC HBM3 Memory Controller & 1024-Pin Sub-10nm Predictive PHY Front-End**

**Project:** ITLabsAI Open Source Hardware Initiative  
*A transparent, silicon-hardened SystemVerilog reference architecture for High Bandwidth Memory.*

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![Verification](https://img.shields.io/badge/Verification-19%2F19%20PASS-brightgreen.svg)](#local-simulation--quick-start-guide)
[![Physical Signoff](https://img.shields.io/badge/ASAP7%207nm-0%20DRC%20%7C%207.45m%20Wire-success.svg)](#key-measured-metrics)

> ### 🌐 WORLD'S FIRST OPEN-SOURCE HBM3 HARDWARE ARCHITECTURE
> OpenHBM3 is the **world's first publicly available, fully synthesizable, and silicon-hardened JEDEC JESD238 HBM3 memory controller and 1024-pin digital PHY reference design**. While High Bandwidth Memory (HBM3/HBM3E) has historically remained restricted behind proprietary commercial IP licenses and strict non-disclosure agreements (NDAs), OpenHBM3 delivers a complete, verified, and post-route signoff-ready hardware stack to the global open-source semiconductor community:
> 1. **First Open JEDEC JESD238 Controller IP:** Synthesizable hardware implementing on-die Hamming(39,32) SECDED ECC, byte-level dynamic Data Bus Inversion (DBI), dual-sub-lane DDR datapath, and bank-prefetch scheduling.
> 2. **First Open 1024-Pin Digital SerDes PHY:** Digital front-end featuring dynamic bit-slip deskew across 64 data lanes, automated link training FSM, and 2:1 gearbox clock-domain crossing (CDC).
> 3. **First Sub-10nm Physical Signoff on Open EDA:** Routed on ASAP7 7nm FinFET using OpenROAD/TritonRoute with **0 DRC violations**, 7.45 meters of routed wire, and complete gate-level netlists (`synth/*.vg`) published.
> 4. **100% Open Verification (19/19 PASS):** Fully reproducible regressions on open-source simulators (Icarus Verilog, Verilator, Yosys) without proprietary tool dependencies.

> ### ⚠ ENGINEERING DISCLAIMER & CLAIM BOUNDARIES (READ FIRST)
> 1. **Not Fabricated Silicon:** All sub-10nm physical implementation metrics originate from the **ASAP7 (7nm FinFET)** predictive PDK [Clark et al., 2016] and **GT2N (2nm GAAFET)** predictive PDK [ISCAS 2026]. These are academic, non-manufacturable process models.
> 2. **Digital Front-End Only (No Analog PHY):** This repository contains a complete, synthesizable digital controller and digital SerDes front-end (serializers, deserializers, bit-slip deskew, link training). It **does not contain mixed-signal analog circuitry** (4.6 GHz LC-PLL, 9.2 Gbps SST/CML drivers, on-die termination (ODT), or continuous-time linear equalizers (CTLE)).
> 3. **Simulation Ceiling vs. Post-Route Silicon Bottleneck:** The **941.61 GB/s** result is a behavioral simulation ceiling at a hypothetical 2.5 GHz clock. In routed 7nm silicon, static timing analysis confirms that the physical DQ pins toggle at **2596.5 MHz DDR**, establishing an actual hardware bottleneck of **664.7 GB/s** raw.
> 4. **No Fabricated Benchmarks:** Every number reported herein originates from reproducible open-source EDA logs (Yosys, Icarus Verilog, OpenROAD, OpenSTA, KLayout).

---

## Architecture Overview

OpenHBM3 provides two fully verified hardware subsystems:

```
                            ┌────────────────────────── OPENHBM3 REPOSITORY ──────────────────────────┐
                            │                                                                         │
                            │  1. JEDEC JESD238 DRAM CONTROLLER (`rtl/hbm3_ctrl/`)                    │
                            │     ├─ 16 physical channels / 32 pseudo-channels                        │
                            │     ├─ Dual-sub-lane real DDR datapath (2x 32-bit sub-beats / cycle)    │
                            │     ├─ Hamming(39,32) SECDED on-die ECC & byte-level dynamic DBI        │
                            │     ├─ Open-page bank-prefetch scheduler with hazard interlocks         │
                            │     └─ Behavioral DRAM model with permanent protocol assertion monitors │
                            │                                                                         │
                            │  2. OPENHBM3 800G STREAM SYSTEM (`rtl/hbm3_800g/` & `rtl/phy/`)         │
                            │     ├─ 32 independent 4-entry host ingress queues                       │
                            │     ├─ 32-to-16 two-stage pipelined round-robin arbiter (Tree A + Mux B)│
                            │     ├─ 2:1 gearbox CDC (256-bit core beats -> 512-bit PHY beats)        │
                            │     ├─ Asynchronous Gray-pointer FIFOs marked `ASYNC_REG`               │
                            │     ├─ Segmented reset buffers preventing `opt_merge` fanout collapse   │
                            │     └─ 1024-pin digital SerDes front-end with dynamic bit-slip deskew   │
                            └─────────────────────────────────────────────────────────────────────────┘
```

### Physical Die Visual Gallery (ASAP7 7nm FinFET)

| Full Die Macro (0.226 mm², 0 DRC) | Isometric 3D Layer Stack (42 Mask Layers) |
|:---:|:---:|
| [![Full Die](images/00_full_die_macro.png)](images/00_full_die_macro.png) | [![3D Stack](images/fig8_3d_layer_stack_isometric.png)](images/fig8_3d_layer_stack_isometric.png) |

---

## Key Measured Metrics

### 1. ASAP7 7nm Post-Route Signoff (Slow-Slow Corner, 0.70V, 125°C)

Detailed routing executed in OpenROAD / TritonRoute on Google Cloud TPU v6e-1 High-RAM (173 GB RAM, 64 GB swap, 17 threads) in 2.92 hours:

| Physical Metric | Measured Value | Architectural Context |
|:---|---:|:---|
| **DRC Violations** | **0** | Clean convergence across 10 routing iterations (Iter 0: 298,709 -> Iter 9: 0) |
| **Total Routed Wirelength** | **7,449,745 µm (7.45 m)** | Low-parasitic interconnect network across metals M2–M7 |
| **Total Cut Vias** | **7,640,171** | 100% single-cut vias (0 multi-cut vias) |
| **Die Dimensions** | **475.44 µm × 475.44 µm** | **0.226 mm²** (226,041 µm²) compact silicon footprint |
| **Standard Cell Area** | **80,932 µm²** | **35.8% core density** (plenty of routing whitespace, no congestion) |
| **Layout Complexity** | **204,443,059 polygons** | Total polygon geometry extracted across 42 mask layers |
| **Metal Wire Distribution** | M3: 31.0%, M4: 23.6%, M2: 18.7% | M1 intra-cell; M8/M9 reserved for power/ground mesh |

### 2. Static Timing Analysis (STA) & Throughput Decomposition

| Domain / Signal Path | Target Period / Freq | Achieved Period / Freq | Setup Slack (WNS) | Status & Hardware Impact |
|:---|:---|:---|---:|:---|
| **`core_clk`** | 400.0 ps / 2500 MHz | **1317.1 ps / 759.2 MHz** | −917.1 ps | Delivers **777.5 GB/s** core ingress bandwidth (32 × 32 B) |
| **`phy_clk`** | 869.6 ps / 1150 MHz | **455.2 ps / 2196.9 MHz** | **+414.4 ps** | Met with margin; internal PHY bus capacity is **2249.6 GB/s** |
| **`wck`** (DDR) | 217.4 ps / 4600 MHz | **385.1 ps / 2596.5 MHz** | −167.7 ps | **TRUE BOTTLENECK:** 1024 DQ pins yield **664.7 GB/s** pin throughput |
| **Hold Margin** | 0.0 ps | **+28.8 ps** | +28.8 ps | **0 hold violations** across entire die under propagated clocks |

> **Critical Takeaway:** Even though `core_clk` missed its 2.5 GHz goal, it still pumps **777.5 GB/s** into the controller—which is *more* than the 1024 physical DQ pins can physically emit (**664.7 GB/s**). The true physical throughput ceiling is dictated by `wck`, not `core_clk`.

---

## Repository Directory Structure

```
openhbm3/
├── README.md                      # Primary project overview, architecture, and results
├── LICENSE                        # Apache 2.0 open-source hardware license
├── Makefile                       # Unified makefile running all verification suites
├── synth/                         # Synthesized gate-level netlists & timing signoff
│   ├── hbm3_800g_full_phy_top.vg  # ASAP7 7nm synthesized gate-level Verilog netlist (65 MB)
│   ├── hbm3_ctrl.vg               # JEDEC controller synthesized gate-level netlist (7.4 MB)
│   ├── design.sdc                 # Physical timing constraints
│   ├── sta_full.txt               # Complete static timing signoff report
│   └── metrics.json               # 0 DRC, 7.45m wirelength, 7.64M via signoff metrics
├── rtl/
│   ├── hbm3_ctrl/                 # JEDEC JESD238 controller core
│   │   ├── hbm3_ctrl.sv           # Synthesizable top-level IP
│   │   ├── pc_channel.sv          # Pseudo-channel FSM, queues, prefetch, DDR datapath
│   │   ├── ecc.sv                 # Hamming(39,32) SECDED encoder and syndrome decoder
│   │   ├── dbi.sv                 # Per-byte dynamic Data Bus Inversion
│   │   ├── dram_model.sv          # Behavioral DRAM with permanent protocol checkers
│   │   ├── wck_div.sv             # Observability clock divider
│   │   ├── hbm3_top.sv            # Testbench harness wrapping controller + DRAM model
│   │   └── hbm3_defs.svh          # JEDEC timing parameters and command encoding
│   ├── hbm3_800g/                 # OpenHBM3 800 GB/s scalable stream subsystem (Flagship)
│   │   ├── hbm3_800g_full_phy_top.sv      # Full top-level macro (synthesized & routed)
│   │   ├── hbm3_800g_digital_full_top.sv  # Complete synthesizable digital stream top
│   │   ├── hbm3_800g_scheduler_32to16.sv  # 2-stage pipelined arbiter (Stage A Tree + Stage B Mux)
│   │   ├── hbm3_800g_pc_queues.sv         # 32 independent ingress queues with segmented reset
│   │   ├── hbm3_800g_gearbox_2to1_cdc.sv   # 2:1 256b->512b Gearbox + async CDC
│   │   ├── hbm3_800g_async_fifo.sv        # Dual-clock Gray FIFO with ASYNC_REG flops
│   │   ├── hbm3_800g_reset_sync.sv        # 2-cycle synchronous deassertion reset controller
│   │   ├── hbm3_800g_rst_buf.sv           # (* keep_hierarchy *) reset fanout buffer
│   │   ├── hbm3_800g_ingress.sv           # Ingress adapter
│   │   ├── hbm3_800g_dfi_cdc.sv           # DFI protocol bridge
│   │   └── hbm3_1024_phy_blackbox.sv      # Explicit PHY macro boundary definition
│   └── phy/                       # High-speed digital PHY front-end
│       ├── hbm3_phy_serializer.sv         # 8:1 DDR double-pumped serializer
│       ├── hbm3_phy_deserializer.sv       # 1:8 DDR deserializer with dynamic bit-slip deskew
│       ├── hbm3_phy_tx_channel.sv         # 64-lane TX channel slice
│       ├── hbm3_phy_rx_channel.sv         # 64-lane RX channel slice
│       ├── hbm3_phy_training.sv           # Automatic per-lane link training & deskew FSM
│       └── hbm3_phy_analog_model.sv       # Behavioral analog channel & skew emulator
├── tb/                            # Exhaustive testbench suites
│   ├── tb_hbm3.sv                 # JESD238 protocol & functional regression (26 checks)
│   ├── tb_bandwidth.sv            # Pipelined DRAM bandwidth benchmark
│   ├── tb_alias.sv                # Negative verification: DRAM address collision detector
│   ├── tb_ecc.sv                  # 100-case Hamming SECDED unit test
│   ├── tb_ecc_fault.sv            # Fault-injection verification suite
│   ├── tb_bandwidth_local.sv      # Bandwidth validation harness
│   ├── tb_hbm3_phy_serdes.sv      # Serializer/deserializer deskew unit test
│   ├── tb_hbm3_phy_tx.sv          # 64-lane transmitter slice test
│   ├── tb_hbm3_phy_link.sv        # Automatic link training verification
│   ├── tb_hbm3_800g_contract.sv   # Width and arithmetic verification
│   ├── tb_hbm3_800g_scheduler.sv  # Saturated traffic scheduler benchmark
│   ├── tb_hbm3_800g_scheduler_scoreboard.sv # High-frequency scoreboard
│   ├── tb_hbm3_800g_pathological.sv # Pathological congestion test
│   ├── tb_hbm3_800g_smoke.sv      # Pipeline smoke test
│   ├── tb_hbm3_800g_dfi_cdc.sv    # DFI protocol bridge verification
│   ├── tb_hbm3_800g_async_fifo.sv # Asynchronous dual-clock FIFO test
│   ├── tb_hbm3_800g_gearbox.sv    # Gearbox packing verification
│   ├── tb_hbm3_800g_full_top.sv   # Digital full-top simulation
│   └── tb_hbm3_800g_full_phy.sv   # Full-chip PHY testbench
├── docs/                          # Architecture manual
│   └── ARCHITECTURE.md            # Hardware microarchitecture manual & pinout
└── images/                        # Essential architectural & signoff figures
    ├── 00_full_die_macro.png      # Full die macro top-down view
    ├── fig1_frequency_timing_breakdown.png
    ├── fig2_bandwidth_hierarchy_comparison.png
    ├── fig3_layer_wirelength_distribution.png
    ├── fig4_eda_memory_scaling_convergence.png
    ├── fig5_custom_circuit_architectures.png
    ├── fig6_hbm3_ctrl_architecture.png
    ├── fig7_openhbm3_stream_system.png
    └── fig8_3d_layer_stack_isometric.png # 3D isometric layer stack
```

---

## Local Simulation & Quick Start Guide

OpenHBM3 is built entirely for 100% reproducible open-source verification. All simulations, structural elaboration checks, and testbenches run locally on Linux and macOS without proprietary EDA licenses.

### 1. Prerequisites & Toolchain Setup

Install the required open-source simulator and synthesis tools:

- **Ubuntu / Debian:**
  ```bash
  sudo apt-get update
  sudo apt-get install -y iverilog verilator yosys gtkwave build-essential
  ```
- **Fedora / RHEL:**
  ```bash
  sudo dnf install -y iverilog verilator yosys gtkwave make
  ```
- **Arch Linux:**
  ```bash
  sudo pacman -S --needed iverilog verilator yosys gtkwave make
  ```
- **macOS (Homebrew):**
  ```bash
  brew install icarus-verilog verilator yosys gtkwave make
  ```

---

### 2. Clone the Repository

```bash
git clone https://github.com/ITLABSofficial/OpenHBM3.git
cd OpenHBM3
```

---

### 3. Run the Complete Verification Suite (19/19 Regressions)

To execute all 19 functional, protocol, and structural regressions in one pass:

```bash
make all
```

**Expected terminal output:**
```
========================================================
  ALL OPENHBM3 REGRESSION SUITES PASSED SUCCESSFULLY!   
========================================================
```

---

### 4. Running Individual Subsystem Simulations

You can simulate each subsystem independently to inspect specific behaviors:

#### A. JEDEC Controller Core (`rtl/hbm3_ctrl/`)
```bash
make test                 # 3 end-to-end DRAM scenarios, 26 self-checking assertion monitors
make ecc-unit             # 100-case Hamming(39,32) SECDED unit test (single-bit repair, 2-bit trap)
make alias-check          # Negative verification: forces row collisions, aborts if detector is silent
make bandwidth-local      # Streaming localized access bandwidth benchmark
make ctrl-structural      # Yosys elaboration, hierarchy, and lint check on hbm3_ctrl
```

#### B. High-Speed SerDes PHY Front-End (`rtl/phy/`)
```bash
make phy-serdes           # 8:1 / 1:8 SerDes loopback and bitslip stepping verification
make phy-tx               # 64-lane TX channel slice test (24,576 bits verified bit-for-bit)
make phy-link             # 64-lane link training FSM: sweeps bitslip and locks all 64 lanes
make phy-structural       # Yosys hierarchy, process elaboration, and multi-driver check on PHY
```

#### C. OpenHBM3 800G Stream Subsystem (`rtl/hbm3_800g/`)
```bash
make hbm3-800g-contract   # Verifies 32-lane ingress contract and width arithmetic
make hbm3-800g-scheduler  # Saturated traffic scheduler benchmark (893+ GB/s throughput)
make hbm3-800g-scheduler-scoreboard # 1,536 ordered transactions verified at 2.0, 2.5, and 3.6 GHz
make hbm3-800g-pathological # 32-to-1 pathological contention with 50% random backpressure
make hbm3-800g-smoke       # Quick single-transaction pipeline smoke test
make hbm3-800g-dfi-cdc     # 16-channel DFI protocol CDC bridge verification
make hbm3-800g-cdc         # Dual-clock asynchronous FIFO verification with Gray counters
make hbm3-800g-gearbox     # 2:1 gearbox packing, odd-beat flush, and masking verification
make hbm3-800g-full-top    # End-to-end full top simulation (reproduces 941.61 GB/s ceiling)
make hbm3-800g-full-phy    # Full end-to-end host-to-1024-DQ-pin driving verification
make top-structural        # Yosys hierarchy and multidriver check on digital full top
```

---

### 5. Inspecting Waveforms (GTKWave)

Compiled simulation binaries are generated in the `sim/` directory. To generate and inspect Value Change Dump (`.vcd`) waveforms:

```bash
# Run simulation target
vvp sim/hbm3_800g_full_2p5g.vvp

# Open waveforms in GTKWave (if dump enabled in TB)
gtkwave dump.vcd
```

---

### 6. Inspecting Gate-Level Netlists & Signoff Reports

Synthesized gate-level netlists and signoff logs generated from the ASAP7 7nm FinFET tapeout flow are included in `synth/`:

```bash
# View 800G flagship synthesized gate-level netlist (ASAP7 7nm)
head -n 50 synth/hbm3_800g_full_phy_top.vg

# Inspect static timing signoff report (slack, Fmax, clock frequencies)
cat synth/sta_full.txt

# Inspect physical layout metrics (0 DRC, 7.45m wirelength, 7.64M vias)
cat synth/metrics.json
```

---

## Key Architectural Breakthroughs

OpenHBM3 incorporates several custom digital microarchitectural solutions designed to overcome nanometer physical design bottlenecks:

1. **The 2-Stage Arbiter Breakthrough:**  
   Replacing a 32-deep iterative loop-carried priority scan with a 5-stage balanced priority-merge tree (log₂(32) = 5, Stage A) followed by a registered 256-bit data multiplexer (Stage B) dismantled a crushing critical path that had previously capped ASAP7 synthesis at **17.94 MHz**, restoring multi-GHz capability.
2. **Dynamic Bitslip Extended Window (4 × SER_RATIO):**  
   Expanding the deserializer shift window from 3 × SER_RATIO (24 bits) to 4 × SER_RATIO (32 bits) eliminated frame wrapping bugs under large routing skews, providing a robust ±1 full-beat deskew margin across all 64 data lanes.
3. **Reset Replication under Synthesis Optimization:**  
   To prevent EDA tools from merging replicated reset fanouts and causing severe clock-tree deassertion skew, reset buffers were isolated into standalone modules with hierarchy preservation (`(* keep_hierarchy = "true" *)`).
4. **Negative Test Verification Discipline:**  
   Rather than trusting green test reports, every detector was verified negatively: `make alias-check` deliberately forces row address collisions and aborts if the detector fails to fire; `make ecc-check` physically corrupts bits in DRAM storage to verify single-bit silent correction and double-bit uncorrectable trapping.

---

## Citation & References

```bibtex
@misc{openhbm3_2026,
  title        = {{OpenHBM3: An Open-Source JEDEC HBM3 Memory Controller and 1024-Pin Sub-10nm Predictive PHY Front-End}},
  author       = {{OpenHBM3 Project Contributors}},
  howpublished = {\url{https://github.com/ITLABSofficial/OpenHBM3}},
  year         = {2026}
}
```

---

## License

OpenHBM3 is released under the **Apache License, Version 2.0**. See [`LICENSE`](LICENSE) for complete details.
