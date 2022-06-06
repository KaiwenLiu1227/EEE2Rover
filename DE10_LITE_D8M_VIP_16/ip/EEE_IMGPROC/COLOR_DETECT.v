module  COLOR_DETECT(
	input	     [7:0]            rgb_r,
	input	     [7:0]            rgb_g,
	input	     [7:0]            rgb_b,	
	output [2:0] color
);

wire [8:0]h;
wire [7:0]s;
wire [7:0]v;
parameter BLACK = 3'b000;
parameter WHITE = 3'b111;
parameter RED = 3'b100;
parameter BLUE = 3'b001;
parameter YELLOW = 3'b110;
parameter PURPLE = 3'b101;

parameter HSV_V_MIN= 8'd80;

RGB2HSV RGB2HSV_module(
  .rgb_r(rgb_r),
  .rgb_g(rgb_g),
  .rgb_b(rgb_b),
  .hsv_h(h),
  .hsv_s(s),
  .hsv_v(v));
reg [2:0] _color;
assign color=_color;
always @ (*)
begin
  if ((h>=9'd200 & h<=9'd250)&s>=8'd43&v>=HSV_V_MIN) begin
    _color=BLUE;
  end
  else if ((h>=9'd0 & h<=9'd20)&s>=8'd43&v>=HSV_V_MIN) begin
    _color=RED;
  end
  else if ((h>=9'd46 & h<=9'd92)&s>=8'd43&v>=HSV_V_MIN) begin
    _color=YELLOW;
  end
  else if ((h>=9'd340 & h<=9'd360)&s>=8'd43&v>=HSV_V_MIN) begin
    _color=PURPLE;
  end
  else if (v>=8'd245) begin
    _color=WHITE;
  end
  else if (v<=8'd010) begin
    _color=BLACK;
  end

end


endmodule