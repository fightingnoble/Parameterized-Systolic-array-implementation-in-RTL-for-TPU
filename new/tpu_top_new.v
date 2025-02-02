module tpu_top#(
    parameter ARRAY_SIZE = 8,
    parameter SRAM_DATA_WIDTH = 32,
    parameter DATA_WIDTH = 8,
    parameter OUTPUT_DATA_WIDTH = 16,
    parameter QUEUE_COUNT = (ARRAY_SIZE + 3) / 4  // 计算所需队列数量
)
(
    input clk,
    input srstn,
    input tpu_start,

    // Packed input data for (data, weight) from SRAM
    input [(SRAM_DATA_WIDTH * QUEUE_COUNT) - 1:0] sram_rdata_w_packed,
    input [(SRAM_DATA_WIDTH * QUEUE_COUNT) - 1:0] sram_rdata_d_packed,

    // Packed output addr for (data, weight) from SRAM
    output [(QUEUE_COUNT * 10) - 1:0] sram_raddr_w_packed,
    output [(QUEUE_COUNT * 10) - 1:0] sram_raddr_d_packed,
    
    // Write to three SRAM for comparison
    output sram_write_enable_a0,
    output [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] sram_wdata_a,
    output [5:0] sram_waddr_a,

    output sram_write_enable_b0,
    output [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] sram_wdata_b,
    output [5:0] sram_waddr_b,

    output sram_write_enable_c0,
    output [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] sram_wdata_c,
    output [5:0] sram_waddr_c,
    
    output tpu_done
);

localparam ORI_WIDTH = DATA_WIDTH+DATA_WIDTH+5;

//----addr_sel parameter----
wire [6:0] addr_serial_num;

//----quantized parameter----
wire signed [ARRAY_SIZE*ORI_WIDTH-1:0] ori_data;
wire signed [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] quantized_data;

//-----systolic parameter----
wire alu_start;
wire [8:0] cycle_num;
wire [5:0] matrix_index;

//----ststolic_controll parameter---
wire sram_write_enable;
wire [1:0] data_set;

//----write_out parameter----
// nothing XD



//----addr_sel module----
addr_sel #(
    .ARRAY_SIZE(ARRAY_SIZE),
    .QUEUE_COUNT(QUEUE_COUNT)
) addr_sel_inst 
(
    //input
    .clk(clk),
    .addr_serial_num(addr_serial_num),

    //output
    .sram_raddr_w_packed(sram_raddr_w_packed),
    .sram_raddr_d_packed(sram_raddr_d_packed)
);

//----quantize module----
quantize #(
    .ARRAY_SIZE(ARRAY_SIZE),
    .SRAM_DATA_WIDTH(SRAM_DATA_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .OUTPUT_DATA_WIDTH(OUTPUT_DATA_WIDTH)
) quantize_inst
(
    //input
    .ori_data(ori_data),

    //output
    .quantized_data(quantized_data)	
);

//----systolic module----
systolic #(
    .ARRAY_SIZE(ARRAY_SIZE),
    .SRAM_DATA_WIDTH(SRAM_DATA_WIDTH),
    .DATA_WIDTH(DATA_WIDTH)
) systolic_inst
(
    //input
    .clk(clk),
    .srstn(srstn),
    .alu_start(alu_start),
    .cycle_num(cycle_num),

    .sram_rdata_w_packed(sram_rdata_w_packed),
    .sram_rdata_d_packed(sram_rdata_d_packed),

    .matrix_index(matrix_index),
    
    //output
    .mul_outcome(ori_data)
);

//----systolic_controller module----
systolic_controll  #(
	.ARRAY_SIZE(ARRAY_SIZE)
) systolic_controll
(
	//input
	.clk(clk),
	.srstn(srstn),
	.tpu_start(tpu_start),

	//output
	.sram_write_enable(sram_write_enable),
	.addr_serial_num(addr_serial_num),
	.alu_start(alu_start),
	.cycle_num(cycle_num),
	.matrix_index(matrix_index),
	.data_set(data_set),
	.tpu_done(tpu_done)
);

//----write_out module----
write_out #(
	.ARRAY_SIZE(ARRAY_SIZE),
	.OUTPUT_DATA_WIDTH(OUTPUT_DATA_WIDTH)
) write_out
(
	//input
	.clk(clk), 
	.srstn(srstn),
	.sram_write_enable(sram_write_enable),
	.data_set(data_set),
	.matrix_index(matrix_index),
	.quantized_data(quantized_data),

	//output
	.sram_write_enable_a0(sram_write_enable_a0),
	.sram_wdata_a(sram_wdata_a),
	.sram_waddr_a(sram_waddr_a),

	.sram_write_enable_b0(sram_write_enable_b0),
	.sram_wdata_b(sram_wdata_b),
	.sram_waddr_b(sram_waddr_b),

	.sram_write_enable_c0(sram_write_enable_c0),
	.sram_wdata_c(sram_wdata_c),
	.sram_waddr_c(sram_waddr_c)
);

endmodule

