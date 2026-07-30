//===========================================
// Module: audio_usb2pcm
// Description: Receives 8-bit USB audio data, packs into 16/24/32-bit,
// writes to L/R Async FIFOs, and outputs 32-bit parallel data via MCLK & EXT_LRCK.
//===========================================
module audio_tx_usb2pcm #(
     parameter CH_NUM           = 2    // 必须为偶数，
    ,parameter SYNC_MODE        = 0 // 0: ASYNC    , 1: SYNC
    ,parameter USB_SPEED        = 1 // 0: FS       , 1: HS
    ,parameter SOF_TARGET_CLK0  = 17'd98304  // I_CLK_SEL = 0 时的 SOF 计数值 (98.304MHz / 1kHz)
    ,parameter SOF_TARGET_CLK1  = 17'd12288   // I_CLK_SEL = 1 时的 SOF 计数值 (12.288MHz / 1kHz)
) (
    // ====== USB Clock Domain ======
    input  logic        PHY_CLKOUT,     // USB Clock
    input  logic        RESET,          // Global Reset
    input  logic        MCLK,           // Audio Master Clock

    input  logic        I_SOF,          // Start of Frame

    // ====== Audio Control ======
    input  logic [31:0] I_SAMPLE_RATE   ,  
    input  logic [ 7:0] I_DATA_BITS     ,    
    input  logic        I_CLK_SEL       ,      

    input  logic        I_DSD_EN       ,   
    input  logic        I_DOP_EN       ,   
    // ====== Output Status ======
    output logic        O_TX_EN,
    output logic [ 7:0] O_BCLK_DIV      ,
    output logic        O_FIFO_ALEMPTY  ,//目标时钟域是mclk 
    output logic        O_FIFO_ALFULL   ,  

    // ======External Audio clk======
    input  logic        EXT_LRCK,       // External Frame Sync Clock
    
    // ====== USB EP Input ======
    input  logic        I_AUDIO_DVAL,   // USB Data Valid
    input  logic [ 7:0] I_AUDIO_DATA,   // USB Data Input
    // ====== Parallel Output ======
    output logic [$clog2(CH_NUM)-1:0]   O_ADDR,         // 0: Left, 1: Right
    output logic [31:0]                 O_DATA,      
    output logic                        O_WINC          // Parallel Data Write Enable (1 MCLK pulse)
);

parameter  FIFO_ASIZE = 11 ;


wire    dop_en    ,   dsd_en;
assign dsd_en           = I_DSD_EN;
assign dop_en           = I_DOP_EN;


//==============================================================
// 0. 异步复位同步释放，打牌保证数据稳定
//==============================================================
logic rst_phy_r1, rst_phy_sync;
logic rst_mclk_r1, rst_mclk_sync;
// PHY_CLKOUT RESET
always_ff @(posedge PHY_CLKOUT or posedge RESET) begin
    if (RESET) begin
        rst_phy_r1   <= 1'b1;
        rst_phy_sync <= 1'b1;
    end else begin
        rst_phy_r1   <= 1'b0;
        rst_phy_sync <= rst_phy_r1;
    end
end

// MCLK RESET
always_ff @(posedge MCLK or posedge RESET) begin
    if (RESET) begin
        rst_mclk_r1   <= 1'b1;
        rst_mclk_sync <= 1'b1;
    end else begin
        rst_mclk_r1   <= 1'b0;
        rst_mclk_sync <= rst_mclk_r1;
    end
end

logic [ 5:0] tx_dval_r;
logic [ 7:0] tx_data_r [0:5];
always_ff @(posedge PHY_CLKOUT or posedge rst_phy_sync) begin
    if (rst_phy_sync) begin
        tx_dval_r <= 6'b0;
        for (int i=0; i<6; i++) tx_data_r[i] <= 8'h00;
    end else begin
        tx_dval_r    <= {tx_dval_r[4:0], I_AUDIO_DVAL};
        tx_data_r[0] <= I_AUDIO_DATA;
        for (int i=1; i<6; i++) tx_data_r[i] <= tx_data_r[i-1];
    end
end
logic       tx_dval_in;
logic [7:0] tx_data_in;
assign tx_dval_in = tx_dval_r[5];
assign tx_data_in = tx_data_r[5];

logic   dsd_enable;
assign  dsd_enable = (dsd_en|dop_en) & tx_en;        

//==============================================================
// 1. USB OUT 端，将N个通道 拼装为 N*32 宽数据
//==============================================================
logic [2:0] byte_threshold;
assign byte_threshold = (I_DATA_BITS == 8'd16) ? 3'd1 : 
                        (I_DATA_BITS == 8'd24) ? 3'd2 : 3'd3; // 32bit

logic                       fifo_wr         ;
logic [CH_NUM*32-1:0]       frame_wr_data   ;
logic [$clog2(CH_NUM)-1:0]  wr_ch_cnt       ;
logic [3:0]                 byte_cnt        ;

//默认 Left_en、right_en均为1
always_ff @(posedge PHY_CLKOUT or posedge rst_phy_sync) begin
    if (rst_phy_sync) begin
        fifo_wr         <= 1'b0;
        frame_wr_data   <= '0;
        byte_cnt        <= 4'd0;
        wr_ch_cnt       <= '0;
    end 
    else if (tx_dval_in) begin
        fifo_wr         <= 1'b0;

        if (byte_cnt == byte_threshold) begin // 当前通道拼装完毕
            byte_cnt <= 4'd0;
            //===统一处理===
                // 16bit: [B1] [B0] [00] [00] 
                // 24bit: [B2] [B1] [B0] [00] 
                // 32bit: [B3] [B2] [B1] [B0]
            frame_wr_data[wr_ch_cnt*32 +: 32] <= {tx_data_in, frame_wr_data[wr_ch_cnt*32 + 8 +: 24]};

            if (wr_ch_cnt == (CH_NUM - 1)) begin
                // 所有通道均收集完毕，触发一次超大位宽写入
                fifo_wr   <= 1'b1;
                wr_ch_cnt <= '0;
            end 
            else begin
                wr_ch_cnt <= wr_ch_cnt + 1'b1;
            end
        end 
        else begin  // 当前通道 进行拼装
            // 移位拼装当前通道字节
            frame_wr_data[wr_ch_cnt*32 +: 32] <= (byte_cnt == 0) ?  {tx_data_in, 24'd0} : 
                                                                    {tx_data_in, frame_wr_data[wr_ch_cnt*32 + 8 +: 24]};;
            byte_cnt <= byte_cnt + 1'b1;
        end
    end
    else begin
        fifo_wr         <= 1'b0;
    end
end


//========================================================================================================
// 2. 超宽FRAME 数据跨时钟 PHY_CLKOUT → MCLK
//========================================================================================================
logic                       fifo_rd_req     ;
logic [CH_NUM*32-1:0]       fifo_rd_data    ;
logic [FIFO_ASIZE:0]        fifo_rdnum      ;   //针对 2通道 32bit 768khz,一次写入768包。稳定1.5包 → 1152[10:0] 
                                                //此时 8通道 32bit 192khz, 下降至96*1.5
                                                //采样率不要求这么高可以适量降低
logic                       fifo_empty      ;

async_fifo #(
       .DSIZE  (CH_NUM * 32) // 通道自适应
      ,.ASIZE  (FIFO_ASIZE  )
      ,.AEMPT  (10  )
      ,.AFULL  (64  )
) fifo_main (
       .WrClock    (PHY_CLKOUT      )
      ,.WPReset    (rst_phy_sync    )
      ,.WrEn       (fifo_wr         )
      ,.Data       (frame_wr_data   )
      ,.WrDataNum  (                )
      ,.AlmostFull (                )
      ,.Full       (                )
      ,.RdClock    (MCLK            )
      ,.RPReset    (rst_mclk_sync   )
      ,.RdEn       (fifo_rd_req     )
      ,.Q          (fifo_rd_data    )
      ,.RdDataNum  (fifo_rdnum      )
      ,.AlmostEmpty(                )
      ,.Empty      (fifo_empty      )
);


//========================================================================================================
// 3. 水池预缓存 + bclk_div 处理
//========================================================================================================
//=================== TX_EN = SOF + 水池 ===================
logic [1:0] sof_r;
always_ff @(posedge MCLK or posedge rst_mclk_sync) begin
    if (rst_mclk_sync) sof_r <= 2'b0;
    else       sof_r <= {sof_r[0], I_SOF};
end
logic sof_rise;
assign sof_rise = (sof_r == 2'b01);

logic [FIFO_ASIZE:0] prebuffer_threshold;
logic [11:0] s_sample_freq;
always_ff @(posedge MCLK or posedge rst_mclk_sync) begin
    if (rst_mclk_sync) begin
        prebuffer_threshold <= 12'd48; // 1ms
    end 
    else begin
        prebuffer_threshold <= (s_sample_freq);
    end
end

logic        prebuffer_rdy;
always_ff @(posedge MCLK or posedge rst_mclk_sync) begin
    if (rst_mclk_sync) begin
        prebuffer_rdy <= 1'b0;
    end else begin
        if (fifo_empty) begin
            prebuffer_rdy <= 1'b0;
        end else if (fifo_rdnum > prebuffer_threshold) begin
            prebuffer_rdy <= 1'b1;
        end
    end
end

logic        tx_en;
always_ff @(posedge MCLK or posedge rst_mclk_sync) begin
    if (rst_mclk_sync) begin
        tx_en <= 1'b0;
    end 
    else begin
        if (!prebuffer_rdy) begin
            tx_en <= 1'b0;
        end 
        else if (prebuffer_rdy && sof_rise) begin
            tx_en <= 1'b1;
        end
    end
end
//=============================================

logic [FIFO_ASIZE:0]    empty_thr      , full_thr      ;
logic                   fifo_alempty   , fifo_alfull   ;

//ASIZE = 11
assign empty_thr        = s_sample_freq[11:0] +  (s_sample_freq[11:0]>>1)    ; //1.5数据帧
assign full_thr         = s_sample_freq[11:0] << 1 ;
assign fifo_alempty     = (fifo_rdnum <= empty_thr);
assign fifo_alfull      = (fifo_rdnum >  full_thr);

logic       fifo_alfull_d, fifo_alempty_d;
always_ff @(posedge MCLK or posedge rst_mclk_sync) begin
    if (rst_mclk_sync) begin
        fifo_alfull_d   <= 1'b0;
        fifo_alempty_d  <= 1'b0;
    end else begin
        fifo_alfull_d   <= fifo_alfull ;
        fifo_alempty_d  <= fifo_alempty ;
    end
end
//================================================
//=============== BCLK_DIV =======================
logic [16:0] sof_cnt, sof_target, sof_tolerance;
logic        sof_long, sof_short;

always_ff @(posedge MCLK or posedge rst_mclk_sync) begin
    if (rst_mclk_sync) begin
        sof_target    <= 17'd12288;
        sof_tolerance <= 17'd16;
    end else begin
        if (I_CLK_SEL) begin 
            sof_target    <= SOF_TARGET_CLK1;
            sof_tolerance <= 17'd1;
        end else begin         
            sof_target    <= SOF_TARGET_CLK0; 
            sof_tolerance <= 17'd8; 
        end
    end
end
always_ff @(posedge MCLK or posedge rst_mclk_sync) begin
    if (rst_mclk_sync) begin
        sof_cnt   <= 17'b0;
        sof_long  <= 1'b0;
        sof_short <= 1'b0;
    end else if (sof_rise) begin
        if (sof_cnt >= (sof_target + sof_tolerance)) begin
            sof_long  <= 1'b1; sof_short <= 1'b0;
        end else if (sof_cnt < (sof_target - sof_tolerance)) begin
            sof_long  <= 1'b0; sof_short <= 1'b1;
        end else begin
            sof_long  <= 1'b0; sof_short <= 1'b0;
        end
        sof_cnt <= 17'b0; 
    end else begin
        sof_cnt <= sof_cnt + 17'd1;
    end
end

logic [7:0] s_bclk_div, s_bclk_div_0;
always_ff @(posedge MCLK or posedge rst_mclk_sync) begin
    if (rst_mclk_sync) begin
        s_sample_freq <= 12'd48;
        s_bclk_div    <= 8'd32;
        s_bclk_div_0  <= 8'd32;
    end else begin
        case (I_SAMPLE_RATE)
            SAMPLE_RATE_768:   begin s_sample_freq <= 12'd768; s_bclk_div_0 <= 8'd2;  end
            SAMPLE_RATE_384:   begin s_sample_freq <= 12'd384; s_bclk_div_0 <= 8'd4;  end
            SAMPLE_RATE_192:   begin s_sample_freq <= 12'd192; s_bclk_div_0 <= 8'd8;  end
            SAMPLE_RATE_96:    begin s_sample_freq <= 12'd96;  s_bclk_div_0 <= 8'd16; end
            SAMPLE_RATE_48:    begin s_sample_freq <= 12'd48;  s_bclk_div_0 <= 8'd32; end
            SAMPLE_RATE_128:   begin s_sample_freq <= 12'd128; s_bclk_div_0 <= 8'd12; end
            SAMPLE_RATE_64:    begin s_sample_freq <= 12'd64;  s_bclk_div_0 <= 8'd24; end
            SAMPLE_RATE_32:    begin s_sample_freq <= 12'd32;  s_bclk_div_0 <= 8'd48; end
            SAMPLE_RATE_705_6: begin s_sample_freq <= 12'd705; s_bclk_div_0 <= 8'd2;  end
            SAMPLE_RATE_352_8: begin s_sample_freq <= 12'd352; s_bclk_div_0 <= 8'd4;  end
            SAMPLE_RATE_176_4: begin s_sample_freq <= 12'd176; s_bclk_div_0 <= 8'd8;  end
            SAMPLE_RATE_88_2:  begin s_sample_freq <= 12'd88;  s_bclk_div_0 <= 8'd16; end
            SAMPLE_RATE_44_1:  begin s_sample_freq <= 12'd44;  s_bclk_div_0 <= 8'd32; end
            default:           begin s_sample_freq <= 12'd48;  s_bclk_div_0 <= 8'd32; end
        endcase

        if (SYNC_MODE) begin
            if (fifo_alfull_d && sof_short)         s_bclk_div <= s_bclk_div_0 - 8'd1;
            else if (fifo_alempty_d && sof_long)    s_bclk_div <= s_bclk_div_0 + 8'd1;
            else                                    s_bclk_div <= s_bclk_div_0;
        end else begin
            s_bclk_div <= s_bclk_div_0;
        end
    end
end
//================================================


//============================================================================================================
// 4. FIFO 分发读取
//============================================================================================================
logic [2:0] lrck_sync;
logic [3:0] rd_req_pipe;

always_ff @(posedge MCLK or posedge rst_mclk_sync) begin
    if (rst_mclk_sync) begin
        lrck_sync   <= 3'b0;
        rd_req_pipe <= 4'b0;
    end else begin
        lrck_sync   <= {lrck_sync[1:0], EXT_LRCK};
        // 上升沿提前缓存下一周期 + 2拍 + 数据缓冲
        rd_req_pipe <= {rd_req_pipe[2:0], (lrck_sync[2:1] == 2'b01) & tx_en};
    end
end
assign fifo_rd_req = rd_req_pipe[0];

logic [31:0]            silence_pattern;
logic [CH_NUM*32-1:0]   safe_frame_data;
assign silence_pattern = dsd_enable ? 32'h96969696 : 32'h00000000;
assign safe_frame_data = fifo_empty ? {CH_NUM{silence_pattern}} : fifo_rd_data;

logic [CH_NUM*32-1:0]      dist_buffer; 
logic [$clog2(CH_NUM)-1:0] out_ch_cnt;
logic                      burst_busy;
always_ff @(posedge MCLK or posedge rst_mclk_sync) begin
    if (rst_mclk_sync) begin
        O_ADDR      <= 1'b0;
        O_DATA      <= 32'd0;
        O_WINC      <= 1'b0;
        out_ch_cnt  <= '0;
        burst_busy  <= 1'b0;
        dist_buffer <= '0;
    end 
    else begin
        O_WINC <= 1'b0;
        if (rd_req_pipe[2]) begin   //先传输 第0通道
            dist_buffer <= safe_frame_data;
            O_ADDR  <= '0; 
            O_DATA  <= safe_frame_data[31:0]; 
            O_WINC  <= 1'b1;
            if (CH_NUM > 1) begin
                out_ch_cnt <= 1'b1; // 
                burst_busy <= 1'b1; // 开始传输后续通道
            end
        end
        else if (burst_busy) begin //传输 1 ~ N-1通道
            O_ADDR  <= out_ch_cnt;
            O_DATA  <= dist_buffer[out_ch_cnt*32 +: 32]; // 从锁存的总线中截取32
            O_WINC  <= 1'b1;

            // 最后一个通道
            if (out_ch_cnt == (CH_NUM - 1))     burst_busy <= 1'b0; // 所有通道发送完毕，退出忙碌
            else                                out_ch_cnt <= out_ch_cnt + 1'b1;
        end

    end
end

assign O_FIFO_ALEMPTY   = fifo_alempty  ;
assign O_FIFO_ALFULL    = fifo_alfull   ;
assign O_BCLK_DIV       = s_bclk_div    ;

assign O_TX_EN          = tx_en;

endmodule