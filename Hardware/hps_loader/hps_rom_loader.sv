// =============================================================================
// hps_rom_loader.sv — Avalon-MM Register-Interface für den HPS-ROM-Loader
//
// Drei 32-bit Register (word-addressed):
//
//   Offset 0x00  CTRL      bit 0 = cpu_resetN (0=CPU angehalten, 1=CPU läuft)
//   Offset 0x04  LOAD_ADDR bits [14:0] = Startadresse im ROM (setzt Zähler)
//   Offset 0x08  LOAD_DATA bits [15:0] = Instruktion schreiben + Adresse++
//
// Ladereihenfolge (HPS C-Programm):
//   1. CTRL      = 0       CPU anhalten
//   2. LOAD_ADDR = 0       Adresszähler auf 0
//   3. LOAD_DATA = instr0  Instruktion 0 schreiben, Adresse → 1
//   4. LOAD_DATA = instr1  Instruktion 1 schreiben, Adresse → 2
//   ...
//   N. CTRL      = 1       CPU freigeben
//
// Autor:  Sebastian Schwiebert
// Lizenz: MIT
// HDL:    SystemVerilog IEEE 1800-2005
// =============================================================================
module hps_rom_loader (
    input  logic        clk,
    input  logic        rst,

    // Avalon-MM Slave (von HPS Lightweight Bridge)
    input  logic  [1:0] avs_address,
    input  logic        avs_write,
    input  logic [31:0] avs_writedata,
    output logic [31:0] avs_readdata,

    // ROM-Schreibport
    output logic [14:0] rom_wr_addr,
    output logic [15:0] rom_wr_data,
    output logic        rom_wr_en,

    // CPU-Steuerung
    output logic        cpu_resetN
);
    localparam logic [1:0] REG_CTRL      = 2'h0;
    localparam logic [1:0] REG_LOAD_ADDR = 2'h1;
    localparam logic [1:0] REG_LOAD_DATA = 2'h2;

    logic [14:0] addr_ctr;   // interner Adresszähler

    always_ff @(posedge clk) begin
        if (rst) begin
            cpu_resetN <= 1'b0;
            addr_ctr   <= '0;
            rom_wr_en  <= 1'b0;
            rom_wr_addr <= '0;
            rom_wr_data <= '0;
        end else begin
            rom_wr_en <= 1'b0;   // Default: kein Schreiben

            if (avs_write) begin
                case (avs_address)
                    REG_CTRL: begin
                        cpu_resetN <= avs_writedata[0];
                    end
                    REG_LOAD_ADDR: begin
                        addr_ctr <= avs_writedata[14:0];
                    end
                    REG_LOAD_DATA: begin
                        rom_wr_addr <= addr_ctr;
                        rom_wr_data <= avs_writedata[15:0];
                        rom_wr_en   <= 1'b1;
                        addr_ctr    <= addr_ctr + 15'h1;
                    end
                    default: ;
                endcase
            end
        end
    end

    // Lesepfad: Adresszähler zurücklesen (nützlich für Fehlerdiagnose)
    always_comb begin
        case (avs_address)
            REG_CTRL:      avs_readdata = {31'h0, cpu_resetN};
            REG_LOAD_ADDR: avs_readdata = {17'h0, addr_ctr};
            default:       avs_readdata = 32'h0;
        endcase
    end

endmodule
