// --------------------------------------------------------------------
// Copyright (c) 2010 by Terasic Technologies Inc.
// --------------------------------------------------------------------
//
// Permission:
//
//   Terasic grants permission to use and modify this code for use
//   in synthesis for all Terasic Development Boards and Altera Development
//   Kits made by Terasic.  Other use of this code, including the selling
//   ,duplication, or modification of any portion is strictly prohibited.
//
// Disclaimer:
//
//   This VHDL/Verilog or C/C++ source code is intended as a design reference
//   which illustrates how these types of functions can be implemented.
//   It is the user's responsibility to verify their design for
//   consistency and functionality through the use of formal
//   verification methods.  Terasic provides no warranty regarding the use
//   or functionality of this code.
//
// --------------------------------------------------------------------
//
//                     Terasic Technologies Inc
//                     356 Fu-Shin E. Rd Sec. 1. JhuBei City,
//                     HsinChu County, Taiwan
//                     302
//
//                     web: http://www.terasic.com/
//                     email: support@terasic.com
//
// --------------------------------------------------------------------

/*
 * adc_ltc2308.c
 *
 *  Created on: 2013/8/14
 *      Author: Richard
 */

#include "terasic_includes.h"
#include "adc_ltc2308.h"

#define ADC_LTC2308_BASE	ADC_BASE

bool ADC_LTC2308_Read(int ch, int nReadNum, alt_u16 szData[]){
	alt_u16 Value;
	int i;
	bool bSuccess = FALSE;
	alt_u32 Timeout;

		IOWR(ADC_LTC2308_BASE, 0x01, nReadNum);

		// start measure
		IOWR(ADC_LTC2308_BASE, 0x00, (ch << 1) | 0x00);
		IOWR(ADC_LTC2308_BASE, 0x00, (ch << 1) | 0x01);
		IOWR(ADC_LTC2308_BASE, 0x00, (ch << 1) | 0x00);
		usleep(1);

	// wait measure done
	Timeout = alt_nticks() + alt_ticks_per_second()/2;
	while ( ((IORD(ADC_LTC2308_BASE,0x00) & 0x01) == 0x00) && (alt_nticks() < Timeout)){

	}

	if ((IORD(ADC_LTC2308_BASE,0x00) & 0x01) == 0x01)
		bSuccess = TRUE;

		// read adc value
	if (bSuccess){
		for(i=0;i<nReadNum;i++){
			Value = IORD(ADC_LTC2308_BASE, 0x01);
			szData[i] = Value;
			//printf("CH%d=%.3fV\r\n", ch, (float)Value/1000.0);
		}
	}

	return bSuccess;

}
