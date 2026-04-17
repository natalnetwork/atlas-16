/*
 * DE10-Nano Arduino shield 1.8" TFT LED demo
 *
 *
 */

#include <stdio.h>
#include "altera_avalon_pio_regs.h"
#include "terasic_includes.h"

#include "adc_ltc2308.h"

// include Arduino 1.8" TFT LCD header files
#include "ST7735.h"
#include "Schedule.inc"


#define FR_WIDTH			800
#define FR_HEIGHT	 		600
#define FR_BYTES_PER_PIXEL	4
#define FR_SIZE             (FR_WIDTH*FR_HEIGHT*FR_BYTES_PER_PIXEL)

#define FR_FRAME_0			(SDRAM_BASE + 0x00000000)
#define FR_FRAME_1			(FR_FRAME_0 + FR_SIZE)

#define KEY_TRIGGER_FREE	0x01
#define KEY_RESET_MAX_MIN	0x02
#define SEARCH_WIDTH		800



//-- Arduino 1.8" TFT LCD demo define
#define KeyMark				0x03	// define use Key Mark, 1 for enable.
// KEY0 for color pattern demo
// KEY1 for Joystick demo

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
int CheckJoystick(void);
int Check_Mode_Change(void);
//---end

float expected_adc_value_H[7] = {0.3, 0.6, 0.9, 1.2,
                              1.5, 1.8, 2.1};

float expected_adc_value_L[7] = {0.15, 0.3, 0.45, 0.6,
                               0.75,0.9, 1.05};


int main()
{

  char szText[256];

// Ardiono 1.8" TFT demo
  printf("\nArduino 1.8\" TFT Demo\n");

  Demo_Mode = 0x00;
  KeyStatus = 0x00;

  ST7735_initR(INITR_BLACKTAB);
  ST7735_setRotation(3);
  ST7735_fillScreen(ST7735_BLACK);


//*** Logo Test ***
  ST7735_fillRect(4,4,152,49,ST7735_TERASIC);
  Show_Logo();
  usleep(300*1000);

//*** string test ***

  sprintf(szText, "    Cyclone V SoC");
  ST7735_print_string(0, 5*(FONT_10PT_ROW+1)+4, ST7735_WHITE, cour10_font, szText);

  sprintf(szText, "Arduino Shield Demo.");
  ST7735_print_string(0, 6*(FONT_10PT_ROW+1)+6, ST7735_YELLOW, cour10_font, szText);

  sprintf(szText, "KEY0:");
  ST7735_print_string(0, 7*(FONT_10PT_ROW+1)+6, ST7735_GREEN, cour10_font, szText);
  sprintf(szText, "Color Pattern");
  ST7735_print_string(8*5, 7*(FONT_10PT_ROW+1)+6, 0xFF00, cour10_font, szText);
  sprintf(szText, "KEY1:");
  ST7735_print_string(0, 8*(FONT_10PT_ROW+1)+6, ST7735_GREEN, cour10_font, szText);
  sprintf(szText, "JoyStick");
  ST7735_print_string(8*5, 8*(FONT_10PT_ROW+1)+6, 0xFF00, cour10_font, szText);

  sprintf(szText, "    Terasic Inc.");
  ST7735_print_string(0, 9*(FONT_10PT_ROW+1)+8, 0x04FF, cour10_font, szText);

//*** wait for Mode select and change
  while (1){
	KeyStatus = ~IORD(KEY_BASE, 0x00) & KeyMark;	// Get Key status
	if (KeyStatus){										// Key Press
		if (Demo_Mode != KeyStatus){					// check mode change
			Demo_Mode = KeyStatus;						// save mode status
			ST7735_fillScreen(ST7735_BLACK);			// clean screen
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

////////////////////////////////////////////////////////////////////////////////

  printf("Stop Nios II!\n");
  return 0;

}


// for Arduino 1.8" TFT demo
///////////////////////////////////////////////////////////////////////////////
typedef struct {
  alt_u8 *	pBuff;	//
  int		nIndex;	// Index point
  int		nStart;	// start time
  int		nEnd;	// end time
  char		bDir;	// Specifies the drawing direction, 1 -> count up, 0 -> count down
  alt_u16   wcolor;	// display color

} show_task;



void Show_Logo(void)
{
	int	i,j;
	int	nTotal_DrawPixel;
	int nSched_DelayTime[8];
	int	nSched_DrawNum[8];

	show_task	TaskList[8] = {{NULL,0,0,0,0},{NULL,0,0,0,0},{NULL,0,0,0,0},{NULL,0,0,0,0},{NULL,0,0,0,0},{NULL,0,0,0,0},{NULL,0,0,0,0},{NULL,0,0,0,0}};
	show_task	TaskList2[4] = {{NULL,0,0,0,0},{NULL,0,0,0,0},{NULL,0,0,0,0},{NULL,0,0,0,0}};
	int			nTaskNum;

// Task 1 start ...

	nTaskNum = sizeof(TaskList) / sizeof(TaskList[0]);
	nTaskNum = nTaskNum - 1;// disable task 7

// for debug
	nSched_DrawNum[0] = sizeof(Schedule_0) / sizeof(Schedule_0[0]);
	printf ("Schedule_0 count = %d\n", nSched_DrawNum[0]);
	nSched_DrawNum[1] = sizeof(Schedule_1) / sizeof(Schedule_1[0]);
	printf ("Schedule_1 count = %d\n", nSched_DrawNum[1]);
	nSched_DrawNum[2] = sizeof(Schedule_2) / sizeof(Schedule_2[0]);
	printf ("Schedule_2 count = %d\n", nSched_DrawNum[2]);
	nSched_DrawNum[3] = sizeof(Schedule_3) / sizeof(Schedule_3[0]);
	printf ("Schedule_3 count = %d\n", nSched_DrawNum[3]);
	nSched_DrawNum[4] = sizeof(Schedule_4) / sizeof(Schedule_4[0]);
	printf ("Schedule_4 count = %d\n", nSched_DrawNum[4]);
	nSched_DrawNum[5] = sizeof(Schedule_5) / sizeof(Schedule_5[0]);
	printf ("Schedule_5 count = %d\n", nSched_DrawNum[5]);
	nSched_DrawNum[6] = sizeof(Schedule_6) / sizeof(Schedule_6[0]);
	printf ("Schedule_6 count = %d\n", nSched_DrawNum[6]);
	nSched_DrawNum[7] = sizeof(Schedule_7) / sizeof(Schedule_7[0]);
	printf ("Schedule_7 count = %d\n", nSched_DrawNum[7]);


// end
	nTotal_DrawPixel = nSched_DrawNum[0] + nSched_DrawNum[1] + nSched_DrawNum[2] + nSched_DrawNum[6];
	printf ("Total Draw Pixel = %d\n", nTotal_DrawPixel);

	// initialize Task

	TaskList[0].pBuff	= (alt_u8 *) Schedule_0;
	TaskList[0].nIndex	= 0;
	TaskList[0].nStart	= 0;
	TaskList[0].nEnd	= TaskList[0].nStart + (sizeof(Schedule_0) / sizeof(Schedule_0[0]));
	TaskList[0].bDir	= 1;
	TaskList[0].wcolor	= ST7735_WHITE;
	nSched_DelayTime[0] = 1500;

	TaskList[1].pBuff	= (alt_u8 *) Schedule_1;
	TaskList[1].nIndex	= 0;
	TaskList[1].nStart	= TaskList[0].nEnd;
	TaskList[1].nEnd	= TaskList[1].nStart + (sizeof(Schedule_1) / sizeof(Schedule_1[0]));
	TaskList[1].bDir	= 1;
	TaskList[1].wcolor	= ST7735_WHITE;
	nSched_DelayTime[1] = 1500;

	TaskList[2].pBuff	= (alt_u8 *) Schedule_2;
	TaskList[2].nIndex	= 0;
	TaskList[2].nStart	= TaskList[1].nEnd;
	TaskList[2].nEnd	= TaskList[2].nStart + (sizeof(Schedule_2) / sizeof(Schedule_2[0]));
	TaskList[2].bDir	= 1;
	TaskList[2].wcolor	= ST7735_WHITE;
	nSched_DelayTime[2] = 1500;

	TaskList[3].pBuff	= (alt_u8 *) Schedule_3;
	TaskList[3].nIndex	= 0;
	TaskList[3].nStart	= TaskList[2].nEnd;
	TaskList[3].nEnd	= TaskList[3].nStart + (sizeof(Schedule_3) / sizeof(Schedule_3[0]));
	TaskList[3].bDir	= 1;
	TaskList[3].wcolor	= ST7735_WHITE;
	nSched_DelayTime[3] = 2800;

	TaskList[4].pBuff	= (alt_u8 *) Schedule_4;
	TaskList[4].nIndex	= 0;
	TaskList[4].nStart	= TaskList[2].nEnd;
	TaskList[4].nEnd	= TaskList[4].nStart + (sizeof(Schedule_4) / sizeof(Schedule_4[0]));
	TaskList[4].bDir	= 1;
	TaskList[4].wcolor	= ST7735_WHITE;
	nSched_DelayTime[4] = 2000;

	TaskList[5].pBuff	= (alt_u8 *) Schedule_5;
	TaskList[5].nIndex	= 0;
	TaskList[5].nStart	= TaskList[2].nEnd;
	TaskList[5].nEnd	= TaskList[5].nStart + (sizeof(Schedule_5) / sizeof(Schedule_5[0]));
	TaskList[5].bDir	= 1;
	TaskList[5].wcolor	= ST7735_WHITE;
	nSched_DelayTime[5] = 2000;

	TaskList[6].pBuff	= (alt_u8 *) Schedule_6;
	TaskList[6].nIndex	= 0;
	TaskList[6].nStart	= TaskList[2].nEnd;
	TaskList[6].nEnd	= TaskList[6].nStart + (sizeof(Schedule_6) / sizeof(Schedule_6[0]));
	TaskList[6].bDir	= 1;
	TaskList[6].wcolor	= ST7735_WHITE;
	nSched_DelayTime[6] = 2000;

	TaskList[7].pBuff	= (alt_u8 *) Schedule_7;
	TaskList[7].nIndex	= 0;
	TaskList[7].nStart	= 0;
	TaskList[7].nEnd	= TaskList[7].nStart + (sizeof(Schedule_7) / sizeof(Schedule_7[0]));
	TaskList[7].bDir	= 1;
	TaskList[7].wcolor	= ST7735_WHITE;
	nSched_DelayTime[7] = 100;

	//
	for (i = 0 ; i < nTotal_DrawPixel ; i++){
		for (j = 0 ; j < nTaskNum ; j++){
			if (TaskList[j].pBuff == NULL){

			}
			else {
				if ((i >= TaskList[j].nStart) & (i < TaskList[j].nEnd)) {
					ST7735_draw_Pixel(TaskList[j].pBuff[TaskList[j].nIndex*2], TaskList[j].pBuff[TaskList[j].nIndex*2+1], TaskList[j].wcolor);// 0x06FF);
					if(TaskList[j].bDir)
						TaskList[j].nIndex ++;
					else
						TaskList[j].nIndex --;
					usleep(nSched_DelayTime[j]);
				}
			}
			//usleep(800);
		}
	}

	usleep(600 * 1000);

// Task 2 start ...

	nTaskNum = sizeof(TaskList2) / sizeof(TaskList2[0]);

	nSched_DrawNum[0] = sizeof(Schedule_20) / sizeof(Schedule_20[0]);
	printf ("Schedule_20 count = %d\n", nSched_DrawNum[0]);
	nSched_DrawNum[1] = sizeof(Schedule_21) / sizeof(Schedule_21[0]);
	printf ("Schedule_21 count = %d\n", nSched_DrawNum[1]);
	nSched_DrawNum[2] = sizeof(Schedule_22) / sizeof(Schedule_22[0]);
	printf ("Schedule_22 count = %d\n", nSched_DrawNum[2]);
	nSched_DrawNum[3] = sizeof(Schedule_23) / sizeof(Schedule_23[0]);
	printf ("Schedule_23 count = %d\n", nSched_DrawNum[3]);

	nTotal_DrawPixel = nSched_DrawNum[2] + nSched_DrawNum[3];
	printf ("Total Draw Pixel = %d\n", nTotal_DrawPixel);
	// initialize Task 2

	TaskList2[0].pBuff	= (alt_u8 *) Schedule_20;
	TaskList2[0].nIndex	= 0;
	TaskList2[0].nStart	= 0;
	TaskList2[0].nEnd	= TaskList2[0].nStart + (sizeof(Schedule_20) / sizeof(Schedule_20[0]));
	TaskList2[0].bDir	= 1;
	TaskList2[0].wcolor	= ST7735_WHITE;

	TaskList2[1].pBuff	= (alt_u8 *) Schedule_21;
	TaskList2[1].nIndex	= TaskList2[1].nStart + (sizeof(Schedule_21) / sizeof(Schedule_21[0])) - 1;
	TaskList2[1].nStart	= 0;
	TaskList2[1].nEnd	= TaskList2[1].nStart + (sizeof(Schedule_21) / sizeof(Schedule_21[0]));
	TaskList2[1].bDir	= 0;
	TaskList2[1].wcolor	= ST7735_WHITE;

	TaskList2[2].pBuff	= (alt_u8 *) Schedule_22;
	TaskList2[2].nIndex	= 0;
	TaskList2[2].nStart	= 0;
	TaskList2[2].nEnd	= TaskList2[2].nStart + (sizeof(Schedule_22) / sizeof(Schedule_22[0]));
	TaskList2[2].bDir	= 1;
	TaskList2[2].wcolor	= ST7735_TERASIC;

	TaskList2[3].pBuff	= (alt_u8 *) Schedule_23;
	TaskList2[3].nIndex	= 0;
	TaskList2[3].nStart	= sizeof(Schedule_22) / sizeof(Schedule_22[0]);
	TaskList2[3].nEnd	= TaskList2[3].nStart + (sizeof(Schedule_23) / sizeof(Schedule_23[0]));
	TaskList2[3].bDir	= 1;
	TaskList2[3].wcolor	= ST7735_WHITE;


	//
	for (i = 0 ; i < nTotal_DrawPixel ; i++){
		for (j = 0 ; j < nTaskNum ; j++){
			if (TaskList2[j].pBuff == NULL){

			}
			else {
				if ((i >= TaskList2[j].nStart) & (i < TaskList2[j].nEnd)) {
					ST7735_draw_Pixel(TaskList2[j].pBuff[TaskList2[j].nIndex*2], TaskList2[j].pBuff[TaskList2[j].nIndex*2+1], TaskList2[j].wcolor);// 0x06FF);
					if(TaskList2[j].bDir)
						TaskList2[j].nIndex ++;
					else
						TaskList2[j].nIndex --;
				}
			}
				usleep(100);
		}
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
#if 0
	//=== Fill Circle and Line ======================================
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
#endif

}

///////////////////////////////////////////////////////////////////////
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
				ST7735_fillRect(index_x,index_y,width,height,fill_color);
				fill_color = ST7735_WHITE;
				if (joystickState == Joystick_Up){
					if (index_y > 0)
					{
						ST7735_draw_sloped_line(index_x,index_y+height-1,index_x+width-1,index_y+height-1,1,ST7735_BLACK);
						index_y --;
						ST7735_draw_sloped_line(index_x,index_y,index_x+width-1,index_y,1,fill_color);
					}
				}
				else if (joystickState == Joystick_Left){
					if (index_x > 0)
					{
						ST7735_draw_sloped_line(index_x+width-1,index_y,index_x+width-1,index_y+height-1,1,ST7735_BLACK);
						index_x --;
						ST7735_draw_sloped_line(index_x,index_y,index_x,index_y+height-1,1,fill_color);
					}
				}
				else if (joystickState == Joystick_Down){
					if ((index_y + height) < _height)
					{
						ST7735_draw_sloped_line(index_x,index_y,index_x+width-1,index_y,1,ST7735_BLACK);
						index_y ++;
						ST7735_draw_sloped_line(index_x,index_y+height-1,index_x+width-1,index_y+height-1,1,fill_color);
					}
				}
				else if (joystickState == Joystick_Right){
					if ((index_x + width) < _width)
					{
						ST7735_draw_sloped_line(index_x,index_y,index_x,index_y+height-1,1,ST7735_BLACK);
						index_x ++;
						ST7735_draw_sloped_line(index_x+width-1,index_y,index_x+width-1,index_y+height-1,1,fill_color);
					}
				}
//				ST7735_fillRect(index_x,index_y,width,height,fill_color);
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


// Check the joystick position
int CheckJoystick(void)
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

///////////////////////////////////////////////////////////////////////////////

