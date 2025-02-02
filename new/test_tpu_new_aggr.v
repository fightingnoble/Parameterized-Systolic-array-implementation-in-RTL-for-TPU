`timescale 1ns/100ps

`include "param.v"
module test_tpu;

    localparam DATA_WIDTH = 8;
    localparam OUT_DATA_WIDTH = 16;
    localparam SRAM_DATA_WIDTH = 32;
    localparam WEIGHT_NUM = 25, WEIGHT_WIDTH = 8;
    localparam ARRAY_SIZE = 8;
    localparam QUEUE_COUNT = (ARRAY_SIZE + 3) / 4;
	localparam SRAM_DEPTH = 128;

    //====== module I/O =====
    reg clk;
    reg srstn;
    reg tpu_start;

    wire tpu_finish;

	// unused signals
    wire [3:0] sram_bytemask_a;
    wire [3:0] sram_bytemask_b;
    wire [9:0] sram_waddr_a;
    wire [9:0] sram_waddr_b;
    wire [7:0] sram_wdata_a;
    wire [7:0] sram_wdata_b;

	wire [5:0] sram_raddr_c [0:2];
	wire [DATA_WIDTH*OUT_DATA_WIDTH-1:0] sram_rdata_c [0:2];
	// ===================================
    wire [DATA_WIDTH*OUT_DATA_WIDTH-1:0] sram_wdata_c [0:2];
    wire [5:0] sram_waddr_c [0:2];
    wire sram_write_enable_c [0:2];

    wire [(SRAM_DATA_WIDTH * QUEUE_COUNT) - 1:0] sram_rdata_w_packed;
    wire [(SRAM_DATA_WIDTH * QUEUE_COUNT) - 1:0] sram_rdata_d_packed;
    wire [(QUEUE_COUNT * 10) - 1:0] sram_raddr_w_packed;
    wire [(QUEUE_COUNT * 10) - 1:0] sram_raddr_d_packed;

    wire signed [7:0] out;

    //====== top connection =====

    // tpu_top instance
    tpu_top #(
       .ARRAY_SIZE(ARRAY_SIZE),
       .SRAM_DATA_WIDTH(SRAM_DATA_WIDTH),
       .DATA_WIDTH(DATA_WIDTH),
       .OUTPUT_DATA_WIDTH(OUT_DATA_WIDTH),
       .QUEUE_COUNT(QUEUE_COUNT)
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
    // Generate SRAM instances for weight data
    generate
        for (unpk_idx = 0; unpk_idx < QUEUE_COUNT; unpk_idx = unpk_idx + 1) begin: weight_sram_gen
            sram_128x32b sram_128x32b_w (
               .clk(clk),
               .bytemask(sram_bytemask_a),
               .csb(1'b0),
               .wsb(1'b0), // Assume not writing for simplicity, adjust as needed
               .wdata(sram_wdata_a), 
               .waddr(sram_waddr_a), 
               .raddr(sram_raddr_w_packed[(unpk_idx * 10) +: 10]), 
               .rdata(sram_rdata_w_packed[(unpk_idx * SRAM_DATA_WIDTH) +: SRAM_DATA_WIDTH])
            );
        end
    endgenerate

	// Generate SRAM instances for input data
    generate
        for (unpk_idx = 0; unpk_idx < QUEUE_COUNT; unpk_idx = unpk_idx + 1) begin: input_sram_gen
            sram_128x32b sram_128x32b_d (
               .clk(clk),
               .bytemask(sram_bytemask_b),
               .csb(1'b0),
               .wsb(1'b0), // Assume not writing for simplicity, adjust as needed
               .wdata(sram_wdata_b), 
               .waddr(sram_waddr_b), 
               .raddr(sram_raddr_d_packed[(unpk_idx * 10) +: 10]), 
               .rdata(sram_rdata_d_packed[(unpk_idx * SRAM_DATA_WIDTH) +: SRAM_DATA_WIDTH])
            );
        end
    endgenerate

	// Generate SRAM instances for output data
    generate
		genvar type_idx;
        for (type_idx = 0; type_idx < 3; type_idx = type_idx + 1) begin: output_sram_gen
			sram_16x128b sram_16x128b_c (
				.clk(clk),
				.csb(1'b0),
				.wsb(sram_write_enable_c[type_idx]),
				.wdata(sram_wdata_c[type_idx]), 
				.waddr(sram_waddr_c[type_idx]), 
				.raddr(sram_raddr_c[type_idx]), 
				.rdata(sram_rdata_c[type_idx])
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

reg [ARRAY_SIZE*DATA_WIDTH-1:0] mat1[0:ARRAY_SIZE*3-1];
reg [ARRAY_SIZE*DATA_WIDTH-1:0] mat2[0:ARRAY_SIZE*3-1];
reg [ARRAY_SIZE*3*DATA_WIDTH-1:0] tmp_c_mat1[0:ARRAY_SIZE-1];
reg [ARRAY_SIZE*3*DATA_WIDTH-1:0] tmp_c_mat2[0:ARRAY_SIZE-1];
reg [(ARRAY_SIZE*3+3)*DATA_WIDTH-1:0] tmp_mat1[0:ARRAY_SIZE-1];
reg [(ARRAY_SIZE*3+3)*DATA_WIDTH-1:0] tmp_mat2[0:ARRAY_SIZE-1];

reg [ARRAY_SIZE*OUT_DATA_WIDTH-1:0] golden1[0:ARRAY_SIZE-1];
reg [ARRAY_SIZE*OUT_DATA_WIDTH-1:0] golden2[0:ARRAY_SIZE-1];
reg [ARRAY_SIZE*OUT_DATA_WIDTH-1:0] golden3[0:ARRAY_SIZE-1];

reg [ARRAY_SIZE*OUT_DATA_WIDTH-1:0] trans_golden[0:3*(ARRAY_SIZE*2-1)-1];
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
    $readmemb("data/mat1.txt", mat1);
    $readmemb("data/mat2.txt", mat2);
    $readmemb("golden/golden1.txt",golden1);
    $readmemb("golden/golden2.txt",golden2);
    $readmemb("golden/golden3.txt",golden3);

    #(`cycle_period);
    
	data2sram;
	golden_transform;
        $write("|\n");
        $write("Three input groups of matrix\n");
        $write("|\n");
        display_data;  

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

	// test our three sets of answer!!!
	// for (type_idx_verify = 0; type_idx_verify < 3; type_idx_verify = type_idx_verify + 1) begin
	// 	// 输出验证提示信息
	// 	$display("Verifying output data for #c%d", type_idx_verify);
	// 	$display("-");
	// 	for (i = 0; i < (ARRAY_SIZE*2 - 1); i = i + 1) begin
	// 		if (trans_golden[i+type_idx_verify*(ARRAY_SIZE*2-1)] == output_sram_gen[type_idx_verify].sram_16x128b_c.mem[i]) begin
	// 			$write("sram #c0 address: %d PASS!!\n", i[5:0]);
	// 		end else begin
	// 			// 调用任务输出错误信息
	// 			print_error_info(i[5:0], output_sram_gen[type_idx_verify].sram_16x128b_c.mem[i], trans_golden[i+type_idx_verify*(ARRAY_SIZE*2-1)]);
	// 			// $finish;
	// 		end
	// 	end
	// end

for (type_idx_verify = 0; type_idx_verify < 3; type_idx_verify = type_idx_verify + 1) begin
    // 输出验证提示信息
    $display("Verifying output data for #c%d", type_idx_verify);
    $display("-");
    for (i = 0; i < (ARRAY_SIZE * 2 - 1); i = i + 1) begin
        // 使用 case 语句替换动态索引
        case (type_idx_verify)
            0: begin
                if (trans_golden[i + type_idx_verify * (ARRAY_SIZE * 2 - 1)] == output_sram_gen[0].sram_16x128b_c.mem[i]) begin
                    $write("sram #c0 address: %d PASS!!\n", i[5:0]);
                end else begin
                    // 调用任务输出错误信息
                    print_error_info(i[5:0], output_sram_gen[0].sram_16x128b_c.mem[i], trans_golden[i + type_idx_verify * (ARRAY_SIZE * 2 - 1)]);
                    // $finish;
                end
            end
            1: begin
                if (trans_golden[i + type_idx_verify * (ARRAY_SIZE * 2 - 1)] == output_sram_gen[1].sram_16x128b_c.mem[i]) begin
                    $write("sram #c1 address: %d PASS!!\n", i[5:0]);
                end else begin
                    // 调用任务输出错误信息
                    print_error_info(i[5:0], output_sram_gen[1].sram_16x128b_c.mem[i], trans_golden[i + type_idx_verify * (ARRAY_SIZE * 2 - 1)]);
                    // $finish;
                end
            end
            2: begin
                if (trans_golden[i + type_idx_verify * (ARRAY_SIZE * 2 - 1)] == output_sram_gen[2].sram_16x128b_c.mem[i]) begin
                    $write("sram #c2 address: %d PASS!!\n", i[5:0]);
                end else begin
                    // 调用任务输出错误信息
                    print_error_info(i[5:0], output_sram_gen[2].sram_16x128b_c.mem[i], trans_golden[i + type_idx_verify * (ARRAY_SIZE * 2 - 1)]);
                    // $finish;
                end
            end
            default: begin
                $display("Error: Invalid type_idx_verify = %0d", type_idx_verify);
            end
        endcase
    end
end
    $display("Total cycle count C after three matrix evaluation = %d.", cycle_cnt);
    #5 $finish;
end


task print_error_info;
    input [5:0] addr;
    input [ARRAY_SIZE*16-1:0] your_answer;
    input [ARRAY_SIZE*16-1:0] golden_answer;
    integer k;
begin
    $write("You have wrong answer in the sram #c0 !!!\n\n");
    $write("Your answer at address %d is \n", addr);
    for (k = ARRAY_SIZE - 1; k >= 0; k = k - 1) begin
        $write("%d ", $signed(your_answer[(k*16 + 15) -: OUT_DATA_WIDTH]));
    end
    $write("\n");
    $write("But the golden answer is  \n");
    for (k = ARRAY_SIZE - 1; k >= 0; k = k - 1) begin
        $write("%d ", $signed(golden_answer[(k*16 + 15) -: OUT_DATA_WIDTH]));
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
	// reshape mat1/2 from [3*array_size, array_size*data_width] to [array_size, 3*array_size*data_width]
	for(i = 0; i< 3 ; i = i + 1) begin
		for(j = 0; j< ARRAY_SIZE; j = j+1)begin
			tmp_c_mat1[j] = {mat1[ARRAY_SIZE*i+j], tmp_c_mat1[j][(ARRAY_SIZE*3*DATA_WIDTH-1) -: 2*DATA_WIDTH*ARRAY_SIZE]};
			tmp_c_mat2[j] = {mat2[ARRAY_SIZE*i+j], tmp_c_mat2[j][(ARRAY_SIZE*3*DATA_WIDTH-1) -: 2*DATA_WIDTH*ARRAY_SIZE]};
		end
	end
	// [array_size, 3*array_size*data_width] -> [array_size, (3*array_size+3)*data_width]
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
	
	// reg [(ARRAY_SIZE*3+3)*DATA_WIDTH-1:0] tmp_mat1[0:ARRAY_SIZE-1];
	// [array_size, (3*array_size+3)*data_width] -> array_size/4, (3*array_size+3), 4*data_width]
	for (j=0; j<QUEUE_COUNT; j=j+1) begin
		for(i = 0; i < SRAM_DEPTH; i=i+1)begin
			if(i < (ARRAY_SIZE*3+3))begin
				for (k=0; k<4; k=k+1) begin
					sram_weight[(3-k)*WEIGHT_WIDTH +: WEIGHT_WIDTH] = tmp_mat1[j*4+k][(WEIGHT_WIDTH*(i+1)-1) -: WEIGHT_WIDTH];
					sram_data[(3-k)*DATA_WIDTH +: DATA_WIDTH] = tmp_mat2[j*4+k][(DATA_WIDTH*(i+1)-1) -: DATA_WIDTH]; 
				end
			end
			else begin
				sram_data = 32'b0;
				sram_weight = 32'b0;
			end
			// weight_sram_gen[j].sram_128x32b_w.char2sram(i, sram_weight);
			// input_sram_gen[j].sram_128x32b_d.char2sram(i, sram_data);
			case (j) // 0-7
				0: weight_sram_gen[0].sram_128x32b_w.char2sram(i, sram_weight);
				1: weight_sram_gen[1].sram_128x32b_w.char2sram(i, sram_weight);
				2: weight_sram_gen[2].sram_128x32b_w.char2sram(i, sram_weight);
				3: weight_sram_gen[3].sram_128x32b_w.char2sram(i, sram_weight);
				4: weight_sram_gen[4].sram_128x32b_w.char2sram(i, sram_weight);
				5: weight_sram_gen[5].sram_128x32b_w.char2sram(i, sram_weight);
				6: weight_sram_gen[6].sram_128x32b_w.char2sram(i, sram_weight);
				7: weight_sram_gen[7].sram_128x32b_w.char2sram(i, sram_weight);
				default: $display("Error: Invalid index j = %0d", j);
			endcase

			case (j) //0-7 
				0: input_sram_gen[0].sram_128x32b_d.char2sram(i, sram_data);
				1: input_sram_gen[1].sram_128x32b_d.char2sram(i, sram_data);
				2: input_sram_gen[2].sram_128x32b_d.char2sram(i, sram_data);
				3: input_sram_gen[3].sram_128x32b_d.char2sram(i, sram_data);
				4: input_sram_gen[4].sram_128x32b_d.char2sram(i, sram_data);
				5: input_sram_gen[5].sram_128x32b_d.char2sram(i, sram_data);
				6: input_sram_gen[6].sram_128x32b_d.char2sram(i, sram_data);
				7: input_sram_gen[7].sram_128x32b_d.char2sram(i, sram_data);
				default: $display("Error: Invalid index j = %0d", j);
			endcase
		end
	end


	for (j = 0; j < QUEUE_COUNT; j = j + 1) begin
		$write("SRAM a%d!!!!\n", j);
		for (i = 0; i < SRAM_DEPTH; i = i + 1) begin
			$write("SRAM at address %d is \n", i);
			for (k = 0; k < 4; k = k + 1) begin
				case (j)
					0: $write("%d ", $signed(weight_sram_gen[0].sram_128x32b_w.mem[i][(3 - k) * WEIGHT_WIDTH +: WEIGHT_WIDTH]));
					1: $write("%d ", $signed(weight_sram_gen[1].sram_128x32b_w.mem[i][(3 - k) * WEIGHT_WIDTH +: WEIGHT_WIDTH]));
					2: $write("%d ", $signed(weight_sram_gen[2].sram_128x32b_w.mem[i][(3 - k) * WEIGHT_WIDTH +: WEIGHT_WIDTH]));
					3: $write("%d ", $signed(weight_sram_gen[3].sram_128x32b_w.mem[i][(3 - k) * WEIGHT_WIDTH +: WEIGHT_WIDTH]));
					4: $write("%d ", $signed(weight_sram_gen[4].sram_128x32b_w.mem[i][(3 - k) * WEIGHT_WIDTH +: WEIGHT_WIDTH]));
					5: $write("%d ", $signed(weight_sram_gen[5].sram_128x32b_w.mem[i][(3 - k) * WEIGHT_WIDTH +: WEIGHT_WIDTH]));
					6: $write("%d ", $signed(weight_sram_gen[6].sram_128x32b_w.mem[i][(3 - k) * WEIGHT_WIDTH +: WEIGHT_WIDTH]));
					7: $write("%d ", $signed(weight_sram_gen[7].sram_128x32b_w.mem[i][(3 - k) * WEIGHT_WIDTH +: WEIGHT_WIDTH]));
					default: $write("Error: Invalid index j = %0d", j);
				endcase
			end
			$write("\n");
		end
	end

	for (j = 0; j < QUEUE_COUNT; j = j + 1) begin
		$write("SRAM b%d!!!!\n", j);
		for (i = 0; i < SRAM_DEPTH; i = i + 1) begin
			$write("SRAM at address %d is \n", i);
			for (k = 0; k < 4; k = k + 1) begin
				case (j)
					0: $write("%d ", $signed(input_sram_gen[0].sram_128x32b_d.mem[i][(3 - k) * DATA_WIDTH +: DATA_WIDTH]));
					1: $write("%d ", $signed(input_sram_gen[1].sram_128x32b_d.mem[i][(3 - k) * DATA_WIDTH +: DATA_WIDTH]));
					2: $write("%d ", $signed(input_sram_gen[2].sram_128x32b_d.mem[i][(3 - k) * DATA_WIDTH +: DATA_WIDTH]));
					3: $write("%d ", $signed(input_sram_gen[3].sram_128x32b_d.mem[i][(3 - k) * DATA_WIDTH +: DATA_WIDTH]));
					4: $write("%d ", $signed(input_sram_gen[4].sram_128x32b_d.mem[i][(3 - k) * DATA_WIDTH +: DATA_WIDTH]));
					5: $write("%d ", $signed(input_sram_gen[5].sram_128x32b_d.mem[i][(3 - k) * DATA_WIDTH +: DATA_WIDTH]));
					6: $write("%d ", $signed(input_sram_gen[6].sram_128x32b_d.mem[i][(3 - k) * DATA_WIDTH +: DATA_WIDTH]));
					7: $write("%d ", $signed(input_sram_gen[7].sram_128x32b_d.mem[i][(3 - k) * DATA_WIDTH +: DATA_WIDTH]));
					default: $write("Error: Invalid index j = %0d", j);
				endcase
			end
			$write("\n");
		end
	end

  end
endtask	


//display the mnist image in 28x28 SRAM
task display_data;
integer this_i, this_j, this_k;
    begin
	for(this_k=0; this_k<3;this_k = this_k +1)begin
		$write("------------------------\n");
        	for(this_i=0;this_i<ARRAY_SIZE;this_i=this_i+1) begin
            		for(this_j=0;this_j<ARRAY_SIZE;this_j=this_j+1) begin
               			$write("%d",mat1[this_i][this_j]);
				$write(" ");
            		end
            		$write("\n");
        	end
		$write("\n");
        	for(this_i=0;this_i<ARRAY_SIZE;this_i=this_i+1) begin
            		for(this_j=0;this_j<ARRAY_SIZE;this_j=this_j+1) begin
               			$write("%d",mat2[this_i][this_j]);
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
integer this_i, this_j, this_k, type_idx;
begin
	// init trans_golden
	for (type_idx = 0; type_idx < 3; type_idx = type_idx + 1) begin
		for (this_k = 0; this_k < (ARRAY_SIZE*2 - 1); this_k = this_k + 1) begin
			trans_golden[type_idx*(ARRAY_SIZE*2 - 1) + this_k] = 0;
		end
	end
	
	// fill trans_golden
	// reg [ARRAY_SIZE*OUT_DATA_WIDTH-1:0] trans_golden[0:3*(ARRAY_SIZE*2-1)-1];
	// reg [ARRAY_SIZE*OUT_DATA_WIDTH-1:0] golden1[0:ARRAY_SIZE-1];
	for(this_k=0; this_k<(ARRAY_SIZE*2-1);this_k = this_k +1)begin	  
		for(this_i=0;this_i<ARRAY_SIZE;this_i=this_i+1) begin
					for(this_j=0;this_j<ARRAY_SIZE;this_j=this_j+1) begin
				if((this_i+this_j)==this_k)begin
					trans_golden[0*(ARRAY_SIZE*2 - 1) + this_k] = {golden1[this_i][((this_j+1)*OUT_DATA_WIDTH-1) -: OUT_DATA_WIDTH], trans_golden[0*(ARRAY_SIZE*2 - 1) + this_k][(8*16-1)-:(7*OUT_DATA_WIDTH)]};
					trans_golden[1*(ARRAY_SIZE*2 - 1) + this_k] = {golden2[this_i][((this_j+1)*OUT_DATA_WIDTH-1) -: OUT_DATA_WIDTH], trans_golden[1*(ARRAY_SIZE*2 - 1) + this_k][(8*16-1)-:(7*OUT_DATA_WIDTH)]};
					trans_golden[2*(ARRAY_SIZE*2 - 1) + this_k] = {golden3[this_i][((this_j+1)*OUT_DATA_WIDTH-1) -: OUT_DATA_WIDTH], trans_golden[2*(ARRAY_SIZE*2 - 1) + this_k][(8*16-1)-:(7*OUT_DATA_WIDTH)]};
				end 
					end
			end
	end

	// print trans_golden
	for (type_idx = 0; type_idx < 3; type_idx = type_idx + 1) begin
		$write("Here shows the trans_golden%d!!!\n", type_idx + 1);
		for (this_k = 0; this_k < (ARRAY_SIZE*2 - 1); this_k = this_k + 1) begin
			for (this_i = ARRAY_SIZE; this_i > 0; this_i = this_i - 1) begin
				$write("%d ", $signed(trans_golden[type_idx*(ARRAY_SIZE*2 - 1) + this_k][(this_i*OUT_DATA_WIDTH - 1) -: OUT_DATA_WIDTH]));
			end
			$write("\n\n");
		end
	end

end
endtask 

endmodule
