# =============================================================================
# add_rom_loader.tcl — Ergänzt hps_rom_loader in das GHRD-basierte HPS-System
#
# Verwendung:
#   qsys-script --script=add_rom_loader.tcl \
#     --search-path="../../Hardware/hps_loader/,$" \
#     --system-file=hack_hps_sys.qsys
# =============================================================================
package require -exact qsys 16.1

# ROM Loader hinzufügen
add_instance rom_loader hps_rom_loader 1.0

# Takt und Reset (gleiche Quelle wie led_pio, dipsw_pio im GHRD)
add_connection clk_0.clk       rom_loader.clock_sink
add_connection clk_0.clk_reset rom_loader.reset_sink

# An den Avalon-Interconnect (mm_bridge_0) hängen — Adresse 0x8000
# (led_pio=0x3000, dipsw_pio=0x4000, button_pio=0x5000 sind schon belegt)
add_connection mm_bridge_0.m0 rom_loader.slave
set_connection_parameter_value mm_bridge_0.m0/rom_loader.slave baseAddress 0x00008000

# ROM-Konduit nach außen exportieren
add_interface rom_ctrl conduit end
set_interface_property rom_ctrl EXPORT_OF rom_loader.rom_ctrl

save_system
