// =============================================================================
// hack_ram.sv — Datenspeicher des Atlas 16
//
// Implementiert den vollständigen Datenspeicher-Adressraum:
//
//   0x0000–0x3FFF  RAM (16 KB, Hack-kompatibel)
//   0x4000–0x5FFF  Framebuffer-Fenster (wird an VGA weitergereicht)
//   0x6000         Keyboard (read-only, Hack-kompatibel)
//   0x6001–0x6FFF  Peripherie-Register (werden weitergereicht)
//   0x7000–0x7FFF  Bank-Fenster (über Bank-Controller ins SDRAM)
//
// Referenz: [N2T] Kapitel 5, Abschnitt 5.2.3 (Memory)
//
// Autor:  Sebastian Schwiebert
// Lizenz: MIT
// HDL:    SystemVerilog IEEE 1800-2005
// =============================================================================
module hack_ram (
    input  logic        clk,
    input  logic        rst,

    // -------------------------------------------------------------------------
    // CPU-Interface (vom Bus-Arbiter)
    // -------------------------------------------------------------------------
    input  logic [15:0] address,
    input  logic [15:0] data_in,
    input  logic        write_en,
    output logic [15:0] data_out,

    // -------------------------------------------------------------------------
    // Keyboard-Eingang (Hack-kompatibel: Adresse 0x6000)
    // Der Tastatur-Scan-Code wird extern eingespeist
    // -------------------------------------------------------------------------
    input  logic [15:0] keyboard_in,

    // -------------------------------------------------------------------------
    // Framebuffer-Fenster-Interface (0x4000–0x5FFF)
    // Schreibzugriffe in diesem Bereich gehen an den VGA-Controller
    // -------------------------------------------------------------------------
    output logic [12:0] fb_addr,    // Adresse innerhalb des Framebuffers
    output logic [15:0] fb_data,    // Schreibdaten
    output logic        fb_write,   // Schreibfreigabe für Framebuffer

    // -------------------------------------------------------------------------
    // Peripherie-Weiterleitungs-Interface (0x6001–0x7FFF)
    // Der Bus-Arbiter/Toplevel leitet diese an die richtigen Module weiter
    // -------------------------------------------------------------------------
    output logic [15:0] per_addr,   // Adresse (relativ zu 0x6000)
    output logic [15:0] per_data,   // Schreibdaten
    output logic        per_write,  // Schreibfreigabe
    input  logic [15:0] per_read    // Lesedaten vom Peripherie-Decoder
);
    // -------------------------------------------------------------------------
    // RAM: 16 KB = 16.384 × 16-bit Worte
    // Quartus inferiert M10K Block-RAMs
    // -------------------------------------------------------------------------
    localparam int RAM_SIZE = 16384;
    logic [15:0] ram [0:RAM_SIZE-1];

    // -------------------------------------------------------------------------
    // Adressbereiche als lokale Parameter (verbessert Lesbarkeit)
    // -------------------------------------------------------------------------
    localparam logic [15:0] RAM_END  = 16'h3FFF;
    localparam logic [15:0] FB_START = 16'h4000;
    localparam logic [15:0] FB_END   = 16'h5FFF;
    localparam logic [15:0] KBD_ADDR = 16'h6000;
    localparam logic [15:0] PER_END  = 16'h7FFF;

    // -------------------------------------------------------------------------
    // Synchrones Schreiben in den RAM
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (write_en && address <= RAM_END)
            ram[address[13:0]] <= data_in;
    end

    // -------------------------------------------------------------------------
    // Framebuffer-Fenster weiterleten (kombinatorisch)
    // -------------------------------------------------------------------------
    assign fb_addr  = address[12:0];
    assign fb_data  = data_in;
    assign fb_write = write_en && (address >= FB_START) && (address <= FB_END);

    // -------------------------------------------------------------------------
    // Peripherie-Bus weiterleiten (kombinatorisch)
    // -------------------------------------------------------------------------
    assign per_addr  = address;
    assign per_data  = data_in;
    assign per_write = write_en && (address > KBD_ADDR) && (address <= PER_END);

    // -------------------------------------------------------------------------
    // Lesemultiplexer (kombinatorisch)
    // Wählt die richtige Datenquelle je nach Adressbereich
    // -------------------------------------------------------------------------
    always_comb begin
        if (address <= RAM_END)
            data_out = ram[address[13:0]];
        else if (address >= FB_START && address <= FB_END)
            data_out = 16'h0000;    // Framebuffer ist write-only für CPU
        else if (address == KBD_ADDR)
            data_out = keyboard_in; // Hack Keyboard (0x6000)
        else if (address <= PER_END)
            data_out = per_read;    // Peripherie-Decoder
        else
            data_out = 16'hDEAD;   // undefinierter Bereich
    end

endmodule
