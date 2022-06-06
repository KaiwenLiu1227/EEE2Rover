module EEE_IMGPROC(
	// global clock & reset
	clk,
	reset_n,
	
	// mm slave
	s_chipselect,
	s_read,
	s_write,
	s_readdata,
	s_writedata,
	s_address,

	// stream sink
	sink_data,
	sink_valid,
	sink_ready,
	sink_sop,
	sink_eop,
	
	// streaming source
	source_data,
	source_valid,
	source_ready,
	source_sop,
	source_eop,
	
	// conduit
	mode
	
);


// global clock & reset
input	clk;
input	reset_n;

// mm slave
input							s_chipselect;
input							s_read;
input							s_write;
output	reg	[31:0]	s_readdata;
input	[31:0]				s_writedata;
input	[2:0]					s_address;


// streaming sink
input	[23:0]            	sink_data;
input								sink_valid;
output							sink_ready;
input								sink_sop;
input								sink_eop;

// streaming source
output	[23:0]			  	   source_data;
output								source_valid;
input									source_ready;
output								source_sop;
output								source_eop;

// conduit export
input                         mode;

////////////////////////////////////////////////////////////////////////
//
parameter IMAGE_W = 11'd640;
parameter IMAGE_H = 11'd480;
parameter MESSAGE_BUF_MAX = 256;
parameter MSG_INTERVAL = 6;
parameter BB_COL_DEFAULT = 24'h00ff00;
parameter CENTER_COL_DEFAULT=24'h0000ff;

wire [7:0]   red, green, blue, grey;
wire [7:0]   red_out, green_out, blue_out;

wire         sop, eop, in_valid, out_ready;
////////////////////////////////////////////////////////////////////////

// Detect red areas
wire red_detect,blue_detect,color_detect;
assign red_detect = red[7] & ~green[7] & ~blue[7];
// assign blue_detect = ~red[7] & ~green[7] & blue[7];
// assign purple_detect = red[7] & ~green[7] & blue[7];
// assign yellow_detect = red[7] & green[7] & ~blue[7];
// assign black_detect = ~red[7] & ~green[7] & ~blue[7];
// assign white_detect = red[7] & green[7] & blue[7];
// assign cyan_detect = ~red[7] & green[7] & blue[7];

wire [2:0] detected_color;
wire [8:0]h;
wire [7:0]s;
wire [7:0]v;

assign blue_detect = (h>=9'd200 & h<=9'd250)&s>=8'd43&v>=8'd50;

assign color_detect=blue_detect;
// Find boundary of cursor box

// Highlight detected areas
wire [23:0] red_high;
assign grey = green[7:1] + red[7:2] + blue[7:2]; //Grey = green/2 + red/4 + blue/4
// assign red_high  =  red_detect ? {8'hff, 8'h0, 8'h0} : {grey, grey, grey};
assign red_high  =  color_detect ? {8'hff, 8'h0, 8'h0} : {grey, grey, grey};

// Show bounding box
wire [23:0] new_image;
wire bb_active;
wire center_active;
assign bb_active = (x == left) | (x == right) | (y == top) | (y == bottom) ;
assign center_active= (x==center_x) | (y==center_y);

assign new_image = is_color_valid ? (center_active ? center_col : (bb_active ? bb_col : red_high)) : red_high;

// Switch output pixels depending on mode switch
// Don't modify the start-of-packet word - it's a packet discriptor
// Don't modify data in non-video packets
assign {red_out, green_out, blue_out} = (mode & ~sop & packet_video) ? new_image : {red,green,blue};

//Count valid pixels to tget the image coordinates. Reset and detect packet type on Start of Packet.
reg [9:0] x, y;

reg packet_video;
always@(posedge clk) begin
	if (sop) begin
		x <= 10'h0;
		y <= 10'h0;
		packet_video <= (blue[3:0] == 3'h0);
	end
	else if (in_valid) begin
		if (x == IMAGE_W-1) begin
			x <= 10'h0;
			y <= y + 10'h1;
		end
		else begin
			x <= x + 10'h1;
		end
	end
end

//Find first and last red pixels





reg [9:0] x_min[0:2], y_min[0:2], x_max[0:2], y_max[0:2];
reg [9:0] left[0:2], right[0:2], top[0:2], bottom[0:2],center_x[0:2],center_y[0:2];
reg [18:0] xy_cnt[0:2];
reg [31:0] x_increment[0:2],y_increment[0:2]; 


always@(posedge clk) begin
	// if (red_detect & in_valid) begin	//Update bounds when the pixel is red
	// 	if (x < x_min) x_min <= x;
	// 	if (x > x_max) x_max <= x;
	// 	if (y < y_min) y_min <= y;
	// 	y_max <= y;
	// end
	if (color_detect & in_valid) begin	//Update bounds when the pixel is red
		if (x < x_min[detected_color]) x_min[detected_color] <= x;
		if (x > x_max[detected_color]) x_max[detected_color] <= x;
		if (y < y_min[detected_color]) y_min[detected_color] <= y;
		y_max[detected_color] <= y;
		x_increment[detected_color]<=x_increment[detected_color]+x;
		y_increment[detected_color]<=y_increment[detected_color]+y;
		xy_cnt[detected_color]<=xy_cnt[detected_color]+1;
	end
	if (sop & in_valid) begin	//Reset bounds on start of packet
		x_min <= IMAGE_W-10'h1;
		x_max <= 0;
		y_min <= IMAGE_H-10'h1;
		y_max <= 0;
		x_increment<=0;
		y_increment<=0;
		xy_cnt<=0;
	end
end

//Process bounding box at the end of the frame.
reg [4:0] msg_state;

reg [7:0] frame_count;
reg is_color_valid=1;
always@(posedge clk) begin
	if (eop & in_valid & packet_video) begin  //Ignore non-video packets
		
		//Latch edges for display overlay on next frame
		if(xy_cnt<=200) begin
			is_color_valid<=0;
		end
		else begin
			is_color_valid<=1;
			left <= x_min;
			right <= x_max;
			top <= y_min;
			bottom <= y_max;
			center_x<=x_increment/xy_cnt;
			center_y<=y_increment/xy_cnt;
		end
		
		
		//Start message writer FSM once every MSG_INTERVAL frames, if there is room in the FIFO
		frame_count <= frame_count - 1;
		
		if (frame_count == 0 && msg_buf_size < MESSAGE_BUF_MAX - 3) begin
			msg_state <= 1;
			frame_count <= MSG_INTERVAL-1;
		end
	end
	
	//Cycle through message writer states once started
	if (msg_state != 0) msg_state <= msg_state + 1;
	else if(msg_state>=5) msg_state <=0;

end
	
//Generate output messages for CPU
reg [31:0] msg_buf_in; 
wire [31:0] msg_buf_out;
reg msg_buf_wr;
wire msg_buf_rd, msg_buf_flush;
wire [7:0] msg_buf_size;
wire msg_buf_empty;

parameter  BLACK_CODE = 3'b000;
parameter  WHITE_CODE = 3'b111;
parameter  RED_CODE = 3'b100;
parameter  BLUE_CODE = 3'b001;
parameter YELLOW_CODE=  3'b110;
parameter  PURPLE_CODE = 3'b101;

`define RED_BOX_MSG_ID "RBB"

// COLOR 3 COLOR 3 XYCNT 18 = 24
// X_C 10 Y_C 10 X_TOP 10 32
// BOT 10 LEFT 10 RIGHT 10 32 

always@(*) begin	//Write words to FIFO as state machine advances
	case(msg_state)
		0: begin
			msg_buf_in = 32'b0;
			msg_buf_wr = 1'b0;
		end
		1: begin
			msg_buf_in = 32'hffffffff;	//Message ID
			msg_buf_wr = 1'b1;
		end
		2: begin
			msg_buf_in = {RED_CODE,1'b0,RED_CODE,1'b0,xy_cnt,5'b0};
			msg_buf_wr = 1'b1;
		end
		3: begin
			msg_buf_in = {center_x,1'b0,center_y,1'b0,top};	//Top left coordinate
			msg_buf_wr = 1'b1;
		end
		4: begin
			msg_buf_in = {bottom,1'b0,left,1'b0,right}; //Bottom right coordinate
			msg_buf_wr = 1'b1;
		end
		// 4: begin
		// 	msg_buf_in = {5'b0, x_max, 5'b0, y_max}; //Bottom right coordinate
		// 	msg_buf_wr = 1'b1;
		// end
		// 5: begin
		// 	msg_buf_in = {5'b0, x_max, 5'b0, y_max}; //Bottom right coordinate
		// 	msg_buf_wr = 1'b1;
		// end
	endcase
end

// COLOR_DETECT COLOR_DETECT_module(
// 	  .rgb_r(red),
//   .rgb_g(green),
//   .rgb_b(blue),
// 	.color(detected_color),
// )

RGB2HSV RGB2HSV_module(
  .rgb_r(red),
  .rgb_g(green),
  .rgb_b(blue),
  .hsv_h(h),
  .hsv_s(s),
  .hsv_v(v));


//Output message FIFO
MSG_FIFO	MSG_FIFO_inst (
	.clock (clk),
	.data (msg_buf_in),
	.rdreq (msg_buf_rd),
	.sclr (~reset_n | msg_buf_flush),
	.wrreq (msg_buf_wr),
	.q (msg_buf_out),
	.usedw (msg_buf_size),
	.empty (msg_buf_empty)
	);


//Streaming registers to buffer video signal
STREAM_REG #(.DATA_WIDTH(26)) in_reg (
	.clk(clk),
	.rst_n(reset_n),
	.ready_out(sink_ready),
	.valid_out(in_valid),
	.data_out({red,green,blue,sop,eop}),
	.ready_in(out_ready),
	.valid_in(sink_valid),
	.data_in({sink_data,sink_sop,sink_eop})
);

STREAM_REG #(.DATA_WIDTH(26)) out_reg (
	.clk(clk),
	.rst_n(reset_n),
	.ready_out(out_ready),
	.valid_out(source_valid),
	.data_out({source_data,source_sop,source_eop}),
	.ready_in(source_ready),
	.valid_in(in_valid),
	.data_in({red_out, green_out, blue_out, sop, eop})
);


/////////////////////////////////
/// Memory-mapped port		 /////
/////////////////////////////////

// Addresses
`define REG_STATUS    			0
`define READ_MSG    				1
`define READ_ID    				2
`define REG_BBCOL					3

//Status register bits
// 31:16 - unimplemented
// 15:8 - number of words in message buffer (read only)
// 7:5 - unused
// 4 - flush message buffer (write only - read as 0)
// 3:0 - unused


// Process write

reg  [7:0]   reg_status;
reg	[23:0]	bb_col,center_col;

always @ (posedge clk)
begin
	if (~reset_n)
	begin
		reg_status <= 8'b0;
		bb_col <= BB_COL_DEFAULT;
		center_col<=CENTER_COL_DEFAULT;
	end
	else begin
		if(s_chipselect & s_write) begin
		   if      (s_address == `REG_STATUS)	reg_status <= s_writedata[7:0];
		   if      (s_address == `REG_BBCOL)	bb_col <= s_writedata[23:0];
		end
	end
end


//Flush the message buffer if 1 is written to status register bit 4
assign msg_buf_flush = (s_chipselect & s_write & (s_address == `REG_STATUS) & s_writedata[4]);


// Process reads
reg read_d; //Store the read signal for correct updating of the message buffer

// Copy the requested word to the output port when there is a read.
always @ (posedge clk)
begin
   if (~reset_n) begin
	   s_readdata <= {32'b0};
		read_d <= 1'b0;
	end
	
	else if (s_chipselect & s_read) begin
		if   (s_address == `REG_STATUS) s_readdata <= {16'b0,msg_buf_size,reg_status};
		if   (s_address == `READ_MSG) s_readdata <= {msg_buf_out};
		if   (s_address == `READ_ID) s_readdata <= 32'h1234EEE2;
		if   (s_address == `REG_BBCOL) s_readdata <= {8'h0, bb_col};
	end
	
	read_d <= s_read;
end

//Fetch next word from message buffer after read from READ_MSG
assign msg_buf_rd = s_chipselect & s_read & ~read_d & ~msg_buf_empty & (s_address == `READ_MSG);
						


endmodule

