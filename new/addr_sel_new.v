//-------do the address select for queue, the number of queues can be adjusted by ARRAY_SIZE---

module addr_sel #(
    parameter ARRAY_SIZE = 8,
    parameter QUEUE_COUNT = (ARRAY_SIZE + 3) / 4,  // Calculate the number of required queues
    parameter ADDR_MAX = 127,
    parameter ADDR_OFFSET = 4,
    parameter ADDR_WIDTH = 10
) (
    input clk,
    input [6:0] addr_serial_num,

    // Packed output addresses for weight queues
    output [(QUEUE_COUNT * ADDR_WIDTH) - 1:0] sram_raddr_w_packed,
    // Packed output addresses for data queues
    output [(QUEUE_COUNT * ADDR_WIDTH) - 1:0] sram_raddr_d_packed
);

reg [(ADDR_WIDTH - 1):0] sram_raddr_w [0:QUEUE_COUNT - 1];
reg [(ADDR_WIDTH - 1):0] sram_raddr_d [0:QUEUE_COUNT - 1];
wire [(ADDR_WIDTH - 1):0] sram_raddr_w_nx [0:QUEUE_COUNT - 1];
wire [(ADDR_WIDTH - 1):0] sram_raddr_d_nx [0:QUEUE_COUNT - 1];

integer i;

// Sequential logic: Update addresses at the rising edge of the clock
always @(posedge clk) begin
    for (i = 0; i < QUEUE_COUNT; i = i + 1) begin
        sram_raddr_w[i] <= sram_raddr_w_nx[i];
        sram_raddr_d[i] <= sram_raddr_d_nx[i];
    end
end

// Combinational logic: Calculate the next addresses using generate for
genvar k;
generate
    for (k = 0; k < QUEUE_COUNT; k = k + 1) begin : addr_gen
        localparam integer start_addr = k * ADDR_OFFSET;
        localparam integer end_addr = 98 + k * ADDR_OFFSET;

        assign sram_raddr_w_nx[k] = (addr_serial_num >= start_addr && addr_serial_num <= end_addr)? { {3{1'd0}} , addr_serial_num - start_addr} : ADDR_MAX;
        assign sram_raddr_d_nx[k] = (addr_serial_num >= start_addr && addr_serial_num <= end_addr)? { {3{1'd0}} , addr_serial_num - start_addr} : ADDR_MAX;
    end
endgenerate

// Pack the output addresses
// `PACK_ARRAY(ADDR_WIDTH, QUEUE_COUNT, sram_rdata_w, sram_rdata_w_packed)
// `PACK_ARRAY(ADDR_WIDTH, QUEUE_COUNT, sram_rdata_d, sram_rdata_d_packed)
genvar pk_idx;
generate
    for (pk_idx = 0; pk_idx < QUEUE_COUNT; pk_idx = pk_idx + 1) begin
        assign sram_raddr_w_packed[(pk_idx + 1) * ADDR_WIDTH - 1 -: ADDR_WIDTH] = sram_raddr_w[pk_idx];
        assign sram_raddr_d_packed[(pk_idx + 1) * ADDR_WIDTH - 1 -: ADDR_WIDTH] = sram_raddr_d[pk_idx];
    end
endgenerate

endmodule