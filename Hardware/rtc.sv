// =============================================================================
// rtc.sv — Echtzeituhr (Real-Time Clock)
//
// Die Zeit wird vom HPS/Linux über die Mailbox eingestellt.
// Der FPGA-Teil zählt Sekunden selbstständig weiter (50 MHz Referenztakt).
//
// Register-Offsets (relativ zu 0x6410):
//   0: RTC_SEC  (0–59)
//   1: RTC_MIN  (0–59)
//   2: RTC_HOUR (0–23)
//   3: RTC_DAY  (1–31)
//   4: RTC_MON  (1–12)
//   5: RTC_YEAR
//
// Autor:  Sebastian Schwiebert
// Lizenz: MIT
// HDL:    SystemVerilog IEEE 1800-2005
// =============================================================================
module rtc (
    input  logic        clk,         // 50 MHz
    input  logic        rst,
    // CPU-Interface (read-only für CPU, Adressen 0–5)
    input  logic  [2:0] reg_addr,
    output logic [15:0] reg_rdata,
    // HPS-Update-Interface
    input  logic  [7:0] upd_sec,
    input  logic  [7:0] upd_min,
    input  logic  [7:0] upd_hour,
    input  logic        upd_en       // 1 Takt Puls → Zeit übernehmen
);
    // Sekunden-Ticker: zählt 50.000.000 Takte = 1 Sekunde
    localparam int TICKS_PER_SEC = 50_000_000;
    logic [25:0] tick_cnt;
    logic        sec_tick;  // 1-Takt-Puls jede Sekunde

    always_ff @(posedge clk) begin
        if (rst) begin
            tick_cnt <= '0;
            sec_tick <= 1'b0;
        end else begin
            sec_tick <= 1'b0;
            if (tick_cnt == TICKS_PER_SEC - 1) begin
                tick_cnt <= '0;
                sec_tick <= 1'b1;
            end else begin
                tick_cnt <= tick_cnt + 1;
            end
        end
    end

    // Uhrzeit-Register
    logic [7:0] sec, min, hour, day, mon;
    logic [15:0] year;

    always_ff @(posedge clk) begin
        if (rst) begin
            sec  <= 8'h00;
            min  <= 8'h00;
            hour <= 8'h00;
            day  <= 8'h01;
            mon  <= 8'h01;
            year <= 16'd2026;
        end else if (upd_en) begin
            // HPS aktualisiert die Zeit
            sec  <= upd_sec;
            min  <= upd_min;
            hour <= upd_hour;
        end else if (sec_tick) begin
            // Sekunde weiterschalten
            if (sec == 8'd59) begin
                sec <= 8'h00;
                if (min == 8'd59) begin
                    min <= 8'h00;
                    if (hour == 8'd23)
                        hour <= 8'h00;
                    else
                        hour <= hour + 1;
                end else min <= min + 1;
            end else sec <= sec + 1;
        end
    end

    // Lesemultiplexer
    always_comb begin
        unique case (reg_addr)
            3'd0: reg_rdata = {8'h00, sec};
            3'd1: reg_rdata = {8'h00, min};
            3'd2: reg_rdata = {8'h00, hour};
            3'd3: reg_rdata = {8'h00, day};
            3'd4: reg_rdata = {8'h00, mon};
            3'd5: reg_rdata = year;
            default: reg_rdata = 16'h0;
        endcase
    end

endmodule
