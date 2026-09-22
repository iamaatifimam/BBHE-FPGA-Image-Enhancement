// UART Receiver Module
// Kaam: Laptop se aane wale bytes receive karta hai

module uart_rx(
    input        clk,         // 100MHz clock
    input        rst,         // reset
    input        rx,          // UART wire (laptop se aata hai)
    output reg [7:0] data_out,// Receive hua byte
    output reg   data_ready   // "1 matlab naya byte aaya"
);

parameter CLKS_PER_BIT = 868;
// Beech ka sample lena hai isliye half:
parameter HALF_BIT     = 434;

parameter IDLE  = 2'd0;
parameter START = 2'd1;
parameter DATA  = 2'd2;
parameter STOP  = 2'd3;

reg [1:0] state    = IDLE;
reg [9:0] clk_cnt  = 0;
reg [2:0] bit_idx  = 0;
reg [7:0] data_reg = 0;

always @(posedge clk) begin
    if (rst) begin
        state      <= IDLE;
        data_ready <= 0;
        clk_cnt    <= 0;
        bit_idx    <= 0;
    end
    else begin
        data_ready <= 0;  // Default: koi naya data nahi
        
        case (state)
        
        IDLE: begin
            if (rx == 0) begin   // Start bit detect hua (LOW)
                state   <= START;
                clk_cnt <= 0;
            end
        end
        
        START: begin
            // Beech tak wait karo (half bit time)
            if (clk_cnt < HALF_BIT - 1)
                clk_cnt <= clk_cnt + 1;
            else begin
                clk_cnt <= 0;
                state   <= DATA;
                bit_idx <= 0;
            end
        end
        
        DATA: begin
            if (clk_cnt < CLKS_PER_BIT - 1)
                clk_cnt <= clk_cnt + 1;
            else begin
                clk_cnt            <= 0;
                data_reg[bit_idx]  <= rx;  // Bit save karo
                if (bit_idx < 7)
                    bit_idx <= bit_idx + 1;
                else begin
                    bit_idx <= 0;
                    state   <= STOP;
                end
            end
        end
        
        STOP: begin
            if (clk_cnt < CLKS_PER_BIT - 1)
                clk_cnt <= clk_cnt + 1;
            else begin
                clk_cnt    <= 0;
                data_out   <= data_reg;  // Data output karo
                data_ready <= 1;         // "Data ready hai!"
                state      <= IDLE;
            end
        end
        
        endcase
    end
end
endmodule