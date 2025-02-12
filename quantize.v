//-------ori data is from systolic array, output to quantized data-------

module quantize#(
	parameter ARRAY_SIZE = 8,
	parameter SRAM_DATA_WIDTH = 32,
	parameter DATA_WIDTH = 8,
	parameter OUTPUT_DATA_WIDTH = 16,
	parameter CUM_BITS_EXT = 5, // $clog2(ARRAY_SIZE),
    parameter ORI_WIDTH = DATA_WIDTH+DATA_WIDTH+CUM_BITS_EXT 
)
(
	input signed [ARRAY_SIZE*(ORI_WIDTH)-1:0] ori_data,
	output reg signed [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] quantized_data
);

localparam max_val = 2**(OUTPUT_DATA_WIDTH-1)-1,min_val = -2**(OUTPUT_DATA_WIDTH-1);

reg signed [ORI_WIDTH-1:0] ori_shifted_data;

integer i;

//quantize the data from 32 bit(16: integer, 8: precision) to 16 bit(8: integer, 8: precision)
always@* begin
	for(i=0; i<ARRAY_SIZE; i=i+1) begin	
		ori_shifted_data = ori_data[i*ORI_WIDTH +: ORI_WIDTH];
		if(ori_shifted_data >= max_val) quantized_data[i*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH] = max_val;
		else if(ori_shifted_data <= min_val) quantized_data[i*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH] = min_val;
		else quantized_data[i*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH] = ori_shifted_data[OUTPUT_DATA_WIDTH-1:0];
	end
end

endmodule

