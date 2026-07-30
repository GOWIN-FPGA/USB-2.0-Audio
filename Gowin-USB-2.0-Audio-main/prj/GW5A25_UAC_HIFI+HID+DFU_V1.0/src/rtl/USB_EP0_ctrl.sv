
//===========================================
module USB_EP0_ctrl #(
     parameter CLOCK_SOURCE_ID       = 8'h05//Clock Source
    ,parameter FEATURE_UNIT_ID       = 8'h03//Audio Control Feature Unit
)
(
     input                  PHY_CLKOUT         //clock
    ,input                  RESET              //reset
    //USB Interface     
    ,input                  I_USB_SETUP        
    ,input  [3:0]           I_USB_ENDPT_SEL    
    ,input                  I_USB_RXPKTVAL              
    ,input                  I_USB_RXACT        
    ,input                  I_USB_RXVAL        
    ,input  [7:0]           I_USB_RXDAT        
    ,input                  I_USB_TXACT        
    ,input                  I_USB_TXPOP        

    ,input  [7:0]           I_INTERFACE_ALTER  
    ,output [7:0]           O_INTERFACE_ALTER  
    ,input  [7:0]           I_INTERFACE_SEL    
    ,input                  I_INTERFACE_UPDATE 
    //EP0 DATA
    ,output                 endpt0_send_0      
    ,output        [7:0]    endpt0_dat_0     
    ,output reg    [11:0]   usb_txdat_len_o

//UAC Audio Control     
    ,output                 O_MUTE             
    ,output [15:0]          O_CH0_VOLUME       
    ,output [15:0]          O_CH1_VOLUME       
    ,output [15:0]          O_CH2_VOLUME       
    ,output [31:0]          O_SAMPLE_RATE      
    ,output [ 7:0]          O_TX_DATA_BITS     
    ,output [ 7:0]          O_RX_DATA_BITS

    ,output                 O_DOP_EN
    ,output                 O_DSD_EN
// CDC Control
    ,output [31:0]          O_UART1_BAUD_RATE 
    ,output [7:0]           O_UART1_PARITY_BIT
    ,output [7:0]           O_UART1_STOP_BIT  
    ,output [7:0]           O_UART1_DATA_BITS
// DFU Control  
    ,input                  i_dfu_mode          // 重枚举后 进入 1：DFU_mode 0：APP_mode
    ,output                 o_dfu_detach_flag   // 接收DFU_DETACH指令
// EP0 DFU DATA     
    ,output reg             o_dfu_spi_wr_req    // 写请求
    ,input  wire            i_dfu_spi_wr_ack    // 写应答
    ,output reg             o_dfu_spi_wr_flush  // 强制刷写Flash 
    ,output reg  [31:0]     o_dfu_spi_lba       // 逻辑块地址 (512B为单位)
    ,input  wire [8:0]      i_dfu_spi_buf_addr  // Flash控制器给出的读地址
    ,output wire [7:0]      o_dfu_spi_buf_rdata // 输出给Flash控制器的数据
// UMS Control
    //nothing
);


typedef struct packed {
    logic [15:0] wLength;
    logic [15:0] wIndex;
    logic [15:0] wValue;
    logic [ 7:0] bRequest;
    logic [ 7:0] bmRequestType;
} usb_setup_pkt_t;

typedef enum logic [4:0] {
    CMD_IDLE,
//UAC
    CMD_SET_SAM_FREQ,
    CMD_GET_SAM_FREQ,
    CMD_GET_SAM_FREQ_RANGE, 
    CMD_SET_MUTE,
    CMD_GET_MUTE,
    CMD_SET_VOL,
    CMD_GET_VOL_CUR,
    CMD_GET_VOL_MAX,
    CMD_GET_VOL_MIN,
    CMD_GET_VOL_RES,
    CMD_GET_VOL_RANGE, 
    CMD_GET_CLK_VALID,
    CMD_GET_VAL_ALT_SET,
// UMS
    CMD_UMS_GET_MAX_LUN, //14
// CDC
    CMD_CDC_GET_LINE_CODING,
    CMD_CDC_SET_LINE_CODING,
// DFU
    CMD_DFU_DETACH,
    CMD_DFU_DNLOAD,
    CMD_DFU_GETSTATUS, //19
    CMD_DFU_CLRSTATUS
} uac_cmd_e;

// ============================================================================
// UAC Local Params
// ============================================================================
//==========================bmRequestType============================
localparam  GET_STAND_INTF         = 8'h81;
localparam  SET_STAND_INTF         = 8'h01;
localparam  GET_CLASS_INTF         = 8'hA1;
localparam  SET_CLASS_INTF         = 8'h21;
localparam  GET_CLASS_EP           = 8'hA2;
localparam  SET_CLASS_EP           = 8'h22;

localparam  SET_CUR                = 8'h01;
localparam  GET_CUR                = 8'h81;

//============================bRequest==================================
    //UAC1.1
localparam  SET_MIN                = 8'h02;
localparam  GET_MIN                = 8'h82;
localparam  SET_MAX                = 8'h03;
localparam  GET_MAX                = 8'h83;
localparam  SET_RES                = 8'h04;
localparam  GET_RES                = 8'h84;
    //UAC2.0
localparam  CUR                    = 8'h01;
localparam  RANGE                  = 8'h02;


//============================wValue====================================
localparam  CS_SAM_FREQ_CONTROL         = 8'h01;
localparam  CS_CLOCK_VALID_CONTROL      = 8'h02;
localparam  FU_MUTE_CONTROL             = 8'h01;
localparam  FU_VOLUME_CONTROL           = 8'h02;
localparam  CX_CLOCK_SELECTOR_CONTROL   = 8'h01;
localparam  AS_VAL_ALT_SETTINGS_CONTROL = 8'h02;

localparam  CN0                      = 8'h00;
localparam  CN1                      = 8'h01;
localparam  CN2                      = 8'h02;



// UAC 2.0 采样率配置
localparam int NUM_FREQS = 12;
localparam int LEN_FREQS = 12 * NUM_FREQS + 2 ;
localparam logic [31:0] SUPPORTED_FREQS [NUM_FREQS] = '{
    SAMPLE_RATE_44_1,  SAMPLE_RATE_48, 
    SAMPLE_RATE_64,    SAMPLE_RATE_88_2,  SAMPLE_RATE_96, 
    SAMPLE_RATE_128,   SAMPLE_RATE_176_4, SAMPLE_RATE_192, 
    SAMPLE_RATE_352_8, SAMPLE_RATE_384,   SAMPLE_RATE_705_6, 
    SAMPLE_RATE_768
};


localparam  VOLUME_NUM               = 16'h0001;
localparam  VOLUME_FS_MIN            = 16'hD200;
localparam  VOLUME_FS_MAX            = 16'h0000;
localparam  VOLUME_FS_RES            = 16'h0300;

localparam  VOLUME_HS_MAX            = 16'h0000;
localparam  VOLUME_HS_MIN            = 16'hC080;
localparam  VOLUME_HS_RES            = 16'h0080;


// ============================================================================
// UMS, CDC, DFU Local Params
// ============================================================================
localparam ENDPT_UART_CONFIG     = 4'h0;
localparam ENDPT_UMS_CONFIG      = 4'h0;
localparam UMS_INTERFACE_NUM     = 8'h03;
localparam CDC_INTERFACE_NUM     = 8'h04;

localparam GET_REQ               = 8'hA1;
localparam SET_REQ               = 8'h21;

// UMS
localparam GET_MAX_LUN           = 8'hfe;
// CDC
localparam SET_LINE_CODING       = 8'h20;
localparam GET_LINE_CODING       = 8'h21;
// DFU
localparam DFU_DETACH            = 8'h00;
localparam DFU_DNLOAD            = 8'h01;
localparam DFU_GETSTATUS         = 8'h03;
localparam DFU_CLRSTATUS         = 8'h04;

// DFU States (bState)
localparam APP_STATE_IDLE          = 8'd1; // appIDLE               APP状态 空闲
localparam DFU_STATE_IDLE          = 8'd2; // dfuIDLE               DFU状态 空闲
localparam DFU_STATE_DNLOAD_SYNC   = 8'd3; // dfuDNLOAD-SYNC        接收到数据包，等待主机GETSTATUS命令
localparam DFU_STATE_DNBUSY        = 8'd4; // dfuDNBUSY             接收到数据包，正在下载到flash中 
localparam DFU_STATE_DNLOAD_IDLE   = 8'd5; // dfuDNLOAD-IDLE        flash等待新的数据包
localparam DFU_STATE_MANIFEST_SYNC = 8'd6; // dfuMANIFEST-SYNC      文件完全传输，等待主机GETSTATUS命令
localparam DFU_STATE_MANIFEST      = 8'd7; // dfuMANIFEST           收尾工作，CDC/解密等操作


//==============================================================
//======USB Signals
wire        setup_active     = I_USB_SETUP;
wire [ 3:0] endpt_sel        = I_USB_ENDPT_SEL;
wire        usb_rxact        = I_USB_RXACT;
wire        usb_rxval        = I_USB_RXVAL;
wire [ 7:0] usb_rxdat        = I_USB_RXDAT;
wire        usb_txact        = I_USB_TXACT;
wire        usb_txpop        = I_USB_TXPOP;


reg  [7:0]  interface0_alter , interface1_alter , interface2_alter ;
reg         audio_rx_reset   , audio_tx_reset   ;


//==============================================================
//======USB Setup
reg     [ 7:0]  stage;
reg     [ 7:0]  sub_stage;
reg     [ 8:0]  sub2_stage; // For DFU 512B payload

logic           endpt0_send;
logic   [ 7:0]  endpt0_dat;

usb_setup_pkt_t setup_pkt;
uac_cmd_e       active_cmd;

logic [47:0] route_word;
// 拼接顺序：[RequestType 8] + [Request 8]  + [wValue 16] + [wIndex 16]
assign route_word = {setup_pkt.bmRequestType, setup_pkt.bRequest, setup_pkt.wValue , setup_pkt.wIndex};
//==============================================================
//====== UAC Parameters     
reg  [31:0] sample_rate_cur ,   pre_sample_rate_cur ;
reg  [15:0] ch0_volume_cur  ,   ch1_volume_cur   , ch2_volume_cur;
reg         mute_cur;

//====== UMS Parameters
wire [7:0]   lun_max  = 8'h1 ;
//====== CDC Parameters
reg [31:0]  s_dte1_rate;
reg [7:0]   s_char1_format;
reg [7:0]   s_parity1_type;
reg [7:0]   s_data1_bits;

//====== DFU Parameters
reg [7:0]   dfu_state;
reg         flash_trigger;
reg         ram_padding;
reg [23:0]  detach_delay_cnt;
reg         dfu_detach_flag;
reg         usb_txact_d1;
wire        usb_txact_fall = ({usb_txact_d1, usb_txact} == 2'b10);



//==============================================================

//-------------------------------------------------------------
//Comment:USB Control Endpoint0
//-------------------------------------------------------------
always_ff @(posedge PHY_CLKOUT or posedge RESET) begin
    if (RESET) begin
        stage           <= 8'd0;
        sub_stage       <= 8'd0;
        sub2_stage      <= 8'd0;
        active_cmd      <= CMD_IDLE;
        setup_pkt       <= '0;
        endpt0_send     <= 1'b0;
        usb_txdat_len_o <= 12'd0;
//UAC
        sample_rate_cur <= SAMPLE_RATE_48;
        ch0_volume_cur  <= 'h0;     ch1_volume_cur  <= 'h0; ch2_volume_cur  <= 'h0;
        mute_cur        <= 'h0;
//UMS

//CDC
        s_dte1_rate     <= 32'd115200;
        s_char1_format  <= 8'd0;
        s_parity1_type  <= 8'd0;
        s_data1_bits    <= 8'd8;
//DFU
        dfu_state       <= DFU_STATE_IDLE;
        flash_trigger   <= 1'b0;
        ram_padding     <= 1'b0;
        usb_txact_d1    <= 1'b0;
        dfu_detach_flag <= 1'b0;
        detach_delay_cnt<= 24'h0;

    end 
    else begin
        usb_txact_d1 <= usb_txact;
        // ============================================
        // 阶段 1: Setup 包解析 
        // ============================================
        if (setup_active) begin
            if (usb_rxval) begin
                case (stage)
                    8'd0: begin setup_pkt.bmRequestType <= usb_rxdat; stage <= stage + 8'd1; active_cmd <= CMD_IDLE; end
                    8'd1: begin setup_pkt.bRequest      <= usb_rxdat; stage <= stage + 8'd1; end
                    8'd2: begin setup_pkt.wValue[7:0]   <= usb_rxdat; stage <= stage + 8'd1; end
                    8'd3: begin setup_pkt.wValue[15:8]  <= usb_rxdat; stage <= stage + 8'd1; end
                    8'd4: begin setup_pkt.wIndex[7:0]   <= usb_rxdat; stage <= stage + 8'd1; end
                    8'd5: begin setup_pkt.wIndex[15:8]  <= usb_rxdat; stage <= stage + 8'd1; end
                    8'd6: begin setup_pkt.wLength[7:0]  <= usb_rxdat; stage <= stage + 8'd1; end
                    8'd7: begin 
                        setup_pkt.wLength[15:8] <= usb_rxdat; 
                        stage                   <= stage + 1; 
                        sub_stage               <= 8'd0; 
                        sub2_stage              <= 8'd0; 
                        endpt0_send             <= 1'b0;

                        casez (route_word)
                    // ----------------------------------------------------------------
                    // UAC 请求
                    // ----------------------------------------------------------------          
                            {SET_CLASS_INTF, CUR,   {FU_MUTE_CONTROL, 8'b?},   {FEATURE_UNIT_ID, 8'b?}} : active_cmd <= CMD_SET_MUTE;       //该部分 UAC20/UAC10 共有
                            {SET_CLASS_INTF, CUR,   {FU_VOLUME_CONTROL, 8'b?}, {FEATURE_UNIT_ID, 8'b?}} : active_cmd <= CMD_SET_VOL;        //该部分 UAC20/UAC10 共有

                    // UAC 2                                                                
                            // 备用接口（UAC20专用）                                        
                            {GET_CLASS_INTF, CUR,   {AS_VAL_ALT_SETTINGS_CONTROL, 8'b?}, 16'h0001},
                            {GET_CLASS_INTF, CUR,   {AS_VAL_ALT_SETTINGS_CONTROL, 8'b?}, 16'h0002}          : active_cmd <= CMD_GET_VAL_ALT_SET;
                            // Clock Source ID 路由 (匹配 wIndex 高字节为 CLOCK_SOURCE_ID)
                            {SET_CLASS_INTF, CUR,   {CS_SAM_FREQ_CONTROL, 8'b?},    {CLOCK_SOURCE_ID, 8'b?}} : active_cmd <= CMD_SET_SAM_FREQ;
                            {GET_CLASS_INTF, CUR,   {CS_SAM_FREQ_CONTROL, 8'b?},    {CLOCK_SOURCE_ID, 8'b?}} : active_cmd <= CMD_GET_SAM_FREQ;
                            {GET_CLASS_INTF, RANGE, {CS_SAM_FREQ_CONTROL, 8'b?},    {CLOCK_SOURCE_ID, 8'b?}} : active_cmd <= CMD_GET_SAM_FREQ_RANGE;
                            {GET_CLASS_INTF, CUR,   {CS_CLOCK_VALID_CONTROL, 8'b?}, {CLOCK_SOURCE_ID, 8'b?}} : active_cmd <= CMD_GET_CLK_VALID;
                            // Feature Unit ID 路由 (匹配 wIndex 高字节为 FEATURE_UNIT_ID)
                            {GET_CLASS_INTF, CUR,   {FU_VOLUME_CONTROL, 8'b?}, {FEATURE_UNIT_ID, 8'b?}} : active_cmd <= CMD_GET_VOL_CUR;
                            {GET_CLASS_INTF, CUR,   {FU_MUTE_CONTROL, 8'b?},   {FEATURE_UNIT_ID, 8'b?}} : active_cmd <= CMD_GET_MUTE;
                            {GET_CLASS_INTF, RANGE, {FU_VOLUME_CONTROL, 8'b?}, {FEATURE_UNIT_ID, 8'b?}} : active_cmd <= CMD_GET_VOL_RANGE;

                    // UAC 1.0
                            {SET_CLASS_EP,   SET_CUR, {CS_SAM_FREQ_CONTROL, 8'b?}, 16'b?}                 : active_cmd <= CMD_SET_SAM_FREQ;
                            {GET_CLASS_EP,   GET_CUR, {CS_SAM_FREQ_CONTROL, 8'b?}, 16'b?}                 : active_cmd <= CMD_GET_SAM_FREQ;

                            {GET_CLASS_INTF, GET_CUR, {FU_MUTE_CONTROL, 8'b?},   {FEATURE_UNIT_ID, 8'b?}} : active_cmd <= CMD_GET_MUTE;
                            {GET_CLASS_INTF, GET_CUR, {FU_VOLUME_CONTROL, 8'b?}, {FEATURE_UNIT_ID, 8'b?}} : active_cmd <= CMD_GET_VOL_CUR;
                            {GET_CLASS_INTF, GET_MAX, {FU_VOLUME_CONTROL, 8'b?}, {FEATURE_UNIT_ID, 8'b?}} : active_cmd <= CMD_GET_VOL_MAX;
                            {GET_CLASS_INTF, GET_MIN, {FU_VOLUME_CONTROL, 8'b?}, {FEATURE_UNIT_ID, 8'b?}} : active_cmd <= CMD_GET_VOL_MIN;
                            {GET_CLASS_INTF, GET_RES, {FU_VOLUME_CONTROL, 8'b?}, {FEATURE_UNIT_ID, 8'b?}} : active_cmd <= CMD_GET_VOL_RES;

                    // ----------------------------------------------------------------
                    // UMS 请求
                    // ----------------------------------------------------------------
                            // {GET_REQ      , GET_MAX_LUN , 16'b?                      ,   {8'h00, UMS_INTERFACE_NUM} }    : active_cmd <= CMD_UMS_GET_MAX_LUN;  // usb_txdat_len_o <= 12'd1;
                    // ----------------------------------------------------------------
                    // CDC 请求
                    // ----------------------------------------------------------------
                            // {GET_REQ     ,GET_LINE_CODING,  16'b?                    ,   {8'h00, CDC_INTERFACE_NUM} }    : active_cmd <= CMD_CDC_GET_LINE_CODING; // usb_txdat_len_o <= 12'd7;
                            // {SET_REQ     ,SET_LINE_CODING,  16'b?                    ,   {8'h00, CDC_INTERFACE_NUM} }    : active_cmd <= CMD_CDC_SET_LINE_CODING;
                    // ----------------------------------------------------------------
                    // DFU 请求 (接口号使用 8'b? 通配，或指定 {8'h00, DFU_INTERFACE_NUM})
                    // ----------------------------------------------------------------
                            {SET_REQ     , DFU_DETACH    , 16'b?                     , 16'b?             }               : active_cmd <= CMD_DFU_DETACH;
                            {SET_REQ     , DFU_CLRSTATUS , 16'b?                     , 16'b?             }               : begin
                                active_cmd      <= CMD_DFU_CLRSTATUS;
                                dfu_state       <= DFU_STATE_IDLE; // 状态立即复位
                            end
                            {GET_REQ, DFU_GETSTATUS, 16'b?, 16'b?}: begin
                                active_cmd      <= CMD_DFU_GETSTATUS;
                                usb_txdat_len_o <= 12'd6;
                                // DFU 内部状态机流转
                                if (dfu_state == DFU_STATE_DNLOAD_SYNC || dfu_state == DFU_STATE_DNBUSY) begin
                                    if (o_dfu_spi_wr_req) dfu_state <= DFU_STATE_DNBUSY;        // Flash 还没回 Ack，处于忙碌状态
                                    else                  dfu_state <= DFU_STATE_DNLOAD_IDLE;   // Flash 写完了，可以接下一包
                                end
                                else if (dfu_state == DFU_STATE_MANIFEST_SYNC) begin
                                    if (!o_dfu_spi_wr_req) dfu_state <= DFU_STATE_MANIFEST;     // Manifest 阶段的刷写也完成了
                                end
                                else if (dfu_state == DFU_STATE_MANIFEST) begin
                                    dfu_state  <= DFU_STATE_IDLE;
                                    // active_cmd <= CMD_DFU_DETACH;                               // 触发重枚举
                                    detach_delay_cnt <= 24'd1_200_000; // 直接启动 20ms 重枚举倒计时
                                end
                            end
                            {SET_REQ, DFU_DNLOAD, 16'b?, 16'b?}: begin
                                if ({usb_rxdat, setup_pkt.wLength[7:0]} == 16'd0) begin          // DFU边界条件，wLength==0时证明下载完成
                                    active_cmd         <= CMD_IDLE;
                                    dfu_state          <= DFU_STATE_MANIFEST_SYNC;
                                    o_dfu_spi_wr_flush <= 1'b1;                                 // 通知 Flash 控制器将内部 SRAM 最后的数据刷入 Flash
                                    flash_trigger      <= 1'b1;
                                end else begin
                                    //wLength！=0时，正常下载数据准备
                                    active_cmd         <= CMD_DFU_DNLOAD;
                                    dfu_state          <= DFU_STATE_DNLOAD_SYNC;
                                    // 将 wValue (块序号, 通常从0开始) 转换为 LBA 起始地址
                                    o_dfu_spi_lba      <= {16'd0, setup_pkt.wValue};
                                end
                            end

                            default: active_cmd <= CMD_IDLE;
                        endcase
                    end
                endcase
            end 
        end
        // ============================================
        // 阶段 2: 数据传输阶段 (Data Phase)
        // ============================================
        else if (active_cmd != CMD_IDLE) begin
//================================================== 2.1 主机读取数据 (IN 请求, GET_xxx) ============================================================//
            if (setup_pkt.bmRequestType[7] == 1'b1) begin
                if (usb_txact && (endpt_sel == 4'd0)) begin
                    if (usb_txpop) begin
                    // 特殊命令：get_sample_range，主机请求wLength会大于实际长度
                        if (active_cmd == CMD_GET_SAM_FREQ_RANGE) begin
                            if ((sub_stage + 1'b1 >= LEN_FREQS) || (sub_stage + 1'b1 >= setup_pkt.wLength)) begin
                                sub_stage   <= 8'd0;
                                active_cmd  <= CMD_IDLE; 
                                endpt0_send <= 1'b0;
                            end 
                            else begin
                                sub_stage  <= sub_stage + 1'b1;
                                if ((sub_stage + 1'b1 == 8'd64) || (sub_stage + 1'b1 == 8'd128)) begin
                                    endpt0_send <= 1'b0;
                                end
                            end
                        end
                    //正常命令
                        else begin
                            if (sub_stage + 1'b1 >= setup_pkt.wLength) begin
                                sub_stage   <= 8'd0;
                                active_cmd  <= CMD_IDLE;
                                endpt0_send <= 1'b0;
                            end 
                            else begin
                                sub_stage  <= sub_stage + 1'b1;
                            end
                        end
                    end
                    else begin
                        if (active_cmd != CMD_IDLE) begin
                            endpt0_send <= 1'b1;
                        end
                    end
                end
                else begin
                    endpt0_send     <= 1'b0;
                end
            end

//================================================== 2.2 主机写入数据 (OUT 请求, SET_xxx) ============================================================//
            else begin
                if (usb_rxact && usb_rxval && (endpt_sel == 4'd0)) begin
                    case (active_cmd)
            //=========UAC===========
                        CMD_SET_SAM_FREQ: begin
                            if      (sub_stage == 0) sample_rate_cur[7:0]   <= usb_rxdat;
                            else if (sub_stage == 1) sample_rate_cur[15:8]  <= usb_rxdat;
                            else if (sub_stage == 2) sample_rate_cur[23:16] <= usb_rxdat; // UAC 1.1 第 3 字节
                            else if (sub_stage == 3) sample_rate_cur[31:24] <= usb_rxdat; // UAC 2.0 第 4 字节

                            if (sub_stage + 1'b1 >= setup_pkt.wLength) begin
                                active_cmd <= CMD_IDLE; 
                                sub_stage  <= 8'd0;
                            end 
                            else begin
                                sub_stage <= sub_stage + 1'b1;
                            end
                        end
                        
                        CMD_SET_MUTE: begin
                            if (sub_stage == 0) mute_cur <= usb_rxdat[0];
                            active_cmd <= CMD_IDLE; 
                            sub_stage <= 8'd0;
                        end
                        
                        CMD_SET_VOL: begin
                            if (sub_stage == 0) begin
                                case (setup_pkt.wValue[7:0])
                                    CN0: begin ch0_volume_cur[7:0] <= usb_rxdat; ch1_volume_cur[7:0] <= usb_rxdat; ch2_volume_cur[7:0] <= usb_rxdat; end
                                    CN1: begin ch1_volume_cur[7:0] <= usb_rxdat; end
                                    CN2: begin ch2_volume_cur[7:0] <= usb_rxdat; end
                                endcase
                                sub_stage <= sub_stage + 1'b1;
                            end
                            else if (sub_stage == 1) begin
                                case (setup_pkt.wValue[7:0])
                                    CN0: begin ch0_volume_cur[15:8] <= usb_rxdat; ch1_volume_cur[15:8] <= usb_rxdat; ch2_volume_cur[15:8] <= usb_rxdat; end
                                    CN1: begin ch1_volume_cur[15:8] <= usb_rxdat; end
                                    CN2: begin ch2_volume_cur[15:8] <= usb_rxdat; end
                                endcase
                                active_cmd <= CMD_IDLE;
                                sub_stage  <= 8'd0;
                            end
                        end
            //=========CDC==========
                        // CMD_CDC_SET_LINE_CODING: begin
                        //     case (sub_stage)
                        //         8'd0: s_dte1_rate[7:0]   <= usb_rxdat;
                        //         8'd1: s_dte1_rate[15:8]  <= usb_rxdat;
                        //         8'd2: s_dte1_rate[23:16] <= usb_rxdat;
                        //         8'd3: s_dte1_rate[31:24] <= usb_rxdat;
                        //         8'd4: s_char1_format     <= usb_rxdat;
                        //         8'd5: s_parity1_type     <= usb_rxdat;
                        //         8'd6: begin
                        //             s_data1_bits <= usb_rxdat;
                        //             active_cmd   <= CMD_IDLE;
                        //             sub_stage    <= 8'd0;
                        //         end
                        //         default: ;
                        //     endcase
                        //     if (active_cmd != CMD_IDLE) sub_stage <= sub_stage + 8'd1;
                        // end
            //=========DFU==========
                        CMD_DFU_DNLOAD: begin
                            dfu_ram[sub2_stage] <= usb_rxdat;
                            if (sub2_stage + 1'b1 >= setup_pkt.wLength) begin
                                if (setup_pkt.wLength < 16'd512 && setup_pkt.wLength > 16'd0) begin
                                    active_cmd  <= CMD_IDLE; 
                                    sub2_stage  <= sub2_stage + 1'b1;
                                    ram_padding <= 1'b1;        // 短包，触发填充
                                end else begin
                                    sub2_stage    <= 9'd0;
                                    active_cmd    <= CMD_IDLE;
                                    flash_trigger <= 1'b1;      // 满包，通知flash_ctr接收
                                end
                            end else begin
                                sub2_stage <= sub2_stage + 1'b1;
                            end
                        end


                        default: begin 
                            active_cmd <= CMD_IDLE;
                            sub_stage  <= 8'd0;
                        end
                    endcase
                end
            end
        end
        // DFU RAM 填充逻辑
        else if (ram_padding) begin
            dfu_ram[sub2_stage] <= 8'hFF;
            if (sub2_stage == 9'd511) begin
                ram_padding   <= 1'b0;
                sub2_stage    <= 9'd0;
                flash_trigger <= 1'b1; // 使用 FF 补全512字节数据，然后再写入
            end else begin
                sub2_stage <= sub2_stage + 1'b1;
            end
        end 
        // ============================================
        // 阶段 3:空闲状态保护 && DFU 预处理部分
        // ============================================
        else begin
            stage     <= 8'd0;
            sub_stage <= 8'd0;
        end

        // DFU 模式更换
        if (active_cmd == CMD_DFU_DETACH && usb_txact_fall && endpt_sel == 4'd0) begin
            detach_delay_cnt <= 24'd1_200_000; // 20ms at 60MHz
            active_cmd <= CMD_IDLE;
        end
        if (active_cmd == CMD_DFU_CLRSTATUS && usb_txact_fall && endpt_sel == 4'd0) begin
            active_cmd <= CMD_IDLE;
        end

// Flash 写入命令
        if (flash_trigger) begin
            o_dfu_spi_wr_req <= 1'b1;   //开始写入
            flash_trigger    <= 1'b0;
        end else if (i_dfu_spi_wr_ack) begin
            o_dfu_spi_wr_req   <= 1'b0; //直到收到ACK
            o_dfu_spi_wr_flush <= 1'b0;
        end

        // Detach pulse generation
        if (detach_delay_cnt > 0) begin
            detach_delay_cnt <= detach_delay_cnt - 1'b1;
            if (detach_delay_cnt == 24'd1) begin
                dfu_detach_flag <= 1'b1; //一拍脉冲
            end
        end else begin
            dfu_detach_flag <= 1'b0;

        end
    end
end


reg [7:0]   dfu_ram     [511:0]/*synthesis syn_ramstyle="block_ram"*/;






//仅用于 CMD_GET_SAM_FREQ_RANGE 除数计
logic [7:0] freq_idx;
logic [3:0] byte_off;
assign freq_idx = (sub_stage >= 2) ? (sub_stage - 2) / 12 : 8'd0; //目前是第 N 个 采样率
assign byte_off = (sub_stage >= 2) ? (sub_stage - 2) % 12 : 4'd0; //采样率第 M 位

// ========================================  端点0的数据输出（GET_xxx） =======================================
always_comb begin
    endpt0_dat = 8'h00;
    if ((active_cmd != CMD_IDLE) && (setup_pkt.bmRequestType[7] == 1'b1)) begin
        case (active_cmd)
//====  UAC Output
            CMD_GET_VOL_MIN     : endpt0_dat = (sub_stage == 0) ? VOLUME_FS_MIN[7:0]    : VOLUME_FS_MIN[15:8];
            CMD_GET_VOL_MAX     : endpt0_dat = (sub_stage == 0) ? VOLUME_FS_MAX[7:0]    : VOLUME_FS_MAX[15:8];
            CMD_GET_VOL_RES     : endpt0_dat = (sub_stage == 0) ? VOLUME_FS_RES[7:0]    : VOLUME_FS_RES[15:8];
            CMD_GET_VOL_CUR     : endpt0_dat = (sub_stage == 0) ? ch0_volume_cur[7:0]   : ch0_volume_cur[15:8];
            CMD_GET_MUTE        : endpt0_dat = {7'd0, mute_cur}; // 1 byte 数据
            CMD_GET_CLK_VALID   : endpt0_dat = 8'h01; 
            CMD_GET_VAL_ALT_SET : endpt0_dat = 8'h00;   //  UAC2.0: 5 byte 全0==》默认态    
            CMD_GET_SAM_FREQ: begin // UAC1.1: 3 byte / UAC2.0: 4 byte
                if (sub_stage == 0)      endpt0_dat = sample_rate_cur[7:0];
                else if (sub_stage == 1) endpt0_dat = sample_rate_cur[15:8];
                else if (sub_stage == 2) endpt0_dat = sample_rate_cur[23:16];
                else                     endpt0_dat = sample_rate_cur[31:24];
            end
            CMD_GET_SAM_FREQ_RANGE: begin
                if      (sub_stage == 0) endpt0_dat = NUM_FREQS[7:0];  // wNumSubRanges LSB
                else if (sub_stage == 1) endpt0_dat = NUM_FREQS[15:8]; // wNumSubRanges MSB
                else begin
                    if (freq_idx < NUM_FREQS) begin
                        case (byte_off)
                            4'd0, 4'd4: endpt0_dat = SUPPORTED_FREQS[freq_idx][7:0];    // MIN 和 MAX  Byte 0
                            4'd1, 4'd5: endpt0_dat = SUPPORTED_FREQS[freq_idx][15:8];   // MIN 和 MAX  Byte 1
                            4'd2, 4'd6: endpt0_dat = SUPPORTED_FREQS[freq_idx][23:16];  // MIN 和 MAX  Byte 2
                            4'd3, 4'd7: endpt0_dat = SUPPORTED_FREQS[freq_idx][31:24];  // MIN 和 MAX  Byte 3
                            default:    endpt0_dat = 8'h00;                             // RES 分辨率
                        endcase
                    end else            endpt0_dat = 8'h00; 
                end
            end
            CMD_GET_VOL_RANGE: begin
                case (sub_stage)
                    8'd0: endpt0_dat = VOLUME_NUM[7:0];    // wNumSubRanges LSB
                    8'd1: endpt0_dat = VOLUME_NUM[15:8];   // wNumSubRanges MSB
                    8'd2: endpt0_dat = VOLUME_HS_MIN[7:0]; // MIN LSB
                    8'd3: endpt0_dat = VOLUME_HS_MIN[15:8];// MIN MSB
                    8'd4: endpt0_dat = VOLUME_HS_MAX[7:0]; // MAX LSB
                    8'd5: endpt0_dat = VOLUME_HS_MAX[15:8];// MAX MSB
                    8'd6: endpt0_dat = VOLUME_HS_RES[7:0]; // RES LSB
                    8'd7: endpt0_dat = VOLUME_HS_RES[15:8];// RES MSB
                    default: endpt0_dat = 8'h00;
                endcase
            end


//====  UMS Output
            // CMD_UMS_GET_MAX_LUN : endpt0_dat = lun_max; // MAX LUN = 1 (LUN0 + LUN1)

//====  CDC Output
            // CMD_CDC_GET_LINE_CODING: begin
            //     case (sub_stage)
            //         8'd0: endpt0_dat = s_dte1_rate[7:0];
            //         8'd1: endpt0_dat = s_dte1_rate[15:8];
            //         8'd2: endpt0_dat = s_dte1_rate[23:16];
            //         8'd3: endpt0_dat = s_dte1_rate[31:24];
            //         8'd4: endpt0_dat = s_char1_format;
            //         8'd5: endpt0_dat = s_parity1_type;
            //         8'd6: endpt0_dat = s_data1_bits;
            //         default: endpt0_dat = 8'd0;
            //     endcase
            // end

//====  DFU Output
            CMD_DFU_GETSTATUS: begin
                case (sub_stage)
                    8'd0: endpt0_dat = 8'h00; // bStatus
                    8'd1: endpt0_dat = 8'h32; // bwPollTimeout L
                    8'd2: endpt0_dat = 8'h00; // bwPollTimeout M
                    8'd3: endpt0_dat = 8'h00; // bwPollTimeout H
                    8'd4: endpt0_dat = i_dfu_mode ? dfu_state : APP_STATE_IDLE; // bState
                    8'd5: endpt0_dat = 8'h00; // iString
                    default: endpt0_dat = 8'd0;
                endcase
            end


            default: endpt0_dat = 8'h00;
        endcase
    end
end





//=============================================================
//======Tx Cork
//==============================================================
//======Interface Select

reg  [ 7:0] tx_data_bits    ,   rx_data_bits    ;
reg         dsd_en          ,   dop_en          ;   
always@(posedge PHY_CLKOUT, posedge RESET) begin
    if (RESET) begin
        tx_data_bits <= 8'd32;
        rx_data_bits <= 8'd32;
    end
    else begin
        unique case (interface1_alter)
        8'h01:      tx_data_bits <= 8'd16;  //2 slots 16bit PCM
        8'h02:      tx_data_bits <= 8'd24;  //3 slots 24bit PCM
        8'h03:      tx_data_bits <= 8'd32;  //4 slots 32bit PCM
        8'h04:      tx_data_bits <= 8'd32;  // DSD
        default:    tx_data_bits <= 8'd32;  // default
        endcase

        if (interface1_alter == 8'h04) begin
            dsd_en      <= 1'b1;
        end
        else if (interface1_alter == 8'h00) begin
            dsd_en      <= dsd_en;
        end
        else begin
            dsd_en      <= 1'b0;
        end

        // if (interface2_alter == 8'h01) begin
        //     rx_data_bits <= 8'd32;  //2 slots 16bit PCM  
        // end
        // else if (interface2_alter == 8'h02) begin
        //     rx_data_bits <= 8'd32;  //4 slots 24bit PCM
        // end
    end
end



//-----------------------------------------------------
//DOP Detection
//-----------------------------------------------------
wire      audio_data_endpt;
reg       usb_rxact_d0;
reg       usb_rxval_d0;
reg [7:0] usb_rxdat_d0;

assign audio_data_endpt  = (endpt_sel==4'd1) ; //检查UAC EP
always @(posedge PHY_CLKOUT or posedge RESET) begin
    if (RESET) begin
        usb_rxact_d0 <= 1'b0;
        usb_rxval_d0 <= 1'b0;
        usb_rxdat_d0 <= 8'd0;
    end
    else begin
        usb_rxact_d0 <= usb_rxact;
        usb_rxval_d0 <= usb_rxval & audio_data_endpt;
        usb_rxdat_d0 <= usb_rxdat;
    end
end

logic [3:0] byte_cnt;
logic       dop_pkt_valid; // 当前包是否仍然符合 DoP 规范
logic       dop_detected;  // 是否在当前包中检测到了 DoP 标志
logic [7:0] curr_marker;   // 当前需要校验的 MSB 标识符
logic       audio_pkt_rxing; // 当前是否正在接收音频包 当前端点
always @(posedge PHY_CLKOUT or posedge RESET) begin
    if (RESET) begin
        dop_pkt_valid   <=  1'b1;
        dop_en          <=  1'b0;
        dop_detected    <=  1'b0;
        byte_cnt        <=  4'd0;

        curr_marker     <= 8'd0;

        audio_pkt_rxing <=  1'b0; 
    end
    else begin
        if (usb_rxact_d0) begin
            if (usb_rxval_d0) begin
                audio_pkt_rxing     <= 1'b1; 
                byte_cnt            <= byte_cnt + 1'd1;
// dop 格式必定为 8bit 0x05/0xFA 标志位 + 16bit data + 8bit 0x00 填充
// 处理时注意小端
                if (dop_pkt_valid) begin
                    // [校验1]： 后8位不为填充位00
                    if (byte_cnt[1:0] == 2'd0) begin
                        if (usb_rxdat_d0 != 8'h00) begin
                            dop_pkt_valid <= 1'b0;
                        end
                    end
                    //[校验2]： 校验标志位0x05 / 0xFA，每个数据帧交替一次
                    else if (byte_cnt[1:0] == 4'd3) begin
                        // 左声道
                        if (byte_cnt[2] == 1'b0) begin
                            if (!dop_detected) begin
                                dop_detected <= 1'b1;
                                curr_marker  <= usb_rxdat_d0;
                                if (usb_rxdat_d0 != DOP_PACKET_CODE0 && usb_rxdat_d0 != DOP_PACKET_CODE1) begin
                                    dop_pkt_valid <= 1'b0;
                                end
                            end 
                            else begin
                                // 后续左声道：Marker 必须交替 (0x05 <-> 0xFA)
                                if ((curr_marker == DOP_PACKET_CODE0 && usb_rxdat_d0 != DOP_PACKET_CODE1) ||
                                    (curr_marker == DOP_PACKET_CODE1 && usb_rxdat_d0 != DOP_PACKET_CODE0)) begin
                                    dop_pkt_valid <= 1'b0;
                                end 
                                else begin
                                    curr_marker <= usb_rxdat_d0; // 右声道marker应与左声道相同
                                end
                            end
                        end
                        //右声道应与左声道相同 (byte_cnt[2] == 1'b1)
                        else begin 
                            if (usb_rxdat_d0 != curr_marker) begin
                                dop_pkt_valid <= 1'b0;
                            end
                        end
                    end
                end
            end
        end
        //!rxact 接收包结束
        else begin
            byte_cnt            <= 4'd0;

            // if (dop_detected) begin
            //     dop_detected    <= 1'b0;            //清除标志
            //     dop_en          <= dop_pkt_valid;   //完全校验成功
            // end
            // else    dop_pkt_valid       <= 1'b1;

// 【核心修改】只要这是一包音频数据，结束时无论校验提前终止与否，都更新 dop_en
            if (audio_pkt_rxing) begin
                // 增加硬件互斥：如果当前已经是 DSD 模式，强制不允许拉高 DoP，防止误判
                dop_en          <= dop_pkt_valid & (~dsd_en); 
            end
            
            // 包结束，彻底清零所有状态，迎接下一包
            dop_detected        <= 1'b0;            
            dop_pkt_valid       <= 1'b1;   
            audio_pkt_rxing     <= 1'b0; 
        end
    end
end

//==============================================================
//======Mute Control
reg        sw_mute;
reg [31:0] sw_mute_dly;
always@(posedge PHY_CLKOUT, posedge RESET) begin
    if (RESET) begin
        sw_mute <= 1'b1;
        sw_mute_dly <= 32'd0;
    end
    else begin
        if (audio_tx_reset) begin
            sw_mute <= 1'b1;
            sw_mute_dly <= 32'd0;
        end
        else if (pre_sample_rate_cur != sample_rate_cur) begin
            sw_mute <= 1'b1;
            sw_mute_dly <= 32'd0;
        end
        else if (sw_mute_dly>=18000000) begin
            sw_mute <= 1'b0;
        end
        else begin
            sw_mute_dly <= sw_mute_dly + 32'd1;
        end
    end
end
always@(posedge PHY_CLKOUT, posedge RESET) begin
    if (RESET) begin
        pre_sample_rate_cur <= SAMPLE_RATE_44_1;
    end
    else begin
        pre_sample_rate_cur <= sample_rate_cur;
    end
end

//==============================================================
//======Interface Setting ( UAC )
assign O_INTERFACE_ALTER = (I_INTERFACE_SEL == 0) ? interface0_alter :
                           (I_INTERFACE_SEL == 1) ? interface1_alter :
                           (I_INTERFACE_SEL == 2) ? interface2_alter : 8'd0;
always@(posedge PHY_CLKOUT, posedge RESET) begin
    if (RESET) begin
        interface0_alter <= 'd0;
        interface1_alter <= 'd0;
    end
    else begin
        if (I_INTERFACE_UPDATE) begin
            if (I_INTERFACE_SEL == 0) begin
                interface0_alter <= I_INTERFACE_ALTER;
            end
            else if (I_INTERFACE_SEL == 1) begin
                interface1_alter <= I_INTERFACE_ALTER;
            end
            else if (I_INTERFACE_SEL == 2) begin
                interface2_alter <= I_INTERFACE_ALTER;
            end
        end
    end
end

always@(posedge PHY_CLKOUT, posedge RESET) begin
    if (RESET) begin
        audio_rx_reset <= 1'b0;
        audio_tx_reset <= 1'b0;
    end
    else begin
        if (I_INTERFACE_UPDATE) begin
            if (I_INTERFACE_SEL == 1) begin
                if (O_INTERFACE_ALTER == 8'd0) begin
                    audio_tx_reset <= 1'b1;
                end
                else begin
                    audio_tx_reset <= 1'b0;
                end
            end
            else if (I_INTERFACE_SEL == 2) begin
                if (O_INTERFACE_ALTER == 8'd0) begin
                    audio_rx_reset <= 1'b1;
                end
                else begin
                    audio_rx_reset <= 1'b0;
                end
            end
        end
        else begin
            audio_rx_reset <= 1'b0;
            audio_tx_reset <= 1'b0;
        end
    end
end

//==========================================================
//DFU
//==========================================================
assign o_dfu_detach_flag    = dfu_detach_flag;

assign o_dfu_spi_buf_rdata  = dfu_ram[i_dfu_spi_buf_addr];
//-------------------------------------------------------------
//Comment:In/Out Interface
//-------------------------------------------------------------
assign endpt0_send_0         = endpt0_send;
assign endpt0_dat_0          = endpt0_dat ; 


assign O_UART1_BAUD_RATE    = s_dte1_rate;
assign O_UART1_PARITY_BIT   = s_parity1_type;
assign O_UART1_STOP_BIT     = s_char1_format;
assign O_UART1_DATA_BITS    = s_data1_bits;

assign O_MUTE               = mute_cur|sw_mute;
assign O_CH0_VOLUME         = ch0_volume_cur;
assign O_CH1_VOLUME         = ch1_volume_cur;
assign O_CH2_VOLUME         = ch2_volume_cur;
assign O_SAMPLE_RATE        = sample_rate_cur;    
assign O_TX_DATA_BITS       = tx_data_bits;
assign O_RX_DATA_BITS       = rx_data_bits;
assign O_DOP_EN             = dop_en;
assign O_DSD_EN             = dsd_en;

endmodule
//===========================================

