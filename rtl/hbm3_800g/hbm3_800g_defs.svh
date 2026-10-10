`ifndef HBM3_800G_DEFS_SVH
`define HBM3_800G_DEFS_SVH

// HBM3E-class *digital architecture contract* for one 1024-bit HBM stack.
// This is deliberately separate from rtl/ and rtl/gt2n_fork/: it does not
// claim to implement the analog WCK/DQ/TSV PHY that a real 800 GB/s stack
// requires.

localparam int HBM3_CHANNELS       = 16;
localparam int HBM3_PC_PER_CHANNEL = 2;
localparam int HBM3_PSEUDO_CHANNELS = HBM3_CHANNELS * HBM3_PC_PER_CHANNEL;
localparam int HBM3_DQ_BITS_PER_CHANNEL = 64;
localparam int HBM3_DQ_BITS = HBM3_CHANNELS * HBM3_DQ_BITS_PER_CHANNEL;

// The digital controller runs at a 2 GHz core target. One independent 256-bit
// (32-byte) request stream feeds each pseudo-channel. Its 32 lanes provide
// 2048 GB/s raw *core ingress*, deliberately more than one HBM3E stack can
// consume. The scheduler/CDC must meter that down to the PHY rate below.
localparam int HBM3_HOST_LANES       = HBM3_PSEUDO_CHANNELS;
localparam int HBM3_HOST_DATA_BITS   = 256;
localparam int HBM3_HOST_LINE_BYTES  = HBM3_HOST_DATA_BITS / 8;
localparam int HBM3_CORE_TARGET_MHZ  = 2000;
localparam int HBM3_GEAR_RATIO       = 2;
localparam int HBM3_PHY_DATA_BITS_PER_CHANNEL =
    HBM3_HOST_DATA_BITS * HBM3_GEAR_RATIO; // 512 bits / channel / PHY CK

// 16 channels × 64 B × 1.15 GHz = 1177.6 GB/s raw PHY-side payload budget.
// 800 GB/s sustained payload therefore requires at least 67.9% efficiency.
localparam int HBM3_PHY_CK_MHZ       = 1150;
localparam int HBM3_PAYLOAD_TARGET_GBPS = 800;

// The external PHY must deliver 9.2 GT/s per DQ pin (4.6 GHz WCK DDR).
// This is an HBM3E integration target, not a digital-RTL claim.
localparam int HBM3_WCK_MHZ          = 4600;
localparam int HBM3_DQ_MT_S          = 9200;
localparam int HBM3_STACK_CAPACITY_GIB = 24;
localparam int HBM3_ADDR_BITS        = 35; // 24 GiB addressable byte space

`endif
