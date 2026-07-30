
module usb_ep_top #(
    // -----------------------------------------------------------------
    // 端点模式配置：0:DISABLE, 1:UMS(RAM), 2:CDC(FIFO), 3:UAC(Audio FIFO)
    // -----------------------------------------------------------------
    parameter int EP_IN_MODE  [15:1] = '{default: 0}, 
    parameter int EP_OUT_MODE [15:1] = '{default: 0},

    parameter int EP_UAC_INTF [15:1] = '{default: 1},
    // -----------------------------------------------------------------
    // size parameter
    // -----------------------------------------------------------------
    parameter int EP_RAM_IN_BUF_SIZE    [15:1] = '{default: 1024},  // For UMS
   
    parameter int EP_FIFO_OUT_BUF_ASIZE [15:1] = '{default: 11},    // For CDC/UAC
    parameter int EP_FIFO_IN_BUF_ASIZE  [15:1] = '{default: 11},    // For CDC/UAC
    parameter int EP_FIFO_OUT_BUF_AFULL [15:1] = '{default: 1024}   // For CDC/UAC
)
(
    input  logic        i_clk,
    input  logic        i_reset,        
    input  logic [3:0]  i_usb_endpt,   

    // =================================================================
    // USB IP核 全局接口 
    // =================================================================
    input  logic        i_usb_txact,
    output logic        o_usb_txcork,
    input  logic        i_usb_txpop,
    input  logic        i_usb_txpktfin, 
    output logic [11:0] o_usb_txlen,
    output logic [7:0]  o_usb_txdat,

    input  logic        i_usb_rxact,
    input  logic        i_usb_rxval,
    input  logic        i_usb_rxpktval, 
    
    input  logic [7:0]  i_interface_sel,
    input  logic [7:0]  i_interface_alter,

    input  logic [7:0]  i_usb_rxdat,
    output logic        o_usb_rxrdy,

    // =================================================================
    // RAM interface (用于 UMS 模式)
    // =================================================================
    ep_mem_out_if.ep   ep_mem_out [15:1],
    ep_mem_in_if.ep    ep_mem_in  [15:1],

    // =================================================================
    // FIFO interface (用于 CDC / UAC 模式)
    // =================================================================
    ep_fifo_out_if.ep   ep_fifo_out [15:1],
    ep_fifo_in_if.ep    ep_fifo_in  [15:1]
);

    // =================================================================
    logic [15:1] ep_usb_txcork;
    logic [11:0] ep_usb_txlen  [15:1];
    logic [7:0]  ep_usb_txdata [15:1];
    logic [15:1] ep_usb_rxrdy;

    logic [3:0] s_endpt_sel;
    
    // 统一改为高电平复位逻辑
    always_ff @(posedge i_clk or posedge i_reset) begin
        if (i_reset) s_endpt_sel <= 4'd0;
        else         s_endpt_sel <= i_usb_endpt;
    end

    // -----------------------------------------------------------------
    assign o_usb_txcork = (i_usb_endpt == 4'd0) ? 1'b0  : ep_usb_txcork[i_usb_endpt];
    assign o_usb_txlen  = (i_usb_endpt == 4'd0) ? 12'd0 : ep_usb_txlen[i_usb_endpt];
    assign o_usb_txdat  = (i_usb_endpt == 4'd0) ? 8'b0  : ep_usb_txdata[i_usb_endpt];
    assign o_usb_rxrdy  = (i_usb_endpt == 4'd0) ? 1'b1  : ep_usb_rxrdy[i_usb_endpt];
    // -----------------------------------------------------------------
    genvar i;
    generate
        for (i = 1; i < 16; i = i + 1) begin : gen_ep_logic
            
// ============================================================================================
// OUT (RX) 
// ============================================================================================
            if (EP_OUT_MODE[i] == 1 ) begin : gen_UMS_out        //1 : UMS
                usb_ram_out_mem #(
                    .PP_BUF_SIZE(1024)
                ) u_usb_ep_out_mem (
                    .clk                        (i_clk),
                    .rst_n                      (~i_reset), 
                    .enable                     (i_usb_endpt == i), 
                    .usb_rxact                  (i_usb_rxact),
                    .usb_rxval                  (i_usb_rxval),
                    .usb_rxfin                  (i_usb_rxpktval),
                    .usb_rxdata                 (i_usb_rxdat),
                    .usb_rxrdy                  (ep_usb_rxrdy[i]),
                    // 修改点：直接绑定至对应的 ep_mem_out 接口同名信号
                    .transfer_out_mem_has_data  (ep_mem_out[i].transfer_out_mem_has_data),
                    .transfer_out_mem_len       (ep_mem_out[i].transfer_out_mem_len),
                    .transfer_out_mem_rd_data   (ep_mem_out[i].transfer_out_mem_rd_data),
                    .transfer_out_mem_rd_addr   (ep_mem_out[i].transfer_out_mem_rd_addr),
                    .transfer_out_mem_clr       (ep_mem_out[i].transfer_out_mem_clr)
                );
                assign ep_fifo_out[i].o_rx_dval = 1'b0;
                assign ep_fifo_out[i].o_rx_data = '0;
            end 
            else if ((EP_OUT_MODE[i] == 2)) begin : gen_fifo_out //2: CDC
                usb_cdc_out_buf #(
                     .P_ENDPOINT (i)
                    ,.P_AFULL    (EP_FIFO_OUT_BUF_AFULL[i])
                     ,.P_DSIZE    (8)
                    ,.P_ASIZE    (EP_FIFO_OUT_BUF_ASIZE[i])
                ) u_cdc_out_buf (
                     .i_clk         (i_clk)
                    ,.i_reset       (i_reset)         
                    ,.i_usb_endpt   (s_endpt_sel)   
                    ,.i_usb_rxact   (i_usb_rxact)
                    ,.i_usb_rxval   (i_usb_rxval)
                    ,.i_usb_rxpktval(i_usb_rxpktval)      
                    ,.i_usb_rxdat   (i_usb_rxdat)
                    ,.o_usb_rxrdy   (ep_usb_rxrdy[i])
                    ,.i_ep_clk      (ep_fifo_out[i].i_rx_clk)
                    ,.i_ep_rx_rdy   (ep_fifo_out[i].i_rx_rdy)
                    ,.o_ep_rx_dval  (ep_fifo_out[i].o_rx_dval)
                    ,.o_ep_rx_data  (ep_fifo_out[i].o_rx_data)
                );
                // 非 UMS 模式下，清零接口输出信号
                assign ep_mem_out[i].transfer_out_mem_has_data = '0;
                assign ep_mem_out[i].transfer_out_mem_rd_data   = '0;
                assign ep_mem_out[i].transfer_out_mem_len      = '0;
            end 
            else if ((EP_OUT_MODE[i] == 3)) begin : gen_uac_out //3: UAC
                usb_uac_out_buf #(
                     .P_ENDPOINT (i)
                    ,.P_AFULL    (EP_FIFO_OUT_BUF_AFULL[i])
                     ,.P_DSIZE    (8)
                    ,.P_ASIZE    (EP_FIFO_OUT_BUF_ASIZE[i])
                ) u_uac_out_buf (
                     .i_clk         (i_clk)
                    ,.i_reset       (i_reset)         
                    ,.i_usb_endpt   (s_endpt_sel)   
                    ,.i_usb_rxact   (i_usb_rxact)
                    ,.i_usb_rxval   (i_usb_rxval)
                    ,.i_usb_rxpktval(i_usb_rxpktval)      
                    ,.i_usb_rxdat   (i_usb_rxdat)
                    ,.o_usb_rxrdy   (ep_usb_rxrdy[i])
                    ,.i_ep_clk      (ep_fifo_out[i].i_rx_clk)
                    ,.i_ep_rx_rdy   (ep_fifo_out[i].i_rx_rdy)
                    ,.o_ep_rx_dval  (ep_fifo_out[i].o_rx_dval)
                    ,.o_ep_rx_data  (ep_fifo_out[i].o_rx_data)
                );
                // 非 UMS 模式下，清零接口输出信号
                assign ep_mem_out[i].transfer_out_mem_has_data = '0;
                assign ep_mem_out[i].transfer_out_mem_rd_data   = '0;
                assign ep_mem_out[i].transfer_out_mem_len      = '0;
            end 
            else begin : gen_no_out         // 0:DISABLE
                assign ep_usb_rxrdy[i]                          = 1'b0;
                //关闭模式下清零所有相关接口输出
                assign ep_mem_out[i].transfer_out_mem_has_data = '0;
                assign ep_mem_out[i].transfer_out_mem_rd_data   = '0;
                assign ep_mem_out[i].transfer_out_mem_len      = '0;
                assign ep_fifo_out[i].o_rx_dval                = 1'b0;
                assign ep_fifo_out[i].o_rx_data                = '0;
            end

// ==============================================================================================
// IN (TX) 
// ==============================================================================================
            if (EP_IN_MODE[i] == 1 ) begin : gen_UMS_in         //1 : UMS
                usb_ram_in_mem #(
                    .PP_BUF_SIZE(EP_RAM_IN_BUF_SIZE[i])
                ) u_usb_ep_in_mem (
                    .clk                        (i_clk),
                    .rst_n                      (~i_reset),
                    .enable                     (i_usb_endpt == i),
                    .usb_txact                  (i_usb_txact),
                    .usb_txcork                 (ep_usb_txcork[i]),
                    .usb_txpop                  (i_usb_txpop),
                    .usb_txdone                 (i_usb_txpktfin),
                    .usb_txlen                  (ep_usb_txlen[i]),
                    .usb_txdata                 (ep_usb_txdata[i]),
                    // 完全使用 ep_mem_in[i] 与 ep_mem_out[i] 接口内的信号绑定
                    .transfer_in_mem_wr         (ep_mem_in[i].transfer_in_mem_wr),
                    .transfer_in_mem_wr_addr    (ep_mem_in[i].transfer_in_mem_wr_addr[$clog2(EP_RAM_IN_BUF_SIZE[i])-1:0]),
                    .transfer_in_mem_wr_data    (ep_mem_in[i].transfer_in_mem_wr_data),
                    .transfer_in_mem_commit     (ep_mem_in[i].transfer_in_mem_commit),
                    .transfer_in_mem_commit_len (ep_mem_in[i].transfer_in_mem_commit_len[$clog2(EP_RAM_IN_BUF_SIZE[i]):0]),
                    .transfer_in_mem_ready      (ep_mem_in[i].transfer_in_mem_ready),
                    .transfer_in_done           (ep_mem_in[i].transfer_in_done)
                );
                assign ep_fifo_in[i].o_tx_full    = 1'b1; 
                assign ep_fifo_in[i].o_tx_alfull  = 1'b1;
                assign ep_fifo_in[i].o_tx_alempty = 1'b0;
            end 
            else if (EP_IN_MODE[i] == 2 ) begin : gen_CDC_in // 2: CDC 模式
                logic [7:0] ep_txdat;
                logic       ep_txcork;
                logic [EP_FIFO_IN_BUF_ASIZE[i]:0] ep_txlen;
                usb_cdc_in_buf #(
                     .P_ENDPOINT (i)
                    ,.P_DSIZE    (8)
                    ,.P_ASIZE    (EP_FIFO_IN_BUF_ASIZE[i])
                ) u_cdc_in_buf (
                     .i_clk         (i_clk)
                    ,.i_reset       (i_reset)
                    ,.i_usb_endpt   (s_endpt_sel)
                    ,.i_usb_txact   (i_usb_txact)
                    ,.i_usb_txpop   (i_usb_txpop)
                    ,.i_usb_txpktfin(i_usb_txpktfin)    
                    ,.o_usb_txdat   (ep_txdat)
                    ,.o_usb_txcork  (ep_txcork)
                    ,.o_usb_txlen   (ep_txlen)
                    ,.i_ep_clk      (ep_fifo_in[i].i_tx_clk)
                    ,.i_ep_tx_dval  (ep_fifo_in[i].i_tx_dval)
                    ,.i_ep_tx_data  (ep_fifo_in[i].i_tx_data)
                );
                assign ep_usb_txcork[i] = ep_txcork;
                assign ep_usb_txdata[i] = ep_txdat;
                
                // 非 UMS 模式下，清零接口输出
                assign ep_mem_in[i].transfer_in_mem_ready = 1'b0;
                assign ep_mem_in[i].transfer_in_done      = 1'b0;

                // 2: CDC 模式 -> 上限裁剪 
                assign ep_usb_txlen[i] = (ep_txlen >= ep_fifo_in[i].i_tx_max) ?
                                         ep_fifo_in[i].i_tx_max : ep_txlen[11:0]; 
                assign ep_fifo_in[i].o_tx_full    = 1'b0;
                assign ep_fifo_in[i].o_tx_alfull  = 1'b0;
                assign ep_fifo_in[i].o_tx_alempty = 1'b0;
            end
            else if (EP_IN_MODE[i] == 3) begin : gen_uac_in // 3: UAC模式
                logic [7:0]  ep_txdat;
                logic        ep_txcork;
                logic [11:0] ep_txlen;
                usb_uac_in_buf #(
                     .P_ENDPOINT  (i)
                    ,.P_INTERFACE (EP_UAC_INTF[i])  
                    ,.P_DSIZE     (8)
                    ,.P_ASIZE     (EP_FIFO_IN_BUF_ASIZE[i])
                ) u_uac_in_buf (
                     .i_clk             (i_clk),            
                     .i_reset           (i_reset),
                     .i_usb_endpt       (s_endpt_sel),    
                     .i_usb_txact       (i_usb_txact),
                     .i_usb_txpop       (i_usb_txpop),      
                     .i_usb_txpktfin    (i_usb_txpktfin),
                     
                     .i_interface_sel   (i_interface_sel),
                     .i_interface_alter (i_interface_alter),
                     
                     .o_usb_txfull      (ep_fifo_in[i].o_tx_full),
                     .o_usb_txalfull    (ep_fifo_in[i].o_tx_alfull),
                     .o_usb_txalempty   (ep_fifo_in[i].o_tx_alempty),

                     .o_usb_txdat       (ep_txdat),
                     .o_usb_txcork      (ep_txcork),
                     .o_usb_txlen       (ep_txlen),
                     
                     .i_ep_pkt_nor      (ep_fifo_in[i].i_tx_nor),
                     .i_ep_pkt_min      (ep_fifo_in[i].i_tx_min),

                     .i_ep_clk          (ep_fifo_in[i].i_tx_clk),
                     .i_ep_tx_dval      (ep_fifo_in[i].i_tx_dval),
                     .i_ep_tx_data      (ep_fifo_in[i].i_tx_data)
                );
                assign ep_usb_txcork[i] = ep_txcork;
                assign ep_usb_txdata[i] = ep_txdat;
                
                // 非 UMS 模式下，清零接口输出
                assign ep_mem_in[i].transfer_in_mem_ready = 1'b0;
                assign ep_mem_in[i].transfer_in_done      = 1'b0;

                // UAC 的长度判断逻辑 (基于 Nor/Min/Max)
                assign ep_usb_txlen[i] = (ep_txlen >= (ep_fifo_in[i].i_tx_max << 1)) ? ep_fifo_in[i].i_tx_max :
                                         (ep_txlen >= ep_fifo_in[i].i_tx_nor)        ? ep_fifo_in[i].i_tx_nor :
                                         (ep_txlen >= ep_fifo_in[i].i_tx_min)        ? ep_fifo_in[i].i_tx_min : 12'd0;
            end
            else begin : gen_no_in          // 0:DISABLE
                // 修改点：关闭状态下清零所有相关接口输出
                assign ep_fifo_in[i].o_tx_full     = 1'b1;
                assign ep_fifo_in[i].o_tx_alfull   = 1'b1;
                assign ep_fifo_in[i].o_tx_alempty  = 1'b0;

                assign ep_usb_txcork[i]            = 1'b1;
                assign ep_usb_txlen[i]             = '0;
                assign ep_usb_txdata[i]            = '0;
                assign ep_mem_in[i].transfer_in_mem_ready = 1'b0;
                assign ep_mem_in[i].transfer_in_done      = 1'b0;
            end

        end
    endgenerate

endmodule