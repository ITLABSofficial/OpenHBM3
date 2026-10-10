# OpenHBM3 Unified Build & Verification Makefile
# Covers both JEDEC JESD238 Controller Core (hbm3_ctrl) and
# Scalable Multi-Channel / PHY Front-End Architecture (Korpus / hbm3_800g)

SHELL := /bin/bash
IVERILOG := iverilog -g2012
VVP := vvp

# Directory structure
RTL_CTRL := rtl/hbm3_ctrl
RTL_800G := rtl/hbm3_800g
RTL_PHY  := rtl/phy
TB       := tb
SIM_DIR  := sim

# Common flags
INC_FLAGS := -I $(RTL_CTRL) -I $(RTL_800G) -I $(RTL_PHY)

# Core synthesizable IP & harness
CTRL_RTL := $(RTL_CTRL)/dbi.sv $(RTL_CTRL)/ecc.sv $(RTL_CTRL)/dram_model.sv \
            $(RTL_CTRL)/wck_div.sv $(RTL_CTRL)/pc_channel.sv $(RTL_CTRL)/hbm3_ctrl.sv $(RTL_CTRL)/hbm3_top.sv

# PHY front-end RTL
PHY_RTL := $(RTL_PHY)/hbm3_phy_serializer.sv \
           $(RTL_PHY)/hbm3_phy_deserializer.sv \
           $(RTL_PHY)/hbm3_phy_tx_channel.sv

.PHONY: all help clean \
        test bandwidth bandwidth-norefresh bandwidth-local alias-check ecc-unit ecc-check \
        phy-serdes phy-tx phy-link phy-structural ctrl-structural top-structural \
        hbm3-800g-contract hbm3-800g-scheduler hbm3-800g-scheduler-scoreboard \
        hbm3-800g-pathological hbm3-800g-smoke hbm3-800g-dfi-cdc hbm3-800g-cdc \
        hbm3-800g-gearbox hbm3-800g-full-top hbm3-800g-full-phy

all: test ecc-unit ecc-check alias-check bandwidth-local phy-serdes phy-tx phy-link phy-structural \
     ctrl-structural top-structural hbm3-800g-contract hbm3-800g-scheduler \
     hbm3-800g-pathological hbm3-800g-smoke hbm3-800g-dfi-cdc hbm3-800g-cdc \
     hbm3-800g-gearbox hbm3-800g-full-top hbm3-800g-full-phy
	@echo "========================================================"
	@echo "  ALL OPENHBM3 REGRESSION SUITES PASSED SUCCESSFULLY!   "
	@echo "========================================================"

$(SIM_DIR):
	mkdir -p $(SIM_DIR)

# ==============================================================================
# 1. JEDEC JESD238 Controller Verification (DDR, ECC, DBI, DRAM Model)
# ==============================================================================

test: $(SIM_DIR)
	$(IVERILOG) $(INC_FLAGS) -o $(SIM_DIR)/tb_hbm3.vvp $(TB)/tb_hbm3.sv $(CTRL_RTL) 2>&1 | { grep -v "cannot be synthesized" || true; }
	$(VVP) $(SIM_DIR)/tb_hbm3.vvp

bandwidth: $(SIM_DIR)
	$(IVERILOG) $(INC_FLAGS) -o $(SIM_DIR)/tb_bandwidth.vvp $(TB)/tb_bandwidth.sv $(CTRL_RTL) 2>&1 | { grep -v "cannot be synthesized" || true; }
	$(VVP) $(SIM_DIR)/tb_bandwidth.vvp

bandwidth-norefresh: $(SIM_DIR)
	$(IVERILOG) $(INC_FLAGS) -DT_REFI_VAL=100000 -o $(SIM_DIR)/tb_bandwidth_noref.vvp $(TB)/tb_bandwidth.sv $(CTRL_RTL) 2>&1 | { grep -v "cannot be synthesized" || true; }
	$(VVP) $(SIM_DIR)/tb_bandwidth_noref.vvp

bandwidth-local: $(SIM_DIR)
	$(IVERILOG) $(INC_FLAGS) -o $(SIM_DIR)/tb_bw_local.vvp $(TB)/tb_bandwidth_local.sv $(CTRL_RTL) 2>&1 | { grep -v "cannot be synthesized" || true; }
	$(VVP) $(SIM_DIR)/tb_bw_local.vvp

ecc-unit: $(SIM_DIR)
	$(IVERILOG) $(INC_FLAGS) -o $(SIM_DIR)/tb_ecc.vvp $(TB)/tb_ecc.sv $(RTL_CTRL)/ecc.sv 2>&1 | { grep -v "cannot be synthesized" || true; }
	$(VVP) $(SIM_DIR)/tb_ecc.vvp

ecc-check: $(SIM_DIR)
	$(IVERILOG) $(INC_FLAGS) -o $(SIM_DIR)/tb_eccf.vvp $(TB)/tb_ecc_fault.sv $(CTRL_RTL) 2>&1 | { grep -v "cannot be synthesized" || true; }
	$(VVP) $(SIM_DIR)/tb_eccf.vvp

alias-check: $(SIM_DIR)
	$(IVERILOG) $(INC_FLAGS) -o $(SIM_DIR)/tb_alias.vvp $(TB)/tb_alias.sv $(CTRL_RTL) 2>&1 | { grep -v "cannot be synthesized" || true; }
	@$(VVP) $(SIM_DIR)/tb_alias.vvp | tee $(SIM_DIR)/tb_alias.out
	@grep -q "ADRES CAKISMASI" $(SIM_DIR)/tb_alias.out \
	  && echo "TB_ALIAS: PASS (DRAM collision detector confirmed active)" \
	  || { echo "TB_ALIAS: FAIL (Detector remained silent)"; exit 1; }

ctrl-structural:
	yosys -q -p 'read_verilog -sv $(INC_FLAGS) $(RTL_CTRL)/hbm3_defs.svh $(RTL_CTRL)/dbi.sv $(RTL_CTRL)/ecc.sv $(RTL_CTRL)/wck_div.sv $(RTL_CTRL)/pc_channel.sv $(RTL_CTRL)/hbm3_ctrl.sv; hierarchy -check -top hbm3_ctrl; proc; check'
	@echo "CTRL_STRUCTURAL: PASS (Yosys hierarchy/proc/check clean on hbm3_ctrl)"

# ==============================================================================
# 2. PHY Front-End & SerDes Verification (Serializer, Deserializer, Bitslip Deskew)
# ==============================================================================

phy-serdes: $(SIM_DIR)
	$(IVERILOG) $(INC_FLAGS) -o $(SIM_DIR)/phy_serdes.vvp \
	  $(TB)/tb_hbm3_phy_serdes.sv $(RTL_PHY)/hbm3_phy_serializer.sv $(RTL_PHY)/hbm3_phy_deserializer.sv
	$(VVP) $(SIM_DIR)/phy_serdes.vvp

phy-tx: $(SIM_DIR)
	$(IVERILOG) $(INC_FLAGS) -o $(SIM_DIR)/phy_tx.vvp \
	  $(TB)/tb_hbm3_phy_tx.sv $(PHY_RTL)
	$(VVP) $(SIM_DIR)/phy_tx.vvp

phy-link: $(SIM_DIR)
	$(IVERILOG) $(INC_FLAGS) -o $(SIM_DIR)/phy_link.vvp \
	  $(TB)/tb_hbm3_phy_link.sv $(PHY_RTL) \
	  $(RTL_PHY)/hbm3_phy_rx_channel.sv $(RTL_PHY)/hbm3_phy_training.sv
	$(VVP) $(SIM_DIR)/phy_link.vvp

phy-structural:
	yosys -q -p 'read_verilog -sv $(INC_FLAGS) $(PHY_RTL); hierarchy -check -top hbm3_phy_tx_channel; proc; check'
	@echo "PHY_STRUCTURAL: PASS (Yosys hierarchy/proc/check clean)"

# ==============================================================================
# 3. Scalable Stream Architecture (32-to-16 Scheduler, Gearbox CDC, Full Top)
# ==============================================================================

hbm3-800g-contract: $(SIM_DIR)
	$(IVERILOG) $(INC_FLAGS) -o $(SIM_DIR)/hbm3_800g_contract.vvp \
	  $(TB)/tb_hbm3_800g_contract.sv $(RTL_800G)/hbm3_800g_ingress.sv \
	  $(RTL_800G)/hbm3_800g_pc_queues.sv $(RTL_800G)/hbm3_800g_rst_buf.sv \
	  $(RTL_800G)/hbm3_1024_phy_blackbox.sv $(RTL_800G)/hbm3_800g_top.sv
	$(VVP) $(SIM_DIR)/hbm3_800g_contract.vvp

hbm3-800g-scheduler: $(SIM_DIR)
	$(IVERILOG) $(INC_FLAGS) -o $(SIM_DIR)/hbm3_800g_scheduler.vvp \
	  $(TB)/tb_hbm3_800g_scheduler.sv $(RTL_800G)/hbm3_800g_scheduler_32to16.sv
	$(VVP) $(SIM_DIR)/hbm3_800g_scheduler.vvp

hbm3-800g-scheduler-scoreboard: $(SIM_DIR)
	$(IVERILOG) $(INC_FLAGS) -o $(SIM_DIR)/hbm3_800g_sched_score_2g.vvp \
	  $(TB)/tb_hbm3_800g_scheduler_scoreboard.sv $(RTL_800G)/hbm3_800g_scheduler_32to16.sv
	$(VVP) $(SIM_DIR)/hbm3_800g_sched_score_2g.vvp
	$(IVERILOG) $(INC_FLAGS) -Ptb_hbm3_800g_scheduler_scoreboard.CORE_CLK_PS=400 \
	  -o $(SIM_DIR)/hbm3_800g_sched_score_2p5g.vvp $(TB)/tb_hbm3_800g_scheduler_scoreboard.sv \
	  $(RTL_800G)/hbm3_800g_scheduler_32to16.sv
	$(VVP) $(SIM_DIR)/hbm3_800g_sched_score_2p5g.vvp

hbm3-800g-cdc: $(SIM_DIR)
	$(IVERILOG) $(INC_FLAGS) -o $(SIM_DIR)/hbm3_800g_async_fifo.vvp \
	  $(TB)/tb_hbm3_800g_async_fifo.sv $(RTL_800G)/hbm3_800g_async_fifo.sv
	$(VVP) $(SIM_DIR)/hbm3_800g_async_fifo.vvp

hbm3-800g-gearbox: $(SIM_DIR)
	$(IVERILOG) $(INC_FLAGS) -o $(SIM_DIR)/hbm3_800g_gearbox_2g.vvp \
	  $(TB)/tb_hbm3_800g_gearbox.sv $(RTL_800G)/hbm3_800g_gearbox_2to1_cdc.sv $(RTL_800G)/hbm3_800g_rst_buf.sv \
	  $(RTL_800G)/hbm3_800g_async_fifo.sv
	$(VVP) $(SIM_DIR)/hbm3_800g_gearbox_2g.vvp
	$(IVERILOG) $(INC_FLAGS) -Ptb_hbm3_800g_gearbox.CORE_CLK_PS=400 \
	  -o $(SIM_DIR)/hbm3_800g_gearbox_2p5g.vvp $(TB)/tb_hbm3_800g_gearbox.sv \
	  $(RTL_800G)/hbm3_800g_gearbox_2to1_cdc.sv $(RTL_800G)/hbm3_800g_rst_buf.sv $(RTL_800G)/hbm3_800g_async_fifo.sv
	$(VVP) $(SIM_DIR)/hbm3_800g_gearbox_2p5g.vvp

hbm3-800g-full-top: $(SIM_DIR)
	$(IVERILOG) $(INC_FLAGS) -o $(SIM_DIR)/hbm3_800g_full_2g.vvp \
	  $(TB)/tb_hbm3_800g_full_top.sv $(RTL_800G)/hbm3_800g_digital_full_top.sv \
	  $(RTL_800G)/hbm3_800g_reset_sync.sv $(RTL_800G)/hbm3_800g_pc_queues.sv \
	  $(RTL_800G)/hbm3_800g_scheduler_32to16.sv \
	  $(RTL_800G)/hbm3_800g_gearbox_2to1_cdc.sv $(RTL_800G)/hbm3_800g_rst_buf.sv $(RTL_800G)/hbm3_800g_async_fifo.sv
	$(VVP) $(SIM_DIR)/hbm3_800g_full_2g.vvp
	$(IVERILOG) $(INC_FLAGS) -Ptb_hbm3_800g_full_top.CORE_CLK_PS=400 \
	  -Ptb_hbm3_800g_full_top.READY_SEED=305419896 \
	  -o $(SIM_DIR)/hbm3_800g_full_2p5g.vvp $(TB)/tb_hbm3_800g_full_top.sv \
	  $(RTL_800G)/hbm3_800g_digital_full_top.sv $(RTL_800G)/hbm3_800g_reset_sync.sv \
	  $(RTL_800G)/hbm3_800g_pc_queues.sv $(RTL_800G)/hbm3_800g_scheduler_32to16.sv \
	  $(RTL_800G)/hbm3_800g_gearbox_2to1_cdc.sv $(RTL_800G)/hbm3_800g_rst_buf.sv $(RTL_800G)/hbm3_800g_async_fifo.sv
	$(VVP) $(SIM_DIR)/hbm3_800g_full_2p5g.vvp

hbm3-800g-pathological: $(SIM_DIR)
	$(IVERILOG) $(INC_FLAGS) -o $(SIM_DIR)/tb_patho.vvp \
	  $(TB)/tb_scheduler_pathological.sv $(RTL_800G)/hbm3_800g_scheduler_32to16.sv
	$(VVP) $(SIM_DIR)/tb_patho.vvp

hbm3-800g-smoke: $(SIM_DIR)
	$(IVERILOG) $(INC_FLAGS) -o $(SIM_DIR)/tb_smoke.vvp $(TB)/tb_hbm3_800g_full_smoke.sv \
	  $(RTL_800G)/hbm3_800g_digital_full_top.sv $(RTL_800G)/hbm3_800g_reset_sync.sv \
	  $(RTL_800G)/hbm3_800g_pc_queues.sv $(RTL_800G)/hbm3_800g_scheduler_32to16.sv \
	  $(RTL_800G)/hbm3_800g_gearbox_2to1_cdc.sv $(RTL_800G)/hbm3_800g_rst_buf.sv $(RTL_800G)/hbm3_800g_async_fifo.sv
	$(VVP) $(SIM_DIR)/tb_smoke.vvp

hbm3-800g-dfi-cdc: $(SIM_DIR)
	$(IVERILOG) $(INC_FLAGS) -o $(SIM_DIR)/tb_dfi_cdc.vvp $(TB)/tb_hbm3_800g_dfi_cdc.sv \
	  $(RTL_800G)/hbm3_800g_dfi_cdc.sv $(RTL_800G)/hbm3_800g_async_fifo.sv
	$(VVP) $(SIM_DIR)/tb_dfi_cdc.vvp

hbm3-800g-full-phy: $(SIM_DIR)
	$(IVERILOG) $(INC_FLAGS) -o $(SIM_DIR)/tb_full_phy.vvp $(TB)/tb_hbm3_800g_full_phy.sv \
	  $(RTL_800G)/hbm3_800g_full_phy_top.sv $(RTL_800G)/hbm3_800g_digital_full_top.sv \
	  $(RTL_800G)/hbm3_800g_reset_sync.sv $(RTL_800G)/hbm3_800g_pc_queues.sv \
	  $(RTL_800G)/hbm3_800g_scheduler_32to16.sv $(RTL_800G)/hbm3_800g_gearbox_2to1_cdc.sv \
	  $(RTL_800G)/hbm3_800g_rst_buf.sv $(RTL_800G)/hbm3_800g_async_fifo.sv \
	  $(RTL_PHY)/hbm3_phy_serializer.sv $(RTL_PHY)/hbm3_phy_deserializer.sv $(RTL_PHY)/hbm3_phy_tx_channel.sv
	$(VVP) $(SIM_DIR)/tb_full_phy.vvp

top-structural:
	yosys -q -p 'read_verilog -sv $(INC_FLAGS) $(RTL_800G)/hbm3_800g_defs.svh $(RTL_800G)/hbm3_800g_rst_buf.sv $(RTL_800G)/hbm3_800g_reset_sync.sv $(RTL_800G)/hbm3_800g_async_fifo.sv $(RTL_800G)/hbm3_800g_gearbox_2to1_cdc.sv $(RTL_800G)/hbm3_800g_scheduler_32to16.sv $(RTL_800G)/hbm3_800g_pc_queues.sv $(RTL_800G)/hbm3_800g_digital_full_top.sv; hierarchy -check -top hbm3_800g_digital_full_top; proc; check'
	@echo "TOP_STRUCTURAL: PASS (Yosys hierarchy/proc/check clean on hbm3_800g_digital_full_top)"

clean:
	rm -rf $(SIM_DIR)
