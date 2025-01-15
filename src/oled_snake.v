`timescale 1ns / 1ps

/*
All the command can refer to SSD1306 user guide
Author : Zheng Pengfei
Claim  : This is only for fun.
Ps	   : When your code has multipile value set op
		 please use 'tab' to align your code, that
		 makes your code clean.
*/

// now we use oled to do a snake job

module oledctrl_zpf( 
	input 	sysclk,		// system clock input 100MHz
	input 	rstn,		// system reset input active-low

	output 	oled_res,	// oled-chip reset active-low
	output	oled_dc,	// oled data(high)/command(low) select
	output 	oled_sclk,	// oled clk 10MHz
	output	oled_sdin,	// oled data, sending along the falling edge of sclk
	output	oled_vbat,	// oled power enable for internal power supply
	output 	oled_vdd,	// oled power enable for digital power
	
	output  led0  		// connect to init_done
	, input	display,	// connect to bntc
	input	mv_l,		// snake move left
	input	mv_r,		// snake move right
	input	mv_u,		// snake move up
	input	mv_d		// snake move down
);

//wire display;
//wire mv_l;
//wire mv_r;
//wire mv_u;
//wire mv_d;

reg [31:0] timer;   // used for initialization
reg oled_res_reg;
reg oled_dc_reg;
reg oled_sclk_reg;
reg oled_sdin_reg;
reg oled_vdd_reg;
reg oled_vbat_reg;

//wire display;

reg [31:0] timer_update;   // used for update
reg oled_update_dc_reg;

reg [7:0] cd_data;
reg [7:0] cd_data_update;
reg [7:0] parall_reg;
reg trans_start_init;	// the begin of p2s transcation for init
reg trans_start_x;	// the begin of p2s transcation 1cycle delay
reg trans_og;		// p2s transcation ongoing
reg trans_done;		// then end of p2s transcation
reg [7:0] p2s_cnt;  // p2s counter

reg sclk_x, sclk_xx; // nx indicate n cycle delay of clk
reg [8:0] sclk_div_cnt;	// divide clk 1/10

reg [11:0] n_loc; // row + col = 32 + 128 = 5'b11111 + 7'b1111111 = 12 bit

localparam TIMER_OVER = 10000000;

reg [3:0] init_state;
reg [7:0] init_cmd_reg;
reg [3:0] init_cmd_cnt;
reg init_res_set;
reg [31:0]init_res_set_cnt;

reg [31:0] cnt_random; // to generate random data

reg init_done;
reg init_done_d;

reg wait_flag;
reg [31:0] wait_timer;

reg [3:0] update_state;
reg trans_start_update; // the begin of p2s transcation for update
reg [7:0] update_cmd_reg;
reg [7:0] page_index; // for 128*32, 4 pages
reg [7:0] update_cmd_cnt;

reg snake_init;
reg update_snake_cnt;

localparam ADDRMODE	= 4'h1; // Set address mode
localparam UPSCREEN	= 4'h2;
localparam UPDATE	= 4'h3;
localparam FRESHW	= 4'h4; // fresh nop
localparam WDATA	= 4'h5; // 
localparam RDATANOP	= 4'h6; // 
localparam RDATA	= 4'h7; // 
localparam DRAWSNAKE = 4'h8; // 
localparam RDATANOP2 = 4'h9; // 
localparam RDATA2	 = 4'hA; // 
localparam RMAT		 = 4'hB; // 
localparam READGAP	 = 4'hC; // 
localparam CLEARB	 = 4'hD; // clear ram B
localparam DRAWFOOD	 = 4'hE; // 

localparam IDLE  	 = 4'h0; // IDLE
localparam PUVDD 	 = 4'h1; // 1. Power up VDD by pulling OLED_VDD low. Wait 1ms.
localparam PULSERES  = 4'h2; // 2. Pulse RES# low for at least 3us.
localparam ICCMD 	 = 4'h3; // 3. Send initialization/configuration commands.
localparam PUVBAT 	 = 4'h4; // 4. Power up VBAT by pulling OLED_VBAT low. Wait 100ms for voltage to stabilize.
localparam CLRSCREEN = 4'h5; // 5. Clear screen by writing zero to the display buffer.
localparam DISPLAYON = 4'h6; // 6. Send "Display On" command (0xAF).

assign oled_res   =  oled_res_reg ;
assign oled_dc    =  (init_done == 1'b1) ? oled_update_dc_reg   : oled_dc_reg  ;
assign oled_sclk  =  oled_sclk_reg;
assign oled_sdin  =  oled_sdin_reg;
assign oled_vdd   =  oled_vdd_reg ;
assign oled_vbat  =  oled_vbat_reg;

localparam SIM_MODE = 0; // exclusive with SYN_MODE
localparam SYN_MODE = 1; // exclusive with SIM_MODE

localparam ONE_MS  = 100001 * SYN_MODE +  101 * SIM_MODE; // for simulate, decrease
localparam TWO_MS  = 200001 * SYN_MODE +  101 * SIM_MODE; // for simulate, decrease
localparam ONE_HUNDERD_MS  = 10000001 * SYN_MODE +  101 * SIM_MODE; // for simulate, decrease
localparam THREE_US  = 3001 * SYN_MODE +  101 * SIM_MODE; // for simulate, decrease

assign led0 = init_done;

localparam FRESH_TIME = 5000000 * SYN_MODE +  50000 * SIM_MODE;
reg [31:0] fresh_cnt;

//在mat存储完成之前锁定键入，存储完成后释放
reg [1:0] button_latch;
reg dis_on_off;

// ram w/r enable
reg ena, wea, enb, web;
reg [11:0] addra, addrb;
reg [12:0] dina;
reg dinb;

wire [12:0]  douta;
wire  doutb;

// extra buffer
reg [12:0] e_buf;
// | data      | valid|
//12           1      0

reg [11:0] snake_cnt;
reg [11:0] food ;

wire clk;

reg ate; // qualify that food has been ate

reg [31:0] clr_cnt;

reg to_right, to_up, to_down, to_left, dis;
reg mv_d_r, mv_l_r, mv_r_r, mv_u_r, dis_r;

always @(posedge sysclk or negedge rstn) // pluse turn to level
begin
	if (!rstn) begin
		to_right <= 1'b0;
		to_up 	 <= 1'b0;
		to_down  <= 1'b0;
		to_left  <= 1'b0;
		mv_d_r   <= 1'b0;
		mv_l_r   <= 1'b0;
		mv_r_r   <= 1'b0;
		mv_u_r   <= 1'b0;
		dis   	 <= 1'b0;
		dis_r    <= 1'b0;
	end else begin
		mv_d_r	 <= mv_d;
		mv_l_r   <= mv_l;
		mv_r_r   <= mv_r;
		mv_u_r   <= mv_u;
		dis_r    <= display;
		
		if (mv_d_r == 1'b1 && mv_d == 1'b0) begin
			to_down	 <= ~to_down;
			to_right <= 1'b0;
			to_up 	 <= 1'b0;
			to_left  <= 1'b0;
		end
		
		if (mv_r_r == 1'b1 && mv_r == 1'b0) begin
			to_right <= ~to_right;
			to_up 	 <= 1'b0;
			to_down  <= 1'b0;
			to_left  <= 1'b0;
		end
		
		if (mv_u_r == 1'b1 && mv_u == 1'b0) begin
			to_up	 <= ~to_up;
			to_right <= 1'b0;
			to_down  <= 1'b0;
			to_left  <= 1'b0;
		end
		
		if (mv_l_r == 1'b1 && mv_l == 1'b0) begin
			to_left	 <= ~to_left;
			to_right <= 1'b0;
			to_up 	 <= 1'b0;
			to_down  <= 1'b0;
		end
		
		if (dis_r == 1'b1 && display == 1'b0) begin
			dis		<= ~dis;
		end
	end
end

//vio_0 VIO_inst (
//  .clk(clk),                // input wire clk
//  .probe_out0(display),  // output wire [0 : 0] probe_out0
//  .probe_out1(mv_l),  // output wire [0 : 0] probe_out1
//  .probe_out2(mv_r),  // output wire [0 : 0] probe_out2
//  .probe_out3(mv_u),  // output wire [0 : 0] probe_out3
//  .probe_out4(mv_d)  // output wire [0 : 0] probe_out4
//);

ila_0 ILA_inst (
	.clk		(clk			), 	// input wire clk


	.probe0		(update_state	), 	// input wire [3:0]  probe0  
	.probe1		(e_buf			), 	// input wire [12:0]  probe1 
	.probe2		(n_loc			) 	// input wire [11:0]  probe2
);

  clk_wiz_0 ck_gen
   (
    // Clock out ports
    .clk_out1	(clk	),     		// output clk_out1
   // Clock in ports
    .clk_in1	(sysclk ));      	// input clk_in1

blk_mem_gen_0 snake_mat (
  .clka			(clk	),    	// input wire clka
  .ena			(ena	),      // input wire ena
  .wea			(wea	),      // input wire [0 : 0] wea
  .addra		(addra	),  	// input wire [11 : 0] addra
  .dina			(dina	),      // input wire [12 : 0] dina
  .douta		(douta	)
);

blk_mem_gen_1 draw_mat (
  .clka			(clk	),    	// input wire clka
  .ena			(enb	),      // input wire ena
  .wea			(web	),      // input wire [0 : 0] wea
  .addra		(addrb	),  	// input wire [11 : 0] addra
  .dina			(dinb	),      // input wire dina
  .douta		(doutb	)
);

always @(posedge clk or negedge rstn)
begin
	if (!rstn) begin
		button_latch <= 0;
		dis_on_off   <= 0;
	end else begin
		if (update_state != READGAP) begin
			if (to_right)
				button_latch <= 2'b00;
			else if (to_left)
				button_latch <= 2'b01;
			else if (to_down)
				button_latch <= 2'b10;
			else if (to_up)
				button_latch <= 2'b11;
				
			if (dis == 1'b1)
				dis_on_off 	<= 1'b1;
			else
				dis_on_off 	<= 1'b0;
		end
	end
end

// initial sequence
always @ (posedge clk or negedge rstn)
begin
	if (!rstn) begin
		timer 				<= 0;
		oled_res_reg 		<= 1'b1;
		oled_dc_reg 		<= 1'b1;
		oled_vbat_reg		<= 1'b1;
		oled_vdd_reg		<= 1'b1;
		trans_start_init	<= 1'b0;
		init_cmd_reg		<= 0;
		init_cmd_cnt		<= 0;
		init_res_set		<= 0;
		init_res_set_cnt	<= 0;
		init_done			<= 0;
		cd_data				<= 0;
		init_state			<= IDLE;
		cnt_random			<= 0;
	end else begin
		cnt_random <= cnt_random + 1;
		
		case (init_state)
		IDLE : begin
			oled_dc_reg	<= 1'b0;
			if (init_done == 1'b0)
				init_state <= PUVDD;
		end
		PUVDD : begin
			oled_vdd_reg <= 1'b0;
			if (timer == ONE_MS) begin
				init_state 	<= PULSERES;
				timer 		<= 0;
			end else
				timer <= timer + 1;
		end
		PULSERES : begin // do we need this?
		/* 	if (timer == THREE_US) begin
				init_state 		<= ICCMD;
				oled_res_reg 	<= 1'b1;
				timer			<= 0;
			end else begin
				oled_res_reg	<= 1'b0;
				timer 			<= timer + 1;
			end */
			init_state 		<= ICCMD;
		end
		ICCMD : begin
			/* Send DisplayOff command (hAE)
			   Turn RES on (active low), delay 1ms
			   Turn RES off (active low), delay 1ms
			   Send ChargePump1 command (h8D)
			   Send ChargePump2 command (h14)
			   Send PreCharge1 command (hD9)
			   Send PreCharge2 command (hF1)*/
			case (init_cmd_cnt) 
			4'h0 : cd_data <= 8'hAE;
			4'h1 : cd_data <= 8'h8D;
			4'h2 : cd_data <= 8'h14;
			4'h3 : cd_data <= 8'hD9;
			4'h4 : cd_data <= 8'hF1;
			default : ;
			endcase
			
			if (init_res_set == 1'b0 && init_cmd_cnt == 1'b0 && trans_done == 1'b1)
				init_res_set <= 1'b1;
			else begin
				if (init_res_set == 1'b1) begin
					if (init_res_set_cnt <= TWO_MS) begin
						init_res_set_cnt <= init_res_set_cnt + 1'b1;
						if (init_res_set_cnt <= ONE_MS)
							oled_res_reg <= 1'b0;
						else	
							oled_res_reg <= 1'b1;
					end else begin
						oled_res_reg 	 <= 1'b1;
						init_res_set 	 <= 0;
					end
				end else
					init_res_set_cnt <=0;
			end
			
			if (trans_start_init == 1'b0 && init_res_set == 1'b0 && trans_og == 1'b0 && trans_start_x == 1'b0) begin
				if (trans_done == 1'b0) begin
					oled_dc_reg		 <= 1'b0;
					trans_start_init <= 1'b1;
				end 
			
				if (trans_done == 1'b1) begin
					if (init_cmd_cnt < 4'h4)
						init_cmd_cnt <= init_cmd_cnt + 1'b1;
					else begin
						init_cmd_cnt <= 0;
						init_state 	 <= PUVBAT;
					end
				end
			end else
				trans_start_init <= 1'b0;
		end
		PUVBAT : begin
			if (timer == ONE_HUNDERD_MS) begin
				timer 			<= 0;
				oled_vbat_reg 	<= 1'b1;
				init_state		<= CLRSCREEN;
			end else begin
				timer			<= timer + 1'b1;
				oled_vbat_reg	<= 1'b0;
			end
		end
		CLRSCREEN : begin
			/* Send DispContrast1 command (h81)
			   Send DispContrast2 command (h0F)
			   Send SetSegRemap command (hA0)
			   Send SetScanDirection command (hC0)
			   Send Set Lower Column Address command (hDA)
			   Send Lower Column Address (h00)*/
			case (init_cmd_cnt) 
			4'h0 : cd_data <= 8'h81;
			4'h1 : cd_data <= 8'h0F;
			4'h2 : cd_data <= 8'hA0;
			4'h3 : cd_data <= 8'hC0;
			4'h4 : cd_data <= 8'hDA;
			4'h5 : cd_data <= 8'h00;
			default : ;
			endcase
		
			if (trans_start_init == 1'b0 && trans_og == 1'b0 && trans_start_x == 1'b0) begin
				if (trans_done == 1'b0) begin
					oled_dc_reg	<= 1'b0;
					trans_start_init <= 1'b1;
				end else begin
					if (init_cmd_cnt < 4'h5)
						init_cmd_cnt <= init_cmd_cnt + 1'b1;
					else begin
						init_cmd_cnt <= 0;
						init_state 	 <= DISPLAYON;
					end
				end
			end else
				trans_start_init <= 1'b0;
		end
		DISPLAYON : begin
			if (trans_start_init == 1'b0 && trans_og == 1'b0 && trans_start_x == 1'b0) begin
				if (trans_done == 1'b0) begin
					cd_data		<= 8'hAF;
					oled_dc_reg	<= 1'b0;
					trans_start_init <= 1'b1;
				end else begin
					init_state	<= IDLE;
					init_done	<= 1'b1; // here we finished initialization, that's the first step to light up an oled screen
				end
			end else
				trans_start_init <= 1'b0;
		end	
		endcase
	end
end

// Update character
always @ (posedge clk or negedge rstn)
begin
	if (!rstn) begin
		timer_update 		<= 0;
		trans_start_update 	<= 0;
		update_state		<= IDLE;
		update_cmd_reg      <= 0;
		update_cmd_cnt      <= 0;
		page_index		    <= 0;
		cd_data_update	    <= 0;
		oled_update_dc_reg	<= 0;
		n_loc				<= 0;
		fresh_cnt			<= 0;
		e_buf				<= 0;
		// ram
		ena					<= 0;
		wea					<= 0;
		addra				<= 0;
		dina				<= 0;
		enb					<= 0;
		web					<= 0;
		addrb				<= 0;
		dinb				<= 0;
		snake_cnt	        <= 32'hA; // at beginning, snake length = 10
		food				<= 0;
		snake_init			<= 0;
		clr_cnt				<= 0;
		ate					<= 0;
		init_done_d			<= 0;
		update_snake_cnt	<= 0;
	end else begin
		init_done_d		<= init_done;
		
		if (ate == 1'b1 || (init_done == 1'b1 && init_done_d == 1'b0)) begin
			ate  <= 1'b0;
			food <= cnt_random[11:0]; 
	    end 
		
		case (update_state)
		IDLE : begin
			oled_update_dc_reg	<= 1'b0;
			cd_data_update		<= 0;
			trans_start_update	<= 0;
			
			if (init_done == 1'b1 && n_loc == snake_cnt) begin
				snake_init	 <= 1'b0;
				update_state <= FRESHW;
				ena			 <= 1'b0;
				wea			 <= 1'b0;
				dina		 <= 0;
				addra		 <= 0;
				n_loc		 <= 0;
			end else begin
				if (dis_on_off == 1'b1) begin// start up
					snake_init	<= 1'b1;
					snake_cnt	<= 32'hA; // at beginning, snake length = 10
				end
				
				if (dis_on_off == 1'b1) begin		// write initial data
					if (n_loc < snake_cnt) begin
						dina		 <= {5'b00000, 7'b0000000 + ((snake_cnt - n_loc - 1) * 8), 1'b1};
						addra		 <= n_loc;
					end else begin
						addra		<= n_loc;
						dina		<= {food, 1'b1};
					end
					update_state <= WDATA;
					ena			 <= 1'b1;
					wea			 <= 1'b1;
				end else begin
					// the snake head is on the right side of mat
					ena			 <= 1'b1;
					wea			 <= 1'b0;
					addra		 <= n_loc;
					update_state <= RDATANOP;
				end
			end
		end
		WDATA : begin
			if (snake_init == 1'b1) begin // during init , do not need to read
				ena			 <= 1'b0;
				wea 		 <= 1'b0;
				update_state <= IDLE;
				n_loc		 <= n_loc + 1;
			end	else begin   
				wea			 <= 1'b0;	
				if (n_loc == snake_cnt) begin
					update_state <= CLEARB;
					ena			 <= 1'b0;
					wea			 <= 1'b0;
					dina		 <= 0;
					addra		 <= 0;
					n_loc		 <= 0;
					e_buf		 <= 0;
					web			 <= 1'b1;
					enb			 <= 1'b1;
					addrb		 <= 0;
					dinb		 <= 0;
				end else begin
					update_state <= RDATANOP;
					addra		 <= n_loc;
				end
			end
			e_buf		 <= douta;
		end
		RDATANOP : begin
			ena			 <= 1'b0;
			update_state <= RDATA;
		end
		RDATA : begin
			update_state <= READGAP;
		end
		READGAP : begin
			n_loc		 <= n_loc + 1;
			update_state <= WDATA;	
			ena			 <= 1'b1;
			wea			 <= 1'b1;
			if (n_loc == 0) begin // move the snake head first
				if (button_latch == 2'b00) begin // right
					if (douta[10:1] <= 10'h3f7)
						dina	<= {douta[12:1]+4'h8, douta[0]};
					else
						dina	<= {douta[12:11], 7'h00, douta[3:1], douta[0]};
				end else if (button_latch == 2'b01) begin
					if (douta[10:1] >= 10'h8)
						dina	<= {douta[12:1]-4'h8, douta[0]};
					else
						dina	<= {douta[12:11], 7'h7F, douta[3:1], douta[0]};
				end else if (button_latch == 2'b10) begin // down
					if (douta[3:1] == 3'h7)
						dina	<= {douta[12:11]+1'b1, douta[10:4], 3'h0, douta[0]};
					else
						dina	<= {douta[12:11], douta[10:1]+1'b1, douta[0]};
				end else if (button_latch == 2'b11) begin
					if (douta[3:1] == 0)
						dina	<= {douta[12:11]-1'b1, douta[10:4], 3'h7, douta[0]};
					else
						dina	<= {douta[12:11], douta[10:1]-1'b1, douta[0]};
				end
				if (douta[12:1] == food) begin
					ate		  		 <= 1'b1;
					update_snake_cnt <= 1'b1;
				end
			end else
				dina	<= e_buf;
		end
		CLEARB : begin
			addrb	<= clr_cnt[11:0];
			if (clr_cnt <= 32'hFFF)
				clr_cnt 		<= clr_cnt + 1;
			else begin
				update_state	<= FRESHW;
				clr_cnt 		<= 0;
				web				<= 1'b0;
				enb				<= 1'b0;
				addrb			<= 0;
				dinb			<= 0;
			end
		end
		FRESHW : begin
			if (fresh_cnt == FRESH_TIME) begin
				update_state <= ADDRMODE;
				fresh_cnt 	 <= 0;
			end else
				fresh_cnt <= fresh_cnt + 1'b1;
		end
		ADDRMODE : begin
			/* 1.set memory addressing mode command
			   2.set page addressing mode*/
			case (update_cmd_cnt) 
			8'h0 : cd_data_update <= 8'h20;
			8'h1 : cd_data_update <= 8'h10; // set for page addressing mode
			default : ;
			endcase
		
			if (trans_start_update == 1'b0 && trans_og == 1'b0 && trans_start_x == 1'b0) begin
				if (trans_done == 1'b0) begin
					oled_update_dc_reg	<= 1'b0;
					trans_start_update  <= 1'b1;
				end else begin
					if (update_cmd_cnt < 8'h1)
						update_cmd_cnt <= update_cmd_cnt + 1'b1;
					else begin
						update_cmd_cnt <= 0;
						update_state   <= DRAWSNAKE;
						enb	           <= 1'b1;
					end
				end
			end else
				trans_start_update <= 1'b0;
		end
		DRAWSNAKE : begin
			if (n_loc == snake_cnt) begin
				update_state <= DRAWFOOD;
				ena			 <= 1'b0;
				wea			 <= 1'b0;
				addra		 <= 0;
				addrb		 <= food;
				n_loc		 <= 0;
				dinb		 <= 1'b1;
			end else begin
				ena			 <= 1'b1;
				wea			 <= 1'b0;
				addra		 <= n_loc; // n_loc width should compliant with addr width, note*
				update_state <= RDATANOP2;
				enb			 <= 1'b0;
				web			 <= 1'b0;
			end
		end
		DRAWFOOD : begin
			enb			 <= 1'b0;
			web			 <= 1'b0;
			update_state <= UPSCREEN;
			addrb		 <= 0;
			dinb		 <= 0;
		end
		RDATANOP2 : begin
			ena			 <= 1'b0;
			update_state <= RDATA2;
		end
		RDATA2 : begin
			if (douta[0] == 1'b1)
				dinb		 <= 1'b1;
			else 	
				dinb		 <= 1'b0;

			addrb		 <= douta[12:1];
			enb			 <= 1'b1;
			web			 <= 1'b1;
			n_loc		 <= n_loc + 1;
			update_state	<= DRAWSNAKE;
		end
		UPSCREEN : begin
			/* 1.set page address 
			   */
			case (update_cmd_cnt) 
			8'h0 : cd_data_update <= 8'h22;
			8'h1 : cd_data_update <= 8'h00 + page_index; // set for start address
			8'h2 : cd_data_update <= 8'h00; // set for end address
			8'h3 : cd_data_update <= 8'h10; // set for GDDRAM page start address
			default : ;
			endcase
			
			if (trans_start_update == 1'b0 && trans_og == 1'b0 && trans_start_x == 1'b0) begin
				if (trans_done == 1'b0) begin
					oled_update_dc_reg	<= 1'b0;
					trans_start_update  <= 1'b1;
				end else begin
					if (update_cmd_cnt < 8'h3)
						update_cmd_cnt <= update_cmd_cnt + 1'b1;
					else begin
						update_cmd_cnt <= 0;
						update_state   <= UPDATE;
					end
					n_loc		   <= 0;
				end
			end else
				trans_start_update <= 1'b0;
		end
		UPDATE : begin
			cd_data_update[addrb[2:0]] <= doutb;
			
			if (trans_done == 1'b1)
				update_cmd_cnt <= update_cmd_cnt + 1'b1;
			
			if (trans_start_update == 1'b0 && trans_og == 1'b0 && n_loc == 8'h8) begin
				if (trans_done == 1'b0) 
					trans_start_update  <= 1'b1;
					
				if (update_cmd_cnt <= 8'd127) 
					oled_update_dc_reg	<= 1'b1;
				else begin
					update_cmd_cnt 		<= 0;
					oled_update_dc_reg	<= 1'b0;
					if (page_index < 8'h3) begin
						update_state   	<= UPSCREEN;
						page_index	   	<= page_index + 1;
					end	else begin
						update_state   <= IDLE;
						page_index	   <= 0;
						n_loc		   <= 0;
						if (update_snake_cnt == 1'b1) begin
							update_snake_cnt <= 1'b0;
							snake_cnt		 <= snake_cnt + 1'b1;
						end	
					end
				end
			end else begin
				trans_start_update <= 1'b0;
				enb				   <= 1'b1;
				web				   <= 1'b0;
				addrb			   <= {page_index[1:0], update_cmd_cnt[6:0], n_loc[2:0]};
				update_state	   <= RMAT;
				if (n_loc < 8'h8)
					n_loc	<= n_loc + 1;
			end
		end
		RMAT : begin
			enb			 <= 1'b0;
			update_state <= UPDATE;
			if (trans_done == 1'b1) begin
				update_cmd_cnt <= update_cmd_cnt + 1'b1;
				n_loc		   <= 0;
			end
		end
		endcase
	end
end

// paralle to serial
always @ (posedge clk or negedge rstn)
begin
	if (!rstn) begin
		trans_done 		<= 0;
		oled_sdin_reg 	<= 1'b1;
		trans_og 		<= 1'b0;
		p2s_cnt 		<= 1'b0;
		oled_sclk_reg 	<= 1'b1;
		sclk_div_cnt 	<= 0;
		sclk_x 			<= 0;
		sclk_xx 		<= 0;
		parall_reg		<= 0;
		wait_flag		<= 0;
		wait_timer		<= 0;
		trans_start_x	<= 0;
	end else begin
		sclk_x 			<= oled_sclk_reg;
		sclk_xx		 	<= sclk_x;
		trans_start_x 	<= trans_start_init | trans_start_update;
		if (trans_start_x == 1'b1) begin
			trans_og 	<= 1'b1;
			if (init_done == 1'b1)
				parall_reg 	<= cd_data_update;	
			else
				parall_reg 	<= cd_data;	
		end else if (trans_done == 1'b1) 
			trans_done  <= 1'b0;
		else begin
			if (sclk_x == 1'b1 && sclk_xx == 1'b0) begin
				if (trans_og == 1'b1 && wait_flag == 1'b0) begin
					p2s_cnt			<= p2s_cnt + 1;
					parall_reg 		<= {parall_reg[6:0], parall_reg[7]};
				end
				
				if (p2s_cnt == 8'h7) begin
					wait_flag <= 1'b1;
					parall_reg <= 8'hFF;
				end
			end	else begin
				if (p2s_cnt == 8'h8 && wait_flag == 1'b0) 
					p2s_cnt <= 0;
				else if (wait_timer == 32'hC) begin
					wait_timer <= 0;
					trans_og   <= 1'b0;
					trans_done <= 1'b1;
					wait_flag  <= 0;
				end else begin
					if (wait_flag == 1'b1)
						wait_timer <= wait_timer + 1'b1;
				end
			end
		end
		
		// p2s
		if (trans_og == 1'b1) begin
			if (p2s_cnt > 8'h7)
				oled_sclk_reg <= 1'b1;
			else begin 
				if (sclk_div_cnt == 8'h4) begin // 10MHz sclk while clk 100MHz(That's 1 : 10)
					oled_sclk_reg <= ~oled_sclk_reg;
					sclk_div_cnt  <= 0;
				end else	
					sclk_div_cnt <= sclk_div_cnt + 1'b1;
			end
			
			oled_sdin_reg 	<= parall_reg[7];
		end
	end
end
endmodule