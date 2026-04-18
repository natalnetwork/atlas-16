// =============================================================================
// hack_ram_a.sv — Datenspeicher des Atlas 16 (Stufe A: Hack-kompatibel)
//
// Architektur-Spezifikation:
//   Nisan & Schocken, "The Elements of Computing Systems", 2nd Ed., MIT Press
//   https://www.nand2tetris.org
// Die SystemVerilog-Implementierung ist eigenständige Arbeit des Autors.
//
// Implementiert den Datenspeicher-Adressraum für Stufe A:
//
//   0x0000–0x3FFF  RAM  (16 KB, Hack-kompatibel)
//   0x4000–0x5FFF  Framebuffer (8192 × 16-bit, 512×256 Pixel @ 1bpp)
//   0x6000         Keyboard (read-only, Hack-kompatibel)
//   0x6001–0x7FFF  Peripherie-Register (werden an Toplevel weitergereicht)
//
// Speicherimplementierung (Cyclone V / DE10-Nano):
//   Die Hack-CPU ist Single-Cycle: mem_in muss im selben Takt verfügbar sein
//   wie mem_addr. Daher wird mlab_sdp.sv (LUTRAM, 0 Takte Latenz) verwendet.
//   Auf anderen Plattformen: entweder mlab_sdp.sv anpassen (plattformspezifisch)
//   oder die CPU auf 2-Takt-Pipeline umstellen (M10K-kompatibel, portabel).
//
// Referenz: [N2T] Kapitel 5, Abschnitt 5.2.3 (Memory)
//
// Autor:  Sebastian Schwiebert
// Lizenz: MIT
// HDL:    SystemVerilog IEEE 1800-2005
// =============================================================================
module hack_ram_a (
    input  logic        clk,
    input  logic        rst,

    // -------------------------------------------------------------------------
    // CPU-Interface
    // -------------------------------------------------------------------------
    input  logic [15:0] address,
    input  logic [15:0] data_in,
    input  logic        write_en,
    output logic [15:0] data_out,

    // -------------------------------------------------------------------------
    // Keyboard-Eingang (Hack-kompatibel: Adresse 0x6000)
    // -------------------------------------------------------------------------
    input  logic [15:0] keyboard_in,

    // -------------------------------------------------------------------------
    // Framebuffer-Lesepfad für VGA-Controller (kombinatorisch, 0 Latenz)
    // Adresse: img_y * 32 + (img_x / 16)
    // -------------------------------------------------------------------------
    input  logic [12:0] fb_rd_addr,
    output logic [15:0] fb_rd_data,

    // -------------------------------------------------------------------------
    // Peripherie-Weiterleitungs-Interface (0x6001–0x7FFF)
    // -------------------------------------------------------------------------
    output logic [15:0] per_addr,
    output logic [15:0] per_data,
    output logic        per_write,
    input  logic [15:0] per_read
);
    // -------------------------------------------------------------------------
    // Adressbereiche
    // -------------------------------------------------------------------------
    localparam logic [15:0] RAM_END  = 16'h3FFF;
    localparam logic [15:0] FB_START = 16'h4000;
    localparam logic [15:0] FB_END   = 16'h5FFF;
    localparam logic [15:0] KBD_ADDR = 16'h6000;
    localparam logic [15:0] PER_END  = 16'h7FFF;

    // -------------------------------------------------------------------------
    // RAM: 16 KB — MLAB Simple Dual-Port (asynchroner Lesepfad)
    // Schreib- und Leseadresse sind strukturell getrennte Ports → MLAB-Inferenz
    // -------------------------------------------------------------------------
    logic [15:0] ram_data;

    mlab_sdp #(
        .WIDTH  (16),
        .DEPTH  (16384),
        .AWIDTH (14)
    ) u_ram (
        .clk    (clk),
        .wraddr (address[13:0]),
        .wrdata (data_in),
        .wren   (write_en && (address <= RAM_END)),
        .rdaddr (address[13:0]),  // gleicher Wert, aber strukturell getrennter Port
        .rddata (ram_data)
    );

    // -------------------------------------------------------------------------
    // Framebuffer: 8 KB — MLAB Simple Dual-Port
    // Schreiben: CPU (address[12:0])  — Lesen: VGA (fb_rd_addr, immer anders)
    // -------------------------------------------------------------------------
    mlab_sdp #(
        .WIDTH  (16),
        .DEPTH  (8192),
        .AWIDTH (13)
    ) u_fb (
        .clk    (clk),
        .wraddr (address[12:0]),
        .wrdata (data_in),
        .wren   (write_en && (address >= FB_START) && (address <= FB_END)),
        .rdaddr (fb_rd_addr),   // VGA-Leseadresse — strukturell getrennt
        .rddata (fb_rd_data)
    );

    // -------------------------------------------------------------------------
    // Peripherie-Bus weiterleiten (kombinatorisch)
    // -------------------------------------------------------------------------
    assign per_addr  = address;
    assign per_data  = data_in;
    assign per_write = write_en && (address > KBD_ADDR) && (address <= PER_END);

    // -------------------------------------------------------------------------
    // CPU-Lesemultiplexer (kombinatorisch)
    // -------------------------------------------------------------------------
    always_comb begin
        if (address <= RAM_END)
            data_out = ram_data;
        else if (address >= FB_START && address <= FB_END)
            data_out = 16'h0000;        // Framebuffer: write-only für CPU
        else if (address == KBD_ADDR)
            data_out = keyboard_in;
        else if (address <= PER_END)
            data_out = per_read;
        else
            data_out = 16'hDEAD;
    end

endmodule
