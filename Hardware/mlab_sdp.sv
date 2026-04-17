// =============================================================================
// mlab_sdp.sv — Simple Dual-Port RAM, MLAB (asynchroner Lesepfad)
//
// Hilfsbaustein für Cyclone V / DE10-Nano:
//   - Port A: synchrones Schreiben (taktflankengetriggert)
//   - Port B: asynchrones Lesen  (kombinatorisch, 0 Takte Latenz)
//
// Warum dieses Modul?
//   Die Hack-CPU ist Single-Cycle: mem_in muss im selben Takt verfügbar
//   sein wie mem_addr. Das erfordert 0-Latenz-RAM. Auf Cyclone V bieten
//   MLAB-Zellen (LUTRAM) asynchrone Lesepfade — aber nur wenn dies über
//   altsyncram explizit angefordert wird. Quartus' Inferenzpfad lehnt
//   MLAB ab, sobald Schreib- und Leseadresse denselben Wert annehmen
//   können (read-during-write-Konflikt). Die direkte altsyncram-
//   Instanziierung umgeht dieses Problem.
//
// Auf anderen FPGA-Familien:
//   Ersetze durch äquivalente plattformspezifische Primitive oder
//   passe die CPU auf einen 2-Takt-Zyklus an (M10K-kompatibel).
//
// Portierungshinweis (Stufe A, andere Boards):
//   - ECP5 / iCE40: lpm_ram_dp mit async read oder äquivalente Primitive
//   - Xilinx/AMD:   RAMB-Primitiv im SDP-Modus mit asynchronem Ausgang
//   - Gowin:        DPR_S (simple dual-port) mit kombinatorischem Lesen
//
// Autor:  Sebastian Schwiebert
// Lizenz: MIT
// HDL:    SystemVerilog IEEE 1800-2005
// =============================================================================
module mlab_sdp #(
    parameter int WIDTH  = 16,
    parameter int DEPTH  = 16384,
    parameter int AWIDTH = 14
) (
    input  logic              clk,

    // Port A: Schreiben (synchron)
    input  logic [AWIDTH-1:0] wraddr,
    input  logic [WIDTH-1:0]  wrdata,
    input  logic              wren,

    // Port B: Lesen (asynchron/kombinatorisch)
    input  logic [AWIDTH-1:0] rdaddr,
    output logic [WIDTH-1:0]  rddata
);
    // -------------------------------------------------------------------------
    // altsyncram: Simple Dual-Port, MLAB, asynchroner Lesepfad (Port B)
    //
    // ram_block_type="MLAB"      → erzwingt LUTRAM auf Cyclone V
    // outdata_reg_b="UNREGISTERED" → Port B gibt Daten kombinatorisch aus
    // read_during_write="OLD_DATA" → bei gleichzeitigem R/W auf selbe Adresse:
    //                               Port B liefert den ALTEN Wert (sicher für
    //                               Single-Cycle CPU, da Write in eigenem Takt)
    // -------------------------------------------------------------------------
    altsyncram #(
        .operation_mode                    ("DUAL_PORT"),
        .width_a                           (WIDTH),
        .widthad_a                         (AWIDTH),
        .numwords_a                        (DEPTH),
        .width_b                           (WIDTH),
        .widthad_b                         (AWIDTH),
        .numwords_b                        (DEPTH),
        .outdata_reg_b                     ("UNREGISTERED"),
        .read_during_write_mode_mixed_ports("DONT_CARE"),
        .ram_block_type                    ("MLAB"),
        .intended_device_family            ("Cyclone V"),
        .clock_enable_input_a              ("BYPASS"),
        .clock_enable_input_b              ("BYPASS"),
        .clock_enable_output_b             ("BYPASS"),
        .power_up_uninitialized            ("TRUE")
    ) u_altsyncram (
        .clock0        (clk),
        .wren_a        (wren),
        .address_a     (wraddr),
        .data_a        (wrdata),
        .address_b     (rdaddr),
        .q_b           (rddata),
        // Port B ist Read-Only in DUAL_PORT-Modus
        .wren_b        (1'b0),
        .rden_b        (1'b1),
        .data_b        ({WIDTH{1'b0}}),
        // clock1: Port-B-Takt — auf clk setzen (selbe Domäne wie Port A)
        .clock1        (clk),
        .clocken0      (1'b1),
        .clocken1      (1'b1),
        .clocken2      (1'b1),
        .clocken3      (1'b1),
        .aclr0         (1'b0),
        .aclr1         (1'b0),
        .addressstall_a(1'b0),
        .addressstall_b(1'b0),
        .byteena_a     (1'b1),
        .byteena_b     (1'b1),
        // Ungenutzte Ausgänge
        .q_a           (),
        .eccstatus     ()
    );

endmodule
