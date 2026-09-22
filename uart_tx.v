// UART Transmitter Module
// Kaam: FPGA se laptop ko ek byte (8 bits) bhejta hai
// Speed: 115200 baud (115200 bits per second)

module uart_tx(
    input        clk,        // 100MHz clock (board ka)
    input        rst,        // reset button
    input        send,       // "1 karo jab bhejna ho"
    input  [7:0] data_in,    // kaunsa byte bhejna hai
    output reg   tx,         // UART wire (laptop ko jaata hai)
    output reg   busy        // "1 matlab abhi kaam chal raha hai"
);

// 100MHz / 115200 = 868 clock cycles per bit
parameter CLKS_PER_BIT = 868;

// States — kya chal raha hai abhi
parameter IDLE  = 2'd0;  // Kuch nahi kar raha
parameter START = 2'd1;  // Start bit bhej raha hai
parameter DATA  = 2'd2;  // Data bits bhej raha hai
parameter STOP  = 2'd3;  // Stop bit bhej raha hai

reg [1:0]  state    = IDLE;
reg [9:0]  clk_cnt  = 0;   // Clock counter
reg [2:0]  bit_idx  = 0;   // Kaunsa bit bhej raha hai (0-7)
reg [7:0]  data_reg = 0;   // Data store karta hai

always @(posedge clk) begin
    if (rst) begin
        state   <= IDLE;
        tx      <= 1;      // UART idle = HIGH
        busy    <= 0;
        clk_cnt <= 0;
        bit_idx <= 0;
    end
    else begin
        case (state)
        
        IDLE: begin
            tx   <= 1;    // Line high rakhna = idle
            busy <= 0;
            if (send) begin           // Bhejna hai?
                data_reg <= data_in;  // Data save karo
                state    <= START;    // Start karo
                busy     <= 1;
                clk_cnt  <= 0;
            end
        end
        
        START: begin
            tx <= 0;  // Start bit = LOW
            if (clk_cnt < CLKS_PER_BIT - 1)
                clk_cnt <= clk_cnt + 1;
            else begin
                clk_cnt <= 0;
                state   <= DATA;
                bit_idx <= 0;
            end
        end
        
        DATA: begin
            tx <= data_reg[bit_idx];  // Ek ek bit bhejo
            if (clk_cnt < CLKS_PER_BIT - 1)
                clk_cnt <= clk_cnt + 1;
            else begin
                clk_cnt <= 0;
                if (bit_idx < 7)
                    bit_idx <= bit_idx + 1;
                else begin
                    bit_idx <= 0;
                    state   <= STOP;
                end
            end
        end
        
        STOP: begin
            tx <= 1;  // Stop bit = HIGH
            if (clk_cnt < CLKS_PER_BIT - 1)
                clk_cnt <= clk_cnt + 1;
            else begin
                clk_cnt <= 0;
                state   <= IDLE;
                busy    <= 0;
            end
        end
        
        endcase
    end
end
endmodule