// =============================================================================
// uart_loader.sv — UART-Programmlader für den Atlas 16
//
// Empfängt ein kompiliertes Hack-Programm über UART (115200 Baud, 8N1)
// und schreibt es in den Instruction-ROM. Während des Ladens bleibt die
// CPU im Reset. Nach dem Laden wird ein ACK-Byte (0xAA) gesendet und die
// CPU gestartet.
//
// Protokoll (PC → FPGA):
//   Byte 0:   Anzahl Worte HIGH-Byte  (Bits 14..8, max. 32768 Worte)
//   Byte 1:   Anzahl Worte LOW-Byte   (Bits  7..0)
//   Byte 2+3: Instruktion 0 (HIGH, LOW)
//   Byte 4+5: Instruktion 1 (HIGH, LOW)
//   ...
//
// Protokoll (FPGA → PC):
//   0xAA = Ladevorgang abgeschlossen, CPU läuft
//   0xFF = Fehler (Wortanzahl = 0 oder > 32767)
//
// Pins (Arduino-Header):
//   ARDUINO_IO[0] = RX (Eingang vom PC)
//   ARDUINO_IO[1] = TX (ACK an PC)
//
// Autor:  Sebastian Schwiebert
// Lizenz: MIT
// HDL:    SystemVerilog IEEE 1800-2005
// =============================================================================
module uart_loader #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer BAUD   = 115_200
) (
    input  logic        clk,
    input  logic        resetN,

    // UART-Pins (Arduino-Header IO[0]/IO[1])
    input  logic        rx,
    output logic        tx,

    // ROM-Schreibport
    output logic [14:0] rom_wr_addr,
    output logic [15:0] rom_wr_data,
    output logic        rom_wr_en,

    // CPU-Steuerung
    output logic        cpu_resetN,  // 0 = CPU angehalten
    output logic        loading      // 1 = Ladevorgang läuft (für LED)
);
    localparam integer CLKS_PER_BIT = CLK_HZ / BAUD;   // 434 bei 50 MHz / 115200
    localparam integer HALF_BIT     = CLKS_PER_BIT / 2; // 217

    // =========================================================================
    // UART-RX (aus uart.sv übernommen, ohne CPU-Interface)
    // =========================================================================
    typedef enum logic [1:0] {
        RX_IDLE  = 2'b00,
        RX_START = 2'b01,
        RX_DATA  = 2'b10,
        RX_STOP  = 2'b11
    } rx_state_t;

    rx_state_t rx_state;

    logic [15:0] rx_clk_cnt;
    logic  [2:0] rx_bit_idx;
    logic  [7:0] rx_shift;
    logic  [7:0] rx_byte;
    logic        rx_valid;   // Puls: 1 Takt, wenn Byte vollständig empfangen

    // 2-FF-Synchronisierung gegen Metastabilität
    logic rx_s0, rx_sync;
    always_ff @(posedge clk) begin
        rx_s0  <= rx;
        rx_sync <= rx_s0;
    end

    always_ff @(posedge clk, negedge resetN) begin
        if (!resetN) begin
            rx_state   <= RX_IDLE;
            rx_clk_cnt <= '0;
            rx_bit_idx <= '0;
            rx_shift   <= '0;
            rx_byte    <= '0;
            rx_valid   <= 1'b0;
        end else begin
            rx_valid <= 1'b0;   // Default: kein gültiges Byte

            unique case (rx_state)
                RX_IDLE: begin
                    if (!rx_sync) begin
                        rx_clk_cnt <= HALF_BIT[15:0];
                        rx_state   <= RX_START;
                    end
                end
                RX_START: begin
                    if (rx_clk_cnt == 16'h0) begin
                        if (!rx_sync) begin
                            rx_clk_cnt <= CLKS_PER_BIT[15:0] - 16'h1;
                            rx_bit_idx <= 3'h0;
                            rx_state   <= RX_DATA;
                        end else begin
                            rx_state   <= RX_IDLE;   // Störimpuls
                        end
                    end else begin
                        rx_clk_cnt <= rx_clk_cnt - 16'h1;
                    end
                end
                RX_DATA: begin
                    if (rx_clk_cnt == 16'h0) begin
                        rx_shift   <= {rx_sync, rx_shift[7:1]};  // LSB zuerst
                        rx_clk_cnt <= CLKS_PER_BIT[15:0] - 16'h1;
                        if (rx_bit_idx == 3'd7)
                            rx_state <= RX_STOP;
                        else
                            rx_bit_idx <= rx_bit_idx + 3'h1;
                    end else begin
                        rx_clk_cnt <= rx_clk_cnt - 16'h1;
                    end
                end
                RX_STOP: begin
                    if (rx_clk_cnt == 16'h0) begin
                        if (rx_sync) begin   // gültiges Stopp-Bit
                            rx_byte  <= rx_shift;
                            rx_valid <= 1'b1;
                        end
                        rx_state <= RX_IDLE;
                    end else begin
                        rx_clk_cnt <= rx_clk_cnt - 16'h1;
                    end
                end
            endcase
        end
    end

    // =========================================================================
    // UART-TX (nur für ACK-Byte)
    // =========================================================================
    typedef enum logic [1:0] {
        TX_IDLE  = 2'b00,
        TX_START = 2'b01,
        TX_DATA  = 2'b10,
        TX_STOP  = 2'b11
    } tx_state_t;

    tx_state_t tx_state;

    logic [15:0] tx_clk_cnt;
    logic  [2:0] tx_bit_idx;
    logic  [7:0] tx_shift;
    logic        tx_send;    // Puls: 1 Takt, startet TX
    logic  [7:0] tx_byte;    // zu sendendes Byte

    always_ff @(posedge clk, negedge resetN) begin
        if (!resetN) begin
            tx_state   <= TX_IDLE;
            tx         <= 1'b1;
            tx_clk_cnt <= '0;
            tx_bit_idx <= '0;
            tx_shift   <= '0;
        end else begin
            unique case (tx_state)
                TX_IDLE: begin
                    tx <= 1'b1;
                    if (tx_send) begin
                        tx_shift   <= tx_byte;
                        tx_clk_cnt <= CLKS_PER_BIT[15:0] - 16'h1;
                        tx_state   <= TX_START;
                    end
                end
                TX_START: begin
                    tx <= 1'b0;
                    if (tx_clk_cnt == 16'h0) begin
                        tx_clk_cnt <= CLKS_PER_BIT[15:0] - 16'h1;
                        tx_bit_idx <= 3'h0;
                        tx_state   <= TX_DATA;
                    end else begin
                        tx_clk_cnt <= tx_clk_cnt - 16'h1;
                    end
                end
                TX_DATA: begin
                    tx <= tx_shift[tx_bit_idx];
                    if (tx_clk_cnt == 16'h0) begin
                        tx_clk_cnt <= CLKS_PER_BIT[15:0] - 16'h1;
                        if (tx_bit_idx == 3'd7)
                            tx_state <= TX_STOP;
                        else
                            tx_bit_idx <= tx_bit_idx + 3'h1;
                    end else begin
                        tx_clk_cnt <= tx_clk_cnt - 16'h1;
                    end
                end
                TX_STOP: begin
                    tx <= 1'b1;
                    if (tx_clk_cnt == 16'h0)
                        tx_state <= TX_IDLE;
                    else
                        tx_clk_cnt <= tx_clk_cnt - 16'h1;
                end
            endcase
        end
    end

    // =========================================================================
    // Loader-FSM
    // =========================================================================
    typedef enum logic [2:0] {
        LD_COUNT_HI = 3'b000,   // warte auf HIGH-Byte der Wortanzahl
        LD_COUNT_LO = 3'b001,   // warte auf LOW-Byte der Wortanzahl
        LD_DATA_HI  = 3'b010,   // warte auf HIGH-Byte einer Instruktion
        LD_DATA_LO  = 3'b011,   // warte auf LOW-Byte  einer Instruktion
        LD_WRITE    = 3'b100,   // schreibt Wort in ROM (1 Takt)
        LD_ACK      = 3'b101,   // sendet 0xAA, gibt CPU frei
        LD_ERR      = 3'b110    // Fehler: sendet 0xFF
    } ld_state_t;

    ld_state_t ld_state;

    logic [14:0] ld_total;     // Anzahl zu ladender Worte
    logic [14:0] ld_addr;      // aktueller Schreibzeiger
    logic  [7:0] ld_hi;        // HIGH-Byte der aktuellen Instruktion

    always_ff @(posedge clk, negedge resetN) begin
        if (!resetN) begin
            ld_state    <= LD_COUNT_HI;
            ld_total    <= '0;
            ld_addr     <= '0;
            ld_hi       <= '0;
            rom_wr_en   <= 1'b0;
            rom_wr_addr <= '0;
            rom_wr_data <= '0;
            cpu_resetN  <= 1'b1;   // CPU läuft; Reset nur während aktivem UART-Laden
            loading     <= 1'b0;
            tx_send     <= 1'b0;
            tx_byte     <= '0;
        end else begin
            rom_wr_en <= 1'b0;
            tx_send   <= 1'b0;

            unique case (ld_state)

                LD_COUNT_HI: begin
                    if (rx_valid) begin
                        ld_total[14:8] <= rx_byte[6:0];
                        ld_addr        <= '0;
                        cpu_resetN     <= 1'b0;   // CPU anhalten während UART-Laden
                        loading        <= 1'b1;
                        ld_state       <= LD_COUNT_LO;
                    end
                end

                LD_COUNT_LO: begin
                    if (rx_valid) begin
                        ld_total[7:0] <= rx_byte;
                        if ({rx_byte[6:0], rx_byte} == 15'h0) begin
                            // Wortanzahl 0 ist ungültig
                            tx_byte  <= 8'hFF;
                            tx_send  <= 1'b1;
                            ld_state <= LD_ERR;
                        end else begin
                            ld_state <= LD_DATA_HI;
                        end
                    end
                end

                LD_DATA_HI: begin
                    if (rx_valid) begin
                        ld_hi    <= rx_byte;
                        ld_state <= LD_DATA_LO;
                    end
                end

                LD_DATA_LO: begin
                    if (rx_valid) begin
                        rom_wr_addr <= ld_addr;
                        rom_wr_data <= {ld_hi, rx_byte};
                        rom_wr_en   <= 1'b1;
                        ld_state    <= LD_WRITE;
                    end
                end

                LD_WRITE: begin
                    // rom_wr_en war 1 Takt aktiv — ROM hat geschrieben
                    if (ld_addr == ld_total - 15'h1) begin
                        // Letztes Wort geschrieben → ACK senden
                        tx_byte  <= 8'hAA;
                        tx_send  <= 1'b1;
                        loading  <= 1'b0;
                        ld_state <= LD_ACK;
                    end else begin
                        ld_addr  <= ld_addr + 15'h1;
                        ld_state <= LD_DATA_HI;
                    end
                end

                LD_ACK: begin
                    // TX läuft — warte auf Abschluss (tx_state kehrt zu TX_IDLE)
                    if (tx_state == TX_IDLE && !tx_send) begin
                        cpu_resetN <= 1'b1;   // CPU freigeben
                        ld_state   <= LD_COUNT_HI;  // bereit für nächstes Programm
                    end
                end

                LD_ERR: begin
                    // Fehler-ACK gesendet, auf nächste Übertragung warten
                    if (tx_state == TX_IDLE && !tx_send)
                        ld_state <= LD_COUNT_HI;
                end

            endcase
        end
    end

endmodule
