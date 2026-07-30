module usb_uac_in_buf #(
    parameter P_INTERFACE = 1,
    parameter P_ENDPOINT = 1,
    parameter P_AFULL    = 400,
    parameter P_DSIZE    = 8,
    parameter P_ASIZE    = 9
)
(
    input              i_clk         ,//clock
    input              i_reset       ,//reset
    input      [3:0]   i_usb_endpt   ,//
    input              i_usb_txact   ,//
    input              i_usb_txpop   ,//
    input              i_usb_txpktfin,//
	input	   [7:0]   i_interface_sel,
	input	   [7:0]   i_interface_alter,
	output			   o_usb_txfull     ,
	output			   o_usb_txalfull   ,
	output			   o_usb_txalempty  ,

    output     [7:0]   o_usb_txdat   ,//
    output             o_usb_txcork  ,//
    output     [11:0]  o_usb_txlen   ,//
    input      [11:0]  i_ep_pkt_nor  ,//
    input      [11:0]  i_ep_pkt_min  ,//
    input              i_ep_clk      ,//
    input              i_ep_tx_dval  ,//
    input      [7:0]   i_ep_tx_data  //
);
//==============================================================
//======cross fifo
    wire               pkt_fifo_wr;
    reg                pkt_fifo_wr_act;
    reg                pkt_fifo_wr_pktval;
    wire [P_DSIZE-1:0] pkt_fifo_wr_data;
    wire               pkt_fifo_rd_pktfin;
    wire               pkt_fifo_rd_act;
    wire               pkt_fifo_rd;
    reg                pkt_fifo_rd_dval;
    wire [P_DSIZE-1:0] pkt_fifo_rd_data;
    wire [P_DSIZE-1:0] pkt_fifo_rd_data_c;	
    wire [P_ASIZE+1 :0] pkt_fifo_wr_num;
    wire [P_ASIZE  :0] pkt_fifo_wr_num_c;	
    reg  [P_ASIZE+1  :0] pkt_fifo_wr_num_d0;
    wire               c_fifo_wr;
    wire [P_DSIZE-1:0] c_fifo_wr_data;
    reg                c_fifo_rd;
    reg                c_fifo_rd_dval;
    wire [P_DSIZE-1:0] c_fifo_rd_data;
    wire               c_fifo_empty;

    wire               pkt_fifo_empty;

    assign c_fifo_wr      = i_ep_tx_dval;
    assign c_fifo_wr_data = i_ep_tx_data;
    clk_cross_fifo #(
       .DSIZE (8  )
      ,.ASIZE (6  )
      ,.AEMPT (1  )
      ,.AFULL (32 )
    )clk_cross_fifo
    (
         .WrClock    (i_ep_clk      )
        ,.Reset      (i_reset       )
        ,.WrEn       (c_fifo_wr     )
        ,.Data       (c_fifo_wr_data)
        ,.AlmostFull (              )
        ,.Full       ()
        ,.RdClock    (i_clk         )
        ,.RPReset    (i_reset       )
        ,.RdEn       (c_fifo_rd     )
        ,.Q          (c_fifo_rd_data)
        ,.AlmostEmpty()
        ,.Empty      (c_fifo_empty  )
    );


    always@(posedge i_clk, posedge i_reset) begin
        if (i_reset) begin
            c_fifo_rd <= 1'b0;
        end
        else begin
            if (c_fifo_empty) begin
                c_fifo_rd <= 1'b0;
            end
            else begin
                c_fifo_rd <= 1'b1;
            end
        end
    end
    always@(posedge i_clk, posedge i_reset) begin
        if (i_reset) begin
            c_fifo_rd_dval <= 1'b0;
        end
        else begin
            c_fifo_rd_dval <= c_fifo_rd & (!c_fifo_empty);
        end
    end

//==============================================================
//======usb packet crc check fifo
assign pkt_fifo_wr        = c_fifo_rd_dval;
assign pkt_fifo_wr_data   = c_fifo_rd_data;
assign pkt_fifo_rd_pktfin = i_usb_txpktfin&(i_usb_endpt==P_ENDPOINT);
assign pkt_fifo_rd_act    = i_usb_txact&(i_usb_endpt==P_ENDPOINT);
assign pkt_fifo_rd        = i_usb_txpop&(i_usb_endpt==P_ENDPOINT);
assign o_usb_txdat        = pkt_fifo_rd_data;
assign o_usb_txcork       = pkt_fifo_wr_num < i_ep_pkt_min;
assign o_usb_txlen        = pkt_fifo_wr_num_d0;

    always@(posedge i_clk, posedge i_reset) begin
        if (i_reset) begin
            pkt_fifo_wr_num_d0 <= 1'b0;
        end
        else begin
            pkt_fifo_wr_num_d0 <= pkt_fifo_wr_num;
        end
    end


reg rx_bits_change ;
reg rx_bits_d1	   ;

reg rst ;
reg [3:0] i_usb_endpt_d ;
always @ ( posedge i_clk or posedge i_reset )begin
	if(i_reset)
		i_usb_endpt_d <= 1'b0 ;
	else
		i_usb_endpt_d <= i_usb_endpt ;
end

always @ ( posedge i_clk or posedge i_reset )begin
	if(i_reset)
		rst <= 1'b1 ;
// 4080 是 4(16bit), 6(24bit), 8(32bit) 的公倍数 , 不会出现满包清空之后出现的错位现象
	else if ( pkt_fifo_wr_num >= 4080 )
		rst <= 1'b1 ;
	else if ( i_interface_sel == P_INTERFACE && i_interface_alter == 0 )
		rst <= 1'b1 ;
	else if ( rst == 1 &&  pkt_fifo_wr == 0 && i_usb_endpt == P_ENDPOINT )
		rst <= 1'b0 ;
	else
		rst <= rst ;
end

//260603

assign o_usb_txalempty = (pkt_fifo_wr_num < i_ep_pkt_nor);
assign o_usb_txalfull  = (pkt_fifo_wr_num > (i_ep_pkt_nor + (i_ep_pkt_nor >> 1)));


assign o_usb_txfull = rst ;

    sync_tx_pkt_fifo #(
         .DSIZE (8)
        ,.ASIZE (P_ASIZE)
    )sync_tx_pkt_fifo
    (
         .CLK   (i_clk              )
        ,.RSTn  ( ~(i_reset |  rst ))
        ,.write (pkt_fifo_wr        )
        ,.iData (pkt_fifo_wr_data   )
        ,.pktfin(pkt_fifo_rd_pktfin )
        ,.txact (pkt_fifo_rd_act    )
        ,.read  (pkt_fifo_rd        )
        ,.oData (pkt_fifo_rd_data   )
        ,.wrnum (pkt_fifo_wr_num    )
        ,.full  (               )
        ,.empty (pkt_fifo_empty     )
    );



endmodule