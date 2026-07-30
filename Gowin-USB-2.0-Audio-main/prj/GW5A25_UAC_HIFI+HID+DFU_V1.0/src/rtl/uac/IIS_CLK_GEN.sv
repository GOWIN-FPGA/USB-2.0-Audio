import audio_pkg::*;
module IIS_CLK_GEN 
(
     input  logic        PHY_CLKOUT
    ,input  logic        MCLK
    ,input  logic        RESET
    
    ,input  logic [31:0] I_SAMPLE_RATE
    ,input  logic [ 7:0] I_DATA_BITS
 
    ,output logic        O_IIS_LRCK
    ,output logic        O_IIS_BCLK

    ,output logic        O_BCLK_FALL_PULSE
);
//==============================================

wire  [31:0]  sample_rate;
wire  [ 7:0]  data_bits;

assign sample_rate    = I_SAMPLE_RATE;
assign data_bits      = I_DATA_BITS;

//==============================================
reg  [ 7:0]     s_bclk_div;
wire [ 7:0]     pcm_bclk_div;
wire [ 7:0]     pcm_channel_bits;
wire            pcm_enable;
wire [ 7:0]     pcm_data_bits;
//=============================================================
//======PCM and DSD parameters
//==============================================================
always_ff @(posedge PHY_CLKOUT or posedge RESET) begin
    if (RESET) begin
        s_bclk_div <= 8'd32;
    end else begin
        // 使用 case 语句并合并相同分频系数的分支
        case (sample_rate)
            SAMPLE_RATE_768,   SAMPLE_RATE_705_6 : s_bclk_div <= 8'd2;
            SAMPLE_RATE_384,   SAMPLE_RATE_352_8 : s_bclk_div <= 8'd4;
            SAMPLE_RATE_192,   SAMPLE_RATE_176_4 : s_bclk_div <= 8'd8;
            SAMPLE_RATE_128                      : s_bclk_div <= 8'd12;
            SAMPLE_RATE_96,    SAMPLE_RATE_88_2  : s_bclk_div <= 8'd16;
            SAMPLE_RATE_64                       : s_bclk_div <= 8'd24;
            SAMPLE_RATE_48,    SAMPLE_RATE_44_1  : s_bclk_div <= 8'd32;
            SAMPLE_RATE_32                       : s_bclk_div <= 8'd48;
            default                              : s_bclk_div <= 8'd32;
        endcase
    end
end
//==============================================
assign pcm_enable = 1'b1 ;
assign pcm_channel_bits = 8'd32;
assign pcm_bclk_div = s_bclk_div[7:0];
assign pcm_data_bits = data_bits;

iis_gen iis_gen_inst
(
     .CLK          (MCLK             )//clock system
    ,.RESET        (RESET            )//reset
    ,.ENABLE       (pcm_enable       )
    ,.BCLK_DIV     (pcm_bclk_div     )
	,.CHANNEL_BITS (pcm_channel_bits )
	,.DATA_BITS    (pcm_data_bits    )
    ,.IIS_LRCK_O   (O_IIS_LRCK       )
    ,.IIS_BCLK_O   (O_IIS_BCLK       )

    ,.BCLK_FALL_PULSE_O (O_BCLK_FALL_PULSE)
);

endmodule 


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

    ,output logic       BCLK_FALL_PULSE_O
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

// 下周期下降沿
assign BCLK_FALL_PULSE_O = (clk_cnt == 8'd0) && ENABLE;

endmodule