// =============================================================================
// hack_rom.sv — Instruction Memory (ROM) des Atlas 16
//
// Architektur-Spezifikation:
//   Nisan & Schocken, "The Elements of Computing Systems", 2nd Ed., MIT Press
//   https://www.nand2tetris.org
// Die SystemVerilog-Implementierung ist eigenständige Arbeit des Autors.
//
// Speichert das Hack+-Programm als 32.768 × 16-bit Worte (64 KB).
// Wird beim Start vom HPS über die Mailbox-Bridge befüllt.
// Der Instruction Bus ist vom Data Bus physisch getrennt (Harvard).
//
// Synthese: Quartus inferiert automatisch einen oder mehrere M10K
//           Block-RAM-Blöcke für dieses Modul.
//
// Autor:  Sebastian Schwiebert
// Lizenz: MIT
// HDL:    SystemVerilog IEEE 1800-2005
// =============================================================================
module hack_rom #(
    parameter integer ROM_DEPTH      = 32768, // 32K Instruktionen = 64 KB
    parameter         ROM_INIT_FILE  = "",    // $readmemh-Datei (nur Simulation)
    parameter integer USE_TEST_ROM   = 0      // 1 = rom_test.hex in Synthese laden
) (
    input  logic        clk,

    // -------------------------------------------------------------------------
    // Lese-Port: von der CPU (synchron, 1 Takt Latenz)
    // Der PC ist 15-bit, adressiert 0x0000–0x7FFF
    // -------------------------------------------------------------------------
    input  logic [14:0] pc,
    output logic [15:0] instruction,

    // -------------------------------------------------------------------------
    // Schreib-Port: vom HPS-Loader (über Mailbox)
    // -------------------------------------------------------------------------
    input  logic [14:0] wr_addr,
    input  logic [15:0] wr_data,
    input  logic        wr_en
);
    // -------------------------------------------------------------------------
    // Speicher-Array
    // 'logic' Array → Quartus inferiert M10K Block-RAM (2-Port)
    // -------------------------------------------------------------------------
    logic [15:0] rom_mem [0:ROM_DEPTH-1];

    // -------------------------------------------------------------------------
    // ROM-Initialisierung
    //
    // USE_TEST_ROM=1: Quartus lädt rom_test.hex als String-Literal in die
    //                 M10K-BRAMs (Synthese). Funktioniert nur mit Literal,
    //                 nicht mit String-Parametern.
    // ROM_INIT_FILE:  Wird nur in der Simulation ausgewertet ($readmemh).
    // -------------------------------------------------------------------------
    generate
        if (USE_TEST_ROM) begin : gen_test_rom
            initial $readmemh("rom_test.hex", rom_mem);
        end else begin : gen_sim_rom
            initial begin
                if (ROM_INIT_FILE != "")
                    $readmemh(ROM_INIT_FILE, rom_mem);
            end
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Synchrones Lesen — 1 Taktzyklus Latenz
    // (entspricht dem Verhalten echter Block-RAMs auf dem Cyclone V)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        instruction <= rom_mem[pc];
    end

    // -------------------------------------------------------------------------
    // Synchrones Schreiben — nur durch HPS-Loader
    // Im Normalbetrieb ist wr_en = 0 → ROM ist effektiv read-only
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (wr_en)
            rom_mem[wr_addr] <= wr_data;
    end

endmodule
