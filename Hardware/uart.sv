// =============================================================================
// uart.sv — Serielles Terminal (UART, 8N1)
//
// Konfigurierbare Baudrate über Parameter.
// Standard: 115.200 Baud bei 50 MHz Systemtakt.
//
// Register-Offsets (relativ zu 0x6400):
//   0: UART_DATA   (Schreiben = Byte senden, Lesen = empfangenes Byte)
//   1: UART_STATUS (Bit 0: TX_READY,  Bit 1: RX_AVAILABLE)
//
// Protokoll: 8 Datenbits, kein Paritybit, 1 Stoppbit (8N1)
//
// Autor:  Sebastian Schwiebert
// Lizenz: MIT
// HDL:    SystemVerilog IEEE 1800-2005
// =============================================================================
module uart #(
    parameter int CLK_HZ = 50_000_000,
    parameter int BAUD   = 115_200
) (
    input  logic       clk,
    input  logic       rst,
    // Serielle Pins
    input  logic       rx,
    output logic       tx,
    // CPU-Interface
    input  logic       reg_addr,    // 0=DATA, 1=STATUS
    input  logic [7:0] reg_wdata,
    input  logic       reg_write,
    output logic [7:0] reg_rdata
);
    localparam int CLKS_PER_BIT = CLK_HZ / BAUD;

    // =========================================================================
    // TX — Senden
    // =========================================================================
    typedef enum logic [1:0] { TX_IDLE, TX_START, TX_DATA, TX_STOP } tx_state_t;
    tx_state_t tx_state;

    logic [15:0] tx_clk_cnt;
    logic  [2:0] tx_bit_idx;
    logic  [7:0] tx_shift;
    logic        tx_ready;

    always_ff @(posedge clk) begin
        if (rst) begin
            tx_state <= TX_IDLE;
            tx       <= 1'b1;   // Leerlauf: Leitungspegel hoch
            tx_ready <= 1'b1;
        end else begin
            unique case (tx_state)
                TX_IDLE: begin
                    tx       <= 1'b1;
                    tx_ready <= 1'b1;
                    if (reg_write && reg_addr == 1'b0) begin
                        // CPU schreibt Byte → senden
                        tx_shift   <= reg_wdata;
                        tx_clk_cnt <= CLKS_PER_BIT - 1;
                        tx_ready   <= 1'b0;
                        tx_state   <= TX_START;
                    end
                end

                TX_START: begin
                    tx <= 1'b0; // Start-Bit: Leitungspegel runter
                    if (tx_clk_cnt == 0) begin
                        tx_clk_cnt <= CLKS_PER_BIT - 1;
                        tx_bit_idx <= 3'h0;
                        tx_state   <= TX_DATA;
                    end else tx_clk_cnt <= tx_clk_cnt - 1;
                end

                TX_DATA: begin
                    tx <= tx_shift[tx_bit_idx]; // LSB zuerst
                    if (tx_clk_cnt == 0) begin
                        tx_clk_cnt <= CLKS_PER_BIT - 1;
                        if (tx_bit_idx == 3'd7)
                            tx_state <= TX_STOP;
                        else
                            tx_bit_idx <= tx_bit_idx + 1;
                    end else tx_clk_cnt <= tx_clk_cnt - 1;
                end

                TX_STOP: begin
                    tx <= 1'b1; // Stopp-Bit
                    if (tx_clk_cnt == 0)
                        tx_state <= TX_IDLE;
                    else tx_clk_cnt <= tx_clk_cnt - 1;
                end
            endcase
        end
    end

    // =========================================================================
    // RX — Empfangen
    // =========================================================================
    typedef enum logic [1:0] { RX_IDLE, RX_START, RX_DATA, RX_STOP } rx_state_t;
    rx_state_t rx_state;

    logic [15:0] rx_clk_cnt;
    logic  [2:0] rx_bit_idx;
    logic  [7:0] rx_shift;
    logic  [7:0] rx_data;
    logic        rx_available;

    // Eingangs-Synchronisierung: 2 Flip-Flops gegen Metastabilität
    logic rx_sync_0, rx_sync;
    always_ff @(posedge clk) begin
        rx_sync_0 <= rx;
        rx_sync   <= rx_sync_0;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            rx_state    <= RX_IDLE;
            rx_available<= 1'b0;
        end else begin
            unique case (rx_state)
                RX_IDLE: begin
                    rx_available <= 1'b0;
                    if (!rx_sync) begin // Start-Bit: Pegel fällt
                        // Mitte des Start-Bits abwarten
                        rx_clk_cnt <= CLKS_PER_BIT / 2;
                        rx_state   <= RX_START;
                    end
                end

                RX_START: begin
                    if (rx_clk_cnt == 0) begin
                        if (!rx_sync) begin // Start-Bit noch gültig?
                            rx_clk_cnt <= CLKS_PER_BIT - 1;
                            rx_bit_idx <= 3'h0;
                            rx_state   <= RX_DATA;
                        end else
                            rx_state   <= RX_IDLE; // falscher Alarm
                    end else rx_clk_cnt <= rx_clk_cnt - 1;
                end

                RX_DATA: begin
                    if (rx_clk_cnt == 0) begin
                        // Bit in der Mitte abtasten
                        rx_shift   <= {rx_sync, rx_shift[7:1]}; // LSB first
                        rx_clk_cnt <= CLKS_PER_BIT - 1;
                        if (rx_bit_idx == 3'd7)
                            rx_state <= RX_STOP;
                        else
                            rx_bit_idx <= rx_bit_idx + 1;
                    end else rx_clk_cnt <= rx_clk_cnt - 1;
                end

                RX_STOP: begin
                    if (rx_clk_cnt == 0) begin
                        if (rx_sync) begin // gültiges Stopp-Bit?
                            rx_data      <= rx_shift;
                            rx_available <= 1'b1;
                        end
                        rx_state <= RX_IDLE;
                    end else rx_clk_cnt <= rx_clk_cnt - 1;
                end
            endcase

            // Lesen löscht RX_AVAILABLE
            if (!reg_addr && !reg_write)
                rx_available <= 1'b0;
        end
    end

    // =========================================================================
    // CPU-Lesemultiplexer
    // =========================================================================
    always_comb begin
        if (reg_addr == 1'b0)
            reg_rdata = rx_data;                       // UART_DATA
        else
            reg_rdata = {6'h0, rx_available, tx_ready}; // UART_STATUS
    end

endmodule
