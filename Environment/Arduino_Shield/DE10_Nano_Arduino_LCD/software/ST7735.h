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
 * ST7735.h
 *
 *  Created on: 2013/8/26
 *      Author: Eric Chen
 */

#ifndef __ST7735_H__
#define __ST7735_H__

#include <stddef.h>
#include "alt_types.h"

// define for font
#define FONT_10PT_ROW 11
#define FONT_10PT_COLUMN 8

extern char* cour10_font;


//-ST7735 define
// some flags for initR() :(
#define INITR_GREENTAB		0x0
#define INITR_REDTAB		0x1
#define INITR_BLACKTAB		0x2

#define ST7735_TFTWIDTH		128
#define ST7735_TFTHEIGHT	160

#define ST7735_NOP			0x00
#define ST7735_SWRESET		0x01
#define ST7735_RDDID		0x04
#define ST7735_RDDST		0x09

#define ST7735_SLPIN		0x10
#define ST7735_SLPOUT		0x11
#define ST7735_PTLON		0x12
#define ST7735_NORON		0x13

#define ST7735_INVOFF		0x20
#define ST7735_INVON		0x21
#define ST7735_DISPOFF		0x28
#define ST7735_DISPON		0x29
#define ST7735_CASET		0x2A
#define ST7735_RASET		0x2B
#define ST7735_RAMWR		0x2C
#define ST7735_RAMRD		0x2E

#define ST7735_PTLAR		0x30
#define ST7735_COLMOD		0x3A
#define ST7735_MADCTL		0x36

#define ST7735_FRMCTR1		0xB1
#define ST7735_FRMCTR2		0xB2
#define ST7735_FRMCTR3		0xB3
#define ST7735_INVCTR		0xB4
#define ST7735_DISSET5		0xB6

#define ST7735_PWCTR1		0xC0
#define ST7735_PWCTR2		0xC1
#define ST7735_PWCTR3		0xC2
#define ST7735_PWCTR4		0xC3
#define ST7735_PWCTR5		0xC4
#define ST7735_VMCTR1		0xC5

#define ST7735_RDID1		0xDA
#define ST7735_RDID2		0xDB
#define ST7735_RDID3		0xDC
#define ST7735_RDID4		0xDD

#define ST7735_PWCTR6		0xFC

#define ST7735_GMCTRP1		0xE0
#define ST7735_GMCTRN1		0xE1

// Color definitions
#define	ST7735_BLACK		0x0000
#define	ST7735_BLUE			0x001F
#define	ST7735_RED			0xF800
#define	ST7735_GREEN		0x07E0
#define ST7735_CYAN			0x07FF
#define ST7735_MAGENTA		0xF81F
#define ST7735_YELLOW		0xFFE0
#define ST7735_WHITE		0xFFFF



#define	ST7735_WRITE_DATA	1
#define	ST7735_WRITE_COMM	0

#ifdef __cplusplus
extern "C"
{
#endif /* __cplusplus */


void ST7735_write_byte(alt_u8 st7735_d_cx, alt_u8 st7735_data);
void ST7735_initR(alt_u8 options);

void ST7735_setAddrWindow(alt_u8 x0, alt_u8 y0, alt_u8 x1, alt_u8 y1);

void ST7735_drawFastVLine(alt_u16 x, alt_u16 y, alt_u16 h, alt_u16 color);

void ST7735_fillScreen(alt_u16 color);
void ST7735_fillRect(alt_u16 x, alt_u16 y, alt_u16 w, alt_u16 h, alt_u16 color);

void ST7735_draw_sloped_line( unsigned short horiz_start,
                              unsigned short vert_start,
                              unsigned short horiz_end,
                              unsigned short vert_end,
                              unsigned short width,
                              int color );

int ST7735_draw_circle(int Hcenter, int Vcenter, int radius, int color, char fill);
void ST7735_round_corner_points( int cx, int cy, int x, int y,
                              int straight_width, int straight_height,
                              int color, char fill );

int ST7735_print_string(int horiz_offset, int vert_offset, int color, char *font, char string[]);
int ST7735_print_char (int horiz_offset, int vert_offset, int color, char character, char *font);
void ST7735_draw_Pixel(alt_u16 x, alt_u16 y, alt_u16 color);


void ST7735_setRotation(alt_u8 m);

#ifdef __cplusplus
}
#endif /* __cplusplus */

#endif /* __ST7735_H__ */
