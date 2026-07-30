module usb_cdc_in_buf #(
    parameter P_ENDPOINT = 1,
    parameter P_DSIZE    = 8,
    parameter P_ASIZE    = 9
)
(
    input                      i_clk         ,//clock
    input                      i_reset       ,//reset
    input      [3:0]           i_usb_endpt   ,//
    input                      i_usb_txact   ,//
    input                      i_usb_txpop   ,//
    input                      i_usb_txpktfin,//
    output     [P_DSIZE-1:0]   o_usb_txdat   ,//
    output                     o_usb_txcork  ,//
    output     [P_ASIZE:0]     o_usb_txlen   ,//
    input                      i_ep_clk      ,//
    input                      i_ep_tx_dval  ,//
    input      [P_DSIZE-1:0]   i_ep_tx_data   //
);
//==============================================================
//======cross fifo
    wire               pkt_fifo_wr;
    wire               pkt_fifo_wr_act;
    wire               pkt_fifo_wr_pktval;
    wire [P_DSIZE-1:0] pkt_fifo_wr_data;
    wire               pkt_fifo_rd;
    reg                pkt_fifo_rd_dval;
    wire [P_DSIZE-1:0] pkt_fifo_rd_data;
    wire [P_ASIZE  :0] pkt_fifo_wr_num;
    reg  [P_ASIZE  :0] pkt_fifo_wr_num_d0;
    wire               pkt_fifo_empty;
    wire               c_fifo_wr;
    wire [P_DSIZE-1:0] c_fifo_wr_data;
    reg                c_fifo_rd;
    reg                c_fifo_rd_dval;
    wire [P_DSIZE-1:0] c_fifo_rd_data;
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
assign o_usb_txcork       = pkt_fifo_empty;
assign o_usb_txlen        = pkt_fifo_wr_num_d0;

    always@(posedge i_clk, posedge i_reset) begin
        if (i_reset) begin
            pkt_fifo_wr_num_d0 <= 1'b0;
        end
        else begin
            pkt_fifo_wr_num_d0 <= pkt_fifo_wr_num;
        end
    end

    sync_tx_pkt_fifo #(
         .DSIZE (P_DSIZE)
        ,.ASIZE (P_ASIZE)
    )sync_tx_pkt_fifo
    (
         .CLK   (i_clk              )
        ,.RSTn  (!i_reset           )
        ,.write (pkt_fifo_wr        )
        ,.iData (pkt_fifo_wr_data   )
        ,.pktfin(pkt_fifo_rd_pktfin )
        ,.txact (pkt_fifo_rd_act    )
        ,.read  (pkt_fifo_rd        )
        ,.oData (pkt_fifo_rd_data   )
        ,.wrnum (pkt_fifo_wr_num    )
        ,.full  (                   )
        ,.empty (pkt_fifo_empty     )
    );
endmodule
