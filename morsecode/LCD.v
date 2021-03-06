module LCD(
  input CLOCK_50,    //    50 MHz clock
  input [1:0] KEY,      //    Pushbutton[1:0]
  inout [35:0] GPIO_0,GPIO_1,     //    GPIO Connections
//    LCD Module 16X2
  output LCD_ON,    // LCD Power ON/OFF
  output LCD_BLON,    // LCD Back Light ON/OFF
  output LCD_RW,    // LCD Read/Write Select, 0 = Write, 1 = Read
  output LCD_EN,    // LCD Enable
  output LCD_RS,    // LCD Command/Data Select, 0 = Command, 1 = Data
  input	PS2_DAT,
  input	PS2_CLK,
  inout [7:0] LCD_DATA,   // LCD Data bus 8 bits
  input [127:0] row1, 
  input [127:0] row2
);

//    All inout port turn to tri-state
assign    GPIO_0        =    36'hzzzzzzzzz;
assign    GPIO_1        =    36'hzzzzzzzzz;

wire [6:0] myclock;

// reset delay gives some time for peripherals to initialize
wire DLY_RST;
Reset_Delay r0(    .iCLK(CLOCK_50),.oRESET(DLY_RST) );


// turn LCD ON
assign    LCD_ON        =    1'b1;
assign    LCD_BLON    =    1'b1;

//  set all inout ports to tri-state
assign  GPIO_0    =  36'hzzzzzzzzz;
assign  GPIO_1    =  36'hzzzzzzzzz;

wire reset = 1'b0;
wire [7:0] scan_code;

reg [7:0] history[1:4];
wire read, scan_ready;

//oneshot pulser(
//   .pulse_out(read),
//   .trigger_in(scan_ready),
//   .clk(CLOCK_50)
//);
//
//keyboard kbd(
//  .keyboard_clk(PS2_CLK),
//  .keyboard_data(PS2_DAT),
//  .clock50(CLOCK_50),
//  .reset(reset),
//  .read(read),
//  .scan_ready(scan_ready),
//  .scan_code(scan_code)
//);

//always @(posedge scan_ready)
//begin
//	history[4] <= history[3];
//	history[3] <= history[2];
//	history[2] <= history[1];
//	history[1] <= scan_code;
//end
	

LCD_Display u1(
// Host Side
   .iCLK_50MHZ(CLOCK_50),
   .iRST_N(DLY_RST),
   .row1(row1),
   .row2(row2),
// LCD Side
   .DATA_BUS(LCD_DATA),
   .LCD_RW(LCD_RW),
   .LCD_E(LCD_EN),
   .LCD_RS(LCD_RS)
);

endmodule

module LCD_Display(iCLK_50MHZ, iRST_N, row1, row2, 
    LCD_RS,LCD_E,LCD_RW,DATA_BUS);
input iCLK_50MHZ, iRST_N;
input [255:0] row1, row2;
output LCD_RS, LCD_E, LCD_RW;
inout [7:0] DATA_BUS;

parameter
HOLD = 4'h0,
FUNC_SET = 4'h1,
DISPLAY_ON = 4'h2,
MODE_SET = 4'h3,
Print_String = 4'h4,
LINE2 = 4'h5,
RETURN_HOME = 4'h6,
DROP_LCD_E = 4'h7,
RESET1 = 4'h8,
RESET2 = 4'h9,
RESET3 = 4'ha,
DISPLAY_OFF = 4'hb,
DISPLAY_CLEAR = 4'hc;

reg [3:0] state, next_command;
// Enter new ASCII hex data above for LCD Display
reg [7:0] DATA_BUS_VALUE;
wire [7:0] Next_Char;
reg [19:0] CLK_COUNT_400HZ;
reg [4:0] CHAR_COUNT;
reg CLK_400HZ, LCD_RW_INT, LCD_E, LCD_RS;

// BIDIRECTIONAL TRI STATE LCD DATA BUS
assign DATA_BUS = (LCD_RW_INT? 8'bZZZZZZZZ: DATA_BUS_VALUE);

LCD_display_string u1(
.index(CHAR_COUNT),
.out(Next_Char),
.row1(row1),
.row2(row2));

assign LCD_RW = LCD_RW_INT;

always @(posedge iCLK_50MHZ or negedge iRST_N)
    if (!iRST_N)
    begin
       CLK_COUNT_400HZ <= 20'h00000;
       CLK_400HZ <= 1'b0;
    end
    else if (CLK_COUNT_400HZ < 20'h0F424)
    begin
       CLK_COUNT_400HZ <= CLK_COUNT_400HZ + 1'b1;
    end
    else
    begin
      CLK_COUNT_400HZ <= 20'h00000;
      CLK_400HZ <= ~CLK_400HZ;
    end
// State Machine to send commands and data to LCD DISPLAY

always @(posedge CLK_400HZ or negedge iRST_N)
    if (!iRST_N)
    begin
     state <= RESET1;
    end
    else
    case (state)
    RESET1:            
// Set Function to 8-bit transfer and 2 line display with 5x8 Font size
// see Hitachi HD44780 family data sheet for LCD command and timing details
    begin
      LCD_E <= 1'b1;
      LCD_RS <= 1'b0;
      LCD_RW_INT <= 1'b0;
      DATA_BUS_VALUE <= 8'h38;
      state <= DROP_LCD_E;
      next_command <= RESET2;
      CHAR_COUNT <= 5'b00000;
    end
    RESET2:
    begin
      LCD_E <= 1'b1;
      LCD_RS <= 1'b0;
      LCD_RW_INT <= 1'b0;
      DATA_BUS_VALUE <= 8'h38;
      state <= DROP_LCD_E;
      next_command <= RESET3;
    end
    RESET3:
    begin
      LCD_E <= 1'b1;
      LCD_RS <= 1'b0;
      LCD_RW_INT <= 1'b0;
      DATA_BUS_VALUE <= 8'h38;
      state <= DROP_LCD_E;
      next_command <= FUNC_SET;
    end
// EXTRA STATES ABOVE ARE NEEDED FOR RELIABLE PUSHBUTTON RESET OF LCD

    FUNC_SET:
    begin
      LCD_E <= 1'b1;
      LCD_RS <= 1'b0;
      LCD_RW_INT <= 1'b0;
      DATA_BUS_VALUE <= 8'h38;
      state <= DROP_LCD_E;
      next_command <= DISPLAY_OFF;
    end

// Turn off Display and Turn off cursor
    DISPLAY_OFF:
    begin
      LCD_E <= 1'b1;
      LCD_RS <= 1'b0;
      LCD_RW_INT <= 1'b0;
      DATA_BUS_VALUE <= 8'h08;
      state <= DROP_LCD_E;
      next_command <= DISPLAY_CLEAR;
    end

// Clear Display and Turn off cursor
    DISPLAY_CLEAR:
    begin
      LCD_E <= 1'b1;
      LCD_RS <= 1'b0;
      LCD_RW_INT <= 1'b0;
      DATA_BUS_VALUE <= 8'h01;
      state <= DROP_LCD_E;
      next_command <= DISPLAY_ON;
    end

// Turn on Display and Turn off cursor
    DISPLAY_ON:
    begin
      LCD_E <= 1'b1;
      LCD_RS <= 1'b0;
      LCD_RW_INT <= 1'b0;
      DATA_BUS_VALUE <= 8'h0C;
      state <= DROP_LCD_E;
      next_command <= MODE_SET;
    end

// Set write mode to auto increment address and move cursor to the right
    MODE_SET:
    begin
      LCD_E <= 1'b1;
      LCD_RS <= 1'b0;
      LCD_RW_INT <= 1'b0;
      DATA_BUS_VALUE <= 8'h06;
      state <= DROP_LCD_E;
      next_command <= Print_String;
    end

// Write ASCII hex character in first LCD character location
    Print_String:
    begin
      state <= DROP_LCD_E;
      LCD_E <= 1'b1;
      LCD_RS <= 1'b1;
      LCD_RW_INT <= 1'b0;
    // ASCII character to output
      if (Next_Char[7:4] != 4'h0)
        DATA_BUS_VALUE <= Next_Char;
        // Convert 4-bit value to an ASCII hex digit
      else if (Next_Char[3:0] >9)
        // ASCII A...F
         DATA_BUS_VALUE <= {4'h4,Next_Char[3:0]-4'h9};
      else
        // ASCII 0...9
         DATA_BUS_VALUE <= {4'h3,Next_Char[3:0]};
    // Loop to send out 32 characters to LCD Display  (16 by 2 lines)
      if ((CHAR_COUNT < 31) && (Next_Char != 8'hFE))
         CHAR_COUNT <= CHAR_COUNT + 1'b1;
      else
         CHAR_COUNT <= 5'b00000; 
    // Jump to second line?
      if (CHAR_COUNT == 15)
        next_command <= LINE2;
    // Return to first line?
      else if ((CHAR_COUNT == 31) || (Next_Char == 8'hFE))
        next_command <= RETURN_HOME;
      else
        next_command <= Print_String;
    end

// Set write address to line 2 character 1
    LINE2:
    begin
      LCD_E <= 1'b1;
      LCD_RS <= 1'b0;
      LCD_RW_INT <= 1'b0;
      DATA_BUS_VALUE <= 8'hC0;
      state <= DROP_LCD_E;
      next_command <= Print_String;
    end

// Return write address to first character postion on line 1
    RETURN_HOME:
    begin
      LCD_E <= 1'b1;
      LCD_RS <= 1'b0;
      LCD_RW_INT <= 1'b0;
      DATA_BUS_VALUE <= 8'h80;
      state <= DROP_LCD_E;
      next_command <= Print_String;
    end

// The next three states occur at the end of each command or data transfer to the LCD
// Drop LCD E line - falling edge loads inst/data to LCD controller
    DROP_LCD_E:
    begin
      LCD_E <= 1'b0;
      state <= HOLD;
    end
// Hold LCD inst/data valid after falling edge of E line                
    HOLD:
    begin
      state <= next_command;
    end
    endcase
endmodule

module LCD_display_string(index, out, row1, row2);
input [4:0] index;
input [127:0] row1, row2;
output [7:0] out;
reg [7:0] out;


// Line 1
   always 
     case (index)
      5'h00: out <= row1[7:0];
	   5'h01: out <= row1[15:8];
      5'h02: out <= row1[23:16];
      5'h03: out <= row1[31:24];
      5'h04: out <= row1[39:32];
      5'h05: out <= row1[47:40];
      5'h06: out <= row1[55:48];
      5'h07: out <= row1[63:56];
      5'h08: out <= row1[71:64];
      5'h09: out <= row1[79:72];
      5'ha: out <= row1[87:80];
      5'hb: out <= row1[95:88];
      5'hc: out <= row1[103:96];
      5'hd: out <= row1[111:104];
      5'he: out <= row1[119:112];
      5'hf: out <= row1[127:120];

// Line 2
      5'h10: out <= row2[7:0];
      5'h11: out <= row2[15:8];
      5'h12: out <= row2[23:16];
      5'h13: out <= row2[31:24];
      5'h14: out <= row2[39:32];
      5'h15: out <= row2[47:40];
      5'h16: out <= row2[55:48];
      5'h17: out <= row2[63:56];
      5'h18: out <= row2[71:64];
      5'h19: out <= row2[79:72];
      5'h1a: out <= row2[87:80];
      5'h1b: out <= row2[95:88];
      5'h1c: out <= row2[103:96];
      5'h1d: out <= row2[111:104];
      5'h1e: out <= row2[119:112];
      5'h1f: out <= row2[127:120];
    default: out <= 8'h20;
     endcase
endmodule

module    Reset_Delay(iCLK,oRESET);
input        iCLK;
output reg    oRESET;
reg    [19:0]    Cont;

always@(posedge iCLK)
begin
    if(Cont!=20'hFFFFF)
    begin
        Cont    <=    Cont+1'b1;
        oRESET    <=    1'b0;
    end
    else
    oRESET    <=    1'b1;
end

endmodule
