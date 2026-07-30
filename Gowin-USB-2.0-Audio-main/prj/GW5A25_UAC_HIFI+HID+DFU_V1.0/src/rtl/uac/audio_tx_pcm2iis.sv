

import audio_pkg::*;
module audio_tx_pcm2iis #(
parameter CH_NUM = 8  // 必须为偶数，如 2, 4, 6, 8
) (
     input  logic        MCLK
    ,input  logic        RESET

    ,input  logic                      I_TX_EN

    // ====== External IIS Clock (From IIS_CLK_GEN) ======
    ,input  logic                      I_IIS_BCLK
    ,input  logic                      I_IIS_LRCK
    ,input  logic                      I_BCLK_FALL_PULSE
    // ====== Inputs from audio_tx_usb2pcm ======
    ,input  logic                      I_WINC
    ,input  logic [$clog2(CH_NUM)-1:0] I_ADDR
    ,input  logic [31:0]               I_DATA
// ====== Outputs to DAC (IIS Data Lanes) ======
    ,output logic [(CH_NUM/2)-1:0]     O_IIS_DATA
);

localparam DATA_PINS = CH_NUM / 2;

//==============================================================
// 1. 不再进行 跨时钟域与边缘检测： 使用直接信号I_BCLK_FALL_PULSE替代
//==============================================================
logic lrck_d;
always_ff @(posedge MCLK or posedge RESET) begin
    if (RESET) begin
        lrck_d <= 1'b0;
    end else if (I_BCLK_FALL_PULSE) begin
        // 只有在 BCLK 下降沿前夕，才抓取并记录 LRCK 的状态
        lrck_d <= I_IIS_LRCK; //同步更新
    end
end
//==============================================================
// 2. IIS 内部64bit 计数器  
//==============================================================
logic [5:0] tx_bit_cnt;
logic [31:0] shift_data [0:CH_NUM-1];   //实际加载数据
always_ff @(posedge MCLK or posedge RESET) begin
    if (RESET) begin
        tx_bit_cnt  <= 6'd0;
        for (int i = 0; i < CH_NUM; i++) shift_data[i] <= 32'd0;
    end 

    //当 LRCK 发生翻转时，数据并不在当前下降沿更新，而是延迟 1 个 BCLK 周期，在下一个 BCLK 下降沿才更新 MSB
    else if (I_BCLK_FALL_PULSE) begin    // LRCK翻转后的下一个BCLK下降沿
        if (I_IIS_LRCK != lrck_d) begin  // LRCK之前已经翻转
            tx_bit_cnt <= 6'd0; 
            // 当预测下个状态为 0 (Left Channel) 时，加载新数据
            if (I_IIS_LRCK == 1'b0) begin
                for (int i = 0; i < CH_NUM; i++) begin
                    shift_data[i] <= hold_data[i];
                end
            end
            else begin
                tx_bit_cnt <= tx_bit_cnt + 6'd1;
            end
        end 
        else begin
            tx_bit_cnt <= tx_bit_cnt + 6'd1;
        end
    end
end


//==============================================================
// 3. 数据突发捕获与移位寄存器
//==============================================================
logic [31:0] hold_data  [0:CH_NUM-1];   //异步捕获数据
always_ff @(posedge MCLK or posedge RESET) begin
    if (RESET) begin
        for (int i = 0; i < CH_NUM; i++) begin
            hold_data[i]  <= 32'd0;
        end
    end else begin
        // 异步突发捕获：抓取usb2pcm数据
        if (I_WINC) begin
            hold_data[I_ADDR] <= I_DATA;
        end
    end
end

//==============================================================
// 4. 即时转串行
//==============================================================
always_comb begin
    int ch_l, ch_r;

    if (!I_TX_EN) begin
        O_IIS_DATA = '0; 
    end
    else begin
        for (int i = 0; i < DATA_PINS; i++) begin
            ch_l = i * 2;       // 偶数地址为左声道
            ch_r = i * 2 + 1;   // 奇数地址为右声道

        if (tx_bit_cnt < 6'd32) begin
            // 左声道：tx_bit_cnt 为 0 时输出最高位 [31]
            O_IIS_DATA[i] = shift_data[ch_l][5'd31 - tx_bit_cnt[4:0]];
        end else begin
            // 右声道：tx_bit_cnt 为 32 时输出最高位 [31]
            O_IIS_DATA[i] = shift_data[ch_r][5'd31 - tx_bit_cnt[4:0]];
        end
        end
    end
        // for (int i = 0; i < DATA_PINS; i++) begin
        //     ch_l = i * 2;       // 偶数地址为左声道
        //     ch_r = i * 2 + 1;   // 奇数地址为右声道

        // if (tx_bit_cnt < 6'd32) begin
        //     // 左声道：tx_bit_cnt 为 0 时输出最高位 [31]
        //     O_IIS_DATA[i] = shift_data[ch_l][5'd31 - tx_bit_cnt[4:0]];
        // end else begin
        //     // 右声道：tx_bit_cnt 为 32 时输出最高位 [31]
        //     O_IIS_DATA[i] = shift_data[ch_r][5'd31 - tx_bit_cnt[4:0]];
        // end
end

endmodule