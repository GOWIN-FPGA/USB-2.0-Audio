//----------------------------------------------------------------------
//===========================================
module audio_rx_pcm2usb#(
     parameter int CH_NUM    = 2         // 必须是偶数
    ,parameter int I2S_LINES = CH_NUM/2  // 并行 I2S 数据线数量
)
(
     input  logic           PHY_CLKOUT    //clock
    ,input  logic           RESET         //reset
    ,input  logic           MCLK          //clock

    //=========================================
    ,input                  EXT_LRCK      //仅用于针对windows系统隐式反馈 
    //=========================================
    ,input  logic [$clog2(CH_NUM)-1:0]  I_ADDR
    ,input  logic                       I_WINC        // 写有效脉冲 (高电平 1 个 MCLK)
    ,input  logic [31:0]                I_DATA        // 并行音频数据

    ,input  logic [7:0]     DATA_BITS_I   
    ,input  logic [31:0]    SAMPLE_FREQ_I 
    
	,input  logic		    async_fifo_rst
    ,output logic [11:0]    AUDIO_PKT_MAX 
    ,output logic [11:0]    AUDIO_PKT_NOR 
    ,output logic [11:0]    AUDIO_PKT_MIN 
    ,output logic           AUDIO_RX_DVAL_O
    ,output logic [7:0]     AUDIO_RX_DATA_O
);


//========================================================================================
// 1. PCM 数据格式对齐与同步标识
//========================================================================================
//正常 有数据时
logic sync_flag;
// 保证 FIFO 总是从0声道(I_ADDR == 0)开始接收第一笔数据，防止声道错位
always_ff @(posedge MCLK or posedge RESET) begin
    if (RESET) begin
        sync_flag <= 1'b0;
    end
    else if (async_fifo_rst) begin
        sync_flag <= 1'b0;
    end
    else if (I_WINC && (I_ADDR == 1'b0)) begin
        sync_flag <= 1'b1; // 捕获到0声道后拉高，允许后续数据写入
    end
end

logic fifo_wr_en;
assign fifo_wr_en = I_WINC & (sync_flag | (I_ADDR == '0)) & (!async_fifo_rst);

//PCM数据 重新转换 为USB数据
logic [31:0] aligned_data;
// 16bit 例: B1 B0 00 00    -> 00 00 B1 B0 
// 24bit 例: B2 B1 B0 00    -> 00 B2 B1 B0
// 32bit 例: B3 B2 B1 B0    -> B3 B2 B1 B0
always_comb begin
    unique case(DATA_BITS_I)
        8'd16:      aligned_data = {16'h00, I_DATA[15:0]};
        8'd24:      aligned_data = {8'h00 , I_DATA[31:8]};
        8'd32:      aligned_data = I_DATA[31:0];
        default:    aligned_data = I_DATA[31:0];
    endcase
end


//==========================================================================================
// 2. 特殊 隐式反馈与看门狗
//==========================================================================================
//特殊！ 某些情况下，主机变更为隐式反馈，必须提供00作为启动源。
logic lrck_d1, lrck_d2;
always_ff @(posedge MCLK or posedge RESET) begin
    if (RESET) begin
        {lrck_d2, lrck_d1} <= 2'b00;
    end
    else begin
        {lrck_d2, lrck_d1} <= {lrck_d1, EXT_LRCK};
    end
end
wire lrck_edge = lrck_d1 ^ lrck_d2; 

// 2. 看门狗：利用 LRCK 边沿检测 I_WINC 断流
logic [3:0] winc_watchdog;
logic       audio_loss;

always_ff @(posedge MCLK or posedge RESET) begin
    if (RESET) begin
        winc_watchdog <= 4'd0;
        audio_loss    <= 1'b1; 
    end
    else if (I_WINC) begin
        winc_watchdog <= 4'd0;
        audio_loss    <= 1'b0; // 有效写使能，判定为正常
    end
    else if (lrck_edge) begin
        if (winc_watchdog < 4'd4) begin
            winc_watchdog <= winc_watchdog + 1'b1;
        end
        else begin
            audio_loss <= 1'b1;
        end
    end
end



//========================================================================================
// 3. 多通道宽位 Frame 拼装逻辑 (CH_NUM 自适应)
//========================================================================================
logic                   frame_wr_en;
logic [CH_NUM*32-1:0]   frame_wr_data;

always_ff @(posedge MCLK or posedge RESET) begin
    if (RESET) begin
        frame_wr_en   <= 1'b0;
        frame_wr_data <= '0;
    end
    else if (audio_loss) begin
        // 隐式反馈断流状态：在 LRCK 边沿塞入一整个 Frame 的 0 维持 USB 同步
        if (lrck_edge && !async_fifo_rst) begin
            frame_wr_data <= '0;
            frame_wr_en   <= 1'b1;
        end else begin
            frame_wr_en   <= 1'b0;
        end
    end
    else begin
        // 正常状态：拼装当前通道
        if (fifo_wr_en) begin
            frame_wr_data[I_ADDR * 32 +: 32] <= aligned_data;
            // 当前为最后一个通道时，触发完整 Frame 写入
            if (I_ADDR == (CH_NUM - 1)) begin
                frame_wr_en <= 1'b1;
            end else begin
                frame_wr_en <= 1'b0;
            end
        end else begin
            frame_wr_en <= 1'b0;
        end
    end
end
//==============================================================
// 4. Async FIFO 跨时钟域 (CH_NUM * 32宽)
//==============================================================
logic  [CH_NUM*32-1:0]  fifo_rd_data;
logic                   fifo_rd;
logic                   fifo_empty;

async_fifo #(
       .DSIZE  (CH_NUM * 32 )
      ,.ASIZE  (4           )
      ,.AEMPT  (1           )
      ,.AFULL  (10          )
) async_fifo (
       .WrClock    (MCLK            )
      ,.WPReset    (RESET           )
      ,.WrEn       (frame_wr_en     ) 
      ,.Data       (frame_wr_data   ) 
      ,.WrDataNum  (                )
      ,.AlmostFull (                )
      ,.Full       (                )
      ,.RdClock    (PHY_CLKOUT      )
      ,.RPReset    (RESET           )
      ,.RdEn       (fifo_rd         )
      ,.Q          (fifo_rd_data    )
      ,.RdDataNum  (                )
      ,.AlmostEmpty(                )
      ,.Empty      (fifo_empty      )
);

//==============================================================
// 5. 后端 Wide Frame -> 8-bit USB 拆包逻辑 (多通道轮询)
//==============================================================
typedef enum logic [1:0] {
    IDLE    ,
    D_SAVE  ,
    NEXT_CH 
} state_t;
state_t state;

logic [7:0]                 bit_cnt;
logic                       tx_fifo_wr;
logic [31:0]                tx_fifo_wr_data;

logic [CH_NUM*32-1:0]       tx_frame_data;
logic [$clog2(CH_NUM):0]    out_ch_cnt;
always_ff @(posedge PHY_CLKOUT or posedge RESET) begin
    if (RESET) begin
        tx_fifo_wr      <= 1'b0;
        tx_fifo_wr_data <= 32'd0;
        bit_cnt         <= 8'd0;
        state           <= IDLE;
        fifo_rd         <= 1'b0;
        out_ch_cnt      <= '0;
        tx_frame_data   <= '0;
    end
    else begin
        unique case (state)
        IDLE: begin
            if ((!fifo_rd)&(!fifo_empty)) begin
                fifo_rd         <= 1'b1;
                tx_fifo_wr      <= 1'b1;

                tx_fifo_wr_data <= fifo_rd_data[31:0];
                tx_frame_data   <= fifo_rd_data;
                bit_cnt         <= 8'd8;
                out_ch_cnt      <= '0;
                state           <= D_SAVE;
            end
            else begin
                fifo_rd         <= 1'b0;
                tx_fifo_wr      <= 1'b0;
                tx_fifo_wr_data <= 32'd0;
                bit_cnt         <= 8'd0;
                state           <= IDLE;
            end
        end
        D_SAVE: begin
            fifo_rd             <= 1'b0; 
            if (bit_cnt >= DATA_BITS_I) begin
                tx_fifo_wr      <= 1'b0;
                bit_cnt         <= 8'd0;

                // 判断是否发送完最后一个通道
                if (out_ch_cnt == (CH_NUM - 1)) begin
                    state      <= IDLE;
                end else begin
                    state      <= NEXT_CH;
                    out_ch_cnt <= out_ch_cnt + 1'b1;
                end
            end
            else begin
                tx_fifo_wr      <= 1'b1;
                tx_fifo_wr_data <= {8'd0,tx_fifo_wr_data[31:8]};
                bit_cnt         <= bit_cnt + 8'd8;
            end
        end
        NEXT_CH: begin
            // 提取下一个通道的数据
            tx_fifo_wr      <= 1'b1;
            tx_fifo_wr_data <= tx_frame_data[out_ch_cnt * 32 +: 32];
            bit_cnt         <= 8'd8;
            state           <= D_SAVE;
        end
        default: state <= IDLE;
        endcase
    end
end

//==============================================================
// 6. 包大小计算逻辑
//==============================================================
logic   [11:0]  s_sample_freq;
always_ff @(posedge PHY_CLKOUT or posedge RESET) begin
    if (RESET) begin
        s_sample_freq <= 12'd48;
    end 
    else begin
        unique case (SAMPLE_FREQ_I)
            SAMPLE_RATE_768:   s_sample_freq <= 12'd768;
            SAMPLE_RATE_705_6: s_sample_freq <= 12'd704;
            SAMPLE_RATE_384:   s_sample_freq <= 12'd384;
            SAMPLE_RATE_352_8: s_sample_freq <= 12'd352;
            SAMPLE_RATE_192:   s_sample_freq <= 12'd192;
            SAMPLE_RATE_176_4: s_sample_freq <= 12'd176;
            SAMPLE_RATE_128:   s_sample_freq <= 12'd128;
            SAMPLE_RATE_96:    s_sample_freq <= 12'd96;
            SAMPLE_RATE_88_2:  s_sample_freq <= 12'd88;
            SAMPLE_RATE_64:    s_sample_freq <= 12'd64;
            SAMPLE_RATE_48:    s_sample_freq <= 12'd48;
            SAMPLE_RATE_44_1:  s_sample_freq <= 12'd40; // HS 下必须是 40 (5个点)
            SAMPLE_RATE_32:    s_sample_freq <= 12'd32;
            default:           s_sample_freq <= 12'd48;
        endcase
    end
end

//===================================包大小=============================
// 每通道字节数
logic [11:0] bytes_per_ch;
always_comb begin
    unique case (DATA_BITS_I)
        8'd16:   bytes_per_ch = 12'd2;
        8'd24:   bytes_per_ch = 12'd3;
        8'd32:   bytes_per_ch = 12'd4;
        default: bytes_per_ch = 12'd4;
    endcase
end

//基准包
logic   [11:0] next_nor;
always_comb begin
    // UAC20 High Speed (125us microframes)
    // 计算公式： (频率/8) * 通道数 * 每通道字节数
    next_nor = (s_sample_freq >> 3) * CH_NUM * bytes_per_ch;
end

//偏移包
wire    [11:0] audio_packet_offset = CH_NUM * bytes_per_ch;
//======================================================================

always_ff @(posedge PHY_CLKOUT or posedge RESET) begin
    if (RESET) begin
        AUDIO_PKT_MAX <= 12'd0;
        AUDIO_PKT_NOR <= 12'd0;
        AUDIO_PKT_MIN <= 12'd0;
    end 
    else begin
        AUDIO_PKT_MAX <= next_nor + audio_packet_offset;
        AUDIO_PKT_NOR <= next_nor;
        AUDIO_PKT_MIN <= next_nor - audio_packet_offset;
    end
end


assign AUDIO_RX_DVAL_O = tx_fifo_wr;
assign AUDIO_RX_DATA_O = tx_fifo_wr_data[7:0];

endmodule