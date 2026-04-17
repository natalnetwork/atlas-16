	component DE10_Nano_QSYS is
		port (
			adc_conduit_end_CONVST : out std_logic;                                       -- CONVST
			adc_conduit_end_SCK    : out std_logic;                                       -- SCK
			adc_conduit_end_SDI    : out std_logic;                                       -- SDI
			adc_conduit_end_SDO    : in  std_logic                    := 'X';             -- SDO
			clk_clk                : in  std_logic                    := 'X';             -- clk
			key_export             : in  std_logic_vector(3 downto 0) := (others => 'X'); -- export
			led_export             : out std_logic_vector(7 downto 0);                    -- export
			pll_locked_export      : out std_logic;                                       -- export
			reset_reset_n          : in  std_logic                    := 'X';             -- reset_n
			sw_export              : in  std_logic_vector(9 downto 0) := (others => 'X'); -- export
			tft_dc_export          : out std_logic;                                       -- export
			tft_spi_MISO           : in  std_logic                    := 'X';             -- MISO
			tft_spi_MOSI           : out std_logic;                                       -- MOSI
			tft_spi_SCLK           : out std_logic;                                       -- SCLK
			tft_spi_SS_n           : out std_logic                                        -- SS_n
		);
	end component DE10_Nano_QSYS;

	u0 : component DE10_Nano_QSYS
		port map (
			adc_conduit_end_CONVST => CONNECTED_TO_adc_conduit_end_CONVST, -- adc_conduit_end.CONVST
			adc_conduit_end_SCK    => CONNECTED_TO_adc_conduit_end_SCK,    --                .SCK
			adc_conduit_end_SDI    => CONNECTED_TO_adc_conduit_end_SDI,    --                .SDI
			adc_conduit_end_SDO    => CONNECTED_TO_adc_conduit_end_SDO,    --                .SDO
			clk_clk                => CONNECTED_TO_clk_clk,                --             clk.clk
			key_export             => CONNECTED_TO_key_export,             --             key.export
			led_export             => CONNECTED_TO_led_export,             --             led.export
			pll_locked_export      => CONNECTED_TO_pll_locked_export,      --      pll_locked.export
			reset_reset_n          => CONNECTED_TO_reset_reset_n,          --           reset.reset_n
			sw_export              => CONNECTED_TO_sw_export,              --              sw.export
			tft_dc_export          => CONNECTED_TO_tft_dc_export,          --          tft_dc.export
			tft_spi_MISO           => CONNECTED_TO_tft_spi_MISO,           --         tft_spi.MISO
			tft_spi_MOSI           => CONNECTED_TO_tft_spi_MOSI,           --                .MOSI
			tft_spi_SCLK           => CONNECTED_TO_tft_spi_SCLK,           --                .SCLK
			tft_spi_SS_n           => CONNECTED_TO_tft_spi_SS_n            --                .SS_n
		);

