/*
 * "Hello World" example.
 *
 * This example prints 'Hello from Nios II' to the STDOUT stream. It runs on
 * the Nios II 'standard', 'full_featured', 'fast', and 'low_cost' example
 * designs. It runs with or without the MicroC/OS-II RTOS and requires a STDOUT
 * device in your system's hardware.
 * The memory footprint of this hosted application is ~69 kbytes by default
 * using the standard reference design.
 *
 * For a reduced footprint version of this template, and an explanation of how
 * to reduce the memory footprint for a given application, see the
 * "small_hello_world" template.
 *
 */

#include <stdio.h>
#include <altera_avalon_pio_regs.h>
#include <altera_avalon_spi.h>

#include "terasic_includes.h"

#include "ST7735.h"

#include "Schedule.inc"

#define KeyMark				0x03	// define use Key Mark, 1 for enable.
// KEY0 for color pattern demo
// KEY1 for Joystick demo
// KEY2
// KEY3 for Show Altera logo animation

#define Joystick_Neutral	0
#define Joystick_Press		1
#define Joystick_Up			2
#define Joystick_Down		3
#define Joystick_Right		4
#define Joystick_Left		5


extern alt_u16	_width;
extern alt_u16	_height;


alt_u8	KeyStatus;
alt_u8	Demo_Mode;

void Show_Logo(void);
void Demo_Pattern(void);
void Demo_Joystick(void);

///////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////

// Check the joystick position
int CheckJoystick()
{
	int	nNum;
	int nActiveChannel;
	alt_u16 szAdcValue[10];

	int joystickStatus = Joystick_Neutral;

	nActiveChannel = 3;		// for Arduino Shield joystick analog input
	nNum = sizeof(szAdcValue)/sizeof(szAdcValue[0]);

	/////////////////////////////
	// read adc
	if (!ADC_LTC2308_Read(nActiveChannel, nNum, szAdcValue)){
		printf("failed to read adc\r\n");
	}
	else{
		//printf ("ADC Channel %d = %d [0x%02x] , \n", nActiveChannel, szAdcValue[1], szAdcValue[1]);
		if (szAdcValue[1] < 100)
			joystickStatus = Joystick_Left;
		else if (szAdcValue[1] < 700)
			joystickStatus = Joystick_Down;
		else if (szAdcValue[1] < 1100)
			joystickStatus = Joystick_Press;
		else if (szAdcValue[1] < 1700)
			joystickStatus = Joystick_Right;
		else if (szAdcValue[1] < 3000)
			joystickStatus = Joystick_Up;
		else
			joystickStatus = Joystick_Neutral;
	}

	return joystickStatus;
}


int Check_Mode_Change(void)
{
	int	result = FALSE;

	KeyStatus = ~IORD(KEY_BASE, 0x00) & KeyMark;	// Get Key status
	if (KeyStatus){									// Key Press
		if (Demo_Mode != KeyStatus){				// check mode change
			result = TRUE;							// if change, return TRUE
		}
	}

	return result;
}

int main()
{
	char	szText[256];


//	int		i,j;
//	alt_u16 color;
//	alt_u16	color_red, color_green, color_blue;

	printf("\nArduino 1.8\" TFT Demo\n");

	Demo_Mode = 0x00;
	KeyStatus = 0x00;

	ST7735_initR(INITR_BLACKTAB);
	ST7735_setRotation(3);
	ST7735_fillScreen(ST7735_BLACK);


//*** Logo Test ***
	Show_Logo();
	usleep(300*1000);

//*** string test ***
//	sprintf(szText, "       ALTERA");
//	ST7735_print_string(0, 0, ST7735_CYAN, cour10_font, szText);

	sprintf(szText, "    Cyclone V SoC");
	ST7735_print_string(0, 4*(FONT_10PT_ROW+1)-2, ST7735_WHITE, cour10_font, szText);

//	sprintf(szText, "Arduino Shield Demo.\n\nKEY0:Color Pattern\nKEY1:JoyStick");
//	ST7735_print_string(0, 5*(FONT_10PT_ROW+1), ST7735_YELLOW, cour10_font, szText);

	sprintf(szText, "Arduino Shield Demo.");
	ST7735_print_string(0, 5*(FONT_10PT_ROW+1), ST7735_YELLOW, cour10_font, szText);

	sprintf(szText, "KEY0:");
	ST7735_print_string(0, 7*(FONT_10PT_ROW+1), ST7735_GREEN, cour10_font, szText);
	sprintf(szText, "Color Pattern");
	ST7735_print_string(8*5, 7*(FONT_10PT_ROW+1), 0xFF00, cour10_font, szText);
	sprintf(szText, "KEY1:");
	ST7735_print_string(0, 8*(FONT_10PT_ROW+1), ST7735_GREEN, cour10_font, szText);
	sprintf(szText, "JoyStick");
	ST7735_print_string(8*5, 8*(FONT_10PT_ROW+1), 0xFF00, cour10_font, szText);

	sprintf(szText, "    Terasic Inc.");
	ST7735_print_string(0, 9*(FONT_10PT_ROW+1)+6, 0x04FF, cour10_font, szText);

//*** wait for Mode select and change
	while (1){
		KeyStatus = ~IORD(KEY_BASE, 0x00) & KeyMark;	// Get Key status
		if (KeyStatus){									// Key Press
			if (Demo_Mode != KeyStatus){				// check mode change
				Demo_Mode = KeyStatus;					// save mode status
				ST7735_fillScreen(ST7735_BLACK);		// clean screen
			}
		}

		switch(Demo_Mode){
			case 0x01:
				Demo_Pattern();
				break;
			case 0x02:
				Demo_Joystick();
				break;
			case 0x08:
				ST7735_fillScreen(ST7735_BLACK);
				Show_Logo();
				usleep(3*1000*1000);
				break;
			default:
				break;
		}
	}

  printf("Stop Nios II!\n");
  return 0;
}

///////////////////////////////////////////////////////////////////////////////
typedef struct {
  alt_u8 *	pBuff;
  int		nIndex;
  int		nStart;
  int		nEnd;
} show_task;


unsigned int Schenule_list[8] = {Schedule_1,Schedule_2,Schedule_1,Schedule_1,Schedule_1,Schedule_1,Schedule_1};

void Show_Logo(void)
{
	int	i,j;
	int	nTotal_DrawPixel;
	int nSched_StartTime[5] = {0,100};
	int	nSched_DrawNum[5];

	show_task	TaskList[8] = {{NULL,0,0,0},{NULL,0,0,0},{NULL,0,0,0},{NULL,0,0,0},{NULL,0,0,0},{NULL,0,0,0},{NULL,0,0,0},{NULL,0,0,0}};
	int			nTaskNum;

	nTaskNum = sizeof(TaskList) / sizeof(TaskList[0]);
	nTotal_DrawPixel = sizeof(Schedule_0) / sizeof(Schedule_0[0]);

	// initialize Task

	TaskList[0].pBuff	= Schedule_0;
	TaskList[0].nIndex	= 0;
	TaskList[0].nStart	= 0;
	TaskList[0].nEnd	= TaskList[0].nStart + (sizeof(Schedule_0) / sizeof(Schedule_0[0]));

	TaskList[1].pBuff	= Schedule_1;
	TaskList[1].nIndex	= 0;
	TaskList[1].nStart	= 128;
	TaskList[1].nEnd	= TaskList[1].nStart + (sizeof(Schedule_1) / sizeof(Schedule_1[0]));

	TaskList[2].pBuff	= Schedule_2;
	TaskList[2].nIndex	= 0;
	TaskList[2].nStart	= 200;
	TaskList[2].nEnd	= TaskList[2].nStart + (sizeof(Schedule_2) / sizeof(Schedule_2[0]));

	TaskList[3].pBuff	= Schedule_3;
	TaskList[3].nIndex	= 0;
	TaskList[3].nStart	= 200;
	TaskList[3].nEnd	= TaskList[3].nStart + (sizeof(Schedule_3) / sizeof(Schedule_3[0]));

	TaskList[4].pBuff	= Schedule_4;
	TaskList[4].nIndex	= 0;
	TaskList[4].nStart	= 230;
	TaskList[4].nEnd	= TaskList[4].nStart + (sizeof(Schedule_4) / sizeof(Schedule_4[0]));

	TaskList[5].pBuff	= Schedule_5;
	TaskList[5].nIndex	= 0;
	TaskList[5].nStart	= 400;
	TaskList[5].nEnd	= TaskList[5].nStart + (sizeof(Schedule_5) / sizeof(Schedule_5[0]));

	TaskList[6].pBuff	= Schedule_6;
	TaskList[6].nIndex	= 0;
	TaskList[6].nStart	= 400;
	TaskList[6].nEnd	= TaskList[6].nStart + (sizeof(Schedule_6) / sizeof(Schedule_6[0]));

	TaskList[7].pBuff	= Schedule_7;
	TaskList[7].nIndex	= 0;
	TaskList[7].nStart	= 400;
	TaskList[7].nEnd	= TaskList[7].nStart + (sizeof(Schedule_7) / sizeof(Schedule_7[0]));

	//
	for (i = 0 ; i < nTotal_DrawPixel ; i++){
		for (j = 0 ; j < nTaskNum ; j++){
			if (TaskList[j].pBuff == NULL){

			}
			else {
				if ((i >= TaskList[j].nStart) & (i < TaskList[j].nEnd)) {
					ST7735_draw_Pixel(TaskList[j].pBuff[TaskList[j].nIndex*2], TaskList[j].pBuff[TaskList[j].nIndex*2+1], 0x06FF);
					TaskList[j].nIndex ++;
				}
			}
			usleep(800);
		}
	}
}

void Demo_Joystick(void)
{
//	alt_u16 color;
	alt_u16	index_x,index_y;
	alt_u16	height,width;

	int joystickState;
	alt_u16	fill_color;

	//*** JoystickState Test ***
	index_x	= 0;
	index_y	= 0;
	height	= 10;
	width	= 10;

	fill_color = ST7735_WHITE;
	ST7735_fillRect(index_x,index_y,width,height,fill_color);

	while (1) {
		joystickState = CheckJoystick();										// check JoyStick status
		if (joystickState != Joystick_Neutral){									//
			if (joystickState == Joystick_Press){								// If Press, fill RED Rectangle
				if (fill_color == ST7735_WHITE) {
					fill_color = ST7735_RED;
					ST7735_fillRect(index_x,index_y,width,height,fill_color);
				}
			}
			else{																// Else check direction
				ST7735_fillRect(index_x,index_y,width,height,ST7735_BLACK);
				fill_color = ST7735_WHITE;
				if (joystickState == Joystick_Up){
					if (index_y > 0)
						index_y --;
				}
				else if (joystickState == Joystick_Left){
					if (index_x > 0)
						index_x --;
				}
				else if (joystickState == Joystick_Down){
					if ((index_y + height) < _height)
						index_y ++;
				}
				else if (joystickState == Joystick_Right){
					if ((index_x + width) < _width)
						index_x ++;
				}
				ST7735_fillRect(index_x,index_y,width,height,fill_color);
			}
		}
		else{
			if (fill_color == ST7735_RED){
				fill_color = ST7735_WHITE;
				ST7735_fillRect(index_x,index_y,width,height,fill_color);
			}
		}

		if(Check_Mode_Change())
			break;

		usleep(10*1000);
	}

}


void Demo_Pattern(void)
{

	int		i;
	alt_u16 color;
	alt_u16	color_red, color_green, color_blue;
	alt_u16	index_x,index_y;
	alt_u16	height,width;

	// for color space
	int		x,y;
	int		divisor_x,divisor_y;

	int		ModeChange = FALSE;

	index_x	= 0;
	index_y	= 0;
	height	= 128;
	width	= 160;

	//=== show color pattern ========================================
	// Blue
	for (i = 0 ; i < 32 ; i++)
	{
	  color = i;
	  ST7735_drawFastVLine(index_x++,index_y,128,color);
	}

	// Green
	for (i = 0 ; i < 64 ; i++)
	{
	  color = i << 5;
	  ST7735_drawFastVLine(index_x++,index_y,128,color);
	}

	// Red
	for (i = 0 ; i < 32 ; i++)
	{
	  color = i << 11;
	  ST7735_drawFastVLine(index_x++,index_y,128,color);
	}

	// Gray
	for (i = 0 ; i < 32 ; i++)
	{
	  color = i;
	  color += i << 6;
	  color += i << 11;
	  ST7735_drawFastVLine(index_x++,index_y,128,color);
	}

	// delay 4s, and check Key press
	for (i = 0 ; i < 40 ; i++) {
		if(Check_Mode_Change()){
			ModeChange = TRUE;
			break;
		}
		else
			usleep(100*1000);
	}

	//=== show Color Space ==========================================
	//=== Fill Rectangle ============================================
	if (!ModeChange){	// if no mode change
		color = 0;
		divisor_x = _width/32;
		divisor_y = _height/64;
		for (x = 0 ; x < _width ; x++){
			color_red = (x/divisor_x) << 11;
			color_blue =  31 - (x/divisor_x);
			for (y = 0 ; y < _height ; y++){
				color_green = (y/divisor_y) << 5;
				ST7735_draw_Pixel(x,y,color_red + color_green + color_blue);
			}
		}

		// delay 4s, and check Key press
		for (i = 0 ; i < 40 ; i++) {
			if(Check_Mode_Change()){
				ModeChange = TRUE;
				break;
			}
			else
				usleep(100*1000);
		}
	}

	//=== Fill Rectangle ============================================
	if (!ModeChange){	// if no mode change
		index_x	= 0;
		index_y	= 0;

		ST7735_fillRect(index_x,index_y,width,height,ST7735_WHITE);
		ST7735_fillRect(8,8,width-16,height-16,ST7735_BLUE);
		ST7735_fillRect(16,16,width-32,height-32,ST7735_RED);
		ST7735_fillRect(24,24,width-48,height-48,ST7735_GREEN);
		ST7735_fillRect(32,32,width-64,height-64,ST7735_CYAN);
		ST7735_fillRect(40,40,width-80,height-80,ST7735_MAGENTA);
		ST7735_fillRect(48,48,width-96,height-96,ST7735_YELLOW);
		ST7735_fillRect(56,56,width-112,height-112,ST7735_BLACK);

		// delay 4s, and check Key press
		for (i = 0 ; i < 40 ; i++) {
			if(Check_Mode_Change()){
				ModeChange = TRUE;
				break;
			}
			else
				usleep(100*1000);
		}
	}
/*
	//=== Fill Circle nad Line ======================================
 	if (!ModeChange){	// if no mode change*
		ST7735_fillScreen(ST7735_BLACK);

		for (i = 15 ; i < 160 ; i += 32){
			for (j = 15 ; j < 128 ; j += 32){
				ST7735_draw_circle(i,j,12,ST7735_MAGENTA,1);
			}
		}

		for (i = 0 ; i <= 128 ; i += 32){
			if (i == 0){
				ST7735_draw_sloped_line(0,i,159,i,2,ST7735_YELLOW);
			}
			else {
				ST7735_draw_sloped_line(0,i-1,159,i-1,2,ST7735_YELLOW);
			}
		}

		for (i = 0 ; i <= 160 ; i += 32){
			if (i == 0){
				ST7735_draw_sloped_line(i,0,i,127,2,ST7735_YELLOW);
			}
			else {
				ST7735_draw_sloped_line(i-1,0,i-1,127,2,ST7735_YELLOW);
			}
		}


		//	ST7735_draw_sloped_line(0,0,0,127,2,ST7735_YELLOW);
		//	ST7735_draw_sloped_line(0,0,159,0,2,ST7735_YELLOW);
		//	ST7735_draw_sloped_line(159,0,159,127,2,ST7735_YELLOW);
		//	ST7735_draw_sloped_line(0,127,159,127,2,ST7735_YELLOW);
		ST7735_draw_sloped_line(0,0,159,127,2,ST7735_YELLOW);
		ST7735_draw_sloped_line(159,0,0,127,2,ST7735_YELLOW);

		// delay 4s, and check Key press
		for (i = 0 ; i < 40 ; i++) {
			if(Check_Mode_Change()){
				ModeChange = TRUE;
				break;
			}
			else
				usleep(100*1000);
		}
	}
*/

}


///////////////////////////////////////////////////////////////////////////////
