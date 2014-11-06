module morsecode(
  input CLOCK_50,    //50 MHz clock
  input [1:0] KEY,    //KEY0 is the morse key, KEY1 will be the reset
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
  output [7:0] LEDG,
  input CLOCK_27,
  output TD_RESET, // TV Decoder Reset
  // I2C
  inout  I2C_SDAT, // I2C Data
  output I2C_SCLK, // I2C Clock
  // Audio CODEC
  output/*inout*/ AUD_ADCLRCK, // Audio CODEC ADC LR Clock
  input	 AUD_ADCDAT,  // Audio CODEC ADC Data
  output /*inout*/  AUD_DACLRCK, // Audio CODEC DAC LR Clock
  output AUD_DACDAT,  // Audio CODEC DAC Data
  inout	 AUD_BCLK,    // Audio CODEC Bit-Stream Clock
  output AUD_XCK     // Audio CODEC Chip Clock
);

  reg [31:0] CCount; //represents the clock count. Resets every 0.5 seconds
  reg [31:0] Kcount; //Represents the key-press clock cycle count
  reg [31:0] Bcount; //Represents the pause clock cycle count
  
  reg w; //w == 1 --> dash, w == 0 --> dot
  reg v; //v == 0 --> character break, v == 1 --> word break
 
  reg newdot; //represents whether there is a new dot/dash to append
  reg newbreak; //represents whether there is a new break
  
  wire reset;
  wire ore;
  reg pulse;
  
  reg play;
  
  /* For displaying on a row of the LCD, sizeof(letters_*) == 8 * 32 = 256 
  (- 1 to include 0 -> 255)*/
  
  reg [7:0] letter_one; //for immediate letter 'transfer' of the first row
  reg [7:0] letter_two; //for immediate letter 'transfer' of the second row
  reg [127:0] letters_LCD_one; //holds the values of the first row of the LCD
  reg [127:0] letters_LCD_two; //holds the values of the second row of the LCD
  
  
	/* states are numbered in level-order traversal from the 
	huffman-coding, binary-tree-like representation of Morse Code
	that is provided */
	
	//State enumeration for character FSM
	parameter 
	A = 5'd4, B = 5'd21, C = 5'd23, D = 5'd11,
	E = 5'd1, F = 5'd17, G = 5'd13, H = 5'd15,
	I = 5'd3, J = 5'd20, K = 5'd12, L = 5'd18,
	M = 5'd6, N = 5'd5, O = 5'd14, P = 5'd19,
	Q = 5'd26, R = 5'd9, S = 5'd7, T = 5'd2,
	U = 5'd8, V = 5'd16, W = 5'd10, X = 5'd22,
	Y = 5'd24, Z = 5'd25, BREAK = 4'd0;
	
	//The CHARACTERS' values for the LCD
	parameter
	LA = 8'h41, LB = 8'h42, LC = 8'h43, LD = 8'h44,
	LE = 8'h45,	LF = 8'h46, LG = 8'h47, LH = 8'h48,
	LI = 8'h49, LJ = 8'h4A, LK = 8'h4B, LL = 8'h4C,
	LM = 8'h4D, LN = 8'h4E, LO = 8'h4F, LP = 8'h50,
	LQ = 8'h51, LR = 8'h52, LS = 8'h53, LT = 8'h54,
	LU = 8'h55, LV = 8'h56, LW = 8'h57, LX = 8'h58,
	LY = 8'h59, LZ = 8'h5A, DOT = 8'h2E, DASH = 8'h2D,
	SPACE = 8'h20; 
  
  // 2^4 = 16 < 26 < 2^5 = 32
  reg [4:0] y_Q, Y_D; // y_Q represents current state, Y_D represents next state
  
  //Set defaults
  initial
	begin
	  y_Q = BREAK;
	  Y_D = BREAK;
	   letters_LCD_two[7:0] = SPACE;
      letters_LCD_two[15:8] = SPACE;
      letters_LCD_two[23:16] = SPACE;
      letters_LCD_two[31:24] = SPACE;
      letters_LCD_two[39:32] = SPACE;
      letters_LCD_two[47:40] = SPACE;
      letters_LCD_two[55:48] = SPACE;
      letters_LCD_two[63:56] = SPACE;
      letters_LCD_two[71:64] = SPACE;
      letters_LCD_two[79:72] = SPACE;
      letters_LCD_two[87:80] = SPACE;
      letters_LCD_two[95:88] = SPACE;
      letters_LCD_two[103:96] = SPACE;
      letters_LCD_two[111:104] = SPACE;
      letters_LCD_two[119:112] = SPACE;
      letters_LCD_two[127:120] = SPACE;
		
	   letters_LCD_one[7:0] = SPACE;
      letters_LCD_one[15:8] = SPACE;
      letters_LCD_one[23:16] = SPACE;
      letters_LCD_one[31:24] = SPACE;
      letters_LCD_one[39:32] = SPACE;
      letters_LCD_one[47:40] = SPACE;
      letters_LCD_one[55:48] = SPACE;
      letters_LCD_one[63:56] = SPACE;
      letters_LCD_one[71:64] = SPACE;
      letters_LCD_one[79:72] = SPACE;
      letters_LCD_one[87:80] = SPACE;
      letters_LCD_one[95:88] = SPACE;
      letters_LCD_one[103:96] = SPACE;
      letters_LCD_one[111:104] = SPACE;
      letters_LCD_one[119:112] = SPACE;
      letters_LCD_one[127:120] = SPACE;
	end
	
  always @ (posedge CLOCK_50) begin
	  if (CCount >= 25000000) begin
			CCount = 0;
			pulse = ~pulse;
	  end else begin
			CCount = CCount + 1;
	  end
	  
	  newbreak = 0;
	  newdot = 0;
	  play = 0;
	  
	  //KEY[0] was inverted
	  if (!KEY[0]) begin
			play = 0;
			Kcount = Kcount + 1;
			if (Bcount > 0) begin
				if (Bcount > 15000000) begin
					if (Bcount > 91000000) begin
						v = 1; //word break
						newbreak = 1;
					end else begin
						v = 0; //character break
						newbreak = 1;
					end
				end
			end
			Bcount = 0;
	  end 
	  if (KEY[0]) begin
			play = 1;
			Bcount = Bcount + 1;
			if (Kcount > 0) begin
				if (Kcount > 15000000) begin
					if (Kcount > 39000000) begin
						w <= 1; //dash
						newdot = 1;
					end else begin
						w <= 0; //dot
						newdot = 1;
					end
				end
			end
			Kcount = 0;
	  end
  end
  
  generate
  audio3 player(CLOCK_50, CLOCK_27, KEY[1:0], TD_RESET, I2C_SDAT, I2C_SCLK,
	AUD_ADCLRCK, AUD_ADCDAT, AUD_DACLRCK, AUD_DACDAT, AUD_BCLK, AUD_XCK,
	GPIO_0[35:0], GPIO_1[35:0], play);
  endgenerate
	  
  assign LEDG[7:0] = {~pulse,pulse,~pulse,pulse,~pulse,pulse,~pulse,pulse};
  assign ore = newdot ^ newbreak;
  
  
  /* Due to the nature of the previous loop and how it
  affects newdot and newbreak, they will never be the same
  so we can set ore = newdot || newbreak, but it is left
  as a xor just to be clear that we're avoiding unsteady
  behaviour nonetheless */

always @(posedge ore)	  
  begin: state_table
  case (newdot)
	1: begin
	case (y_Q)
		BREAK: 
			if (w) begin
				Y_D = T;
				letter_two = DASH;
				y_Q = Y_D;
					
				//Shift the next letter's value into the register
				letters_LCD_two = letters_LCD_two >> 8;
				letters_LCD_two[127:120] = letter_two;
				 
			end
			else begin
				Y_D = E;
				letter_two = DOT;
				y_Q = Y_D;
					
				//Shift the next letter's value into the register
				letters_LCD_two = letters_LCD_two >> 8;
				letters_LCD_two[127:120] = letter_two;
				 
			end
			
		E: 
			if (w) begin
				Y_D = A;
				letter_two = DASH;
				y_Q = Y_D;
				
				//Shift the next letter's value into the register
				letters_LCD_two = letters_LCD_two >> 8;
				letters_LCD_two[127:120] = letter_two;
				 
			end
			else begin
				Y_D = I;
				letter_two = DOT;
				y_Q = Y_D;
				
				//Shift the next letter's value into the register
				letters_LCD_two = letters_LCD_two >> 8;
				letters_LCD_two[127:120] = letter_two;
				 
			end
			
		T: 
			if (w) begin
				Y_D = M;
				letter_two = DASH;
				y_Q = Y_D;
				
				//Shift the next letter's value into the register
				letters_LCD_two = letters_LCD_two >> 8;
				letters_LCD_two[127:120] = letter_two;
				 	
			end
			else begin
				Y_D = N;
				letter_two = DOT;
				y_Q = Y_D;
				
				//Shift the next letter's value into the register
				letters_LCD_two = letters_LCD_two >> 8;
				letters_LCD_two[127:120] = letter_two;
				 
			end
			
		I: 
			if (w) begin
				Y_D = U;
				letter_two = DASH;
				y_Q = Y_D;
				letters_LCD_two = letters_LCD_two >> 8;
				letters_LCD_two[127:120] = letter_two;
				 
			end
			else begin
				Y_D = S;
				letter_two = DOT;
				y_Q = Y_D;
				
				//Shift the next letter's value into the register
				letters_LCD_two = letters_LCD_two >> 8;
				letters_LCD_two[127:120] = letter_two;
				 
			end
			
		A: 
			if (w) begin
				Y_D = W;
				letter_two = DASH;
				y_Q = Y_D;
				
				//Shift the next letter's value into the register
				letters_LCD_two = letters_LCD_two >> 8;
				letters_LCD_two[127:120] = letter_two;
				 
			end
			else begin
				Y_D = R;
				letter_two = DOT;
				y_Q = Y_D;
				
				//Shift the next letter's value into the register
				letters_LCD_two = letters_LCD_two >> 8;
				letters_LCD_two[127:120] = letter_two;
				 
			end
			
		N: 
			if (w) begin
				Y_D = K;
				letter_two = DASH;
				y_Q = Y_D;
				
				//Shift the next letter's value into the register
				letters_LCD_two = letters_LCD_two >> 8;
				letters_LCD_two[127:120] = letter_two;
				 
			end
			else begin
				Y_D = D;
				letter_two = DOT;
				y_Q = Y_D;
				
				//Shift the next letter's value into the register
				letters_LCD_two = letters_LCD_two >> 8;
				letters_LCD_two[127:120] = letter_two;
				 
			end
			
		M: 
			if (w) begin
				Y_D = O;
				letter_two = DASH;
				y_Q = Y_D;
				
				//Shift the next letter's value into the register
				letters_LCD_two = letters_LCD_two >> 8;
				letters_LCD_two[127:120] = letter_two; 
			end
			else begin
				Y_D = G;
				letter_two = DOT;
				y_Q = Y_D;
				
				//Shift the next letter's value into the register
				letters_LCD_two = letters_LCD_two >> 8;
				letters_LCD_two[127:120] = letter_two;
			end
			
		S: 
			if (w) begin
				Y_D = V;
				letter_one = LV;
				letter_two = DASH;
				y_Q = Y_D;
				letters_LCD_two = letters_LCD_two >> 8;
				letters_LCD_two[127:120] = letter_two;    
			end
			else begin
				Y_D = H;
				letter_one = LH;
				letter_two = DOT;
				y_Q = Y_D;
				
				//Shift the next letter's value into the register
				letters_LCD_two = letters_LCD_two >> 8;
				letters_LCD_two[127:120] = letter_two;  
			end
			
		U: 
			if (!w) begin
				Y_D = F;
				letter_one = LF;
				letter_two = DOT;
				y_Q = Y_D;
				
				//Shift the next letter's value into the register
				letters_LCD_two = letters_LCD_two >> 8;
				letters_LCD_two[127:120] = letter_two;  
			end
			else begin
				Y_D = BREAK;
				letter_one = LU;
				y_Q = Y_D;
				#1000; //delay to prevent completion of the block 
			end
			
		R: 
			if (!w) begin
				Y_D = L;
				letter_one = LL;
				letter_two = DOT;
				y_Q = Y_D;
				
				//Shift the next letter's value into the register
				letters_LCD_two = letters_LCD_two >> 8;
				letters_LCD_two[127:120] = letter_two;
				#1000; //delay to prevent completion of the block  
			end
			else begin
				Y_D = BREAK;
				letter_one = LR;
				y_Q = Y_D;
				#1000; //delay to prevent completion of the block 
			end
			
		W: 
			if (w) begin
				Y_D = J;
				letter_one = LJ;
				letter_two = DASH;
				y_Q = Y_D;
				
				//Shift the next letter's value into the register
				letters_LCD_two = letters_LCD_two >> 8;
				letters_LCD_two[127:120] = letter_two;
				#1000; //delay to prevent completion of the block   
			end
			else begin
				Y_D = P;
				letter_one = LP;
				letter_two = DOT;
				y_Q = Y_D;
				
				//Shift the next letter's value into the register
				letters_LCD_two = letters_LCD_two >> 8;
				letters_LCD_two[127:120] = letter_two;
				#1000; //delay to prevent completion of the block  
			end
			
		D: 
			if (w) begin
				Y_D = X;
				letter_one = LX;
				letter_two = DASH;
				y_Q = Y_D;
				
				//Shift the next letter's value into the register
				letters_LCD_two = letters_LCD_two >> 8;
				letters_LCD_two[127:120] = letter_two;
				#1000; //delay to prevent completion of the block  	
			end
			else begin
				Y_D = B;
				letter_one = LB;
				letter_two = DOT;
				y_Q = Y_D;
				
				//Shift the next letter's value into the register
				letters_LCD_two = letters_LCD_two >> 8;
				letters_LCD_two[127:120] = letter_two;
				#1000; //delay to prevent completion of the block 
			end
			
		K: 
			if (w) begin
				Y_D = Y;
				letter_one = LY;
				letter_two = DASH;
				y_Q = Y_D;
				
				//Shift the next letter's value into the register
				letters_LCD_two = letters_LCD_two >> 8;
				letters_LCD_two[127:120] = letter_two;
				#1000; //delay to prevent completion of the block 
				 
			end
			else begin
				Y_D = C;
				letter_one = LC;
				letter_two = DOT;
				y_Q = Y_D;
				
				//Shift the next letter's value into the register
				letters_LCD_two = letters_LCD_two >> 8;
				letters_LCD_two[127:120] = letter_two;
				#1000; //delay to prevent completion of the block 
			end
			
		G: 
			if (w) begin
				Y_D = Q;
				letter_one = LQ;
				letter_two = DASH;
				y_Q = Y_D;
				
				//Shift the next letter's value into the register
				letters_LCD_two = letters_LCD_two >> 8;
				letters_LCD_two[127:120] = letter_two;
				#1000; //delay to prevent completion of the block  
			end
			else begin
				Y_D = Z;
				letter_one = LZ;
				letter_two = DOT;
				y_Q = Y_D;
				
				//Shift the next letter's value into the register
				letters_LCD_two = letters_LCD_two >> 8;
				letters_LCD_two[127:120] = letter_two;
				#1000; //delay to prevent completion of the block
				end
		O: 
			begin
				Y_D = BREAK;
				letter_one = LO;
				y_Q = Y_D;
				#1000; //delay to prevent completion of the block 
			end
		default: Y_D = BREAK;
	endcase
	end
	
	/* newbreak == 1 since ore == newbreak ^ newdot 
	and newdot is false */
	0: case (v)
		0: 
			begin
				Y_D = BREAK;
				case (y_Q)
					E: letter_one = LE;
					T: letter_one = LT;
					I: letter_one = LI;
					A: letter_one = LA;
					N: letter_one = LN;
					M: letter_one = LM;
					S: letter_one = LS;
					U: letter_one = LU;
					R: letter_one = LR;
					W: letter_one = LW;
					D: letter_one = LD;
					K: letter_one = LK;
					G: letter_one = LG;
					O: letter_one = LO;
					H: letter_one = LH;
					V: letter_one = LV;
					F: letter_one = LF;
					L: letter_one = LL;
					P: letter_one = LP;
					J: letter_one = LJ;
					B: letter_one = LB;
					X: letter_one = LX;
					C: letter_one = LC;
					Y: letter_one = LY;
					Z: letter_one = LZ;
					Q: letter_one = LQ;
				endcase
				y_Q = Y_D;
				//Shift the next letter's value into the register
				letters_LCD_one = letters_LCD_one >> 8;
				letters_LCD_one[127:120] = letter_one;
				#1000; //delay to prevent completion of the block 
			end
			
		1: 
			begin
				letter_one = SPACE;
				letter_two = SPACE;
				Y_D = BREAK;
				y_Q = Y_D;
				
				//Shift the next letter's value into the register
				letters_LCD_two = letters_LCD_two >> 8;
				letters_LCD_two[127:120] = letter_two;
				letters_LCD_one = letters_LCD_one >> 8;
				letters_LCD_one[127:120] = letter_one;
				#1000; //delay to prevent completion of the block 
			end
		endcase
	endcase 
  end // state_table
	generate
	//Display the two rows
	LCD disp (CLOCK_50, KEY[1:0], GPIO_0, GPIO_1, LCD_ON, LCD_BLON, LCD_RW, LCD_EN,
	LCD_RS, PS2_DAT, PS2_CLK, LCD_DATA, letters_LCD_one, letters_LCD_two);
	endgenerate
endmodule
