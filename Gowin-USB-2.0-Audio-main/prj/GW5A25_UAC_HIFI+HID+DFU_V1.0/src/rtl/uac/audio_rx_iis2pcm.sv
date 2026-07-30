


module audio_rx_iis2pcm #(
    parameter CH_NUM = 8  // 必须为偶数，如 2, 4, 6, 8
) (
     input  logic                      MCLK
    ,input  logic                      RESET

    // ====== External IIS Signals (From ADC / IIS_CLK_GEN) ======
    ,input  logic                      I_IIS_BCLK
    ,input  logic                      I_IIS_LRCK
    ,input  logic [(CH_NUM/2)-1:0]     I_IIS_DATA  // 多通道输入线，如 8CH 对应 4 根线

    // ====== Outputs to audio_rx_pcm2usb ======
    ,output logic                      O_WINC      // 突发写使能脉冲
    ,output logic [$clog2(CH_NUM)-1:0] O_ADDR      // 当前突发写入的通道号
    ,output logic [31:0]               O_DATA       // 32-bit 宽音频数据
);

localparam PINS = CH_NUM / 2;

//==============================================================
// 1. 跨时钟域与边缘检测： MCLK 采样 BCLK 和 LRCK 
//==============================================================
logic [2:0]        bclk_r;
logic [2:0]        lrck_r;
logic [PINS-1:0]   data_r [0:2];

always_ff @(posedge MCLK or posedge RESET) begin
    if (RESET) begin
        bclk_r <= 3'b0;
        lrck_r <= 3'b0;
        for(int i=0; i<3; i++) data_r[i] <= '0;
    end else begin
        bclk_r <= {bclk_r[1:0], I_IIS_BCLK};
        lrck_r <= {lrck_r[1:0], I_IIS_LRCK};
        
        data_r[0] <= I_IIS_DATA;
        data_r[1] <= data_r[0];
        data_r[2] <= data_r[1];
    end
end

// BCLK 上升沿记录数据
logic bclk_rise;
assign bclk_rise = ( bclk_r[2:1] == 2'b10 );


//==============================================================
// 2. I2S 串行转并行 (Deserialization)
//==============================================================

logic [31:0] shift_reg  [0:PINS-1];
logic [31:0] out_buffer [0:CH_NUM-1]; // 0,2,4..存左声道，1,3,5..存右声道
logic        lrck_d;
logic        frame_ready;

always_ff @(posedge MCLK or posedge RESET) begin
    if (RESET) begin
        for(int i=0; i<PINS; i++)   shift_reg[i]  <= 32'd0;
        for(int i=0; i<CH_NUM; i++) out_buffer[i] <= 32'd0;
        lrck_d      <= 1'b0;
        frame_ready <= 1'b0;
    end 
    else begin
        frame_ready <= 1'b0; // 默认仅维持一拍的触发脉冲
        if (bclk_rise) begin
            lrck_d <= lrck_r[2]; //当前左/右声道
            
            // 1. 非边沿，收集IIS数据
            for(int i=0; i<PINS; i++) begin
                shift_reg[i] <= {shift_reg[i][30:0], data_r[2][i]};
            end
            // 2.  LRCK 边沿 → 声道切换 ，32bit 数据缓存
            if (lrck_r[2] != lrck_d) begin
                if (lrck_r[2] == 1'b1) begin 
                    // LRCK 0->1 : 左声道(偶数通道) 结束
                    for(int i=0; i<PINS; i++) begin
                        out_buffer[i*2] <= {shift_reg[i][30:0], data_r[2][i]};
                    end
                end 
                else begin               
                    // LRCK 1->0 : 右声道(奇数通道) 结束，Frame 结尾
                    for(int i=0; i<PINS; i++) begin
                        out_buffer[i*2 + 1] <= {shift_reg[i][30:0], data_r[2][i]};
                    end
                    frame_ready <= 1'b1; // 触发突发传输
                end
            end
        end
    end
end

//==============================================================
// 3. 突发分发
// 收集一完整数据帧后，向后分发
//==============================================================
logic [$clog2(CH_NUM):0] burst_cnt; 
logic                    burst_busy;
always_ff @(posedge MCLK or posedge RESET) begin
    if (RESET) begin
        burst_cnt       <= '0;
        burst_busy      <= 1'b0;
        O_WINC          <= 1'b0;
        O_ADDR          <= '0;
        O_DATA          <= 32'd0;
    end 
    else begin
        if (frame_ready) begin
            burst_busy  <= 1'b1;
            burst_cnt   <=  'h1; 
            
            O_WINC      <= 1'b1;
            O_ADDR      <= '0;   
            O_DATA      <= out_buffer[0];
        end
        else if (burst_busy) begin
            if (burst_cnt == CH_NUM) begin
                // 所有通道发送完毕
                burst_busy <= 1'b0;
                O_WINC     <= 1'b0;
            end else begin
                O_WINC     <= 1'b1;
                O_ADDR     <= burst_cnt[$clog2(CH_NUM)-1:0];
                O_DATA     <= out_buffer[burst_cnt];
                
                burst_cnt  <= burst_cnt + 1'b1;
            end
        end 
        // 空闲状态
        else begin
            O_WINC          <= 1'b0;
            // O_ADDR          <=  'b0;
            // O_DATA          <= 32'd0; //减功耗
        end
        end
    end




endmodule