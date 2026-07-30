

module audio_tx_pcm2dsd#(
    parameter CH_NUM = 2
)(
     input  logic                      MCLK           // 音频主时钟
    ,input  logic                      RESET          // 全局复位

    //====== 控制信号
    ,input  logic                      I_ENABLE       // 全局使能 
    ,input  logic [ 7:0]               I_DATA_BITS    
    ,input  logic                      I_DOP_EN       
    ,input  logic [ 7:0]               I_BCLK_DIV

    //====== 同步音频数据接收接口 (来自 usb2pcm_new)
    ,input  logic [$clog2(CH_NUM)-1:0] I_ADDR         // 通道地址 (0: Left, 1: Right)
    ,input  logic [31:0]               I_DATA         // 32-bit 同步数据
    ,input  logic                      I_WINC         // 脉冲写使能 (与 I_ADDR, I_DATA 同步)

    //====== DSD 输出
    ,output logic                      O_DSD_CLK      
    ,output logic                      O_DSD_DATA1    // Left DSD out
    ,output logic                      O_DSD_DATA2    // Right DSD out  
);

// 内部数据缓存寄存器
logic [31:0] l_data_reg;
logic [31:0] r_data_reg;
logic        dsd_sync; // 新增：内部帧同步脉冲,左右声道均更新数据后拉高


// 悬空 DSD 核心内部的读请求 (解耦外部时序)
logic        dsd_rd_req_nc; 

logic [ 7:0] dsd_data_bits;
logic [ 7:0] dsd_bclk_div;

//==============================================================
//====== 数据接收分离器 (Demultiplexer)
//==============================================================
// 直接在 I_WINC 有效的当前周期，根据 I_ADDR 路由并锁存 I_DATA
// 完美匹配同步对齐的握手时序，无需考虑以往的 2 拍延迟
always_ff @(posedge MCLK or posedge RESET) begin
    if (RESET) begin
        l_data_reg <= 32'd0;
        r_data_reg <= 32'd0;
        dsd_sync   <= 1'b0;
    end
    else begin
        dsd_sync   <= 1'b0;

        if (I_WINC) begin
            if (I_ADDR == 'd0) begin
                // l_data_reg <= I_DATA;
                // l_data_reg <= {I_DATA[7:0],I_DATA[15:8],I_DATA[23:16],I_DATA[31:24]};
                l_data_reg <= I_DOP_EN ? {I_DATA[15:8], I_DATA[23:16], 16'd0} : 
                                         {I_DATA[7:0], I_DATA[15:8], I_DATA[23:16], I_DATA[31:24]};
            end 
            else if (I_ADDR == 'd1) begin
                // r_data_reg <= I_DATA;
                // r_data_reg <= {I_DATA[7:0],I_DATA[15:8],I_DATA[23:16],I_DATA[31:24]};
                r_data_reg <= I_DOP_EN ? {I_DATA[15:8], I_DATA[23:16], 16'd0} : 
                                         {I_DATA[7:0], I_DATA[15:8], I_DATA[23:16], I_DATA[31:24]};
                dsd_sync   <= 1'b1;
            end
        end
    end
end

//==============================================================
//====== DSD 参数映射
//==============================================================
assign dsd_data_bits = I_DOP_EN ? 8'd16 : I_DATA_BITS;
assign dsd_bclk_div  = I_DOP_EN ? {I_BCLK_DIV[5:0], 2'b00} : {I_BCLK_DIV[6:0], 1'b0};

//==============================================================
//====== DSD Core 例化
//==============================================================
dsd dsd_inst (
     .CLK         (MCLK         )
    ,.RESET       (RESET        )
    ,.ENABLE      (I_ENABLE     )
    ,.DSD_MODE    (1'b1         ) //默认DSD标准模式 ：下降沿更新
    //新增，dsd作为从机被动接受数据更新
    ,.SYNC_I      (dsd_sync     ) // 新增：传入顶层提取的同步脉冲
// ,.DATA_REQ_O  (dsd_rd_req_nc) // 悬空该引脚
    ,.BCLK_DIV    (dsd_bclk_div )
    ,.DATA_BITS   (dsd_data_bits)
    ,.L_DATA_I    (l_data_reg   )
    ,.R_DATA_I    (r_data_reg   )

    ,.DSD_DATA1_O (O_DSD_DATA1  )
    ,.DSD_DATA2_O (O_DSD_DATA2  )
    ,.DSD_CLK_O   (O_DSD_CLK    )
);

endmodule


//============================================================
module dsd (
    input  logic        CLK          ,
    input  logic        RESET        ,
    input  logic        ENABLE       ,
    input  logic        SYNC_I       , // 外部数据就绪脉冲 (仅用于首次启动对齐)
    input  logic        DSD_MODE     ,
    input  logic [ 7:0] BCLK_DIV     ,
    input  logic [ 7:0] DATA_BITS    ,
    input  logic [31:0] L_DATA_I     , // 来自顶层的左声道影子寄存器
    input  logic [31:0] R_DATA_I     , // 来自顶层的右声道影子寄存器
    output logic        DSD_DATA1_O  ,
    output logic        DSD_DATA2_O  ,
    output logic        DSD_CLK_O
);

logic [ 7:0] s_bclk_div;
logic [ 7:0] s_data_bits;
logic [31:0] l_data_d1;
logic [31:0] r_data_d1;
logic [15:0] clk_cnt;
logic        bclk;
logic        bclk_rise;
logic        bclk_fall;
logic        clk_cnt_max;
logic [15:0] bclk_cnt;

logic        is_running; // 核心自运行标志

//==============================================================
//====== 1. 启动控制与首次数据加载
//==============================================================
always_ff @(posedge CLK or posedge RESET) begin
    if (RESET) begin
        is_running  <= 1'b0;
        s_bclk_div  <= 8'd4;
        s_data_bits <= 8'd32;
        l_data_d1   <= 32'd0;
        r_data_d1   <= 32'd0;
        bclk_cnt    <= 16'd0;
    end
    else if (ENABLE) begin
        // 核心等待直到收到第一笔数据
        if (!is_running && SYNC_I) begin
            is_running  <= 1'b1;
            s_bclk_div  <= BCLK_DIV;
            s_data_bits <= DATA_BITS;
            // 立即加载第一帧数据，等待移位
            l_data_d1   <= L_DATA_I;
            r_data_d1   <= R_DATA_I;
            bclk_cnt    <= 16'd1; // 因为最高位立刻输出了，相当于已经消耗了1位
        end
        else if (is_running && bclk_fall) begin
            // 依赖内部纯净时钟的自然边界（数满 32 bit）来更新数据
            if (bclk_cnt >= s_data_bits) begin
                bclk_cnt  <= 16'd1;
                l_data_d1 <= L_DATA_I;
                r_data_d1 <= R_DATA_I;
            end
            else begin
                bclk_cnt  <= bclk_cnt + 16'd1;
                l_data_d1 <= {l_data_d1[30:0], 1'b0};
                r_data_d1 <= {r_data_d1[30:0], 1'b0};
            end
        end
    end
    else begin
        is_running <= 1'b0;
    end
end

//==============================================================
//====== 2. 自运行位时钟 DSD_CLK
//==============================================================
always_ff @(posedge CLK or posedge RESET) begin
    if (RESET) begin
        clk_cnt     <= 16'd0;
        bclk        <= 1'b0;
        clk_cnt_max <= 1'b0;
        bclk_rise   <= 1'b0;
        bclk_fall   <= 1'b0;
    end
    else if (is_running) begin
        if (clk_cnt_max) begin
            clk_cnt   <= 16'd0;
            bclk_fall <= 1'b1;
        end
        else begin
            clk_cnt   <= clk_cnt + 16'd1;
            bclk_fall <= 1'b0;
        end

        clk_cnt_max <= (clk_cnt == (s_bclk_div - 2'd2));
        bclk_rise   <= (clk_cnt == (s_bclk_div[7:1] - 1'b1));

        if (bclk_rise) bclk <= 1'b1;
        else if (bclk_fall) bclk <= 1'b0;
    end
    else begin
        clk_cnt     <= 16'd0;
        bclk        <= 1'b0;
    end
end

//==============================================================
//====== 3. 组合逻辑物理输出
//==============================================================
assign  DSD_DATA1_O = l_data_d1[31];
assign  DSD_DATA2_O = r_data_d1[31];
assign  DSD_CLK_O   = bclk;

endmodule