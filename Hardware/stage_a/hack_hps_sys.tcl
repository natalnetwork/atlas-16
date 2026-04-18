# =============================================================================
# hack_hps_sys.tcl — Platform Designer System für den Atlas 16 HPS-Loader
#
# Enthält:
#   - Cyclone V HPS (Lightweight HPS-to-FPGA Bridge aktiviert)
#   - hps_rom_loader (Avalon-MM Slave, 3 Register)
#
# Generierung:
#   qsys-script --script=hack_hps_sys.tcl --quartus-project=hack
#   qsys-generate hack_hps_sys.qsys --synthesis=VERILOG --output-directory=hack_hps_sys
#
# Autor:  Sebastian Schwiebert
# Lizenz: MIT
# =============================================================================
package require -exact qsys 16.1

create_system hack_hps_sys

set_project_property DEVICE_FAMILY {Cyclone V}
set_project_property DEVICE        {5CSEBA6U23I7}

# ---------------------------------------------------------------------------
# Taktquelle (50 MHz vom FPGA-Board)
# ---------------------------------------------------------------------------
add_instance clk_50 clock_source
set_instance_parameter_value clk_50 clockFrequency      50000000
set_instance_parameter_value clk_50 clockFrequencyKnown true
set_instance_parameter_value clk_50 resetSynchronousEdges DEASSERT

# ---------------------------------------------------------------------------
# HPS — nur Lightweight Bridge aktiviert, alles andere minimal
# ---------------------------------------------------------------------------
add_instance hps_0 altera_hps
set_instance_parameter_value hps_0 HPS_PROTOCOL    {JTAG}
set_instance_parameter_value hps_0 F2S_Width        0
set_instance_parameter_value hps_0 S2F_Width        0
set_instance_parameter_value hps_0 LWH2F_Enable     true

# HPS Takt/Reset von Systemtakt
add_connection clk_50.clk       hps_0.h2f_lw_axi_clock
add_connection clk_50.clk_reset hps_0.h2f_reset

# ---------------------------------------------------------------------------
# ROM Loader — Avalon-MM Slave
# ---------------------------------------------------------------------------
add_instance rom_loader hps_rom_loader
set_instance_parameter_value rom_loader {}

add_connection clk_50.clk       rom_loader.clk
add_connection clk_50.clk_reset rom_loader.rst

# HPS Lightweight Bridge → ROM Loader (Platform Designer fügt AXI→Avalon ein)
add_connection hps_0.h2f_lw_axi_master rom_loader.s0
set_connection_parameter_value hps_0.h2f_lw_axi_master/rom_loader.s0 baseAddress 0x0000

# ---------------------------------------------------------------------------
# Exports: Takt, Reset, ROM-Konduit
# ---------------------------------------------------------------------------
add_interface clk_50_in    clock    Input
set_interface_property clk_50_in    EXPORT_OF clk_50.clk_in
add_interface clk_50_reset reset    Input
set_interface_property clk_50_reset EXPORT_OF clk_50.clk_in_reset

add_interface hps_io       conduit  end
set_interface_property hps_io       EXPORT_OF hps_0.hps_io

add_interface rom_ctrl     conduit  end
set_interface_property rom_ctrl     EXPORT_OF rom_loader.rom_ctrl

# ---------------------------------------------------------------------------
# System speichern
# ---------------------------------------------------------------------------
save_system hack_hps_sys.qsys
