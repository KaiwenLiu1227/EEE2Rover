module FPGA_UART (
	input clk,
	input rst_n,
	input uart_rx,
	output uart_tx
);

reg [7:0] uart_send_data = 8'd0;
reg uart_send_valid;
wire uart_send_ready;

reg [31:0] counter = 32'd0;

parameter state_wait = 4'd0;
parameter state_send = 4'd1;
reg [3:0] state = state_wait;

reg send_flag = 0;

always@(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		uart_send_valid <= 0;
		counter <= 32'd0;
		uart_send_data <= 8'd0;
		state <= state_wait;
		send_flag = 0;
	end
	else begin
		case (state)
			state_wait: begin
				counter <= counter + 32'd1;
				if(counter >= 32'd49999999) begin
					counter <= 32'd0;
					state <= state_send;
				end
			end
			state_send: begin
				if(uart_send_ready && !send_flag) begin
					send_flag <= 1;
					uart_send_valid <= 1;
				end
				else begin
					uart_send_data <= uart_send_data + 8'd1;
					uart_send_valid <= 0;
					state <= state_wait;
					send_flag <= 0;
				end
			end
		endcase
	end
end



endmodule

