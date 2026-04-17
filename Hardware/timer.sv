// =============================================================================
// timer.sv — Konfigurierbarer Countdown-Timer
//
// Zählt von RELOAD bis 0, setzt bei Überlauf das Status-Flag.
// Kann über CTRL aktiviert und deaktiviert werden.
//
// Register-Offsets (relativ zu 0x6420):
//   0: TMR_CNT    (read-only, aktueller Zählerstand)
//   1: TMR_RELOAD (Neustartswert)
//   2: TMR_CTRL   (Bit 0: enable)
//   3: TMR_STATUS (Bit 0: overflow, schreibe 1 zum Löschen)
//
// Autor:  Sebastian Schwiebert
// Lizenz: MIT
// HDL:    SystemVerilog IEEE 1800-2005
// =============================================================================
module timer (
    input  logic        clk,
    input  logic        rst,
    // CPU-Interface
    input  logic  [1:0] reg_addr,
    input  logic [15:0] reg_wdata,
    input  logic        reg_write,
    output logic [15:0] reg_rdata
);
    logic [15:0] cnt;
    logic [15:0] reload;
    logic        enable;
    logic        overflow;

    always_ff @(posedge clk) begin
        if (rst) begin
            cnt      <= 16'hFFFF;
            reload   <= 16'hFFFF;
            enable   <= 1'b0;
            overflow <= 1'b0;
        end else begin
            // Register-Schreibzugriff
            if (reg_write) begin
                unique case (reg_addr)
                    2'd1: reload <= reg_wdata;
                    2'd2: enable <= reg_wdata[0];
                    2'd3: if (reg_wdata[0]) overflow <= 1'b0; // löschen
                    default: ;
                endcase
            end

            // Zählerlogik
            if (enable) begin
                if (cnt == 16'h0000) begin
                    cnt      <= reload;
                    overflow <= 1'b1;
                end else begin
                    cnt <= cnt - 1;
                end
            end
        end
    end

    // Lesemultiplexer
    always_comb begin
        unique case (reg_addr)
            2'd0: reg_rdata = cnt;
            2'd1: reg_rdata = reload;
            2'd2: reg_rdata = {15'h0, enable};
            2'd3: reg_rdata = {15'h0, overflow};
        endcase
    end

endmodule
