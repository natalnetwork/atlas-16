# =============================================================================
# atlas16_a.sdc — Timing Constraints für Atlas 16, Stufe A
# Plattform: Terasic DE10-Nano (Intel Cyclone V 5CSEBA6U23I7)
# =============================================================================

# Systemtakt: 50 MHz (DE10-Nano CLOCK_50, PIN_V11)
create_clock -name clk_50 -period 20.0 [get_ports CLOCK_50]

# Pixeltakt: 25 MHz (abgeleitet per clk_div Flip-Flop aus clk_50)
# Hinweis: Für stabilen Betrieb eine PLL verwenden (TODO Stufe A+)
create_generated_clock \
    -name clk_25 \
    -source [get_ports CLOCK_50] \
    -divide_by 2 \
    [get_registers {clk_div}]

# Asynchrone Übergänge zwischen den zwei Taktdomänen deklarieren.
# clk_50 → clk_25: fb_rd_addr (VGA liest FB-Adresse, die von clk_25 kommt)
# clk_25 → clk_50: keine direkten Übergänge
set_clock_groups -asynchronous -group {clk_50} -group {clk_25}

# I/O-Delay: unkritisch für diese Verifikationsstufe
# HDMI-Ausgänge sind über mehrere Takte stabil
set_false_path -from [get_ports {KEY[*]}]
set_false_path -to   [get_ports {HDMI_TX_*}]
