
module speaker_feedback(
     input             PHY_CLKOUT         
    ,input             RESET              

    ,input             XMCLK     
     
    ,input             I_USB_SOF          
    ,input             I_USB_TXACT        
    ,input  [3:0]      I_USB_ENDPT_SEL    
    ,input             I_USB_TXPOP        
    ,input  [31:0]     I_SAMPLE_RATE
//===================feedback======================= 
    ,input             I_FIFO_ALEMPTY     
    ,input             I_FIFO_ALFULL     

    ,output wire [7:0] O_FEEDBACK           

);
parameter  AUDIO_SPEAKER_ENDPOINT   = 8'h02;


wire        usb_txact;
wire [ 3:0] endpt_sel;
wire        usb_txpop;
wire        usb_sof;
wire        fifo_r_alempty;
wire        fifo_r_alfull;


assign usb_sof          = I_USB_SOF;
assign usb_txact        = I_USB_TXACT;
assign endpt_sel        = I_USB_ENDPT_SEL;
assign usb_txpop        = I_USB_TXPOP;

assign fifo_r_alempty   = I_FIFO_ALEMPTY;
assign fifo_r_alfull    = I_FIFO_ALFULL;

//==============================================================
//======Feedback Endpoint

reg  [31:0] ff_value;
reg  [31:0] ff_cnt;
reg  [ 3:0] div3_cnt;
reg         uac_en;
//=======================================================================================
reg  [31:0] sample_rate_cur;
always@(posedge XMCLK or posedge RESET) begin
    if (RESET)      sample_rate_cur <=  SAMPLE_RATE_48;
    else            sample_rate_cur <=  I_SAMPLE_RATE;
end


//SOF_rise
    // -----------------------------------------------------
    // 【audio pll模式】 展宽再打拍
    // -----------------------------------------------------
    reg  [11:0] usb_sof_dly;
    reg         uac_sof;

    always @(posedge PHY_CLKOUT or posedge RESET) begin
        if (RESET) begin
            usb_sof_dly <= 12'd0;
            uac_sof     <= 1'b0;
        end else begin
            if (I_USB_SOF) begin
                usb_sof_dly <= 12'hFFF;
                uac_sof     <= 1'b1;
            end else if (usb_sof_dly <= 12'd100) begin
                uac_sof     <= 1'b0;
            end else begin
                usb_sof_dly <= usb_sof_dly - 1'b1;
            end
        end
    end

    reg  sof_d0, sof_d1;
    wire sof_rise = sof_d0 & (~sof_d1);

    always @(posedge XMCLK or posedge RESET) begin    
        if (RESET) begin
            sof_d0 <= 1'b0;
            sof_d1 <= 1'b0;
        end else begin
            sof_d0 <= uac_sof;
            sof_d1 <= sof_d0;
        end
    end
//=======================================================================================



//-------------------------------------------------------------
//Comment:Audio Feedback Endpoint
//-------------------------------------------------------------
//98.304M/2 = 49.152
//Sample Rate 48  96  192 384 768
//K           13  13  13  13  13
//P           10  9   8   7   6
//P`          11  10  9   8   7
//2^(K-P)     8   16  32  60  128
//98.304M/3 = 32.768
//Sample Rate 32  64  128
//K           13  13  13
//P           10  9   8
//K-P         3   4   5
//2^(K-P)     8   16  32
//90.3168M/2 = 45.1584
//Sample Rate 44.1 88.2 178.4 352.8 705.6
//K           13   13   13    13    13
//P           10   9    8     7     6
//K-P         3    4    5     6     7
//2^(K-P)     8    16   32    60    128
//==============================================================
//=====
wire [ 7:0] ff_period;

//统计周期。采样率越高，需要越长的周期 抓更多的样本 作平均运算 → 保证“每微帧理论采样数”精准。125μs * N
//原设计中768khz 需要16ms 才能更新一次 ，响应过长
//计划修改成 2ms 最多，依靠FIFO水位作调整，抵消小数部分影响

assign  ff_period = (sample_rate_cur == SAMPLE_RATE_768   ) ? 8'd128 :
                    (sample_rate_cur == SAMPLE_RATE_705_6 ) ? 8'd128 :
                    (sample_rate_cur == SAMPLE_RATE_384   ) ? 8'd64  :
                    (sample_rate_cur == SAMPLE_RATE_352_8 ) ? 8'd64  :
                    (sample_rate_cur == SAMPLE_RATE_192   ) ? 8'd32  :
                    (sample_rate_cur == SAMPLE_RATE_176_4 ) ? 8'd32  :
                    (sample_rate_cur == SAMPLE_RATE_96    ) ? 8'd16  :
                    (sample_rate_cur == SAMPLE_RATE_88_2  ) ? 8'd16  :
                    (sample_rate_cur == SAMPLE_RATE_128   ) ? 8'd32  :
                    (sample_rate_cur == SAMPLE_RATE_64    ) ? 8'd16  :
                    (sample_rate_cur == SAMPLE_RATE_48    ) ? 8'd8   :
                    (sample_rate_cur == SAMPLE_RATE_44_1  ) ? 8'd8   : 8'd8;
// assign  ff_period = (sample_rate_cur == SAMPLE_RATE_768   ) ? 8'd16 : // 从 128 降到 16
//                     (sample_rate_cur == SAMPLE_RATE_705_6 ) ? 8'd16 :
//                     (sample_rate_cur == SAMPLE_RATE_384   ) ? 8'd16 : // 从 64 降到 16
//                     (sample_rate_cur == SAMPLE_RATE_352_8 ) ? 8'd16 :
//                     (sample_rate_cur == SAMPLE_RATE_192   ) ? 8'd16 : // 从 32 降到 16
//                     (sample_rate_cur == SAMPLE_RATE_176_4 ) ? 8'd16 :
//                     (sample_rate_cur == SAMPLE_RATE_96    ) ? 8'd16 :
//                     (sample_rate_cur == SAMPLE_RATE_88_2  ) ? 8'd16 :
//                     (sample_rate_cur == SAMPLE_RATE_128   ) ? 8'd16 :
//                     (sample_rate_cur == SAMPLE_RATE_64    ) ? 8'd16 :
//                     (sample_rate_cur == SAMPLE_RATE_48    ) ? 8'd8  : // 保持 8
//                     (sample_rate_cur == SAMPLE_RATE_44_1  ) ? 8'd8  : 8'd8;

//偏移值，目标是
reg [3:0] norm_shift;
always_comb begin
    case (sample_rate_cur)
        // 周期均为 16，但采样率不同，通过不同的移位权重归一化到 16.16 格式
        SAMPLE_RATE_768, SAMPLE_RATE_705_6: norm_shift = 4'd6; // 替代原来的硬编码 3，多移 3 位
        SAMPLE_RATE_384, SAMPLE_RATE_352_8: norm_shift = 4'd5; 
        SAMPLE_RATE_192, SAMPLE_RATE_176_4: norm_shift = 4'd4; 
        SAMPLE_RATE_96,  SAMPLE_RATE_88_2:  norm_shift = 4'd3; 
        SAMPLE_RATE_48,  SAMPLE_RATE_44_1:  norm_shift = 4'd3; // period=8, 维持原有的左移 3 位
        default:                            norm_shift = 4'd3;
    endcase
end




//==============================================================
//====== NO_PLL 模式：标称理论值查找表 (完全跳过时钟计数)
//==============================================================
reg [31:0] ff_nominal;
always @(*) begin
    // UAC 2.0 高速 16.16 格式 (每 125us 的采样数 * 2^16)
    case (sample_rate_cur)
        SAMPLE_RATE_44_1:  ff_nominal = 32'h0005_8333; // 5.5125
        SAMPLE_RATE_48:    ff_nominal = 32'h0006_0000; // 6.0
        SAMPLE_RATE_88_2:  ff_nominal = 32'h000B_0666; // 11.025
        SAMPLE_RATE_96:    ff_nominal = 32'h000C_0000; // 12.0
        SAMPLE_RATE_176_4: ff_nominal = 32'h0016_0CCC; // 22.05
        SAMPLE_RATE_192:   ff_nominal = 32'h0018_0000; // 24.0
        SAMPLE_RATE_352_8: ff_nominal = 32'h002C_199A; // 44.1
        SAMPLE_RATE_384:   ff_nominal = 32'h0030_0000; // 48.0
        SAMPLE_RATE_705_6: ff_nominal = 32'h0058_3333; // 88.2
        SAMPLE_RATE_768:   ff_nominal = 32'h0060_0000; // 96.0
        default:           ff_nominal = 32'h0006_0000;
    endcase
end
//==============================================================
reg  [31:0] ff_cnt;
//==============================================================
//====== 反馈系数运算 
//==============================================================
// 【audio_pll模式】
reg [7:0]   sof_cnt;
always@(posedge XMCLK or posedge RESET) begin  
    if (RESET) begin
        ff_cnt      <= 32'd0;
        sof_cnt     <= 8'd0;
        ff_value    <= 32'd0;
        uac_en      <= 1'b0;
    end
    else begin
        if (sof_rise) begin
            if (uac_en) begin
                if (sof_cnt >= ff_period - 1'b1) begin
                    sof_cnt <= 8'd0;
                    if (fifo_r_alempty) begin
                        ff_value <= ff_cnt + (ff_cnt>>11) ; // 根据FIFO空满情况 得出 的偏转值
                        // ff_value <= ff_cnt + 'h800 ; // 根据FIFO空满情况 得出 的偏转值
                    end
                    else if (fifo_r_alfull) begin 
                        ff_value <= ff_cnt - (ff_cnt>>11);
                    end
                    else begin 
                        ff_value <= ff_cnt ;
                    end
                    ff_cnt <=  32'd1;
                end
                else begin 
                    sof_cnt <= sof_cnt + 1'b1; 
                    ff_cnt  <= ff_cnt + 32'd1;
                end
            end
            else begin
                uac_en <= 1'b1;
            end
        end
        else begin
            if (uac_en) begin
                ff_cnt <= ff_cnt + 32'd1;
            end
        end
    end
end

//===========================中间变量，仅用作提高可读性======================================
wire [31:0] ff_formatted;
// TRUE_PLL 模式：ff_value 是原始计数值，在这里进行统一移位对齐
//UAC 20
assign ff_formatted = {4'b0000, ff_value[24:0], 3'b000};
// assign ff_formatted = (ff_value << norm_shift);


//==============================================================
//====== 最终IO输出 
//==============================================================
//16.16
reg  [31:0] feedback;
always@(posedge PHY_CLKOUT, posedge RESET) begin
    if (RESET) begin
        feedback <= 32'd0;
    end
    else begin
        if (usb_txact&(endpt_sel == AUDIO_SPEAKER_ENDPOINT[3:0])) begin
            if (usb_txpop) begin
                feedback <= {8'd0,feedback[31:8]};
            end
        end
        else begin
            feedback <= ff_formatted;
        end
    end
end
assign O_FEEDBACK       = feedback [7:0] ;

endmodule
