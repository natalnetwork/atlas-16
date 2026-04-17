// =============================================================================
// hack_cpu.sv
// Atlas 16 – Hack+ CPU Core
//
// Implementierung der originalen Hack CPU aus "Nand2Tetris" (Kapitel 5).
// Diese Datei bleibt absichtlich unverändert gegenüber der Hack-Spezifikation,
// um vollständige Rückwärtskompatibilität zu gewährleisten.
//
// ISA Übersicht:
//   A-Instruction: 0vvvvvvvvvvvvvvv  → lade 15-bit Wert in Register A
//   C-Instruction: 111accccccdddjjj  → ALU-Operation, Ziel, Sprung
//
// Autor:    Sebastian Schwiebert
// Projekt:  Atlas 16 / Hack+ Architektur
// HDL:      SystemVerilog IEEE 1800-2005
// =============================================================================

// -----------------------------------------------------------------------------
// Paket: Gemeinsame Typdefinitionen für die Hack CPU
// -----------------------------------------------------------------------------
package hack_cpu_pkg;

    // Instruktionstyp
    typedef enum logic {
        A_INST = 1'b0,   // Bit 15 = 0
        C_INST = 1'b1    // Bit 15 = 1
    } inst_type_t;

    // C-Instruction Felder (Bits 15..0)
    // [15]   = 1 (C-Instruction Kennzeichen)
    // [14:13]= 11 (immer gesetzt in Hack)
    // [12]   = a-Bit: 0=ALU liest A-Register, 1=ALU liest Memory
    // [11:6] = comp: ALU-Funktion (6 Bit)
    // [5:3]  = dest: Zielregister (A, D, M)
    // [2:0]  = jump: Sprungbedingung
    typedef struct packed {
        logic        marker;    // Bit 15: immer 1 bei C-Instruction
        logic [1:0]  ones;      // Bits 14-13: immer 11
        logic        a_bit;     // Bit 12: 0=A-Register, 1=Memory als ALU-Eingang
        logic [5:0]  comp;      // Bits 11-6: ALU-Funktion
        logic [2:0]  dest;      // Bits 5-3: Ziel (A=Bit5, D=Bit4, M=Bit3)
        logic [2:0]  jump;      // Bits 2-0: Sprungbedingung
    } c_inst_t;

    // dest-Bits (Bit 5-3 der C-Instruction)
    localparam logic [2:0] DEST_NULL = 3'b000; // kein Ziel
    localparam logic [2:0] DEST_M    = 3'b001; // Memory[A]
    localparam logic [2:0] DEST_D    = 3'b010; // D-Register
    localparam logic [2:0] DEST_MD   = 3'b011; // Memory[A] und D
    localparam logic [2:0] DEST_A    = 3'b100; // A-Register
    localparam logic [2:0] DEST_AM   = 3'b101; // A und Memory[A]
    localparam logic [2:0] DEST_AD   = 3'b110; // A und D
    localparam logic [2:0] DEST_AMD  = 3'b111; // A, Memory[A] und D

    // jump-Bits (Bit 2-0 der C-Instruction)
    localparam logic [2:0] JMP_NULL = 3'b000; // kein Sprung
    localparam logic [2:0] JMP_JGT  = 3'b001; // springe wenn out > 0
    localparam logic [2:0] JMP_JEQ  = 3'b010; // springe wenn out = 0
    localparam logic [2:0] JMP_JGE  = 3'b011; // springe wenn out >= 0
    localparam logic [2:0] JMP_JLT  = 3'b100; // springe wenn out < 0
    localparam logic [2:0] JMP_JNE  = 3'b101; // springe wenn out != 0
    localparam logic [2:0] JMP_JLE  = 3'b110; // springe wenn out <= 0
    localparam logic [2:0] JMP_JMP  = 3'b111; // springe immer

endpackage


// -----------------------------------------------------------------------------
// Modul: hack_alu
// Arithmetisch-Logische Einheit der Hack CPU
//
// comp[5:0] Kodierung (aus Nand2Tetris Tabelle):
//   Bit 5 (zx): setze x auf 0
//   Bit 4 (nx): negiere x (bitweise NOT)
//   Bit 3 (zy): setze y auf 0
//   Bit 2 (ny): negiere y (bitweise NOT)
//   Bit 1 (f) : 0=AND, 1=ADD
//   Bit 0 (no): negiere Ausgabe (bitweise NOT)
// -----------------------------------------------------------------------------
module hack_alu (
    input  logic [15:0] x,       // Erster Operand (D-Register)
    input  logic [15:0] y,       // Zweiter Operand (A-Register oder Memory)
    input  logic [5:0]  comp,    // ALU-Funktion
    output logic [15:0] out,     // Ergebnis
    output logic        zr,      // 1 wenn out == 0
    output logic        ng       // 1 wenn out < 0 (Bit 15 gesetzt)
);
    // Steuerbits aus comp extrahieren
    logic zx, nx, zy, ny, f, no;
    assign {zx, nx, zy, ny, f, no} = comp;

    // Stufe 1: x vorverarbeiten
    logic [15:0] x1, x2;
    assign x1 = zx ? 16'h0000 : x;          // zx: x auf 0 setzen
    assign x2 = nx ? ~x1      : x1;          // nx: x negieren

    // Stufe 2: y vorverarbeiten
    logic [15:0] y1, y2;
    assign y1 = zy ? 16'h0000 : y;          // zy: y auf 0 setzen
    assign y2 = ny ? ~y1      : y1;          // ny: y negieren

    // Stufe 3: Funktion anwenden
    logic [15:0] fout;
    assign fout = f ? (x2 + y2) : (x2 & y2); // f: ADD oder AND

    // Stufe 4: Ausgabe nachverarbeiten
    logic [15:0] pre_out;
    assign pre_out = no ? ~fout : fout;       // no: Ausgabe negieren

    // Ausgabe und Flags
    assign out = pre_out;
    assign ng  = pre_out[15];                 // negativ wenn Bit 15 gesetzt
    assign zr  = (pre_out == 16'h0000);       // zero wenn alle Bits 0

endmodule


// -----------------------------------------------------------------------------
// Modul: hack_cpu
// Vollständige Hack CPU (kombiniert ALU + Register + PC-Logik)
//
// Schnittstelle entspricht exakt der Nand2Tetris Spezifikation:
//   - instruction: 16-bit Instruktionswort vom ROM
//   - mem_in:      16-bit Lesewert vom Datenspeicher (Memory[A])
//   - reset:       synchroner Reset, setzt PC auf 0
//   - mem_out:     Schreibwert für Datenspeicher
//   - mem_addr:    Adresse für Datenspeicher (= Register A)
//   - mem_write:   Schreibfreigabe für Datenspeicher
//   - pc:          Programmzähler (Adresse für nächste Instruktion)
// -----------------------------------------------------------------------------
module hack_cpu
    import hack_cpu_pkg::*;
(
    input  logic        clk,
    input  logic        rst,          // synchroner Reset (active high)
    // Instruction Memory Interface (ROM, read-only)
    input  logic [15:0] instruction,
    // Data Memory Interface (RAM + Memory-Mapped IO)
    input  logic [15:0] mem_in,       // Memory[A] Lesewert
    output logic [15:0] mem_out,      // Schreibwert
    output logic [15:0] mem_addr,     // Adresse = Register A
    output logic        mem_write,    // Schreibfreigabe
    // Program Counter
    output logic [14:0] pc            // 15-bit PC (max. 32K Instruktionen)
);

    // -------------------------------------------------------------------------
    // Interne Register
    // -------------------------------------------------------------------------
    logic [15:0] reg_a;   // A-Register
    logic [15:0] reg_d;   // D-Register
    logic [14:0] reg_pc;  // Program Counter

    // -------------------------------------------------------------------------
    // Instruktion dekodieren
    // -------------------------------------------------------------------------
    inst_type_t inst_type;
    assign inst_type = inst_type_t'(instruction[15]);

    c_inst_t c;
    assign c = c_inst_t'(instruction);

    // -------------------------------------------------------------------------
    // ALU-Eingänge
    // -------------------------------------------------------------------------
    logic [15:0] alu_x;   // immer D-Register
    logic [15:0] alu_y;   // A-Register oder Memory[A] je nach a-Bit
    logic [15:0] alu_out;
    logic        alu_zr, alu_ng;

    assign alu_x = reg_d;
    assign alu_y = (inst_type == C_INST && c.a_bit) ? mem_in : reg_a;

    hack_alu alu (
        .x    (alu_x),
        .y    (alu_y),
        .comp (c.comp),
        .out  (alu_out),
        .zr   (alu_zr),
        .ng   (alu_ng)
    );

    // -------------------------------------------------------------------------
    // Memory-Interface
    // Schreiben nur bei C-Instruction mit dest[0] (M-Bit) gesetzt
    // -------------------------------------------------------------------------
    assign mem_out   = alu_out;
    assign mem_addr  = reg_a;
    assign mem_write = (inst_type == C_INST) && c.dest[0];

    // -------------------------------------------------------------------------
    // Sprunglogik (kombinatorisch)
    // Bedingung gegen ALU-Flags prüfen
    // -------------------------------------------------------------------------
    logic do_jump;

    always_comb begin
        case (c.jump)
            JMP_NULL: do_jump = 1'b0;
            JMP_JGT:  do_jump = ~alu_ng & ~alu_zr;   // out > 0
            JMP_JEQ:  do_jump =  alu_zr;              // out = 0
            JMP_JGE:  do_jump = ~alu_ng;              // out >= 0
            JMP_JLT:  do_jump =  alu_ng;              // out < 0
            JMP_JNE:  do_jump = ~alu_zr;              // out != 0
            JMP_JLE:  do_jump =  alu_ng |  alu_zr;   // out <= 0
            JMP_JMP:  do_jump = 1'b1;                 // immer
            default:  do_jump = 1'b0;
        endcase
    end

    // Sprung nur bei C-Instruction auswerten
    logic jump_taken;
    assign jump_taken = (inst_type == C_INST) && do_jump;

    // -------------------------------------------------------------------------
    // Register-Updates (synchron, flankengetriggert)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            reg_a  <= 16'h0000;
            reg_d  <= 16'h0000;
            reg_pc <= 15'h0000;
        end else begin
            // A-Register:
            //   A-Instruction: lade Instruktionswert (Bits 14:0)
            //   C-Instruction mit dest[2]: lade ALU-Ausgabe
            if (inst_type == A_INST)
                reg_a <= {1'b0, instruction[14:0]};
            else if (c.dest[2])
                reg_a <= alu_out;

            // D-Register:
            //   C-Instruction mit dest[1]: lade ALU-Ausgabe
            if (inst_type == C_INST && c.dest[1])
                reg_d <= alu_out;

            // Program Counter:
            //   Sprung: lade Register A (Sprungziel)
            //   kein Sprung: inkrement
            if (jump_taken)
                reg_pc <= reg_a[14:0];
            else
                reg_pc <= reg_pc + 15'h0001;
        end
    end

    // PC-Ausgabe
    assign pc = reg_pc;

endmodule
