// =============================================================================
// hack_top_a.sv — Toplevel des Atlas 16, Stufe A (Hack-kompatibel)
//
// Stufe A implementiert den Hack-kompatiblen Kern:
//   - Hack CPU (unveränderte N2T-Architektur)
//   - Instruction ROM (32 KB BRAM, per HPS ladbar)
//   - Data RAM + Framebuffer (16 KB RAM + 8 KB FB, MLAB)
//   - VGA/HDMI-Ausgabe (512×256, 1bpp, zentriert in 640×480)
//   - Tastatur-Eingang (via HPS-Mailbox, Hack-kompatibel 0x6000)
//
// Nicht enthalten (Stufe B/C):
//   SDRAM, Sprites, Blitter, Sound, UART, RTC, Timer
//
// Plattform: Terasic DE10-Nano (Intel Cyclone V 5CSEBA6U23I7)
//
// HPS-Hinweis:
//   Die HPS-Schnittstelle (Keyboard-Input, ROM-Loader) erfordert einen
//   Platform-Designer-Block (altera_hps) — die LW-AXI-Bridge ist eine
//   interne HPS↔FPGA-Verbindung, keine externen I/O-Pins.
//   Dieses Toplevel stubbt die HPS-Ports für die initiale FPGA-Verifikation:
//   Der ROM startet leer (CPU hält sich im Reset-Zustand), Keyboard = 0.
//
// Hinweis ADV7513:
//   Der HDMI-Chip muss vor dem ersten Bild per I2C initialisiert werden.
//   Auf dem DE10-Nano geschieht dies vom HPS aus:
//     i2cset -y 1 0x39 0x41 0x10   (Power up)
//     i2cset -y 1 0x39 0xAF 0x06   (HDMI-Modus)
//
// Autor:  Sebastian Schwiebert
// Lizenz: MIT
// HDL:    SystemVerilog IEEE 1800-2005
// =============================================================================
module hack_top_a (
    // -------------------------------------------------------------------------
    // DE10-Nano Basistakt und Reset
    // -------------------------------------------------------------------------
    input  logic        CLOCK_50,       // 50 MHz Systemtakt
    input  logic  [1:0] KEY,            // KEY[0] = Reset (aktiv-niedrig)

    // -------------------------------------------------------------------------
    // HDMI-Ausgabe (an ADV7513)
    // -------------------------------------------------------------------------
    output logic        HDMI_TX_CLK,
    output logic        HDMI_TX_DE,
    output logic        HDMI_TX_HS,
    output logic        HDMI_TX_VS,
    output logic [23:0] HDMI_TX_D,

    // -------------------------------------------------------------------------
    // HDMI I2C (ADV7513-Konfiguration, Open-Drain via FPGA-Pins)
    // -------------------------------------------------------------------------
    output logic        HDMI_I2C_SCL,
    inout  wire         HDMI_I2C_SDA
);
    // =========================================================================
    // Takte und Reset
    // =========================================================================
    logic clk;          // 50 MHz CPU-Takt
    logic clk_25mhz;    // 25 MHz VGA-Pixeltakt (50 MHz / 2)
    logic rst;          // Synchroner Reset (aktiv-hoch)

    assign clk = CLOCK_50;
    assign rst = ~KEY[0];   // KEY[0] gedrückt (low) = Reset

    // 25 MHz Pixeltakt: einfacher Teiler durch 2
    // Für exaktes 25,175 MHz eine PLL verwenden (Quartus IP)
    logic clk_div;
    always_ff @(posedge clk) clk_div <= ~clk_div;
    assign clk_25mhz = clk_div;

    // =========================================================================
    // CPU ↔ Memory Signale
    // =========================================================================
    logic [14:0] cpu_pc;
    logic [15:0] cpu_instruction;
    logic [15:0] cpu_mem_addr;
    logic [15:0] cpu_mem_out;
    logic        cpu_mem_write;
    logic [15:0] cpu_mem_in;

    // =========================================================================
    // Framebuffer-Verbindung (hack_ram_a → vga_ctrl_a)
    // =========================================================================
    logic [12:0] fb_rd_addr;
    logic [15:0] fb_rd_data;

    // =========================================================================
    // Hack-CPU instanziieren
    // =========================================================================
    hack_cpu cpu_inst (
        .clk         (clk),
        .rst         (rst),
        .instruction (cpu_instruction),
        .mem_in      (cpu_mem_in),
        .mem_out     (cpu_mem_out),
        .mem_addr    (cpu_mem_addr),
        .mem_write   (cpu_mem_write),
        .pc          (cpu_pc)
    );

    // =========================================================================
    // Instruction ROM instanziieren
    // =========================================================================
    hack_rom #(
        .ROM_DEPTH    (256),  // Entwicklung: 256 statt 32768 → 2 M10K statt 52, viel schnellere Kompilierung
        .USE_TEST_ROM (1)
    ) rom_inst (
        .clk         (clk),
        .pc          (cpu_pc),
        .instruction (cpu_instruction),
        .wr_addr     (15'h0),
        .wr_data     (16'h0),
        .wr_en       (1'b0)
    );

    // =========================================================================
    // Data RAM + Framebuffer instanziieren (Stufe A)
    // =========================================================================
    hack_ram_a ram_inst (
        .clk         (clk),
        .rst         (rst),
        .address     (cpu_mem_addr),
        .data_in     (cpu_mem_out),
        .write_en    (cpu_mem_write),
        .data_out    (cpu_mem_in),
        .keyboard_in (16'h0000),        // Stufe A standalone: kein Keyboard
        .fb_rd_addr  (fb_rd_addr),
        .fb_rd_data  (fb_rd_data),
        .per_addr    (),
        .per_data    (),
        .per_write   (),
        .per_read    (16'h0000)
    );

    // =========================================================================
    // VGA/HDMI-Controller instanziieren (Stufe A, 1bpp)
    // =========================================================================
    vga_ctrl_a vga_inst (
        .clk_25mhz  (clk_25mhz),
        .rst        (rst),
        .fb_rd_addr (fb_rd_addr),
        .fb_rd_data (fb_rd_data),
        .hsync      (HDMI_TX_HS),
        .vsync      (HDMI_TX_VS),
        .de         (HDMI_TX_DE),
        .hdmi_d     (HDMI_TX_D),
        .hcount     (),
        .vcount     ()
    );

    // HDMI_TX_CLK invertiert: Daten wechseln wenn CLK fällt, ADV7513 sampelt
    // wenn CLK steigt → 20 ns Setup-Zeit (halbe 25-MHz-Periode)
    assign HDMI_TX_CLK = ~clk_25mhz;

    // =========================================================================
    // ADV7513 I2C-Initialisierung
    // =========================================================================
    logic i2c_scl, i2c_sda_out, i2c_sda_oe;

    hdmi_i2c_init i2c_inst (
        .clk     (clk),
        .rst     (rst),
        .scl     (i2c_scl),
        .sda_out (i2c_sda_out),
        .sda_oe  (i2c_sda_oe)
    );

    assign HDMI_I2C_SCL = i2c_scl;
    // Open-Drain: treibt 0 wenn sda_oe=1, sonst Z (Pull-Up am Board)
    assign HDMI_I2C_SDA = (i2c_sda_oe && !i2c_sda_out) ? 1'b0 : 1'bz;

endmodule
