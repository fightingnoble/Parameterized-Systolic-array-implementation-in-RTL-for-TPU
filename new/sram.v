
module simple_sram #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 10,
    parameter DEPTH = 1024
) (
    input clk,
    input csb,  //chip enable, active low
    input wsb,  //write enable, active low
    // read port
    input [ADDR_WIDTH-1:0] raddr,
    output reg [DATA_WIDTH-1:0] rdata,
    // write port
    input [ADDR_WIDTH-1:0] waddr,
    input [DATA_WIDTH-1:0] wdata
);

reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

always @(posedge clk) begin
    if (~csb) begin
        rdata <= mem[raddr];
        if (~wsb) begin
            mem[waddr] <= wdata;
        end
    end
end

task char2sram(
 input [ADDR_WIDTH-1:0]index,
 input [DATA_WIDTH-1:0]char_in
);

  mem[index] = char_in;

endtask

endmodule
