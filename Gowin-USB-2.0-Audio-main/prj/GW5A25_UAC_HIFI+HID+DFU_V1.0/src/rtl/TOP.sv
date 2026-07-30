`include "audio_define.vh"
import audio_pkg::*;
module Top(
     input      CLK_IN
    ,output     LED                 //  Once RESET is successful, LED will remain lit.

    ,inout      usb_dxp_io    
    ,inout      usb_dxn_io     
    ,input      usb_rxdp_i    
    ,input      usb_rxdn_i    
    ,output     usb_pullup_en_o
    ,inout      usb_term_dp_io 
    ,inout      usb_term_dn_io

//SPI
    ,output     spi_sclk 
    ,output     spi_cs 
    ,output     spi_mosi 
    ,input      spi_miso
//IIS
    ,output     IIS_BCLK_O
    ,output     IIS_LRCK_O
    ,output     IIS_DATA1_O  //CN01

//DSD
    ,output     DSD_CLK_O
    ,output     DSD_DATA1_O
    ,output     DSD_DATA2_O

);

parameter CHANNEL_NUM = `CHANNEL_NUM ;

localparam  CLOCK_SOURCE_ID         = 8'h05;
localparam  FEATURE_UNIT_ID         = 8'h03;

localparam  SPEAKER_INTERFACE       = 8'h01;
localparam  MIC_INTERFACE           = 8'h02;

localparam  SPEAKER_OUT_ENDPOINT    = 8'h01;
localparam  SPEAKER_IN_FB_ENDPOINT  = 8'h81;
localparam  HID_OUT_ENDPOINT        = 8'h02;
localparam  HID_IN_ENDPOINT         = 8'h82;

localparam  DOP_PACKET_CODE0         = 8'h05;
localparam  DOP_PACKET_CODE1         = 8'hFA;


wire [1:0]  PHY_XCVRSELECT      ;
wire        PHY_TERMSELECT      ;
wire [1:0]  PHY_OPMODE          ;
wire [1:0]  PHY_LINESTATE       ;
wire        PHY_TXVALID         ;
wire        PHY_TXREADY         ;
wire        PHY_RXVALID         ;
wire        PHY_RXACTIVE        ;
wire        PHY_RXERROR         ;
wire [7:0]  PHY_DATAIN          ;
wire [7:0]  PHY_DATAOUT         ;
wire        PHY_CLKOUT          ;
wire [15:0] DESCROM_RADDR       ;
wire [ 7:0] DESC_INDEX          ;
wire [ 7:0] DESC_TYPE           ;
wire [ 7:0] DESCROM_RDAT        ;
wire [15:0] DESC_DEV_ADDR       ;
wire [15:0] DESC_DEV_LEN        ;
wire [15:0] DESC_QUAL_ADDR      ;
wire [15:0] DESC_QUAL_LEN       ;
wire [15:0] DESC_FSCFG_ADDR     ;
wire [15:0] DESC_FSCFG_LEN      ;
wire [15:0] DESC_HSCFG_ADDR     ;
wire [15:0] DESC_HSCFG_LEN      ;
wire [15:0] DESC_OSCFG_ADDR     ;
wire [15:0] DESC_HIDRPT_ADDR    ;
wire [15:0] DESC_HIDRPT_LEN     ;
wire [15:0] DESC_BOS_ADDR       ;
wire [15:0] DESC_BOS_LEN        ;
wire [15:0] DESC_STRLANG_ADDR   ;
wire [15:0] DESC_STRVENDOR_ADDR ;
wire [15:0] DESC_STRVENDOR_LEN  ;
wire [15:0] DESC_STRPRODUCT_ADDR;
wire [15:0] DESC_STRPRODUCT_LEN ;
wire [15:0] DESC_STRSERIAL_ADDR ;
wire [15:0] DESC_STRSERIAL_LEN  ;
wire        DESCROM_HAVE_STRINGS;

wire        RESET;                  //Global Reset
wire        usb_logic_rst;          //USB power-on reset

wire [7:0]  usb_txdat;
wire [11:0] usb_txdat_len;
wire        usb_txcork;
wire        usb_txpop;
wire        usb_txact;
wire [7:0]  usb_rxdat;
wire        usb_rxval;
wire        usb_rxpktval;
wire        usb_rxact;
wire        usb_rxrdy;
wire [3:0]  usb_endpt_sel;

wire        setup_active;
wire        endpt0_send;
wire [7:0]  endpt0_dat;
wire        pll_locked;
reg  [31:0] reset_cnt;


wire [7:0]  interface_alter_r;
wire [7:0]  interface_alter;
wire [7:0]  interface_sel;
wire        interface_update;

//CDC
wire [31:0] uart_dte_rate;
wire [7:0]  uart_char_format;
wire [7:0]  uart_parity_type;
wire [7:0]  uart_data_bits;
wire [11:0] uart_config_txdat_len;
wire [15:0] uart_tx_data    ;
wire        uart_tx_data_val;
wire        uart_tx_busy    ;
wire [15:0] uart_rx_data    ;
wire        uart_rx_data_val;

wire        clk24;             
wire        fclk_960M;         
wire        fclk;              
wire        xmclk;     

wire        lis_locked0;
wire        lis_locked1;

//========================================================================================================================================================================================================================================================================
// Overall Structure Description
//1) PLL  
//      Gowin_PLL_gen24                 Generate 24MHz operating clock
//      Gowin_PLL_usb                   Generate 60MHz operating clock + 960MHz sampling clock
//      Gowin_PLL_iis                   Generate 49.152MHz
//      Gowin_PLL_fclk                  Generate 98.304MHz
//2) USB IP
//      USB_Device_Controller_Top       USB_DEVICE_CTR IP 
//      USB2_0_SoftPHY_Top              USB Softphy IP
//3) USB EP0 config
//      usb_desc                        Device Descriptor (UAC2.0 HS)
//      USB_EP0_ctrl                    EP0 Specific Class Requirements and Some Parameter Processing (sample/mute/bits)
//                                      (Includes DFU Data Processing)
//4) USB ep top
//      usb_ep_top                      EP1~15 Data Processing
//5) UAC data 
//      IIS_CLK_GEN                     Spekaer+Mic IIS_LRCK/BCLK . This clock section can be modified to use an external input.
//      audio_tx_usb2pcm                Speaker     USB 8-bit parallel data     →   32-bit PCM parallel data
//      audio_tx_pcm2iis                Speaker     32-bit PCM parallel data    →   IIS serial data
//      speaker_feedback                Speaker     Asynchronous feedback - feedback coefficient calculation
//6) SPI flash controller （DFU）
//      spi_flash_controller            Perform read and write operations on SPI flash.
//7) HID
//      loopback

//===================================================================================================================================================================================
// 1) PLL   
//    Generate the clocks needed for subsequent operations, where the 60MHz and 960MHz USB portions must be retained.
//====================================================================================================================================================================================
    Gowin_PLL_gen24 pll0(
        .lock   (lock_o     ), //output lock
        .clkout0(clk24      ), //output clkout0
        .mdclk  (CLK_IN     ),   //input  mdclk
        .clkin  (CLK_IN     ) //input clkin
    );
    Gowin_PLL_usb pll1(
        .lock   (pll_locked ), //output lock
        .clkout0(PHY_CLKOUT ), //output clkout0
        .clkout1(fclk_960M  ), //output clkout1
        .mdclk  (clk24      ),   //input  mdclk
        .clkin  (clk24      ) //input clkin
    );


//=================================================    ATTENTION!! ==============================================================//
// Note!!: In actual operation, please replace the IIS_CLK_49152 and IIS_CLK_45158 clocks with an external crystal oscillator.
// 注意!! ： 正式工作中，请以外部晶振替代 IIS_CLK_49152，IIS_CLK_45158 两个时钟
logic   IIS_CLK_49152;
logic   IIS_CLK_45158;
    Gowin_PLL_iis iis_pll0(
        .clkin      (clk24          ), //input  clkin
        .clkout0    (IIS_CLK_49152  ), //output  clkout0
        .clkout1    (IIS_CLK_45158  ), //output  clkout1
        .lock       (lis_locked0    ), //output  lock
        .mdclk      (clk24          ) //input  mdclk
);

//=================================================    ATTENTION!! ==============================================================//

reg [3:0]   clksel ; // 49.152Mhz , 45.1584Mhz 
always_ff @ ( * ) begin
	case ( sample_rate )
	SAMPLE_RATE_32    : clksel <= 4'b0001;
	SAMPLE_RATE_44_1  : clksel <= 4'b0010;
	SAMPLE_RATE_48    : clksel <= 4'b0001;
	SAMPLE_RATE_64    : clksel <= 4'b0001;
	SAMPLE_RATE_88_2  : clksel <= 4'b0010;
	SAMPLE_RATE_96    : clksel <= 4'b0001;
	SAMPLE_RATE_128   : clksel <= 4'b0001;
	SAMPLE_RATE_176_4 : clksel <= 4'b0010;
	SAMPLE_RATE_192   : clksel <= 4'b0001;
	SAMPLE_RATE_352_8 : clksel <= 4'b0010;
	SAMPLE_RATE_384   : clksel <= 4'b0001;
	SAMPLE_RATE_705_6 : clksel <= 4'b0010;
	SAMPLE_RATE_768   : clksel <= 4'b0001;
	default :           clksel <= 4'b0000;
	endcase
end

    Gowin_DCS Gowin_DCS_inst(
        .clkout     (xmclk      ), //output clkout
        .clksel     (clksel     )    , //input [3:0] clksel
        .clkin0     (IIS_CLK_49152), //input clk0
        .clkin1     (IIS_CLK_45158), //input clk1
        .clkin2     (1'b0), //input clk2
        .clkin3     (1'b0) //input clk3
    );

    Gowin_PLL_fclk iis_pll1(
        .clkin  (xmclk      ), //input  clkin
        .clkout0(fclk       ), //output  clkout0
        .mdclk  (clk24      ) //input  mdclk
);


assign RESET = (~pll_locked)||(reset_cnt <= 32'd60000);
always@(posedge PHY_CLKOUT, negedge pll_locked) begin
    if (!pll_locked) begin
        reset_cnt <= 32'd0;
    end
    else begin
        if (reset_cnt <= 32'd60000) begin
            reset_cnt <= reset_cnt + 1'd1;
        end
    end
end
assign LED = !RESET;
//=================================================END 1)==============================================================================================================================




//===================================================================================================================================================================================
// 2) USB Device Controller IP  
//   Inherent USB port IP module 
//====================================================================================================================================================================================
USB_Device_Controller_Top u_usb_device_controller_top (
     .clk_i                 (PHY_CLKOUT          )
    ,.reset_i               (usb_logic_rst       )
    ,.usbrst_o              (usb_busreset        )
    ,.highspeed_o           (usb_highspeed       )
    ,.suspend_o             (usb_suspend         )
    ,.online_o              (usb_online          )
    ,.txdat_i               (usb_txdat           )
    ,.txval_i               (usb_txval           )
    ,.txdat_len_i           (usb_txdat_len       )
    ,.txcork_i              (usb_txcork          )
    ,.txiso_pid_i           (4'b0011             )
    ,.txpop_o               (usb_txpop           )
    ,.txact_o               (usb_txact           )
    ,.txpktfin_o            (usb_txpktfin        )
    ,.rxdat_o               (usb_rxdat           )
    ,.rxval_o               (usb_rxval           )
    ,.rxact_o               (usb_rxact           )
    ,.rxrdy_i               (usb_rxrdy           )
    ,.rxpktval_o            (usb_rxpktval        )
    ,.setup_o               (setup_active        )
    ,.endpt_o               (usb_endpt_sel       )
    ,.sof_o                 (usb_sof             )
    ,.inf_alter_i           (interface_alter_r   )
    ,.inf_alter_o           (interface_alter     )
    ,.inf_sel_o             (interface_sel       )
    ,.inf_set_o             (interface_update    )
    ,.descrom_rdata_i       (DESCROM_RDAT        )
    ,.descrom_raddr_o       (DESCROM_RADDR       )
    ,.desc_index_o          (DESC_INDEX          )
    ,.desc_type_o           (DESC_TYPE           )
    ,.desc_dev_addr_i       (DESC_DEV_ADDR       )
    ,.desc_dev_len_i        (DESC_DEV_LEN        )
    ,.desc_qual_addr_i      (DESC_QUAL_ADDR      )
    ,.desc_qual_len_i       (DESC_QUAL_LEN       )
    ,.desc_fscfg_addr_i     (DESC_FSCFG_ADDR     )
    ,.desc_fscfg_len_i      (DESC_FSCFG_LEN      )
    ,.desc_hscfg_addr_i     (DESC_HSCFG_ADDR     )
    ,.desc_hscfg_len_i      (DESC_HSCFG_LEN      )
    ,.desc_oscfg_addr_i     (DESC_OSCFG_ADDR     )
    ,.desc_hidrpt_addr_i    (DESC_HIDRPT_ADDR    )//DESC_HIDRPT_ADDR
    ,.desc_hidrpt_len_i     (DESC_HIDRPT_LEN     )//DESC_HIDRPT_LEN
    ,.desc_bos_addr_i       (DESC_BOS_ADDR       )//DESC_BOS_ADDR
    ,.desc_bos_len_i        (DESC_BOS_LEN        )//DESC_BOS_LEN
    ,.desc_strlang_addr_i   (DESC_STRLANG_ADDR   )
    ,.desc_strvendor_addr_i (DESC_STRVENDOR_ADDR )
    ,.desc_strvendor_len_i  (DESC_STRVENDOR_LEN  )
    ,.desc_strproduct_addr_i(DESC_STRPRODUCT_ADDR)
    ,.desc_strproduct_len_i (DESC_STRPRODUCT_LEN )
    ,.desc_strserial_addr_i (DESC_STRSERIAL_ADDR )
    ,.desc_strserial_len_i  (DESC_STRSERIAL_LEN  )
    ,.desc_have_strings_i   (DESCROM_HAVE_STRINGS)
    
    ,.utmi_dataout_o        (PHY_DATAOUT       )
    ,.utmi_txvalid_o        (PHY_TXVALID       )
    ,.utmi_txready_i        (PHY_TXREADY       )
    ,.utmi_datain_i         (PHY_DATAIN        )
    ,.utmi_rxactive_i       (PHY_RXACTIVE      )
    ,.utmi_rxvalid_i        (PHY_RXVALID       )
    ,.utmi_rxerror_i        (PHY_RXERROR       )
    ,.utmi_linestate_i      (PHY_LINESTATE     )
    ,.utmi_opmode_o         (PHY_OPMODE        )
    ,.utmi_xcvrselect_o     (PHY_XCVRSELECT    )
    ,.utmi_termselect_o     (PHY_TERMSELECT    )
    ,.utmi_reset_o          (PHY_RESET         )
);
//==============================================================
//======USB SoftPHY
USB2_0_SoftPHY_Top u_USB_SoftPHY_Top
(
     .clk_i            (PHY_CLKOUT     )
    ,.rst_i            (PHY_RESET      )
    ,.fclk_i           (fclk_960M      )
    ,.pll_locked_i     (pll_locked     )
    ,.utmi_data_out_i  (PHY_DATAOUT    )
    ,.utmi_txvalid_i   (PHY_TXVALID    )
    ,.utmi_op_mode_i   (PHY_OPMODE     )
    ,.utmi_xcvrselect_i(PHY_XCVRSELECT )
    ,.utmi_termselect_i(PHY_TERMSELECT )
    ,.utmi_data_in_o   (PHY_DATAIN     )
    ,.utmi_txready_o   (PHY_TXREADY    )
    ,.utmi_rxvalid_o   (PHY_RXVALID    )
    ,.utmi_rxactive_o  (PHY_RXACTIVE   )
    ,.utmi_rxerror_o   (PHY_RXERROR    )
    ,.utmi_linestate_o (PHY_LINESTATE  )
	,.usb_dxp_io       (usb_dxp_io     ) //inout usb_dxp_io
	,.usb_dxn_io       (usb_dxn_io     ) //inout usb_dxn_io
    ,.usb_rxdp_i       (usb_rxdp_i     )
    ,.usb_rxdn_i       (usb_rxdn_i     )
    ,.usb_pullup_en_o  (usb_pullup_en_o)
    ,.usb_term_dp_io   (usb_term_dp_io )
    ,.usb_term_dn_io   (usb_term_dn_io )
);
//=================================================END 2)==============================================================================================================================





//===================================================================================================================================================================================
// 3) USB EP0 config 
//      usb_desc                        Device Descriptor (UAC2.0 HS)
//      uac_ctrl                        EP0 Specific Class Requirements and Some Parameter Processing (sample/mute/bits)
//                                      (Includes DFU Data Processing)
//====================================================================================================================================================================================
usb_desc
#(
     .VENDORID    (16'h33AA)
    ,.PRODUCTID   (16'h1800)
    ,.VERSIONBCD  (16'h0100)
)
u_usb_desc (
     .CLK                    (PHY_CLKOUT          )
    ,.RESET                  (usb_logic_rst       )

    ,.i_dfu_mode             (dfu_mode            )

    ,.i_descrom_raddr        (DESCROM_RADDR       )
    ,.o_descrom_rdat         (DESCROM_RDAT        )
    ,.i_desc_index_o         (DESC_INDEX          )
    ,.i_desc_type_o          (DESC_TYPE           ) 

    ,.o_desc_dev_addr        (DESC_DEV_ADDR       )
    ,.o_desc_dev_len         (DESC_DEV_LEN        )
    ,.o_desc_qual_addr       (DESC_QUAL_ADDR      )
    ,.o_desc_qual_len        (DESC_QUAL_LEN       )
    ,.o_desc_fscfg_addr      (DESC_FSCFG_ADDR     )
    ,.o_desc_fscfg_len       (DESC_FSCFG_LEN      )
    ,.o_desc_hscfg_addr      (DESC_HSCFG_ADDR     )
    ,.o_desc_hscfg_len       (DESC_HSCFG_LEN      )
    ,.o_desc_hidrpt_addr     (DESC_HIDRPT_ADDR    )
    ,.o_desc_hidrpt_len      (DESC_HIDRPT_LEN     )
    ,.o_desc_oscfg_addr      (DESC_OSCFG_ADDR     )
    ,.o_desc_strlang_addr    (DESC_STRLANG_ADDR   )
    ,.o_desc_strvendor_addr  (DESC_STRVENDOR_ADDR )
    ,.o_desc_strvendor_len   (DESC_STRVENDOR_LEN  )
    ,.o_desc_strproduct_addr (DESC_STRPRODUCT_ADDR)
    ,.o_desc_strproduct_len  (DESC_STRPRODUCT_LEN )
    ,.o_desc_strserial_addr  (DESC_STRSERIAL_ADDR )
    ,.o_desc_strserial_len   (DESC_STRSERIAL_LEN  )
    ,.o_descrom_have_strings (DESCROM_HAVE_STRINGS)
);


//==============================================================
//======EP0 Controller
wire     	    iis0_endpt_send;
wire [ 7:0]     iis0_endpt_dat;
// --- UAC Control Signals ---
logic [7:0]     tx_data_bits;
logic [7:0]     rx_data_bits;
wire            mute;              
wire [15:0]     ch0_volume;        
wire [15:0]     ch1_volume;        
wire [15:0]     ch2_volume;   
wire [31:0]     sample_rate;    
// --- DFU Mode Control Signals ---
logic        dfu_detach_flag;
logic [1:0]  dfu_detach_flag_r;      
logic        dfu_detach_flag_fall;      // Start the power-on countdown on the falling edge of dfu_detach_flag
logic        dfu_mode = 0 ;             // 0: Normal App, 1: DFU Mode
logic [27:0] disconnect_timer;          // Disconnect time, commonly 1 second. Here, to ensure a margin, it is set to 500ms
USB_EP0_ctrl #(
     .CLOCK_SOURCE_ID          (CLOCK_SOURCE_ID         )//Clock Source
    ,.FEATURE_UNIT_ID          (FEATURE_UNIT_ID         )//Audio Control Feature Unit
)
uac_ctrl_inst
( 
     .PHY_CLKOUT        (PHY_CLKOUT       )//clock
    ,.RESET             (RESET            )//reset

    ,.I_USB_SETUP       (setup_active     )
    ,.I_USB_ENDPT_SEL   (usb_endpt_sel    )
    ,.I_USB_RXPKTVAL    (usb_rxpktval     )
    ,.I_USB_RXACT       (usb_rxact        )
    ,.I_USB_RXVAL       (usb_rxval        )
    ,.I_USB_RXDAT       (usb_rxdat        )
    ,.I_USB_TXACT       (usb_txact        )
    ,.I_USB_TXPOP       (usb_txpop        )

    ,.I_INTERFACE_ALTER (interface_alter  )
    ,.O_INTERFACE_ALTER (interface_alter_r)
    ,.I_INTERFACE_SEL   (interface_sel    )
    ,.I_INTERFACE_UPDATE(interface_update )
//==================================================
    ,.endpt0_send_0     (iis0_endpt_send    )   
    ,.endpt0_dat_0      (iis0_endpt_dat     )

//UAC
    ,.O_MUTE            (mute               )
    ,.O_CH0_VOLUME      (ch0_volume         )
    ,.O_CH1_VOLUME      (ch1_volume         )
    ,.O_CH2_VOLUME      (ch2_volume         )
    ,.O_SAMPLE_RATE     (sample_rate        )
    ,.O_TX_DATA_BITS    (tx_data_bits       )
    ,.O_RX_DATA_BITS    (rx_data_bits       )
//CDC
    ,.O_UART1_BAUD_RATE (uart_dte_rate      )
    ,.O_UART1_PARITY_BIT(uart_parity_type   )
    ,.O_UART1_STOP_BIT  (uart_char_format   )
    ,.O_UART1_DATA_BITS (uart_data_bits     )

    ,.O_DOP_EN          (dop_en             )
    ,.O_DSD_EN          (dsd_en             )
// DFU Control  
    ,.i_dfu_mode          (dfu_mode             )
    ,.o_dfu_detach_flag   (dfu_detach_flag      )
// EP0 DFU DATA     
    ,.o_dfu_spi_wr_req     (dfu_spi_wr_req      )
    ,.i_dfu_spi_wr_ack     (m_spi_wr_ack        )
    ,.o_dfu_spi_wr_flush   (dfu_spi_wr_flush    )
    ,.o_dfu_spi_lba        (dfu_spi_lba         )
    ,.i_dfu_spi_buf_addr   (m_spi_buf_addr      )
    ,.o_dfu_spi_buf_rdata  (dfu_spi_buf_rdata   ) 
);
//=================================================END 3)==============================================================================================================================


//===================================================================================================================================================================================
// 4) USB EP1-15 process 
// EP1~15 Data Processing
// There are three data processing modes: 1. Pingpong-RAM based(UMS); 2. Unlimited length FIFO read/write(CDC/HID) 3. Length-limited FIFO read/write(UAC)
//====================================================================================================================================================================================
wire        ep_usb_txcork   ;
wire        ep_usb_rxrdy    ;
wire [11:0] ep_usb_txlen    ;
wire [ 7:0] ep_usb_txdat    ;
wire        audio_rx_full   ;
//==UAC
logic           audio_tx_dval;
logic [7:0]     audio_tx_data;
logic           audio_rx_dval;
logic [7:0]     audio_rx_data;

logic [11:0]    audio_packet_max ,   audio_packet_nor    ,   audio_packet_min;
//==HID
logic           ep2_tx_dval;
logic [7:0]     ep2_tx_data;
logic           ep2_rx_dval;
logic [7:0]     ep2_rx_data;


ep_mem_out_if ep_mem_out_bus [15:1] ();
ep_mem_in_if  ep_mem_in_bus  [15:1] ();

ep_fifo_out_if ep_out_bus [15:1] ();
ep_fifo_in_if  ep_in_bus  [15:1] ();

usb_ep_top #(
        // 0:DISABLE, 1:UMS(RAM), 2:CDC(FIFO), 3:UAC(Audio)
        // 1 SPEAKER    2 HID 

    `ifdef HIFI_ONLY 
        .EP_OUT_MODE ( '{ 1:3, default:0 } ),
        .EP_IN_MODE  ( '{ 1:0, default:0 } ),
    `else
        .EP_OUT_MODE ( '{ 1:3, 2:2, default:0 } ),
        .EP_IN_MODE  ( '{ 1:0, 2:2, default:0 } ),
    `endif
        
        .EP_UAC_INTF ( '{ 1:SPEAKER_INTERFACE,
                          default:0 } ) 
    ) u_usb_ep_top (
        .i_clk              (PHY_CLKOUT         ), // clock
        .i_reset            (usb_busreset       ), // reset (对齐原 usb_fifo 高电平复位) [cite: 341]
        .i_usb_endpt        (usb_endpt_sel      ),

        .i_usb_rxact        (usb_rxact          ),
        .i_usb_rxval        (usb_rxval          ),
        .i_usb_rxpktval     (usb_rxpktval       ),
        .i_usb_rxdat        (usb_rxdat          ),
        .o_usb_rxrdy        (ep_usb_rxrdy       ),

        .i_usb_txact        (usb_txact          ),
        .o_usb_txcork       (ep_usb_txcork      ),
        .i_usb_txpop        (usb_txpop          ),
        .i_usb_txpktfin     (usb_txpktfin       ),
        .i_interface_sel    (interface_sel      ),
        .i_interface_alter  (interface_alter_r  ),
        .o_usb_txdat        (ep_usb_txdat       ),
        .o_usb_txlen        (ep_usb_txlen       ),

        //=======================
        //UMS
        .ep_mem_out         (ep_mem_out_bus     ),
        .ep_mem_in          (ep_mem_in_bus      ),
        //OTHER
        .ep_fifo_out        (ep_out_bus         ),
        .ep_fifo_in         (ep_in_bus          )
    );

// ---------------------------------------------------------
    // EP1: UAC OUT (Speaker) 
    // ---------------------------------------------------------
    assign ep_out_bus[1].i_rx_clk = PHY_CLKOUT;
    assign ep_out_bus[1].i_rx_rdy = 1'b1;         // Always ready to receive
    assign audio_tx_dval          = ep_out_bus[1].o_rx_dval;
    assign audio_tx_data          = ep_out_bus[1].o_rx_data;

    // ---------------------------------------------------------
    // EP2: HID OUT + IN (Interrupted TRANS) 
    // ---------------------------------------------------------
    `ifndef HIFI_ONLY 
    //EP2 OUT    
    assign ep_out_bus[2].i_rx_clk = PHY_CLKOUT;
    assign ep_out_bus[2].i_rx_rdy = 1'b1; 
    assign ep2_rx_dval            = ep_out_bus[2].o_rx_dval; 
    assign ep2_rx_data            = ep_out_bus[2].o_rx_data; 

    //EP2 IN
    assign ep_in_bus[2].i_tx_clk  = PHY_CLKOUT;
    assign ep_in_bus[2].i_tx_max  = 12'd512; 
    assign ep_in_bus[2].i_tx_dval = ep2_tx_dval;
    assign ep_in_bus[2].i_tx_data = ep2_tx_data;
    `endif

// ---------------------------------------------------------
//=================================================HIFI END 4)==============================================================================================================================


//===================================================================================================================================================================================
//5) UAC data 
//  UAC Version ：2.0
//  44.1khz，48kHz family audio sampling rate  
//  Shared clock source: 
//  Explicit Asynchronous Feedback
//  2CN Single Project 
//  UAC protocol ：IIS + DSD + DOP
//====================================================================================================================================================================================
//    

//========================================================================================
//====================================Audio TX============================================
//========================================================================================

logic        w_bclk_fall_pulse;
IIS_CLK_GEN  speaker_CLK_GEN_inst
(
	 .PHY_CLKOUT 	    (PHY_CLKOUT	    ) 
	,.MCLK 			    (fclk			) 
	,.RESET			    (RESET			) 
    ,.I_DATA_BITS  	    (tx_data_bits   ) 
	,.I_SAMPLE_RATE     (sample_rate	) 

    ,.O_IIS_LRCK        (dac_lrclk      )
    ,.O_IIS_BCLK        (dac_bclk       )	
    ,.O_BCLK_FALL_PULSE (w_bclk_fall_pulse) 
);

wire            tx_en;

wire    [7:0]   speaker_bclk_div  ; // 
wire            speaker_alempty   ; //
wire            speaker_alfull    ; //
logic   [$clog2(CHANNEL_NUM)-1:0]           o_addr;
logic   [                   31:0]           o_data;
logic                                       o_winc;

//o_winc           ________________________
//              __/                        \_______
//o_addr        __ ____ _____ _____ ______ _______
//              __X_0__X__1__X__2__X__3___X_______
//o_data        __ ____ _____ _____ ______ _______
//[31:0]        __X_~__X__~__X__~__X__~___X_______
audio_tx_usb2pcm 
#(
    .CH_NUM     (CHANNEL_NUM      )
)
usb2pcm_inst1
(   
     .PHY_CLKOUT        (PHY_CLKOUT           )
    ,.RESET             (RESET                )
    ,.MCLK              (fclk                 )

    ,.I_SOF             (usb_sof              )

    ,.I_SAMPLE_RATE     (sample_rate          )
    ,.I_DATA_BITS       (tx_data_bits         )
    ,.I_CLK_SEL         ('b0                  )//while Async mode ,not care

    ,.I_DSD_EN          (dsd_en               )
    ,.I_DOP_EN          (dop_en               )

    ,.O_TX_EN           (tx_en                )
    ,.O_BCLK_DIV        (speaker_bclk_div     )
    ,.O_FIFO_ALEMPTY    (speaker_alempty      )
    ,.O_FIFO_ALFULL     (speaker_alfull       )

    ,.EXT_LRCK          (dac_lrclk            )

    //======USB DATA
    ,.I_AUDIO_DVAL      (audio_tx_dval        )
    ,.I_AUDIO_DATA      (audio_tx_data        )
    //======PCM DATA   
    ,.O_ADDR            (o_addr               )
    ,.O_DATA            (o_data               )
    ,.O_WINC            (o_winc               )
);

wire dsd_en ;
wire dop_en ;
logic [(CHANNEL_NUM/2)-1:0]     speaker_iis_data;
audio_tx_pcm2iis 
#(
    .CH_NUM     (CHANNEL_NUM      )
) 
audio_tx_pcm2iis_inst
(
     .MCLK              (fclk                   )
    ,.RESET             (RESET                  )


    ,.I_TX_EN           (tx_en&&(!(dsd_en|dop_en)))
    ,.I_IIS_BCLK        (dac_bclk               )    
    ,.I_IIS_LRCK        (dac_lrclk              )    
    ,.I_BCLK_FALL_PULSE (w_bclk_fall_pulse      )

    ,.I_WINC            (o_winc                 )
    ,.I_ADDR            (o_addr                 )
    ,.I_DATA            (o_data                 )

    ,.O_IIS_DATA        (speaker_iis_data       )
);

assign IIS_BCLK_O   =  dac_bclk;
assign IIS_LRCK_O   =  dac_lrclk;
assign IIS_DATA1_O  =  speaker_iis_data[0];

audio_tx_pcm2dsd 
audio_tx_pcm2dsd_inst(
     .MCLK              (fclk               )// 音频主时钟
    ,.RESET             (RESET              )// 全局复位

    ,.I_ENABLE          (tx_en&&(dsd_en|dop_en))// DSD使能 
    ,.I_DATA_BITS       (tx_data_bits       )
    ,.I_DOP_EN          (dop_en             )
    ,.I_BCLK_DIV        (speaker_bclk_div   )

    ,.I_WINC            (o_winc             )// 脉冲写使能
    ,.I_ADDR            (o_addr             )// 通道地址 (0: Left, 1: Right)
    ,.I_DATA            (o_data             )// 32-bit 同步数据

    ,.O_DSD_CLK         (speaker_dsd_clk    )
    ,.O_DSD_DATA1       (speaker_dsd_data1  )// Left DSD out
    ,.O_DSD_DATA2       (speaker_dsd_data2  )// Right DSD out  
);

assign DSD_CLK_O    =  speaker_dsd_clk  ;
assign DSD_DATA1_O  =  speaker_dsd_data1;
assign DSD_DATA2_O  =  speaker_dsd_data2;

// Explicit Asynchronous Feedback
wire [ 7:0]     iis1_feedback   ;
speaker_feedback #(
     .AUDIO_SPEAKER_ENDPOINT    (SPEAKER_IN_FB_ENDPOINT[3:0])
)
speaker_feedback_inst1(
     .PHY_CLKOUT         (PHY_CLKOUT        )
    ,.RESET              (RESET             )
    ,.XMCLK              (xmclk             )

    ,.I_USB_SOF          (usb_sof           )
    ,.I_USB_TXACT        (usb_txact         )
    ,.I_USB_ENDPT_SEL    (usb_endpt_sel     )
    ,.I_USB_TXPOP        (usb_txpop         )
    ,.I_SAMPLE_RATE      (sample_rate       )

    ,.I_FIFO_ALEMPTY     (speaker_alempty   )
    ,.I_FIFO_ALFULL      (speaker_alfull    )

    ,.O_FEEDBACK         (iis1_feedback     )
);
//========================================================================================
//====================================Audio RX============================================
//=======================================================================================
// HIFI不包含Audio RX
//=================================================END 5)==============================================================================================================================


//===================================================================================================================================================================================
//6) SPI flash controller （DFU）
//  UMS + DFU  Perform read and write operations on SPIflash using “spi_flash_controller”
//  The two will not work at the same time. 
//  UMS is not included here.
//  UMS + DFU  均会对spi flash进行操作 “spi_flash_controller”
//  两者不会同时工作. 
//  此处不包含 UMS.
//====================================================================================================================================================================================

`ifndef HIFI_ONLY 


always @(posedge PHY_CLKOUT or posedge RESET) begin
    if (RESET) begin
        dfu_detach_flag_r <= 2'b0;
    end else begin
        dfu_detach_flag_r <= {dfu_detach_flag_r[0],dfu_detach_flag};
    end
end

assign dfu_detach_flag_fall = (dfu_detach_flag_r == 2'b10 );

// --- DFU Disconnect Timer & Mode Switch ---
always @(posedge PHY_CLKOUT or posedge RESET) begin
    if (RESET) begin
        dfu_mode <= 1'b0;
        disconnect_timer <= 28'd0;
    end 
    else begin
        // Triggered when the detach flag is received and the system is not currently in DFU mode.
        if (dfu_detach_flag_fall ) begin
            dfu_mode <= ~dfu_mode;                  // Switch to DFU mode/APP mode
            disconnect_timer <= 28'd30_000_000;     // 500ms 
        end
        else if (disconnect_timer > 0) begin
            disconnect_timer <= disconnect_timer - 1'b1;
        end
    end
end

assign usb_logic_rst = RESET | (disconnect_timer > 0);

//==============================================================
//====== SPI Bus Multiplexer (UMS vs DFU)
//==============================================================
//MUX selects to enter the flash_ctr bus
wire [31:0] m_spi_lba;
wire        m_spi_wr_req;
wire        m_spi_wr_flush;
wire [7:0]  m_spi_buf_rdata;

wire        m_spi_rd_req;
//UMS dedicated control line no used
//DFU dedicated control line
wire [31:0] dfu_spi_lba;
wire        dfu_spi_wr_req;
wire        dfu_spi_wr_flush;
wire [7:0]  dfu_spi_buf_rdata;
//Shared line
wire        m_spi_rd_ack;
wire        m_spi_wr_ack;
wire        m_spi_buf_we;
wire  [8:0] m_spi_buf_addr;
wire  [7:0] m_spi_buf_wdata;

assign m_spi_lba       = dfu_spi_lba       ;
assign m_spi_wr_req    = dfu_spi_wr_req    ;
assign m_spi_wr_flush  = dfu_spi_wr_flush  ;
assign m_spi_buf_rdata = dfu_spi_buf_rdata ;
assign m_spi_rd_req    = 1'b0              ; // DFU only writes and does not read, forcibly pulling low


spi_flash_controller #(
    .CLK_DIV  ( 1   ) 
)
spi_flash_controller
(
     .clk               (PHY_CLKOUT   )
    ,.rst_n             (!RESET       )
    
    ,.is_dfu_mode       (dfu_mode       )

    ,.spi_lba           (m_spi_lba        ) 

    ,.spi_rd_req        (m_spi_rd_req     )
    ,.spi_rd_ack        (m_spi_rd_ack     )

    ,.spi_wr_req        (m_spi_wr_req     )
    ,.spi_wr_ack        (m_spi_wr_ack     )
    ,.spi_wr_flush      (m_spi_wr_flush  )

    ,.spi_buf_we        (m_spi_buf_we     )
    ,.spi_buf_addr      (m_spi_buf_addr   )
    ,.spi_buf_wdata     (m_spi_buf_wdata  )
    ,.spi_buf_rdata     (m_spi_buf_rdata  )

    ,.spi_clk           (spi_sclk       )
    ,.spi_cs_n          (spi_cs         )
    ,.spi_mosi          (spi_mosi       )
    ,.spi_miso          (spi_miso       )
);

//=================================================END 6)==============================================================================================================================

//===================================================================================================================================================================================
//6) HID
// No special treatment is required, only loop closure test.
// 不做任何处理，仅回环测试
//====================================================================================================================================================================================

//HID loopback

logic           ep2_tx_dval;
logic [7:0]     ep2_tx_data;
logic           ep2_rx_dval;
logic [7:0]     ep2_rx_data;
always @(posedge PHY_CLKOUT or posedge RESET) begin
    if (RESET) begin
        ep2_tx_dval <= 1'b0 ;
        ep2_tx_data <= 8'b0 ;
    end 
    else begin
        ep2_tx_dval <= ep2_rx_dval ;
        ep2_tx_data <= ep2_rx_data ;
    end
end

    `endif

//==============================================================
//======Tx Cork
// Distribution of USB EP signals

assign usb_rxrdy        =   (usb_endpt_sel == 4'd0  )  ? 1'b1          :ep_usb_rxrdy;

assign usb_txcork       =   (usb_endpt_sel == HID_IN_ENDPOINT[3:0]) ? ep_usb_txcork :
                            1'b0;

assign usb_txval        =   iis0_endpt_send ;

assign usb_txdat        =   (usb_endpt_sel == 0) ? iis0_endpt_dat : 
                            (usb_endpt_sel == SPEAKER_IN_FB_ENDPOINT[3:0]) ? iis1_feedback : //UAC20 16.16
                            ep_usb_txdat;

assign usb_txdat_len    =   (usb_endpt_sel == 4'd0 ) ?  12'h8 :
                            (usb_endpt_sel == SPEAKER_IN_FB_ENDPOINT[3:0]) ? 12'h4 : //UAC20 4bit
                            ep_usb_txlen ;


endmodule
