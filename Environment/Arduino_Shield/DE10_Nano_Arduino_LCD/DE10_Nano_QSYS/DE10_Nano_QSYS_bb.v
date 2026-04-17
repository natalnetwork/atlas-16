
module DE10_Nano_QSYS (
	adc_conduit_end_CONVST,
	adc_conduit_end_SCK,
	adc_conduit_end_SDI,
	adc_conduit_end_SDO,
	clk_clk,
	key_export,
	led_export,
	pll_locked_export,
	reset_reset_n,
	sw_export,
	tft_dc_export,
	tft_spi_MISO,
	tft_spi_MOSI,
	tft_spi_SCLK,
	tft_spi_SS_n);	

	output		adc_conduit_end_CONVST;
	output		adc_conduit_end_SCK;
	output		adc_conduit_end_SDI;
	input		adc_conduit_end_SDO;
	input		clk_clk;
	input	[3:0]	key_export;
	output	[7:0]	led_export;
	output		pll_locked_export;
	input		reset_reset_n;
	input	[9:0]	sw_export;
	output		tft_dc_export;
	input		tft_spi_MISO;
	output		tft_spi_MOSI;
	output		tft_spi_SCLK;
	output		tft_spi_SS_n;
endmodule
