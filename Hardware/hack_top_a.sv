// =============================================================================
// hack_top_a.sv — Toplevel des Atlas 16, Stufe A (Hack-kompatibel)
//
// Stufe A implementiert den Hack-kompatiblen Kern:
//   - Hack CPU (unveränderte N2T-Architektur)
//   - Instruction ROM (32 KB BRAM, per HPS oder UART ladbar)
//   - Data RAM + Framebuffer (16 KB RAM + 8 KB FB, MLAB)
//   - VGA/HDMI-Ausgabe (512×256, 1bpp, zentriert in 640×480)
//   - HPS-System (Angstrom Linux, Lightweight Bridge → ROM-Loader)
//   - UART-Loader (Arduino-Header, Fallback ohne Netzwerk)
//
// Lade-Priorität: HPS-Loader (LW-Bridge) > UART-Loader
//   Beide halten cpu_resetN=0 während des Ladens.
//   Gleichzeitiges Laden ist nicht vorgesehen — kein Arbiter nötig.
//
// Plattform: Terasic DE10-Nano (Intel Cyclone V 5CSEBA6U23I7)
//
// Autor:  Sebastian Schwiebert
// Lizenz: MIT
// HDL:    SystemVerilog IEEE 1800-2005
// =============================================================================
module hack_top_a (
    // -------------------------------------------------------------------------
    // DE10-Nano Basistakt und Reset
    // -------------------------------------------------------------------------
    input  logic        CLOCK_50,
    input  logic  [1:0] KEY,            // KEY[0] = Reset (aktiv-niedrig)

    // -------------------------------------------------------------------------
    // HDMI-Ausgabe (an ADV7513)
    // -------------------------------------------------------------------------
    output logic        HDMI_TX_CLK,
    output logic        HDMI_TX_DE,
    output logic        HDMI_TX_HS,
    output logic        HDMI_TX_VS,
    output logic [23:0] HDMI_TX_D,

    // -------------------------------------------------------------------------
    // HDMI I2C — High-Z, Konfiguration durch Angstrom OS (HPS I2C1)
    // -------------------------------------------------------------------------
    inout  wire         HDMI_I2C_SCL,
    inout  wire         HDMI_I2C_SDA,

    // -------------------------------------------------------------------------
    // UART-Loader (Arduino-Header IO[0]=RX, IO[1]=TX)
    // -------------------------------------------------------------------------
    input  logic        UART_LOADER_RX,
    output logic        UART_LOADER_TX,
    output logic        LOADER_ACTIVE,

    // -------------------------------------------------------------------------
    // HPS — DDR3 Speicher
    // -------------------------------------------------------------------------
    output wire [14:0]  HPS_DDR3_ADDR,
    output wire  [2:0]  HPS_DDR3_BA,
    output wire         HPS_DDR3_CAS_N,
    output wire         HPS_DDR3_CKE,
    output wire         HPS_DDR3_CK_N,
    output wire         HPS_DDR3_CK_P,
    output wire         HPS_DDR3_CS_N,
    output wire  [3:0]  HPS_DDR3_DM,
    inout  wire [31:0]  HPS_DDR3_DQ,
    inout  wire  [3:0]  HPS_DDR3_DQS_N,
    inout  wire  [3:0]  HPS_DDR3_DQS_P,
    output wire         HPS_DDR3_ODT,
    output wire         HPS_DDR3_RAS_N,
    output wire         HPS_DDR3_RESET_N,
    input  wire         HPS_DDR3_RZQ,
    output wire         HPS_DDR3_WE_N,

    // -------------------------------------------------------------------------
    // HPS — Ethernet (EMAC1, RGMII)
    // -------------------------------------------------------------------------
    output wire         HPS_ENET_GTX_CLK,
    inout  wire         HPS_ENET_INT_N,
    output wire         HPS_ENET_MDC,
    inout  wire         HPS_ENET_MDIO,
    input  wire         HPS_ENET_RX_CLK,
    input  wire  [3:0]  HPS_ENET_RX_DATA,
    input  wire         HPS_ENET_RX_DV,
    output wire  [3:0]  HPS_ENET_TX_DATA,
    output wire         HPS_ENET_TX_EN,

    // -------------------------------------------------------------------------
    // HPS — SD-Karte
    // -------------------------------------------------------------------------
    output wire         HPS_SD_CLK,
    inout  wire         HPS_SD_CMD,
    inout  wire  [3:0]  HPS_SD_DATA,

    // -------------------------------------------------------------------------
    // HPS — USB OTG
    // -------------------------------------------------------------------------
    input  wire         HPS_USB_CLKOUT,
    inout  wire  [7:0]  HPS_USB_DATA,
    input  wire         HPS_USB_DIR,
    input  wire         HPS_USB_NXT,
    output wire         HPS_USB_STP,

    // -------------------------------------------------------------------------
    // HPS — SPI Master 1
    // -------------------------------------------------------------------------
    output wire         HPS_SPIM_CLK,
    input  wire         HPS_SPIM_MISO,
    output wire         HPS_SPIM_MOSI,
    output wire         HPS_SPIM_SS,

    // -------------------------------------------------------------------------
    // HPS — UART0 (Konsole)
    // -------------------------------------------------------------------------
    input  wire         HPS_UART_RX,
    output wire         HPS_UART_TX,

    // -------------------------------------------------------------------------
    // HPS — I2C
    // -------------------------------------------------------------------------
    inout  wire         HPS_I2C0_SCLK,
    inout  wire         HPS_I2C0_SDAT,
    inout  wire         HPS_I2C1_SCLK,
    inout  wire         HPS_I2C1_SDAT,

    // -------------------------------------------------------------------------
    // HPS — GPIO / sonstige
    // -------------------------------------------------------------------------
    inout  wire         HPS_CONV_USB_N,
    inout  wire         HPS_LTC_GPIO,
    inout  wire         HPS_LED,
    inout  wire         HPS_KEY,
    inout  wire         HPS_GSENSOR_INT
);
    // =========================================================================
    // Takte und Reset
    // =========================================================================
    logic clk;
    logic clk_25mhz;
    logic clk_div;
    logic rst;

    assign clk = CLOCK_50;

    always_ff @(posedge clk) clk_div <= ~clk_div;
    assign clk_25mhz = clk_div;

    // =========================================================================
    // HPS-System instanziieren (Lightweight Bridge → ROM-Loader)
    // =========================================================================
    wire [14:0] hps_rom_wr_addr;
    wire [15:0] hps_rom_wr_data;
    wire        hps_rom_wr_en;
    wire        hps_cpu_resetN;
    wire        hps_h2f_reset_n;

    hack_hps_sys hps_sys (
        // Takt und Reset
        .clk_clk                                        (CLOCK_50),
        .reset_reset_n                                  (KEY[0]),

        // HPS-Reset → FPGA (aktiv-niedrig)
        .hps_0_h2f_reset_reset_n                        (hps_h2f_reset_n),

        // Unbenutzte F2H-Reset-Eingänge (auf inaktiv setzen)
        .hps_0_f2h_cold_reset_req_reset_n               (1'b1),
        .hps_0_f2h_debug_reset_req_reset_n              (1'b1),
        .hps_0_f2h_warm_reset_req_reset_n               (1'b1),
        .hps_0_f2h_stm_hw_events_stm_hwevents           (28'h0),

        // Unbenutzte GHRD-Peripherie (Button/Switch/LED — inaktiv)
        .button_pio_external_connection_export          (2'b11),
        .dipsw_pio_external_connection_export           (4'b0000),
        .led_pio_external_connection_export             (),

        // ROM-Loader Konduit
        .rom_ctrl_rom_wr_addr                           (hps_rom_wr_addr),
        .rom_ctrl_rom_wr_data                           (hps_rom_wr_data),
        .rom_ctrl_rom_wr_en                             (hps_rom_wr_en),
        .rom_ctrl_cpu_resetN                            (hps_cpu_resetN),

        // DDR3
        .memory_mem_a                                   (HPS_DDR3_ADDR),
        .memory_mem_ba                                  (HPS_DDR3_BA),
        .memory_mem_ck                                  (HPS_DDR3_CK_P),
        .memory_mem_ck_n                                (HPS_DDR3_CK_N),
        .memory_mem_cke                                 (HPS_DDR3_CKE),
        .memory_mem_cs_n                                (HPS_DDR3_CS_N),
        .memory_mem_ras_n                               (HPS_DDR3_RAS_N),
        .memory_mem_cas_n                               (HPS_DDR3_CAS_N),
        .memory_mem_we_n                                (HPS_DDR3_WE_N),
        .memory_mem_reset_n                             (HPS_DDR3_RESET_N),
        .memory_mem_dq                                  (HPS_DDR3_DQ),
        .memory_mem_dqs                                 (HPS_DDR3_DQS_P),
        .memory_mem_dqs_n                               (HPS_DDR3_DQS_N),
        .memory_mem_odt                                 (HPS_DDR3_ODT),
        .memory_mem_dm                                  (HPS_DDR3_DM),
        .memory_oct_rzqin                               (HPS_DDR3_RZQ),

        // HPS IO
        .hps_0_hps_io_hps_io_emac1_inst_TX_CLK         (HPS_ENET_GTX_CLK),
        .hps_0_hps_io_hps_io_emac1_inst_TXD0           (HPS_ENET_TX_DATA[0]),
        .hps_0_hps_io_hps_io_emac1_inst_TXD1           (HPS_ENET_TX_DATA[1]),
        .hps_0_hps_io_hps_io_emac1_inst_TXD2           (HPS_ENET_TX_DATA[2]),
        .hps_0_hps_io_hps_io_emac1_inst_TXD3           (HPS_ENET_TX_DATA[3]),
        .hps_0_hps_io_hps_io_emac1_inst_RXD0           (HPS_ENET_RX_DATA[0]),
        .hps_0_hps_io_hps_io_emac1_inst_MDIO           (HPS_ENET_MDIO),
        .hps_0_hps_io_hps_io_emac1_inst_MDC            (HPS_ENET_MDC),
        .hps_0_hps_io_hps_io_emac1_inst_RX_CTL         (HPS_ENET_RX_DV),
        .hps_0_hps_io_hps_io_emac1_inst_TX_CTL         (HPS_ENET_TX_EN),
        .hps_0_hps_io_hps_io_emac1_inst_RX_CLK         (HPS_ENET_RX_CLK),
        .hps_0_hps_io_hps_io_emac1_inst_RXD1           (HPS_ENET_RX_DATA[1]),
        .hps_0_hps_io_hps_io_emac1_inst_RXD2           (HPS_ENET_RX_DATA[2]),
        .hps_0_hps_io_hps_io_emac1_inst_RXD3           (HPS_ENET_RX_DATA[3]),
        .hps_0_hps_io_hps_io_sdio_inst_CMD             (HPS_SD_CMD),
        .hps_0_hps_io_hps_io_sdio_inst_D0              (HPS_SD_DATA[0]),
        .hps_0_hps_io_hps_io_sdio_inst_D1              (HPS_SD_DATA[1]),
        .hps_0_hps_io_hps_io_sdio_inst_CLK             (HPS_SD_CLK),
        .hps_0_hps_io_hps_io_sdio_inst_D2              (HPS_SD_DATA[2]),
        .hps_0_hps_io_hps_io_sdio_inst_D3              (HPS_SD_DATA[3]),
        .hps_0_hps_io_hps_io_usb1_inst_D0              (HPS_USB_DATA[0]),
        .hps_0_hps_io_hps_io_usb1_inst_D1              (HPS_USB_DATA[1]),
        .hps_0_hps_io_hps_io_usb1_inst_D2              (HPS_USB_DATA[2]),
        .hps_0_hps_io_hps_io_usb1_inst_D3              (HPS_USB_DATA[3]),
        .hps_0_hps_io_hps_io_usb1_inst_D4              (HPS_USB_DATA[4]),
        .hps_0_hps_io_hps_io_usb1_inst_D5              (HPS_USB_DATA[5]),
        .hps_0_hps_io_hps_io_usb1_inst_D6              (HPS_USB_DATA[6]),
        .hps_0_hps_io_hps_io_usb1_inst_D7              (HPS_USB_DATA[7]),
        .hps_0_hps_io_hps_io_usb1_inst_CLK             (HPS_USB_CLKOUT),
        .hps_0_hps_io_hps_io_usb1_inst_STP             (HPS_USB_STP),
        .hps_0_hps_io_hps_io_usb1_inst_DIR             (HPS_USB_DIR),
        .hps_0_hps_io_hps_io_usb1_inst_NXT             (HPS_USB_NXT),
        .hps_0_hps_io_hps_io_spim1_inst_CLK            (HPS_SPIM_CLK),
        .hps_0_hps_io_hps_io_spim1_inst_MOSI           (HPS_SPIM_MOSI),
        .hps_0_hps_io_hps_io_spim1_inst_MISO           (HPS_SPIM_MISO),
        .hps_0_hps_io_hps_io_spim1_inst_SS0            (HPS_SPIM_SS),
        .hps_0_hps_io_hps_io_uart0_inst_RX             (HPS_UART_RX),
        .hps_0_hps_io_hps_io_uart0_inst_TX             (HPS_UART_TX),
        .hps_0_hps_io_hps_io_i2c0_inst_SDA             (HPS_I2C0_SDAT),
        .hps_0_hps_io_hps_io_i2c0_inst_SCL             (HPS_I2C0_SCLK),
        .hps_0_hps_io_hps_io_i2c1_inst_SDA             (HPS_I2C1_SDAT),
        .hps_0_hps_io_hps_io_i2c1_inst_SCL             (HPS_I2C1_SCLK),
        .hps_0_hps_io_hps_io_gpio_inst_GPIO09          (HPS_CONV_USB_N),
        .hps_0_hps_io_hps_io_gpio_inst_GPIO35          (HPS_ENET_INT_N),
        .hps_0_hps_io_hps_io_gpio_inst_GPIO40          (HPS_LTC_GPIO),
        .hps_0_hps_io_hps_io_gpio_inst_GPIO53          (HPS_LED),
        .hps_0_hps_io_hps_io_gpio_inst_GPIO54          (HPS_KEY),
        .hps_0_hps_io_hps_io_gpio_inst_GPIO61          (HPS_GSENSOR_INT)
    );

    // =========================================================================
    // UART-Loader
    // =========================================================================
    logic [14:0] uart_rom_wr_addr;
    logic [15:0] uart_rom_wr_data;
    logic        uart_rom_wr_en;
    logic        uart_cpu_resetN;

    uart_loader #(
        .CLK_HZ (50_000_000),
        .BAUD   (115_200)
    ) loader_inst (
        .clk         (clk),
        .resetN      (KEY[0]),
        .rx          (UART_LOADER_RX),
        .tx          (UART_LOADER_TX),
        .rom_wr_addr (uart_rom_wr_addr),
        .rom_wr_data (uart_rom_wr_data),
        .rom_wr_en   (uart_rom_wr_en),
        .cpu_resetN  (uart_cpu_resetN),
        .loading     (LOADER_ACTIVE)
    );

    // =========================================================================
    // ROM-Schreibport Mux: HPS hat Priorität
    // =========================================================================
    logic [14:0] rom_wr_addr;
    logic [15:0] rom_wr_data;
    logic        rom_wr_en;

    always_comb begin
        if (hps_rom_wr_en) begin
            rom_wr_addr = hps_rom_wr_addr;
            rom_wr_data = hps_rom_wr_data;
            rom_wr_en   = 1'b1;
        end else begin
            rom_wr_addr = uart_rom_wr_addr;
            rom_wr_data = uart_rom_wr_data;
            rom_wr_en   = uart_rom_wr_en;
        end
    end

    // CPU Reset: beide Loader können die CPU anhalten
    logic loader_cpu_resetN;
    assign loader_cpu_resetN = hps_cpu_resetN & uart_cpu_resetN;
    assign rst     = ~KEY[0] | ~loader_cpu_resetN;  // CPU-Reset (wartet auf Loader)
    logic sys_rst;
    assign sys_rst = ~KEY[0];                        // System-Reset (VGA, I2C immer aktiv)

    // =========================================================================
    // CPU ↔ Memory Signale
    // =========================================================================
    logic [14:0] cpu_pc;
    logic [15:0] cpu_instruction;
    logic [15:0] cpu_mem_addr;
    logic [15:0] cpu_mem_out;
    logic        cpu_mem_write;
    logic [15:0] cpu_mem_in;

    // =========================================================================
    // Framebuffer-Verbindung
    // =========================================================================
    logic [12:0] fb_rd_addr;
    logic [15:0] fb_rd_data;

    // =========================================================================
    // Hack-CPU
    // =========================================================================
    hack_cpu cpu_inst (
        .clk         (clk),
        .rst         (rst),
        .instruction (cpu_instruction),
        .mem_in      (cpu_mem_in),
        .mem_out     (cpu_mem_out),
        .mem_addr    (cpu_mem_addr),
        .mem_write   (cpu_mem_write),
        .pc          (cpu_pc)
    );

    // =========================================================================
    // Instruction ROM
    // =========================================================================
    hack_rom #(
        .ROM_DEPTH    (32768),
        .USE_TEST_ROM (0)
    ) rom_inst (
        .clk         (clk),
        .pc          (cpu_pc),
        .instruction (cpu_instruction),
        .wr_addr     (rom_wr_addr),
        .wr_data     (rom_wr_data),
        .wr_en       (rom_wr_en)
    );

    // =========================================================================
    // Data RAM + Framebuffer
    // =========================================================================
    hack_ram_a ram_inst (
        .clk         (clk),
        .rst         (rst),
        .address     (cpu_mem_addr),
        .data_in     (cpu_mem_out),
        .write_en    (cpu_mem_write),
        .data_out    (cpu_mem_in),
        .keyboard_in (16'h0000),
        .fb_rd_addr  (fb_rd_addr),
        .fb_rd_data  (fb_rd_data),
        .per_addr    (),
        .per_data    (),
        .per_write   (),
        .per_read    (16'h0000)
    );

    // =========================================================================
    // VGA/HDMI-Controller
    // =========================================================================
    vga_ctrl_a vga_inst (
        .clk_25mhz  (clk_25mhz),
        .rst        (sys_rst),
        .fb_rd_addr (fb_rd_addr),
        .fb_rd_data (fb_rd_data),
        .hsync      (HDMI_TX_HS),
        .vsync      (HDMI_TX_VS),
        .de         (HDMI_TX_DE),
        .hdmi_d     (HDMI_TX_D),
        .hcount     (),
        .vcount     ()
    );

    assign HDMI_TX_CLK = ~clk_25mhz;

    // HDMI I2C — ADV7513 Initialisierung via Terasic I2C_HDMI_Config
    I2C_HDMI_Config hdmi_cfg (
        .iCLK        (clk),
        .iRST_N      (~sys_rst),
        .I2C_SCLK    (HDMI_I2C_SCL),
        .I2C_SDAT    (HDMI_I2C_SDA),
        .HDMI_TX_INT (1'b1),
        .READY       ()
    );

endmodule
