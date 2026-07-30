
module iis_gen 
(
     input  logic       CLK
    ,input  logic       RESET
    ,input  logic       ENABLE
    ,input  logic [7:0] BCLK_DIV
    ,input  logic [7:0] CHANNEL_BITS
    ,input  logic [7:0] DATA_BITS   

    ,output logic       IIS_LRCK_O
    ,output logic       IIS_BCLK_O
);

    logic [7:0]     clk_cnt;
    logic           bclk_reg;
    logic [11:0]    bclk_cnt;
    logic           lrck_reg;
    
    // 下降沿条件
    logic bclk_fall;
    assign bclk_fall = (clk_cnt == 8'd0) && ENABLE;

    // --- BCLK 生成 ---
    always_ff @(posedge CLK or posedge RESET) begin
        if (RESET) begin
            clk_cnt  <= '0;
            bclk_reg <= 1'b0;
        end 
        else if (!ENABLE) begin
            clk_cnt  <= '0;
            bclk_reg <= 1'b0;
        end 
        else begin
            // 计数逻辑
            if (clk_cnt >= (BCLK_DIV - 1'b1)) begin
                clk_cnt <= '0;
            end else begin
                clk_cnt <= clk_cnt + 1'b1;
            end
            
            // 翻转逻辑
            if (clk_cnt == (BCLK_DIV >> 1)) begin
                bclk_reg <= 1'b1;
            end else if (clk_cnt == 8'd0) begin
                bclk_reg <= 1'b0;
            end
        end
    end

    // --- LRCK 生成 ---
    always_ff @(posedge CLK or posedge RESET) begin
        if (RESET) begin
            bclk_cnt <= '0;
            lrck_reg <= 1'b0;
        end else if (!ENABLE) begin
            bclk_cnt <= '0;
            lrck_reg <= 1'b0;
        end else if (bclk_fall) begin
            if (bclk_cnt >= (CHANNEL_BITS - 1'b1)) begin
                bclk_cnt <= '0;
                lrck_reg <= ~lrck_reg;
            end else begin
                bclk_cnt <= bclk_cnt + 1'b1;
            end
        end
    end
//==============================================================
//======
assign     IIS_LRCK_O   = lrck_reg ; 
assign     IIS_BCLK_O   = bclk_reg ;

endmodule