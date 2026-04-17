// =============================================================================
// tb_hack_cpu.sv
// Testbench für die Hack CPU
//
// Testet die grundlegenden Operationen der Hack CPU:
//   1. A-Instruction: Wert in A laden
//   2. C-Instruction: ALU-Operationen, Register-Schreiben
//   3. Memory-Schreiben
//   4. Sprünge (JMP, JGT, JEQ, JLT)
//   5. Reset
//
// Ausführen in Quartus: ModelSim / QuestaSim
// Oder: iverilog + vvp (Open-Source Simulator)
//
// HDL: SystemVerilog IEEE 1800-2005
// =============================================================================

`timescale 1ns/1ps

module tb_hack_cpu;

    // -------------------------------------------------------------------------
    // Signale
    // -------------------------------------------------------------------------
    logic        clk;
    logic        rst;
    logic [15:0] instruction;
    logic [15:0] mem_in;
    logic [15:0] mem_out;
    logic [15:0] mem_addr;
    logic        mem_write;
    logic [14:0] pc;

    // -------------------------------------------------------------------------
    // DUT instanziieren
    // -------------------------------------------------------------------------
    hack_cpu dut (
        .clk         (clk),
        .rst         (rst),
        .instruction (instruction),
        .mem_in      (mem_in),
        .mem_out     (mem_out),
        .mem_addr    (mem_addr),
        .mem_write   (mem_write),
        .pc          (pc)
    );

    // -------------------------------------------------------------------------
    // Takt: 50 MHz (20 ns Periode)
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #10 clk = ~clk;

    // -------------------------------------------------------------------------
    // Hilfstask: eine Taktflanke abwarten
    // -------------------------------------------------------------------------
    task tick;
        @(posedge clk);
        #1; // kurze Verzögerung nach Flanke für stabile Ausgaben
    endtask

    // -------------------------------------------------------------------------
    // Hilfstask: Prüfung mit Fehlermeldung
    // -------------------------------------------------------------------------
    int test_nr;
    int pass_count;
    int fail_count;

    task check;
        input [15:0] actual;
        input [15:0] expected;
        input [63:0] label;  // vereinfacht: 8-char Label
        begin
            test_nr = test_nr + 1;
            if (actual === expected) begin
                $display("  PASS [%0d] %s: 0x%04X", test_nr, label, actual);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL [%0d] %s: erwartet 0x%04X, erhalten 0x%04X",
                         test_nr, label, expected, actual);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // ROM: einfache Instruktionssequenz
    // Wir steuern 'instruction' manuell (kein echtes ROM hier)
    // -------------------------------------------------------------------------

    // -------------------------------------------------------------------------
    // Testsequenz
    // -------------------------------------------------------------------------
    initial begin
        $display("=== Hack CPU Testbench ===");
        test_nr    = 0;
        pass_count = 0;
        fail_count = 0;

        // Initialisierung
        instruction = 16'h0000;
        mem_in      = 16'h0000;
        rst         = 1'b1;

        // Reset für 2 Takte halten
        tick; tick;
        rst = 1'b0;

        // -----------------------------------------------------------------
        // TEST 1: A-Instruction — lade 42 in Register A
        // @42 → instruction = 0_000000000101010 = 0x002A
        // Nach tick: reg_a = 42, pc = 1
        // -----------------------------------------------------------------
        $display("\n--- Test 1: A-Instruction (@42) ---");
        instruction = 16'h002A;  // 0_000000000101010
        tick;
        check(mem_addr, 16'h002A, "A-Reg  ");
        check({1'b0, pc}, 16'h0001, "PC     ");
        check({15'b0, mem_write}, 16'h0000, "MWR=0  ");

        // -----------------------------------------------------------------
        // TEST 2: C-Instruction — D = A
        // comp = 110000 (D=A), dest = 010 (D), jump = 000
        // instruction = 111_0_110000_010_000 = 0xEC10
        // Nach tick: reg_d = 42
        // -----------------------------------------------------------------
        $display("\n--- Test 2: C-Instruction (D=A) ---");
        instruction = 16'hEC10;  // D=A
        tick;
        // Wir prüfen via D=A+1 im nächsten Schritt, da D intern ist
        // Zuerst: A = 1, dann D+1 prüfen
        check({1'b0, pc}, 16'h0002, "PC     ");

        // -----------------------------------------------------------------
        // TEST 3: D+1 → D (D-Register war 42, jetzt 43)
        // comp = 011111 (D+1), dest = 010 (D), jump = 000
        // instruction = 111_0_011111_010_000 = 0xE7D0  [a=0, comp=011111]
        // Warte: comp-Bits für D+1 = a=0, zx=0,nx=1,zy=1,ny=1,f=1 = 011111
        // instruction = 1110_011111_010_000 = 0xE7D0
        // -----------------------------------------------------------------
        $display("\n--- Test 3: D = D+1 ---");
        instruction = 16'hE7D0;  // D=D+1
        tick;
        check({1'b0, pc}, 16'h0003, "PC     ");

        // -----------------------------------------------------------------
        // TEST 4: M[A] = D  (Memory schreiben)
        // A ist noch 42 (aus Test 1, nicht überschrieben)
        // comp = 001100 (D), dest = 001 (M), jump = 000
        // instruction = 111_0_001100_001_000 = 0xE308
        // -----------------------------------------------------------------
        $display("\n--- Test 4: M[A]=D (Memory Write) ---");
        instruction = 16'hE308;  // M=D
        tick;
        check(mem_addr,  16'h002A, "Adr=42 ");
        check(mem_write, 1'b1,     "MWR=1  ");
        check(mem_out,   16'h002B, "D=43   "); // D war 43 nach Test 3

        // -----------------------------------------------------------------
        // TEST 5: Memory lesen (A=0, D=M)
        // Zuerst A auf 0 setzen: @0 → 0x0000
        // -----------------------------------------------------------------
        $display("\n--- Test 5: A=0, dann D=M ---");
        instruction = 16'h0000;  // @0
        tick;
        check(mem_addr, 16'h0000, "A=0    ");

        mem_in      = 16'h00FF;  // Simulierter RAM-Inhalt bei Adresse 0
        // D = M: comp = 110000 (A→Y, a=1), dest = 010 (D)
        // instruction = 111_1_110000_010_000 = 0xFC10
        instruction = 16'hFC10;  // D=M
        tick;
        check({1'b0, pc}, 16'h0006, "PC     ");
        // D ist jetzt 0xFF, testen mit D-Ausgabe über M=D
        instruction = 16'hE308;  // M=D (schreibt D nach M[0])
        tick;
        check(mem_out, 16'h00FF, "D=M=FF ");

        // -----------------------------------------------------------------
        // TEST 6: Unbedingter Sprung (JMP)
        // @10 dann 0;JMP
        // 0;JMP = comp=101010 (0), dest=000, jump=111
        // instruction = 111_0_101010_000_111 = 0xEA87
        // -----------------------------------------------------------------
        $display("\n--- Test 6: Unbedingter Sprung ---");
        instruction = 16'h000A;  // @10
        tick;
        instruction = 16'hEA87;  // 0;JMP
        tick;
        check({1'b0, pc}, 16'h000A, "PC=10  ");

        // -----------------------------------------------------------------
        // TEST 7: Bedingter Sprung JEQ (springe wenn out==0)
        // @5, dann D;JEQ (D ist 0xFF, kein Sprung erwartet)
        // D;JEQ = comp=001100 (D), dest=000, jump=010
        // instruction = 111_0_001100_000_010 = 0xE302
        // -----------------------------------------------------------------
        $display("\n--- Test 7: JEQ kein Sprung (D!=0) ---");
        instruction = 16'h0005;  // @5
        tick;
        instruction = 16'hE302;  // D;JEQ
        tick;
        // D != 0 → kein Sprung → PC = vorheriger PC + 1
        // vorheriger PC war 10 (nach Sprung), dann @5 → PC=11, dann JEQ → PC=12
        check({1'b0, pc}, 16'h000C, "PC=12  ");

        // -----------------------------------------------------------------
        // TEST 8: Reset
        // -----------------------------------------------------------------
        $display("\n--- Test 8: Reset ---");
        rst = 1'b1;
        tick;
        check({1'b0, pc},    16'h0000, "PC=0   ");
        check(mem_addr,      16'h0000, "A=0    ");
        check(mem_write,     1'b0,     "MWR=0  ");
        rst = 1'b0;

        // -----------------------------------------------------------------
        // Ergebnis
        // -----------------------------------------------------------------
        $display("\n=== Ergebnis: %0d/%0d Tests bestanden ===",
                 pass_count, pass_count + fail_count);
        if (fail_count == 0)
            $display("ALLE TESTS BESTANDEN");
        else
            $display("ACHTUNG: %0d Test(s) fehlgeschlagen", fail_count);

        $finish;
    end

    // Timeout-Schutz
    initial begin
        #10000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
