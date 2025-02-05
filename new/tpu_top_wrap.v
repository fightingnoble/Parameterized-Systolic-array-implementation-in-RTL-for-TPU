module tpu_top_wrap #(
    parameter ARRAY_SIZE = 8,
    parameter SRAM_DATA_WIDTH = 32,
    parameter SRAM_ADDR_WIDTH = 10,
    parameter BATCH_SIZE = 3,
    parameter DATA_WIDTH = 8,
    parameter WEIGHT_WIDTH = 8,
    parameter OUT_DATA_WIDTH = 16
    )(
    input clk,
    input srstn,
    input tpu_start,
    output tpu_finish
);

	localparam ADDR_WIDTH_MIN = $clog2(BATCH_SIZE*ARRAY_SIZE+3-1); //7;
	localparam SRAM_DEPTH = 2**ADDR_WIDTH_MIN; //2**7
	localparam QUEUE_SIZE = SRAM_DATA_WIDTH / DATA_WIDTH; // 4
    localparam QUEUE_COUNT = (ARRAY_SIZE + QUEUE_SIZE-1) / QUEUE_SIZE;
	localparam CYCLE_MAX = 2*(ARRAY_SIZE)*BATCH_SIZE + ARRAY_SIZE + 1;
	localparam CYCLE_BITS = $clog2(CYCLE_MAX); //9;
	localparam MATRIX_BITS = $clog2(2*ARRAY_SIZE-1); //6;

	// unused signals
	wire [3:0] sram_bytemask_a;
	wire [3:0] sram_bytemask_b;
	wire [SRAM_ADDR_WIDTH-1:0] sram_waddr_a;
	wire [SRAM_ADDR_WIDTH-1:0] sram_waddr_b;
	wire [SRAM_DATA_WIDTH-1:0] sram_wdata_a;
	wire [SRAM_DATA_WIDTH-1:0] sram_wdata_b;

	wire [MATRIX_BITS-1:0] sram_raddr_c [0:2];
	wire [ARRAY_SIZE*OUT_DATA_WIDTH-1:0] sram_rdata_c [0:2];
	// ===================================
    wire [ARRAY_SIZE*OUT_DATA_WIDTH-1:0] sram_wdata_c [0:2];
    wire [MATRIX_BITS-1:0] sram_waddr_c [0:2];
    wire sram_write_enable_c [0:2];

    wire [(QUEUE_COUNT * SRAM_DATA_WIDTH) - 1:0] sram_rdata_w_packed;
    wire [(QUEUE_COUNT * SRAM_DATA_WIDTH) - 1:0] sram_rdata_d_packed;
    wire [(QUEUE_COUNT * SRAM_ADDR_WIDTH) - 1:0] sram_raddr_w_packed;
    wire [(QUEUE_COUNT * SRAM_ADDR_WIDTH) - 1:0] sram_raddr_d_packed;

    wire signed [DATA_WIDTH-1:0] out;

    //====== top connection =====

    // tpu_top instance
    tpu_top #(
       .ARRAY_SIZE(ARRAY_SIZE),
       .SRAM_DATA_WIDTH(SRAM_DATA_WIDTH),
       .DATA_WIDTH(DATA_WIDTH),
       .OUTPUT_DATA_WIDTH(OUT_DATA_WIDTH),
       .QUEUE_COUNT(QUEUE_COUNT),
	   .ADDR_MAX(SRAM_DEPTH-1),
	   .QUEUE_SIZE(QUEUE_SIZE),
	   .SRAM_ADDR_WIDTH(SRAM_ADDR_WIDTH),
	   .CYCLE_BITS(CYCLE_BITS),
	   .MATRIX_BITS(MATRIX_BITS),
	   .ADDR_WIDTH_MIN(ADDR_WIDTH_MIN)
    ) my_tpu_top (
       .clk(clk),
       .srstn(srstn),
       .tpu_start(tpu_start),

		//input data
       .sram_rdata_w_packed(sram_rdata_w_packed),

       .sram_rdata_d_packed(sram_rdata_d_packed),

		//output weight
       .sram_raddr_w_packed(sram_raddr_w_packed),

       .sram_raddr_d_packed(sram_raddr_d_packed),

	//write to the SRAM for comparision
       .sram_write_enable_a0(sram_write_enable_c[0]),
       .sram_wdata_a(sram_wdata_c[0]),
       .sram_waddr_a(sram_waddr_c[0]),

       .sram_write_enable_b0(sram_write_enable_c[1]),
       .sram_wdata_b(sram_wdata_c[1]),
       .sram_waddr_b(sram_waddr_c[1]),

       .sram_write_enable_c0(sram_write_enable_c[2]),
       .sram_wdata_c(sram_wdata_c[2]),
       .sram_waddr_c(sram_waddr_c[2]),

       .tpu_done(tpu_finish)
    );

	genvar unpk_idx;
    // Generate SRAM instances for weight data	sram_128x32b
	simple_sram #(
		.DATA_WIDTH(SRAM_DATA_WIDTH),
		.ADDR_WIDTH(SRAM_ADDR_WIDTH),
		.DEPTH(SRAM_DEPTH)
		) weight_sram_gen[QUEUE_COUNT-1:0] (
		.clk(clk),
		// .bytemask(sram_bytemask_a),
		.csb(1'b0),
		.wsb(1'b1), // Assume not writing for simplicity, adjust as needed
		.raddr(sram_raddr_w_packed), 
		.rdata(sram_rdata_w_packed),
		.waddr(sram_waddr_a), 
		.wdata(sram_wdata_a)
		);


	// Generate SRAM instances for input data sram_128x32b
	simple_sram #(
		.DATA_WIDTH(SRAM_DATA_WIDTH),
		.ADDR_WIDTH(SRAM_ADDR_WIDTH),
		.DEPTH(SRAM_DEPTH)
	) input_sram_gen[QUEUE_COUNT-1:0] (
		.clk(clk),
		// .bytemask(sram_bytemask_b),
		.csb(1'b0),
		.wsb(1'b1), // Assume not writing for simplicity, adjust as needed
		.raddr(sram_raddr_d_packed), 
		.rdata(sram_rdata_d_packed), 
		.waddr(sram_waddr_b), 
		.wdata(sram_wdata_b) 
		);

	// Generate SRAM instances for output data sram_16x128b
    generate
		genvar batch_idx;
        for (batch_idx = 0; batch_idx < BATCH_SIZE; batch_idx = batch_idx + 1) begin: output_sram_gen
			simple_sram #(
				.DATA_WIDTH(ARRAY_SIZE*OUT_DATA_WIDTH),
				.ADDR_WIDTH(MATRIX_BITS),
				.DEPTH(ARRAY_SIZE*2) // original 16
			) sram_16x128b_c (
				.clk(clk),
				.csb(1'b0),
				.wsb(sram_write_enable_c[batch_idx]),
				.wdata(sram_wdata_c[batch_idx]), 
				.waddr(sram_waddr_c[batch_idx]), 
				.raddr(sram_raddr_c[batch_idx]), 
				.rdata(sram_rdata_c[batch_idx])
			);
        end
    endgenerate

endmodule