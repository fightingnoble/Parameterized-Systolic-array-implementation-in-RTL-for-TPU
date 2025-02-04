`timescale 1ns/100ps

`include "param.v"
module test_tpu;

	localparam BATCH_SIZE = 3;
    localparam ARRAY_SIZE = 8;
	localparam SRAM_ADDR_WIDTH = 10;
	localparam ADDR_WIDTH_MIN = $clog2(BATCH_SIZE*ARRAY_SIZE+3-1); //7;
	localparam SRAM_DEPTH = 2**ADDR_WIDTH_MIN; //2**7
	
    localparam DATA_WIDTH = 8; 
    localparam OUT_DATA_WIDTH = 16;
    localparam SRAM_DATA_WIDTH = 32;
    localparam WEIGHT_NUM = 25, WEIGHT_WIDTH = 8;
	localparam QUEUE_SIZE = SRAM_DATA_WIDTH / DATA_WIDTH; // 4
    localparam QUEUE_COUNT = (ARRAY_SIZE + QUEUE_SIZE-1) / QUEUE_SIZE;
	localparam CYCLE_MAX = 2*(ARRAY_SIZE)*BATCH_SIZE + ARRAY_SIZE + 1;
	localparam CYCLE_BITS = $clog2(CYCLE_MAX); //9;
	localparam MATRIX_BITS = $clog2(2*ARRAY_SIZE-1); //6;

    //====== module I/O =====
    reg clk;
    reg srstn;
    reg tpu_start;

    wire tpu_finish;

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


//dump wave file
// initial begin
//   $fsdbDumpfile("tpu.fsdb"); // "gray.fsdb" can be replaced into any name you want
//   $fsdbDumpvars("+mda");              // but make sure in .fsdb format
// end

//====== clock generation =====
initial begin
    srstn = 1'b1;
    clk = 1'b1;
    #(`cycle_period/2);
    while(1) begin
      #(`cycle_period/2) clk = ~clk; 
    end
end

//====== main procedural block for simulation =====
integer cycle_cnt;


integer i,j,k;
integer type_idx_verify;

reg [ARRAY_SIZE*DATA_WIDTH-1:0] mat1[0:ARRAY_SIZE*BATCH_SIZE-1];
reg [ARRAY_SIZE*DATA_WIDTH-1:0] mat2[0:ARRAY_SIZE*BATCH_SIZE-1];
reg [ARRAY_SIZE*BATCH_SIZE*DATA_WIDTH-1:0] tmp_c_mat1[0:ARRAY_SIZE-1];
reg [ARRAY_SIZE*BATCH_SIZE*DATA_WIDTH-1:0] tmp_c_mat2[0:ARRAY_SIZE-1];
reg [(ARRAY_SIZE*BATCH_SIZE+QUEUE_SIZE-1)*DATA_WIDTH-1:0] tmp_mat1[0:ARRAY_SIZE-1];
reg [(ARRAY_SIZE*BATCH_SIZE+QUEUE_SIZE-1)*DATA_WIDTH-1:0] tmp_mat2[0:ARRAY_SIZE-1];

reg [ARRAY_SIZE*OUT_DATA_WIDTH-1:0] golden_t[0:ARRAY_SIZE-1];
reg [ARRAY_SIZE*OUT_DATA_WIDTH-1:0] golden[0:BATCH_SIZE*ARRAY_SIZE-1];
reg [ARRAY_SIZE*OUT_DATA_WIDTH-1:0] trans_golden[0:BATCH_SIZE*(ARRAY_SIZE*2-1)-1];
reg [SRAM_DATA_WIDTH-1:0] sram_data;
reg [SRAM_DATA_WIDTH-1:0] sram_weight;


/*
initial begin
	#(`End_CYCLE);
	$display("-----------------------------------------------------\n");
	$display("Error!!! There is something wrong with your code ...!\n");
 	$display("------The test result is .....FAIL ------------------\n");
 	$display("-----------------------------------------------------\n");
 	$finish;
end
*/
initial begin
    $readmemb("bm/bm1/mat1.txt", mat1);
    $readmemb("bm/bm1/mat2.txt", mat2);

	// load golden data from goldeni.txt, 
    for (i = 0; i < BATCH_SIZE; i = i + 1) begin
        // 动态生成文件路径
        string file_path;
        $sformat(file_path, "bm/bm1/golden%0d.txt", i + 1);

        // 读取文件数据到 golden_t
        $readmemb(file_path, golden_t);

        // 将 golden_t 的数据复制到 golden 数组中
        for (integer j = 0; j < ARRAY_SIZE; j = j + 1) begin
            golden[i * ARRAY_SIZE + j] = golden_t[j];
        end
    end
    // $readmemb("bm/bm1/golden1.txt",golden1);
    // $readmemb("bm/bm1/golden2.txt",golden2);
    // $readmemb("bm/bm1/golden3.txt",golden3);

    #(`cycle_period);
    
	data2sram;
        $write("|\n");
        $write("Three input groups of matrix\n");
        $write("|\n");
        display_data;  

	golden_transform;

        /////////////////////////////////////////////////////////
        
        tpu_start = 1'b0;

        /////////////////////////////////////////////////////////

        
        //start to do CONV2 and POOL2, and write your result into sram a0 

        cycle_cnt = 0;
        @(negedge clk);
        srstn = 1'b0;
        @(negedge clk);
        srstn = 1'b1;
        tpu_start = 1'b1;  //one-cycle pulse signal  
        @(negedge clk);
        tpu_start = 1'b0;
        while(~tpu_finish)begin    //it's mean that your sram c0, c1, c2 can be tested
            @(negedge clk);     begin
                cycle_cnt = cycle_cnt + 1;
            end
        end

		$display("Verifying output data for #c%0d", 0);
		$display("-");
		for (i = 0; i < (ARRAY_SIZE*2 - 1); i = i + 1) begin
			if (trans_golden[i+0*(ARRAY_SIZE*2-1)] == output_sram_gen[0].sram_16x128b_c.mem[i]) begin
				$write("sram #c%0d address: %0d PASS!!\n", 0, i[MATRIX_BITS-1:0]);
			end else begin
				print_error_info(i[MATRIX_BITS-1:0], output_sram_gen[0].sram_16x128b_c.mem[i], trans_golden[i+0*(ARRAY_SIZE*2-1)]);
				$finish;
			end
		end

		$display("Verifying output data for #c%0d", 1);
		$display("-");
		for (i = 0; i < (ARRAY_SIZE*2 - 1); i = i + 1) begin
			if (trans_golden[i+1*(ARRAY_SIZE*2-1)] == output_sram_gen[1].sram_16x128b_c.mem[i]) begin
				$write("sram #c%0d address: %0d PASS!!\n", 1, i[MATRIX_BITS-1:0]);
			end else begin
				print_error_info(i[MATRIX_BITS-1:0], output_sram_gen[1].sram_16x128b_c.mem[i], trans_golden[i+1*(ARRAY_SIZE*2-1)]);
				$finish;
			end
		end

		$display("Verifying output data for #c%0d", 2);
		$display("-");
		for (i = 0; i < (ARRAY_SIZE*2 - 1); i = i + 1) begin
			if (trans_golden[i+2*(ARRAY_SIZE*2-1)] == output_sram_gen[2].sram_16x128b_c.mem[i]) begin
				$write("sram #c%0d address: %0d PASS!!\n", 2, i[MATRIX_BITS-1:0]);
			end else begin
				print_error_info(i[MATRIX_BITS-1:0], output_sram_gen[2].sram_16x128b_c.mem[i], trans_golden[i+2*(ARRAY_SIZE*2-1)]);
				$finish;
			end
		end

    $display("Total cycle count C after three matrix evaluation = %0d.", cycle_cnt);
    #5 $finish;
end


task print_error_info;
    input [MATRIX_BITS-1:0] addr;
    input [ARRAY_SIZE*OUT_DATA_WIDTH-1:0] your_answer;
    input [ARRAY_SIZE*OUT_DATA_WIDTH-1:0] golden_answer;
    integer k;
begin
    $write("You have wrong answer in the sram #c0 !!!\n\n");
    $write("Your answer at address %0d is \n", addr);
    for (k = ARRAY_SIZE - 1; k >= 0; k = k - 1) begin
        $write("%0d ", $signed(your_answer[(k*OUT_DATA_WIDTH) +: OUT_DATA_WIDTH]));
    end
    $write("\n");
    $write("But the golden answer is  \n");
    for (k = ARRAY_SIZE - 1; k >= 0; k = k - 1) begin
        $write("%0d ", $signed(golden_answer[(k*OUT_DATA_WIDTH) +: OUT_DATA_WIDTH]));
    end
    $write("\n");
end
endtask

task data2sram;
  begin
	// reset tmp_mat1, tmp_mat2, tmp_c_mat1, tmp_c_mat2
	for(i = 0; i< ARRAY_SIZE ; i = i + 1) begin
		tmp_c_mat1[i] = 0;
		tmp_c_mat2[i] = 0;
		tmp_mat1[i] = 0;
		tmp_mat2[i] = 0;
	end	
	// combine three batch together into tmp_mat1, tmp_mat2
	// reshape mat1/2 from [BATCH_SIZE*array_size, array_size*data_width] to [array_size, BATCH_SIZE*array_size*data_width]
	for(i = 0; i< BATCH_SIZE ; i = i + 1) begin
		for(j = 0; j< ARRAY_SIZE; j = j+1)begin
			tmp_c_mat1[j] = {mat1[ARRAY_SIZE*i+j], tmp_c_mat1[j][(ARRAY_SIZE*BATCH_SIZE*DATA_WIDTH-1) -: 2*DATA_WIDTH*ARRAY_SIZE]};
			tmp_c_mat2[j] = {mat2[ARRAY_SIZE*i+j], tmp_c_mat2[j][(ARRAY_SIZE*BATCH_SIZE*DATA_WIDTH-1) -: 2*DATA_WIDTH*ARRAY_SIZE]};
		end
	end
	// [array_size, BATCH_SIZE*array_size*data_width] -> [array_size, (BATCH_SIZE*array_size+3)*data_width]
	// generate offset step 1: wihtin each queue, every rows, shift 1 items to the right
	for(i = 0; i< ARRAY_SIZE ; i = i + 1) begin
		case (i % 4)
			0 : begin
				tmp_mat1[i] = {24'b0, tmp_c_mat1[i]};
				tmp_mat2[i] = {24'b0, tmp_c_mat2[i]};
			    end
			1 : begin
				tmp_mat1[i] = {16'b0, tmp_c_mat1[i], 8'b0};
				tmp_mat2[i] = {16'b0, tmp_c_mat2[i], 8'b0};
			    end
			2 : begin
				tmp_mat1[i] = {8'b0, tmp_c_mat1[i], 16'b0};
				tmp_mat2[i] = {8'b0, tmp_c_mat2[i], 16'b0};
			    end
			3 : begin
				tmp_mat1[i] = {tmp_c_mat1[i], 24'b0};
				tmp_mat2[i] = {tmp_c_mat2[i], 24'b0};
			    end
			default : begin
					tmp_mat1[i] = 0;
					tmp_mat2[i] = 0;
				  end
		endcase
	end
	
	sram_load[0].load_sram_j;
	sram_load[1].load_sram_j;

	weight_display[0].display_weight_j;
	weight_display[1].display_weight_j;

	data_display[0].display_data_j;
	data_display[1].display_data_j;

  end
endtask	

generate
	// reg [(ARRAY_SIZE*BATCH_SIZE+3)*DATA_WIDTH-1:0] tmp_mat1[0:ARRAY_SIZE-1];
	// [array_size, (BATCH_SIZE*array_size+3)*data_width] -> array_size/4, (BATCH_SIZE*array_size+3), 4*data_width]
    for (unpk_idx = 0; unpk_idx < QUEUE_COUNT; unpk_idx = unpk_idx + 1) begin: sram_load
        task automatic load_sram_j;
            integer i, k;
            begin
                for (i = 0; i < SRAM_DEPTH; i = i + 1) begin
                    if (i < (ARRAY_SIZE * BATCH_SIZE + 3)) begin
                        for (k = 0; k < QUEUE_SIZE; k = k + 1) begin
                            sram_weight[(QUEUE_SIZE-1 - k) * WEIGHT_WIDTH +: WEIGHT_WIDTH] = tmp_mat1[unpk_idx * QUEUE_SIZE + k][(WEIGHT_WIDTH * (i + 1) - 1) -: WEIGHT_WIDTH];
                            sram_data[(QUEUE_SIZE-1 - k) * DATA_WIDTH +: DATA_WIDTH] = tmp_mat2[unpk_idx * QUEUE_SIZE + k][(DATA_WIDTH * (i + 1) - 1) -: DATA_WIDTH];
                        end
                    end else begin
                        sram_data = {SRAM_ADDR_WIDTH{1'b0}};
                        sram_weight = {SRAM_ADDR_WIDTH{1'b0}};
                    end

                    weight_sram_gen[unpk_idx].char2sram(i, sram_weight);
                    input_sram_gen[unpk_idx].char2sram(i, sram_data);
                end
            end
        endtask
    end
endgenerate

generate
	for (unpk_idx=0; unpk_idx<QUEUE_COUNT; unpk_idx=unpk_idx+1) begin: weight_display
		task automatic display_weight_j;
		$write("SRAM a%0d!!!!\n", unpk_idx);
		for(i = 0; i < SRAM_DEPTH; i=i+1)begin
			$write("SRAM at address %0d is \n", i);
			for (k=0; k<QUEUE_SIZE; k=k+1) begin
				$write("%0d ", $signed(weight_sram_gen[unpk_idx].mem[i][(QUEUE_SIZE-1-k)*WEIGHT_WIDTH +: WEIGHT_WIDTH]));
			end
			$write("\n");
		end
		endtask
	end
endgenerate

generate
	for (unpk_idx=0; unpk_idx<QUEUE_COUNT; unpk_idx=unpk_idx+1) begin: data_display
		task automatic display_data_j;
		$write("SRAM b%0d!!!!\n", unpk_idx);
		for(i = 0; i < SRAM_DEPTH; i=i+1)begin
			$write("SRAM at address %0d is \n", i);
			for (k=0; k<QUEUE_SIZE; k=k+1) begin
				$write("%0d ", $signed(input_sram_gen[unpk_idx].mem[i][(QUEUE_SIZE-1-k)*DATA_WIDTH +: DATA_WIDTH]));
			end
			$write("\n");
		end
		endtask
	end
endgenerate


//display the mnist image in 28x28 SRAM
task display_data;
integer this_i, this_j, this_k;
    begin
	// reg [ARRAY_SIZE*DATA_WIDTH-1:0] mat1[0:ARRAY_SIZE*BATCH_SIZE-1];
	// reg [ARRAY_SIZE*DATA_WIDTH-1:0] mat2[0:ARRAY_SIZE*BATCH_SIZE-1];
	for(this_k=0; this_k<BATCH_SIZE;this_k = this_k +1)begin
		$write("------------------------\n");
        	for(this_i=0;this_i<ARRAY_SIZE;this_i=this_i+1) begin
				for(this_j=0;this_j<ARRAY_SIZE;this_j=this_j+1) begin
					$write("%0d",$signed(mat1[this_k*ARRAY_SIZE+this_i][this_j*DATA_WIDTH+:DATA_WIDTH]));
					$write(" ");
				end
				$write("\n");
        	end
		$write("\n");
        	for(this_i=0;this_i<ARRAY_SIZE;this_i=this_i+1) begin
				for(this_j=0;this_j<ARRAY_SIZE;this_j=this_j+1) begin
					$write("%0d",$signed(mat2[this_k*ARRAY_SIZE+this_i][this_j*DATA_WIDTH+:DATA_WIDTH]));
					$write(" ");
				end
				$write("\n");
        	end
		$write("\n");
        	for(this_i=0;this_i<ARRAY_SIZE;this_i=this_i+1) begin
				for(this_j=0;this_j<ARRAY_SIZE;this_j=this_j+1) begin
					$write("%0d",$signed(golden[this_k*ARRAY_SIZE+this_i][this_j*OUT_DATA_WIDTH+:OUT_DATA_WIDTH]));
					$write(" ");
				end
				$write("\n");
        	end
		$write("------------------------\n");
		$write("\n");
	end
    end
endtask

task golden_transform;
integer this_i, this_j, this_k, batch_idx;
begin
	// init trans_golden
	for (batch_idx = 0; batch_idx < BATCH_SIZE; batch_idx = batch_idx + 1) begin
		for (this_k = 0; this_k < (ARRAY_SIZE*2 - 1); this_k = this_k + 1) begin
			trans_golden[batch_idx*(ARRAY_SIZE*2 - 1) + this_k] = 0;
		end
	end
	
	// fill trans_golden
	// reg [ARRAY_SIZE*OUT_DATA_WIDTH-1:0] trans_golden[0:BATCH_SIZE*(ARRAY_SIZE*2-1)-1];
	// reg [ARRAY_SIZE*OUT_DATA_WIDTH-1:0] golden1[0:ARRAY_SIZE-1];
	for(this_k=0; this_k<(ARRAY_SIZE*2-1);this_k = this_k +1)begin	  
		for(this_i=0;this_i<ARRAY_SIZE;this_i=this_i+1) begin // row
			for(this_j=0;this_j<ARRAY_SIZE;this_j=this_j+1) begin // col
				if((this_i+this_j)==this_k)begin
					for (batch_idx = 0; batch_idx < BATCH_SIZE; batch_idx = batch_idx + 1) begin
						trans_golden[batch_idx*(ARRAY_SIZE*2 - 1) + this_k] = {golden[batch_idx*ARRAY_SIZE+this_i][((this_j+1)*OUT_DATA_WIDTH-1) -: OUT_DATA_WIDTH], trans_golden[batch_idx*(ARRAY_SIZE*2 - 1) + this_k][(ARRAY_SIZE*OUT_DATA_WIDTH-1)-:((ARRAY_SIZE-1)*OUT_DATA_WIDTH)]};
					end 
				end
			end
		end
	end

	// print trans_golden
	for (batch_idx = 0; batch_idx < BATCH_SIZE; batch_idx = batch_idx + 1) begin
		$write("Here shows the trans_golden%0d!!!\n", batch_idx + 1);
		for (this_k = 0; this_k < (ARRAY_SIZE*2 - 1); this_k = this_k + 1) begin
			for (this_i = ARRAY_SIZE; this_i > 0; this_i = this_i - 1) begin
				$write("%8d ", $signed(trans_golden[batch_idx*(ARRAY_SIZE*2 - 1) + this_k][(this_i*OUT_DATA_WIDTH - 1) -: OUT_DATA_WIDTH]));
			end
			$write("\n\n");
		end
	end

end
endtask 

endmodule
