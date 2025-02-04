//-----controller for systolic array----

module systolic_controll#(
	parameter ARRAY_SIZE = 8,
	parameter ADDR_MAX = 127,
	parameter CYCLE_BITS = 9, // $clog2(CYCLE_MAX),
	parameter MATRIX_BITS = 6, //$clog2(2*ARRAY_SIZE-1),
    parameter ADDR_WIDTH_MIN = 7 //$clog2(ADDR_MAX)
)
(
	input clk,
	input srstn,
	input tpu_start,																//total enable signal
	
	output reg sram_write_enable,

	//addr_sel
	output reg [ADDR_WIDTH_MIN-1:0] addr_serial_num,

	//systolic array
	output reg alu_start,																//shift & multiplcation start
	output reg [CYCLE_BITS-1:0] cycle_num,													//for systolic.v
	output reg [MATRIX_BITS-1:0] matrix_index,													//index for write-out SRAM data
	output reg [1:0] data_set,

	output reg tpu_done														//done signal
);

localparam IDLE = 3'd0, LOAD_DATA = 3'd1, WAIT1 = 3'd2, ROLLING = 3'd3;

//----general variable----
reg [2:0] state;
reg [2:0] state_nx;

reg [1:0] data_set_nx;

reg tpu_done_nx;

//----addr_sel----
reg [ADDR_WIDTH_MIN-1:0] addr_serial_num_nx;

//----systolic array----
reg [CYCLE_BITS-1:0] cycle_num_nx;
reg [MATRIX_BITS-1:0] matrix_index_nx;

//----initialization----
always@(posedge clk) begin
	if(~srstn) begin
		state <= IDLE;
		data_set <= 0;
		cycle_num <= 0;
		matrix_index <= 0;
		addr_serial_num <= 0;
		tpu_done <= 0;
	end
	else begin
		state <= state_nx;
		data_set <= data_set_nx;
		cycle_num <= cycle_num_nx;
		matrix_index <= matrix_index_nx;
		addr_serial_num <= addr_serial_num_nx;
		tpu_done <= tpu_done_nx;
	end
end

//----state transition, tpu_done signal----
always@(*) begin
	case(state) 
		IDLE:	 begin
			if(tpu_start)
				state_nx = LOAD_DATA;
			else
				state_nx = IDLE;
			tpu_done_nx = 0;
		end

		LOAD_DATA: begin
			state_nx = WAIT1;
			tpu_done_nx = 0;
		end

		WAIT1: begin
			state_nx = ROLLING;
			tpu_done_nx = 0;
		end

		ROLLING: begin
			if(matrix_index==(2*ARRAY_SIZE-1) && data_set == 1) begin
				state_nx = IDLE;
				tpu_done_nx = 1;
			end
			else begin
				state_nx = ROLLING;
				tpu_done_nx = 0;
			end
		end

		default: begin
			state_nx = IDLE;
			tpu_done_nx = 0;
		end
	endcase
end

//-----addr_sel: addr_serial_num-----
always@(*) begin
	case(state)
		IDLE: begin
			if(tpu_start)
				addr_serial_num_nx = 0;
			else
				addr_serial_num_nx = addr_serial_num;
		end

		LOAD_DATA:
			addr_serial_num_nx = 1;

		WAIT1: 
			addr_serial_num_nx = 2;

		ROLLING: begin
			if(addr_serial_num == ADDR_MAX)
				addr_serial_num_nx = addr_serial_num;
			else
				addr_serial_num_nx = addr_serial_num + 1;
		end

		default:
			addr_serial_num_nx = 0;
	endcase
end

//------systolic: alu_start, cycle_num, matrix_index, data_set,
//sram_write_enable------
always@(*) begin
	case(state)
		IDLE: begin
			alu_start = 0;
			cycle_num_nx = 0;
			matrix_index_nx = 0;
			data_set_nx = 0;
			sram_write_enable = 0;
		end

		LOAD_DATA: begin
			alu_start = 0;
			cycle_num_nx = 0;
			matrix_index_nx = 0;
			data_set_nx = 0;
			sram_write_enable = 0;
		end

		WAIT1: begin
			alu_start = 0;
			cycle_num_nx = 0;
			matrix_index_nx = 0;
			data_set_nx = 0;
			sram_write_enable = 0;
		end

		ROLLING: begin
			alu_start = 1;
			// matrix_index==(2*ARRAY_SIZE-1) && data_set == 1
			cycle_num_nx = cycle_num + 1;
			if(cycle_num >= ARRAY_SIZE+1) begin
				if(matrix_index == (2*ARRAY_SIZE-1)) begin
					matrix_index_nx = 0;
					data_set_nx = data_set + 1;
				end
				else begin
					matrix_index_nx = matrix_index + 1;
					data_set_nx = data_set;
				end
				sram_write_enable = 1;
			end
			else begin
				matrix_index_nx = 0;
				data_set_nx = data_set;
				sram_write_enable = 0;
			end
		end

		default: begin
			alu_start = 0;
			cycle_num_nx = 0;
			matrix_index_nx = 0;
			data_set_nx = 0;
			sram_write_enable = 0;
		end
		
	endcase
end

endmodule

