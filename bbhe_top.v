// BBHE Top Module — Poora system yahan hai
// 
// Kaam kaise karta hai:
// 1. Laptop se 4096 pixels receive karo (Pass 1)
// 2. Histogram banao (256 counters)
// 3. Mean nikalo
// 4. BBHE LUT banao
// 5. Laptop se 4096 pixels dobara receive karo (Pass 2)
// 6. Har pixel ko LUT se map karo
// 7. Enhanced pixels laptop ko bhejo
//
// Image size: 64x64 = 4096 pixels (grayscale)

module bbhe_top(
    input        clk,      // 100MHz (E3 pin)
    input        rst,      // Button (CPU_RESET = C12)
    input        rx,       // UART RX (Laptop se, pin: C4)
    output       tx,       // UART TX (Laptop ko, pin: D4)
    output [7:0] led,      // 8 LEDs (progress dikhane ke liye)
    output [6:0] seg,      // 7-segment display
    output [7:0] an        // 7-segment anode
);

// ─────────────────────────────────────────
// Parameters
// ─────────────────────────────────────────
parameter TOTAL_PIX  = 4096;  // 64x64
parameter IMG_W      = 12;    // log2(4096) = 12 bits counter ke liye

// ─────────────────────────────────────────
// States — system ka mood
// ─────────────────────────────────────────
parameter S_IDLE      = 4'd0;   // Wait kar raha hai
parameter S_WAIT_AA   = 4'd1;   // 0xAA header ka wait
parameter S_RECV_P1   = 4'd2;   // Pass 1: pixels receive
parameter S_CALC_MEAN = 4'd3;   // Mean calculate
parameter S_BUILD_LUT = 4'd4;   // LUT banao
parameter S_WAIT_BB   = 4'd5;   // 0xBB header ka wait
parameter S_RECV_P2   = 4'd6;   // Pass 2: pixels receive + enhance
parameter S_SEND      = 4'd7;   // Enhanced pixels bhejo
parameter S_DONE      = 4'd8;   // Sab khatam

reg [3:0] state = S_IDLE;

// ─────────────────────────────────────────
// UART wires
// ─────────────────────────────────────────
wire       rx_ready;      // Naya byte aaya?
wire [7:0] rx_data;       // Kaunsa byte aaya?
reg        tx_send = 0;   // Bhejna shuru karo
reg  [7:0] tx_data = 0;   // Kya bhejna hai
wire       tx_busy;       // TX abhi busy hai?

// UART modules connect karo
uart_rx u_rx (
    .clk(clk), .rst(rst),
    .rx(rx),
    .data_out(rx_data), .data_ready(rx_ready)
);

uart_tx u_tx (
    .clk(clk), .rst(rst),
    .send(tx_send), .data_in(tx_data),
    .tx(tx), .busy(tx_busy)
);

// ─────────────────────────────────────────
// Memory — histogram aur LUT
// ─────────────────────────────────────────

// Histogram: 256 entries, har entry mein 12-bit count
reg [11:0] histogram [0:255];

// LUT: 256 entries, har entry mein 8-bit new value
reg [7:0]  lut       [0:255];

// ─────────────────────────────────────────
// Counters aur variables
// ─────────────────────────────────────────
reg [IMG_W-1:0] pix_count  = 0;   // Kitne pixels receive hue
reg [31:0]      mean_sum   = 0;   // Mean ke liye sum
reg [7:0]       mean_val   = 0;   // Final mean value
reg [7:0]       lut_idx    = 0;   // LUT banane ka counter
reg [11:0]      cdf        = 0;   // Running CDF
reg [11:0]      n_lower    = 0;   // Lower half pixels count
reg [11:0]      n_upper    = 0;   // Upper half pixels count
reg [7:0]       send_idx   = 0;   // Bhejne ka counter (TX)
reg [7:0]       enh_pixel  = 0;   // Enhanced pixel value

// Pass 1 ke pixels store karne ke liye
// (Pass 2 mein raw pixels dobara aayenge laptop se)

// ─────────────────────────────────────────
// Main State Machine
// ─────────────────────────────────────────
integer i;

always @(posedge clk) begin
    if (rst) begin
        state     <= S_IDLE;
        pix_count <= 0;
        mean_sum  <= 0;
        tx_send   <= 0;
        // Histogram aur LUT clear karo
        for (i = 0; i < 256; i = i + 1) begin
            histogram[i] <= 0;
            lut[i]       <= i;  // Default: passthrough
        end
    end
    else begin
        tx_send <= 0;  // Default: kuch mat bhejo

        case (state)

        // ─────────────────────────
        S_IDLE: begin
        // Kuch nahi karna, wait karo
        // Laptop connect hone pe kaam shuru hoga
            state     <= S_WAIT_AA;
            pix_count <= 0;
            mean_sum  <= 0;
            for (i = 0; i < 256; i = i + 1)
                histogram[i] <= 0;
        end

        // ─────────────────────────
        S_WAIT_AA: begin
        // 0xAA byte ka wait — matlab "start karo"
            if (rx_ready && rx_data == 8'hAA) begin
                state     <= S_RECV_P1;
                pix_count <= 0;
                mean_sum  <= 0;
            end
        end

        // ─────────────────────────
        S_RECV_P1: begin
        // Pass 1: 4096 pixels receive karo
        // Har pixel ka histogram update karo
        // Mean ke liye sum karo
            if (rx_ready) begin
                // Histogram update
                histogram[rx_data] <= histogram[rx_data] + 1;
                // Mean sum update
                mean_sum  <= mean_sum + rx_data;
                pix_count <= pix_count + 1;

                if (pix_count == TOTAL_PIX - 1) begin
                    state <= S_CALC_MEAN;
                end
            end
        end

        // ─────────────────────────
        S_CALC_MEAN: begin
        // Mean = sum / total_pixels
        // TOTAL_PIX = 4096 = 2^12
        // Division by 2^12 = right shift by 12
            mean_val  <= mean_sum[19:12];
            // mean_sum[19:12] = mean_sum / 4096
            lut_idx   <= 0;
            cdf       <= 0;
            n_lower   <= 0;
            n_upper   <= 0;
            state     <= S_BUILD_LUT;

            // n_lower aur n_upper count karo
            // (yeh ek cycle mein nahi hoga, alag loop)
        end

        // ─────────────────────────
        S_BUILD_LUT: begin
        // Har value ke liye LUT entry banao
        // Lower half: 0 to mean
        // Upper half: mean+1 to 255

            if (lut_idx <= 8'd255) begin
                if (lut_idx <= mean_val) begin
                    // Lower half
                    cdf <= cdf + histogram[lut_idx];
                    // n_lower = CDF at mean
                    if (lut_idx == mean_val)
                        n_lower <= cdf + histogram[lut_idx];
                end
                else begin
                    // Upper half
                    cdf <= cdf + histogram[lut_idx];
                end
                lut_idx <= lut_idx + 1;
            end
            else begin
                // Ab actual LUT values calculate karo
                // Dobara lut_idx reset karo
                lut_idx <= 0;
                n_upper <= cdf - n_lower;
                state   <= S_BUILD_LUT + 1;
                // Yahan hum ek extra state use karenge
                // simple rakhne ke liye
            end
        end

        // S_BUILD_LUT + 1 = 4'd5 = S_WAIT_BB
        // Lekin hum LUT fill karne ke liye
        // S_WAIT_BB se pehle ek step add karte hain
        // Iske liye hum S_WAIT_BB ko thoda baad mein use karenge

        // ─────────────────────────
        S_WAIT_BB: begin
        // Pehle LUT fill karo (ek cycle per entry)
            if (lut_idx <= 8'd255) begin
                if (lut_idx <= mean_val) begin
                    // Lower half formula:
                    // lut[k] = mean * CDF_lower(k) / n_lower
                    if (n_lower > 0)
                        lut[lut_idx] <= (mean_val * 
                            histogram[lut_idx]) / n_lower;
                    else
                        lut[lut_idx] <= lut_idx;
                end
                else begin
                    // Upper half formula:
                    // lut[k] = mean+1 + (255-mean)*CDF_upper(k)/n_upper
                    if (n_upper > 0)
                        lut[lut_idx] <= mean_val + 1 + 
                            ((255 - mean_val) * 
                            histogram[lut_idx]) / n_upper;
                    else
                        lut[lut_idx] <= lut_idx;
                end
                lut_idx <= lut_idx + 1;
            end
            else begin
                // LUT ready hai
                // Ab 0xBB ka wait karo (Pass 2 start signal)
                if (rx_ready && rx_data == 8'hBB) begin
                    state     <= S_RECV_P2;
                    pix_count <= 0;
                    send_idx  <= 0;
                end
            end
        end

        // ─────────────────────────
        S_RECV_P2: begin
        // Pass 2: pixels receive karo
        // Turant LUT se map karo aur bhejo
            if (rx_ready) begin
                enh_pixel <= lut[rx_data];  // LUT se map
                pix_count <= pix_count + 1;
                state     <= S_SEND;
            end
        end

        // ─────────────────────────
        S_SEND: begin
        // Enhanced pixel bhejo laptop ko
            if (!tx_busy) begin
                tx_data <= enh_pixel;
                tx_send <= 1;

                if (pix_count >= TOTAL_PIX) begin
                    state <= S_DONE;
                end
                else begin
                    state <= S_RECV_P2;
                end
            end
        end

        // ─────────────────────────
        S_DONE: begin
        // Sab khatam! LED pe dikhao
        // Automatically reset ho jaao next frame ke liye
            state <= S_IDLE;
        end

        endcase
    end
end

// ─────────────────────────────────────────
// LEDs — kya chal raha hai dikhao
// ─────────────────────────────────────────
assign led[0] = (state == S_IDLE    || state == S_WAIT_AA);
assign led[1] = (state == S_RECV_P1);
assign led[2] = (state == S_CALC_MEAN);
assign led[3] = (state == S_BUILD_LUT);
assign led[4] = (state == S_WAIT_BB);
assign led[5] = (state == S_RECV_P2 || state == S_SEND);
assign led[6] = (state == S_DONE);
assign led[7] = rx_ready | tx_send;  // Activity indicator

// 7-segment off rakhna (abhi use nahi kar rahe)
assign seg = 7'b1111111;  // All off
assign an  = 8'b11111111; // All off

endmodule