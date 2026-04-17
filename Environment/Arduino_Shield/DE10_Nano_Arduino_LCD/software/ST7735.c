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
 * ST7735.c
 *
 *  Created on: 2013/8/26
 *      Author: Eric Chen
 */

#include "ST7735.h"

#include "terasic_includes.h"
#include <altera_avalon_spi.h>

alt_u8	tabcolor;
alt_u8	colstart, rowstart;
alt_u16	_width = ST7735_TFTWIDTH;
alt_u16 _height = ST7735_TFTHEIGHT;

#define DELAY	0x80

//-----
alt_u8 Rcmd1[] = {        // Init for 7735R, part 1 (red or green tab)
15,                       // 15 commands in list:
ST7735_SWRESET,   DELAY,  //  1: Software reset, 0 args, w/delay
  150,                    //     150 ms delay
ST7735_SLPOUT ,   DELAY,  //  2: Out of sleep mode, 0 args, w/delay
  255,                    //     500 ms delay
ST7735_FRMCTR1, 3      ,  //  3: Frame rate ctrl - normal mode, 3 args:
  0x01, 0x2C, 0x2D,       //     Rate = fosc/(1x2+40) * (LINE+2C+2D)
ST7735_FRMCTR2, 3      ,  //  4: Frame rate control - idle mode, 3 args:
  0x01, 0x2C, 0x2D,       //     Rate = fosc/(1x2+40) * (LINE+2C+2D)
ST7735_FRMCTR3, 6      ,  //  5: Frame rate ctrl - partial mode, 6 args:
  0x01, 0x2C, 0x2D,       //     Dot inversion mode
  0x01, 0x2C, 0x2D,       //     Line inversion mode
ST7735_INVCTR , 1      ,  //  6: Display inversion ctrl, 1 arg, no delay:
  0x07,                   //     No inversion
ST7735_PWCTR1 , 3      ,  //  7: Power control, 3 args, no delay:
  0xA2,
  0x02,                   //     -4.6V
  0x84,                   //     AUTO mode
ST7735_PWCTR2 , 1      ,  //  8: Power control, 1 arg, no delay:
  0xC5,                   //     VGH25 = 2.4C VGSEL = -10 VGH = 3 * AVDD
ST7735_PWCTR3 , 2      ,  //  9: Power control, 2 args, no delay:
  0x0A,                   //     Opamp current small
  0x00,                   //     Boost frequency
ST7735_PWCTR4 , 2      ,  // 10: Power control, 2 args, no delay:
  0x8A,                   //     BCLK/2, Opamp current small & Medium low
  0x2A,
ST7735_PWCTR5 , 2      ,  // 11: Power control, 2 args, no delay:
  0x8A, 0xEE,
ST7735_VMCTR1 , 1      ,  // 12: Power control, 1 arg, no delay:
  0x0E,
ST7735_INVOFF , 0      ,  // 13: Don't invert display, no args, no delay
ST7735_MADCTL , 1      ,  // 14: Memory access control (directions), 1 arg:
  0xC8,                   //     row addr/col addr, bottom to top refresh
ST7735_COLMOD , 1      ,  // 15: set color mode, 1 arg, no delay:
  0x05 };                 //     16-bit color

//-----
alt_u8 Rcmd2green[] = {   // Init for 7735R, part 2 (green tab only)
2,                        //  2 commands in list:
ST7735_CASET  , 4      ,  //  1: Column addr set, 4 args, no delay:
  0x00, 0x02,             //     XSTART = 0
  0x00, 0x7F+0x02,        //     XEND = 127
ST7735_RASET  , 4      ,  //  2: Row addr set, 4 args, no delay:
  0x00, 0x01,             //     XSTART = 0
  0x00, 0x9F+0x01 };      //     XEND = 159

//-----
alt_u8 Rcmd2red[] = {     // Init for 7735R, part 2 (red tab only)
2,                        //  2 commands in list:
ST7735_CASET  , 4      ,  //  1: Column addr set, 4 args, no delay:
  0x00, 0x00,             //     XSTART = 0
  0x00, 0x7F,             //     XEND = 127
ST7735_RASET  , 4      ,  //  2: Row addr set, 4 args, no delay:
  0x00, 0x00,             //     XSTART = 0
  0x00, 0x9F };           //     XEND = 159

//-----
alt_u8 Rcmd3[] = {        // Init for 7735R, part 3 (red or green tab)
4,                        //  4 commands in list:
ST7735_GMCTRP1, 16      , //  1: Magical unicorn dust, 16 args, no delay:
  0x02, 0x1c, 0x07, 0x12,
  0x37, 0x32, 0x29, 0x2d,
  0x29, 0x25, 0x2B, 0x39,
  0x00, 0x01, 0x03, 0x10,
ST7735_GMCTRN1, 16      , //  2: Sparkles and rainbows, 16 args, no delay:
  0x03, 0x1d, 0x07, 0x06,
  0x2E, 0x2C, 0x29, 0x2D,
  0x2E, 0x2E, 0x37, 0x3F,
  0x00, 0x00, 0x02, 0x10,
ST7735_NORON  ,    DELAY, //  3: Normal display on, no args, w/delay
  10,                     //     10 ms delay
ST7735_DISPON ,    DELAY, //  4: Main screen turn on, no args w/delay
  100 };                  //     100 ms delay

//=============================================================================
void ST7735_write_byte(alt_u8 st7735_d_cx, alt_u8 st7735_data)
{
	alt_u8 tx_data = st7735_data;
	alt_u8 rx_data;
	alt_u8 spi_flags = 0;

	IOWR_ALTERA_AVALON_PIO_DATA(TFT_CD_BASE, st7735_d_cx);	// st7735_d_cx = Low,  command data
															// st7735_d_cx = High, display data or parameter

	alt_avalon_spi_command(TFT_SPI_BASE, 0, 1, &tx_data, 0, &rx_data, spi_flags);

	IOWR_ALTERA_AVALON_PIO_DATA(TFT_CD_BASE, 0x1);			// st7735_d_cx = High, display data or parameter
}

//=============================================================================
//=============================================================================

// Companion code to the above tables.  Reads and issues
// a series of LCD commands stored in PROGMEM byte array.
void ST7735_commandList(alt_u8 *addr) {

	alt_u8	numCommands, numArgs;
	alt_u16	ms;

	numCommands = *addr++;									// Number of commands to follow
	while(numCommands--) {									// For each command...
		ST7735_write_byte(ST7735_WRITE_COMM, *addr++);		//   Read, issue command
		numArgs  = *addr++;									//   Number of args to follow
		ms       = numArgs & DELAY;							//   If hibit set, delay follows args
		numArgs &= ~DELAY;									//   Mask out delay bit
		while(numArgs--) {									//   For each argument...
			ST7735_write_byte(ST7735_WRITE_DATA, *addr++);	//     Read, issue argument
		}

		if(ms) {
			ms = *addr++; 									// Read post-command delay time (ms)
			if(ms == 255) ms = 500;     					// If 255, delay for 500 ms
			usleep(ms*1000);
		}
	}
}



// Initialization for ST7735R screens (green or red tabs)
void ST7735_initR(alt_u8 options)
{
	ST7735_commandList(Rcmd1);		// Initialization code common to both 'B' and 'R' type displays
	if(options == INITR_GREENTAB) {
		ST7735_commandList(Rcmd2green);
		colstart = 2;
		rowstart = 1;
	} else {
		// colstart, rowstart left at default '0' values
		ST7735_commandList(Rcmd2red);
	}
	ST7735_commandList(Rcmd3);

	// if black, change MADCTL color filter
	if (options == INITR_BLACKTAB) {
		ST7735_write_byte(ST7735_WRITE_COMM, ST7735_MADCTL);
		ST7735_write_byte(ST7735_WRITE_DATA, 0xC0);
	}

	tabcolor = options;
}


void ST7735_setAddrWindow(alt_u8 x0, alt_u8 y0, alt_u8 x1, alt_u8 y1)
{
	ST7735_write_byte(ST7735_WRITE_COMM, ST7735_CASET);			// Column addr set
	ST7735_write_byte(ST7735_WRITE_DATA, 0x00);
	ST7735_write_byte(ST7735_WRITE_DATA, x0+colstart);			// XSTART
	ST7735_write_byte(ST7735_WRITE_DATA, 0x00);
	ST7735_write_byte(ST7735_WRITE_DATA, x1+colstart);			// XEND

	ST7735_write_byte(ST7735_WRITE_COMM, ST7735_RASET);			// Row addr set
	ST7735_write_byte(ST7735_WRITE_DATA, 0x00);
	ST7735_write_byte(ST7735_WRITE_DATA, y0+rowstart);			// YSTART
	ST7735_write_byte(ST7735_WRITE_DATA, 0x00);
	ST7735_write_byte(ST7735_WRITE_DATA, y1+rowstart);			// YEND

	ST7735_write_byte(ST7735_WRITE_COMM, ST7735_RAMWR);			// write to RAM
}




void ST7735_drawFastVLine(alt_u16 x, alt_u16 y, alt_u16 h, alt_u16 color)
{
	alt_u8	hi, lo;
	// Rudimentary clipping
	if((x >= _width) || (y >= _height)) return;
	if((y+h-1) >= _height) h = _height-y;
	ST7735_setAddrWindow(x, y, x, y+h-1);

	hi = color >> 8, lo = color;
		while (h--) {
			ST7735_write_byte(ST7735_WRITE_DATA, hi);
			ST7735_write_byte(ST7735_WRITE_DATA, lo);
		}

}

/******************************************************************
*  Function: ST7735_fillScreen
*
*  Purpose: fill a full screen using the specified color.
*
******************************************************************/

void ST7735_fillScreen(alt_u16 color)
{
	ST7735_fillRect(0, 0,  _width, _height, color);
}

/******************************************************************
*  Function: ST7735_fillRect
*
*  Purpose: fill a rectangle to the specified location of the
*           screen using the specified color.
*
******************************************************************/
void ST7735_fillRect(alt_u16 x, alt_u16 y, alt_u16 w, alt_u16 h, alt_u16 color)
{
	alt_u8	hi, lo;
	// rudimentary clipping (drawChar w/big text requires this)
	if((x >= _width) || (y >= _height)) return;
	if((x + w - 1) >= _width)  w = _width  - x;
	if((y + h - 1) >= _height) h = _height - y;

	ST7735_setAddrWindow(x, y, x+w-1, y+h-1);

	hi = color >> 8, lo = color;
	for(y=h; y>0; y--) {
		for(x=w; x>0; x--) {
			ST7735_write_byte(ST7735_WRITE_DATA, hi);
			ST7735_write_byte(ST7735_WRITE_DATA, lo);
		}
	}
}

//=============================================================================
//=============================================================================
//=============================================================================

/******************************************************************
*  Function: ST7735_draw_sloped_line
*
*  Purpose: Draws a line between two end points using
*           Bresenham's line drawing algorithm.
*           width parameter is not used.
*           It is reserved for future use.
*
******************************************************************/
void ST7735_draw_sloped_line( unsigned short horiz_start,
                              unsigned short vert_start,
                              unsigned short horiz_end,
                              unsigned short vert_end,
                              unsigned short width,
                              int color )

{
  // Find the vertical and horizontal distance between the two points
  int horiz_delta = abs(horiz_end-horiz_start);
  int vert_delta = abs(vert_end-vert_start);

  // Find out what direction we are going
  int horiz_incr, vert_incr;
  if (horiz_start > horiz_end) { horiz_incr=-1; } else { horiz_incr=1; }
  if (vert_start > vert_end) { vert_incr=-1; } else { vert_incr=1; }

  // Find out which axis is always incremented when drawing the line
  // If it's the horizontal axis
  if (horiz_delta >= vert_delta) {
    int dPr   = vert_delta<<1;
    int dPru  = dPr - (horiz_delta<<1);
    int P     = dPr - horiz_delta;

    // Process the line, one horizontal point at at time
    for (; horiz_delta >= 0; horiz_delta--) {
      // plot the pixel
    	ST7735_draw_Pixel(horiz_start, vert_start, color);
      // If we're moving both up and right
      if (P > 0) {
        horiz_start+=horiz_incr;
        vert_start+=vert_incr;
        P+=dPru;
      } else {
        horiz_start+=horiz_incr;
        P+=dPr;
      }
    }
  // If it's the vertical axis
  } else {
    int dPr   = horiz_delta<<1;
    int dPru  = dPr - (vert_delta<<1);
    int P     = dPr - vert_delta;

    // Process the line, one vertical point at at time
    for (; vert_delta>=0; vert_delta--) {
      // plot the pixel
    	ST7735_draw_Pixel(horiz_start, vert_start, color);
      // If we're moving both up and right
      if (P > 0) {
        horiz_start+=horiz_incr;
        vert_start+=vert_incr;
        P+=dPru;
      } else {
        vert_start+=vert_incr;
        P+=dPr;
      }
    }
  }
}

/******************************************************************
*  Function: ST7735_draw_circle
*
*  Purpose: Draws a circle on the screen with the specified center
*  and radius.  Draws symetric circles only.  The fill parameter
*  tells the function whether or not to fill in the box.  1 = fill,
*  0 = do not fill.
*
******************************************************************/
int ST7735_draw_circle(int Hcenter, int Vcenter, int radius, int color, char fill)
{
  int x = 0;
  int y = radius;
  int p = (5 - radius*4)/4;

  // Start the circle with the top, bottom, left, and right pixels.
  ST7735_round_corner_points(Hcenter, Vcenter, x, y, 0, 0, color, fill);

  // Now start moving out from those points until the lines meet
  while (x < y) {
    x++;
    if (p < 0) {
      p += 2*x+1;
    } else {
      y--;
      p += 2*(x-y)+1;
    }
    ST7735_round_corner_points(Hcenter, Vcenter, x, y, 0, 0, color, fill);
  }
  return (0);
}

/******************************************************************
*  Function: ST7735_round_corner_points
*
*  Purpose: Called by vid_draw_round_corner_box() and
*  vid_draw_circle() to plot the actual points of the round corners.
*  Draws horizontal lines to fill the shape.
*  0 = do not fill.
*
******************************************************************/

void ST7735_round_corner_points( int cx, int cy, int x, int y,
                              int straight_width, int straight_height,
                              int color, char fill )
{

    // If we're directly above, below, left and right of center (0 degrees), plot those 4 pixels
    if (x == 0) {
        // bottom
    	ST7735_draw_Pixel(cx, cy + y + straight_height, color);
    	ST7735_draw_Pixel(cx + straight_width, cy + y + straight_height, color);
        // top
    	ST7735_draw_Pixel(cx, cy - y, color);
    	ST7735_draw_Pixel(cx + straight_width, cy - y, color);

        if(fill) {
          ST7735_draw_sloped_line(cx - y, cy, cx + y + straight_width, cy, 1, color);
          ST7735_draw_sloped_line(cx - y, cy + straight_height, cx + y + straight_width, cy + straight_height, 1, color);
        } else {
          //right
          ST7735_draw_Pixel(cx + y + straight_width, cy, color);
          ST7735_draw_Pixel(cx + y + straight_width, cy + straight_height, color);
          //left
          ST7735_draw_Pixel(cx - y, cy, color);
          ST7735_draw_Pixel(cx - y, cy + straight_height, color);
        }

    } else
    // If we've reached the 45 degree points (x=y), plot those 4 pixels
    if (x == y) {
      if(fill) {
        ST7735_draw_sloped_line(cx - x, cy + y + straight_height, cx + x + straight_width, cy + y + straight_height, 1, color); // lower
        ST7735_draw_sloped_line(cx - x, cy - y, cx + x + straight_width, cy - y, 1, color); // upper

      } else {
        ST7735_draw_Pixel(cx + x + straight_width, cy + y + straight_height, color); // bottom right
        ST7735_draw_Pixel(cx - x, cy + y + straight_height, color); // bottom left
        ST7735_draw_Pixel(cx + x + straight_width, cy - y, color); // top right
        ST7735_draw_Pixel(cx - x, cy - y, color); // top left
      }
    } else
    // If we're between 0 and 45 degrees plot 8 pixels.
    if (x < y) {
        if(fill) {
          ST7735_draw_sloped_line(cx - x, cy + y + straight_height, cx + x + straight_width, cy + y + straight_height, 1, color);
          ST7735_draw_sloped_line(cx - y, cy + x + straight_height, cx + y + straight_width, cy + x + straight_height, 1, color);
          ST7735_draw_sloped_line(cx - y, cy - x, cx + y + straight_width, cy - x, 1, color);
          ST7735_draw_sloped_line(cx - x, cy - y, cx + x + straight_width, cy - y, 1, color);
        } else {
          ST7735_draw_Pixel(cx + x + straight_width, cy + y + straight_height, color);
          ST7735_draw_Pixel(cx - x, cy + y + straight_height, color);
          ST7735_draw_Pixel(cx + x + straight_width, cy - y, color);
          ST7735_draw_Pixel(cx - x, cy - y, color);
          ST7735_draw_Pixel(cx + y + straight_width, cy + x + straight_height, color);
          ST7735_draw_Pixel(cx - y, cy + x + straight_height, color);
          ST7735_draw_Pixel(cx + y + straight_width, cy - x, color);
          ST7735_draw_Pixel(cx - y, cy - x, color);
        }
    }
}

/******************************************************************
*  Function: ST7735_print_string
*
*  Purpose: Prints a string to the specified location of the screen
*           using the specified font and color.
*           Calls vid_print_char
*
******************************************************************/
int ST7735_print_string(int horiz_offset, int vert_offset, int color, char *font, char string[])
{
  int i = 0;
  int original_horiz_offset;

  original_horiz_offset = horiz_offset;

  // Print until we hit the '\0' char.
  while (string[i]) {
    //Handle newline char here.
    if (string[i] == '\n') {
      horiz_offset = original_horiz_offset;
      vert_offset += 12;
      i++;
      continue;
    }
    // Lay down that character and increment our offsets.
    ST7735_print_char(horiz_offset, vert_offset, color, string[i], font);
    i++;
    horiz_offset += 8;
  }
  return (0);
}


/******************************************************************
*  Function: ST7735_print_char
*
*  Purpose: Prints a character to the specified location of the
*           screen using the specified font and color.
*
******************************************************************/
int ST7735_print_char (int horiz_offset, int vert_offset, int color, char character, char *font)
{

  int i, j;

  char temp_char, char_row;

  // Convert the ASCII value to an array offset
  temp_char = (character - 0x20);

  //Each character is 8 pixels wide and 11 tall.
  for(i = 0; i < 11; i++) {
      char_row = *(font + (temp_char * FONT_10PT_ROW) + i);
    for (j = 0; j < 8; j++) {
      //If the font table says the pixel in this location is on for this character, then set it.
      if (char_row & (((unsigned char)0x80) >> j)) {
    	  ST7735_draw_Pixel((horiz_offset + j), (vert_offset + i), color); // draw the pixel to panel
      }
    }
  }
  return(0);
}


/******************************************************************
*  Function: ST7735_draw_Pixel
*
*  Purpose: Sets the specified pixel to the specified color.
*           Sets one pixel although frame buffer consists of
*           two-pixel words.  Therefore this function is not
*           efficient when painting large areas of the screen.
*
******************************************************************/
void ST7735_draw_Pixel(alt_u16 x, alt_u16 y, alt_u16 color)
{
	if((x >= 0) && (x < _width) && (y >= 0) && (y < _height)){
	ST7735_setAddrWindow(x,y,x+1,y+1);
	ST7735_write_byte(ST7735_WRITE_DATA, color >> 8);
	ST7735_write_byte(ST7735_WRITE_DATA, color);
	}
}

//=============================================================================
#define MADCTL_MY  0x80
#define MADCTL_MX  0x40
#define MADCTL_MV  0x20
#define MADCTL_ML  0x10
#define MADCTL_RGB 0x00
#define MADCTL_BGR 0x08
#define MADCTL_MH  0x04

void ST7735_setRotation(alt_u8 m)
{
	alt_u8	rotation;

	ST7735_write_byte(ST7735_WRITE_COMM, ST7735_MADCTL);//writecommand(ST7735_MADCTL);
	rotation = m % 4; // can't be higher than 3
	switch (rotation) {
	case 0:
		if (tabcolor == INITR_BLACKTAB) {
			ST7735_write_byte(ST7735_WRITE_DATA, MADCTL_MX | MADCTL_MY | MADCTL_RGB);//writedata(MADCTL_MX | MADCTL_MY | MADCTL_RGB);
		} else {
			ST7735_write_byte(ST7735_WRITE_DATA, MADCTL_MX | MADCTL_MY | MADCTL_BGR);//writedata(MADCTL_MX | MADCTL_MY | MADCTL_BGR);
		}
		_width  = ST7735_TFTWIDTH;
		_height = ST7735_TFTHEIGHT;
		break;
	case 1:
		if (tabcolor == INITR_BLACKTAB) {
			ST7735_write_byte(ST7735_WRITE_DATA, MADCTL_MY | MADCTL_MV | MADCTL_RGB);//writedata(MADCTL_MY | MADCTL_MV | MADCTL_RGB);
		} else {
			ST7735_write_byte(ST7735_WRITE_DATA, MADCTL_MY | MADCTL_MV | MADCTL_BGR);//writedata(MADCTL_MY | MADCTL_MV | MADCTL_BGR);
		}
		_width  = ST7735_TFTHEIGHT;
		_height = ST7735_TFTWIDTH;
		break;
	case 2:
		if (tabcolor == INITR_BLACKTAB) {
			ST7735_write_byte(ST7735_WRITE_DATA, MADCTL_RGB);//writedata(MADCTL_RGB);
		} else {
			ST7735_write_byte(ST7735_WRITE_DATA, MADCTL_BGR);//writedata(MADCTL_BGR);
		}
		_width  = ST7735_TFTWIDTH;
		_height = ST7735_TFTHEIGHT;
		break;
	case 3:
		if (tabcolor == INITR_BLACKTAB) {
			ST7735_write_byte(ST7735_WRITE_DATA, MADCTL_MX | MADCTL_MV | MADCTL_RGB);//writedata(MADCTL_MX | MADCTL_MV | MADCTL_RGB);
		} else {
			ST7735_write_byte(ST7735_WRITE_DATA, MADCTL_MX | MADCTL_MV | MADCTL_BGR);//writedata(MADCTL_MX | MADCTL_MV | MADCTL_BGR);
		}
		_width  = ST7735_TFTHEIGHT;
		_height = ST7735_TFTWIDTH;
		break;
	}
}



/******************************************************************
*  Data: cour10_font
*
*  Purpose: Data array that represents a 10-point courier font.
*
******************************************************************/
char cour10_font_array[95][11] = {
 {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},
 {0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x00, 0x10, 0x00, 0x00},
 {0x28, 0x28, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},
 {0x14, 0x14, 0x7E, 0x28, 0x28, 0x28, 0xFC, 0x50, 0x50, 0x00, 0x00},
 {0x10, 0x38, 0x44, 0x40, 0x38, 0x04, 0x44, 0x38, 0x10, 0x00, 0x00},
 {0x40, 0xA2, 0x44, 0x08, 0x10, 0x20, 0x44, 0x8A, 0x04, 0x00, 0x00},
 {0x30, 0x40, 0x40, 0x20, 0x60, 0x92, 0x94, 0x88, 0x76, 0x00, 0x00},
 {0x10, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},
 {0x08, 0x10, 0x10, 0x20, 0x20, 0x20, 0x20, 0x20, 0x10, 0x10, 0x08},
 {0x20, 0x10, 0x10, 0x08, 0x08, 0x08, 0x08, 0x08, 0x10, 0x10, 0x20},
 {0x00, 0x00, 0x6C, 0x38, 0xFE, 0x38, 0x6C, 0x00, 0x00, 0x00, 0x00},
 {0x00, 0x10, 0x10, 0x10, 0xFE, 0x10, 0x10, 0x10, 0x00, 0x00, 0x00},
 {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x20, 0x00},
 {0x00, 0x00, 0x00, 0x00, 0xFE, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},
 {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x00, 0x00},
 {0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x00, 0x00, 0x00, 0x00},
 {0x38, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x38, 0x00, 0x00},
 {0x10, 0x70, 0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x7C, 0x00, 0x00},
 {0x38, 0x44, 0x04, 0x04, 0x08, 0x10, 0x20, 0x40, 0x7C, 0x00, 0x00},
 {0x38, 0x44, 0x04, 0x04, 0x18, 0x04, 0x04, 0x44, 0x38, 0x00, 0x00},
 {0x08, 0x18, 0x18, 0x28, 0x28, 0x48, 0x7C, 0x08, 0x1C, 0x00, 0x00},
 {0x7C, 0x40, 0x40, 0x40, 0x78, 0x04, 0x04, 0x44, 0x38, 0x00, 0x00},
 {0x18, 0x20, 0x40, 0x40, 0x78, 0x44, 0x44, 0x44, 0x38, 0x00, 0x00},
 {0x7C, 0x44, 0x04, 0x08, 0x08, 0x10, 0x10, 0x20, 0x20, 0x00, 0x00},
 {0x38, 0x44, 0x44, 0x44, 0x38, 0x44, 0x44, 0x44, 0x38, 0x00, 0x00},
 {0x38, 0x44, 0x44, 0x44, 0x3C, 0x04, 0x04, 0x08, 0x30, 0x00, 0x00},
 {0x00, 0x00, 0x10, 0x00, 0x00, 0x00, 0x10, 0x00, 0x00, 0x00, 0x00},
 {0x00, 0x00, 0x10, 0x00, 0x00, 0x00, 0x10, 0x20, 0x00, 0x00, 0x00},
 {0x00, 0x04, 0x08, 0x10, 0x20, 0x10, 0x08, 0x04, 0x00, 0x00, 0x00},
 {0x00, 0x00, 0x00, 0x7C, 0x00, 0x7C, 0x00, 0x00, 0x00, 0x00, 0x00},
 {0x00, 0x20, 0x10, 0x08, 0x04, 0x08, 0x10, 0x20, 0x00, 0x00, 0x00},
 {0x38, 0x44, 0x04, 0x04, 0x08, 0x10, 0x10, 0x00, 0x10, 0x00, 0x00},
 {0x3C, 0x42, 0x9A, 0xAA, 0xAA, 0xAA, 0x9C, 0x40, 0x38, 0x00, 0x00},
 {0x30, 0x10, 0x10, 0x28, 0x28, 0x44, 0x7C, 0x44, 0xEE, 0x00, 0x00},
 {0xFC, 0x42, 0x42, 0x42, 0x7C, 0x42, 0x42, 0x42, 0xFC, 0x00, 0x00},
 {0x3C, 0x42, 0x80, 0x80, 0x80, 0x80, 0x80, 0x42, 0x3C, 0x00, 0x00},
 {0xF8, 0x44, 0x42, 0x42, 0x42, 0x42, 0x42, 0x44, 0xF8, 0x00, 0x00},
 {0xFE, 0x42, 0x40, 0x48, 0x78, 0x48, 0x40, 0x42, 0xFE, 0x00, 0x00},
 {0xFE, 0x42, 0x40, 0x48, 0x78, 0x48, 0x40, 0x40, 0xF0, 0x00, 0x00},
 {0x3C, 0x42, 0x80, 0x80, 0x80, 0x8E, 0x82, 0x42, 0x3C, 0x00, 0x00},
 {0xEE, 0x44, 0x44, 0x44, 0x7C, 0x44, 0x44, 0x44, 0xEE, 0x00, 0x00},
 {0x7C, 0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x7C, 0x00, 0x00},
 {0x1E, 0x04, 0x04, 0x04, 0x04, 0x04, 0x44, 0x44, 0x38, 0x00, 0x00},
 {0xE6, 0x44, 0x48, 0x48, 0x50, 0x70, 0x48, 0x44, 0xE6, 0x00, 0x00},
 {0xF8, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x22, 0xFE, 0x00, 0x00},
 {0xC6, 0x44, 0x6C, 0x6C, 0x54, 0x54, 0x44, 0x44, 0xEE, 0x00, 0x00},
 {0xCE, 0x44, 0x64, 0x64, 0x54, 0x4C, 0x4C, 0x44, 0xE4, 0x00, 0x00},
 {0x38, 0x44, 0x82, 0x82, 0x82, 0x82, 0x82, 0x44, 0x38, 0x00, 0x00},
 {0xFC, 0x42, 0x42, 0x42, 0x7C, 0x40, 0x40, 0x40, 0xF0, 0x00, 0x00},
 {0x38, 0x44, 0x82, 0x82, 0x82, 0x82, 0x82, 0x44, 0x38, 0x36, 0x00},
 {0xFC, 0x42, 0x42, 0x42, 0x7C, 0x48, 0x48, 0x44, 0xE6, 0x00, 0x00},
 {0x7C, 0x82, 0x80, 0x80, 0x7C, 0x02, 0x02, 0x82, 0x7C, 0x00, 0x00},
 {0xFE, 0x92, 0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x38, 0x00, 0x00},
 {0xEE, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x38, 0x00, 0x00},
 {0xEE, 0x44, 0x44, 0x44, 0x28, 0x28, 0x28, 0x10, 0x10, 0x00, 0x00},
 {0xEE, 0x44, 0x44, 0x44, 0x54, 0x54, 0x54, 0x28, 0x28, 0x00, 0x00},
 {0xEE, 0x44, 0x28, 0x28, 0x10, 0x28, 0x28, 0x44, 0xEE, 0x00, 0x00},
 {0xEE, 0x44, 0x44, 0x28, 0x28, 0x10, 0x10, 0x10, 0x38, 0x00, 0x00},
 {0xFE, 0x84, 0x08, 0x08, 0x10, 0x20, 0x20, 0x42, 0xFE, 0x00, 0x00},
 {0x38, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x38, 0x00, 0x00},
 {0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x00, 0x00, 0x00, 0x00},
 {0x1C, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04, 0x1C, 0x00, 0x00},
 {0x10, 0x28, 0x44, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},
 {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFE, 0x00, 0x00},
 {0x20, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},
 {0x00, 0x00, 0x00, 0x78, 0x04, 0x7C, 0x84, 0x84, 0x7A, 0x00, 0x00},
 {0xC0, 0x40, 0x40, 0x7C, 0x42, 0x42, 0x42, 0x42, 0xFC, 0x00, 0x00},
 {0x00, 0x00, 0x00, 0x7C, 0x82, 0x80, 0x80, 0x82, 0x7C, 0x00, 0x00},
 {0x0C, 0x04, 0x04, 0x7C, 0x84, 0x84, 0x84, 0x84, 0x7E, 0x00, 0x00},
 {0x00, 0x00, 0x00, 0x7C, 0x82, 0xFE, 0x80, 0x82, 0x7C, 0x00, 0x00},
 {0x30, 0x40, 0x40, 0xF0, 0x40, 0x40, 0x40, 0x40, 0xF0, 0x00, 0x00},
 {0x00, 0x00, 0x00, 0x7E, 0x84, 0x84, 0x84, 0x7C, 0x04, 0x04, 0x78},
 {0xC0, 0x40, 0x40, 0x58, 0x64, 0x44, 0x44, 0x44, 0xEE, 0x00, 0x00},
 {0x08, 0x00, 0x00, 0x38, 0x08, 0x08, 0x08, 0x08, 0x3E, 0x00, 0x00},
 {0x08, 0x00, 0x00, 0x78, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x70},
 {0xC0, 0x40, 0x40, 0x4C, 0x48, 0x50, 0x70, 0x48, 0xC6, 0x00, 0x00},
 {0x30, 0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x7C, 0x00, 0x00},
 {0x00, 0x00, 0x00, 0xE8, 0x54, 0x54, 0x54, 0x54, 0xD6, 0x00, 0x00},
 {0x00, 0x00, 0x00, 0xD8, 0x64, 0x44, 0x44, 0x44, 0xEE, 0x00, 0x00},
 {0x00, 0x00, 0x00, 0x7C, 0x82, 0x82, 0x82, 0x82, 0x7C, 0x00, 0x00},
 {0x00, 0x00, 0x00, 0xFC, 0x42, 0x42, 0x42, 0x42, 0x7C, 0x40, 0xE0},
 {0x00, 0x00, 0x00, 0x7E, 0x84, 0x84, 0x84, 0x7C, 0x04, 0x0E, 0x00},
 {0x00, 0x00, 0x00, 0xEC, 0x32, 0x20, 0x20, 0x20, 0xF8, 0x00, 0x00},
 {0x00, 0x00, 0x00, 0x7C, 0x82, 0x70, 0x0C, 0x82, 0x7C, 0x00, 0x00},
 {0x00, 0x20, 0x20, 0x78, 0x20, 0x20, 0x20, 0x24, 0x18, 0x00, 0x00},
 {0x00, 0x00, 0x00, 0xCC, 0x44, 0x44, 0x44, 0x4C, 0x36, 0x00, 0x00},
 {0x00, 0x00, 0x00, 0xEE, 0x44, 0x44, 0x28, 0x28, 0x10, 0x00, 0x00},
 {0x00, 0x00, 0x00, 0xEE, 0x44, 0x54, 0x54, 0x28, 0x28, 0x00, 0x00},
 {0x00, 0x00, 0x00, 0xEE, 0x44, 0x38, 0x38, 0x44, 0xEE, 0x00, 0x00},
 {0x00, 0x00, 0x00, 0xEE, 0x44, 0x44, 0x28, 0x28, 0x10, 0x10, 0x60},
 {0x00, 0x00, 0x00, 0xFC, 0x88, 0x10, 0x20, 0x44, 0xFC, 0x00, 0x00},
 {0x0C, 0x10, 0x10, 0x10, 0x10, 0x60, 0x10, 0x10, 0x10, 0x10, 0x0C},
 {0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x10},
 {0x60, 0x10, 0x10, 0x10, 0x10, 0x0C, 0x10, 0x10, 0x10, 0x10, 0x60},
 {0x00, 0x00, 0x62, 0x92, 0x8C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00} };

//Pointer to our font table
char* cour10_font = &cour10_font_array[0][0];
