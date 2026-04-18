# =============================================================================
# hps_rom_loader_hw.tcl — Platform Designer Komponente für den HPS-ROM-Loader
# =============================================================================
package require -exact qsys 13.1

set_module_property NAME         hps_rom_loader
set_module_property VERSION      1.0
set_module_property DISPLAY_NAME "HPS ROM Loader"
set_module_property DESCRIPTION  "Avalon-MM Register-Interface: laedt Hack-Programme in den Instruction ROM"
set_module_property AUTHOR       "Sebastian Schwiebert"
set_module_property ANALYZE_HDL  AUTO

add_fileset QUARTUS_SYNTH QUARTUS_SYNTH "" ""
set_fileset_property QUARTUS_SYNTH TOP_LEVEL hps_rom_loader
add_fileset_file hps_rom_loader.sv SYSTEM_VERILOG PATH hps_rom_loader.sv TOP_LEVEL_FILE

# ---------------------------------------------------------------------------
# Takt
# ---------------------------------------------------------------------------
add_interface clock_sink clock end
set_interface_property clock_sink clockRate 0
set_interface_property clock_sink ENABLED true
add_interface_port clock_sink clk clk Input 1

# ---------------------------------------------------------------------------
# Reset
# ---------------------------------------------------------------------------
add_interface reset_sink reset end
set_interface_property reset_sink associatedClock clock_sink
set_interface_property reset_sink synchronousEdges DEASSERT
set_interface_property reset_sink ENABLED true
add_interface_port reset_sink rst reset Input 1

# ---------------------------------------------------------------------------
# Avalon-MM Slave (3 Wort-Register)
# ---------------------------------------------------------------------------
add_interface slave avalon end
set_interface_property slave associatedClock   clock_sink
set_interface_property slave associatedReset   reset_sink
set_interface_property slave addressAlignment  NATIVE
set_interface_property slave addressUnits      WORDS
set_interface_property slave readLatency       1
set_interface_property slave ENABLED           true
add_interface_port slave avs_address   address   Input  2
add_interface_port slave avs_write     write     Input  1
add_interface_port slave avs_writedata writedata Input  32
add_interface_port slave avs_readdata  readdata  Output 32

# ---------------------------------------------------------------------------
# Conduit: ROM-Schreibport + CPU-Steuerung
# ---------------------------------------------------------------------------
add_interface rom_ctrl conduit end
set_interface_property rom_ctrl ENABLED true
add_interface_port rom_ctrl rom_wr_addr rom_wr_addr Output 15
add_interface_port rom_ctrl rom_wr_data rom_wr_data Output 16
add_interface_port rom_ctrl rom_wr_en   rom_wr_en   Output  1
add_interface_port rom_ctrl cpu_resetN  cpu_resetN  Output  1
