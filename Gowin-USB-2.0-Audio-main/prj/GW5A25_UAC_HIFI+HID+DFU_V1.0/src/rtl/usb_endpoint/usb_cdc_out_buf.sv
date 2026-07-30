module usb_cdc_out_buf #(
    parameter P_ENDPOINT = 1,
    parameter P_AFULL    = 400,
    parameter P_DSIZE    = 8,
    parameter P_ASIZE    = 9
)
(
    input                  i_clk         ,//clock
    input                  i_reset       ,//reset
    input  [3:0]           i_usb_endpt   ,//
    input                  i_usb_rxact   ,//
    input                  i_usb_rxpktval,//
    input                  i_usb_rxval   ,//
    input  [P_DSIZE-1:0]   i_usb_rxdat   ,//
    output                 o_usb_rxrdy   ,//

    input                  i_ep_clk      ,//
    input                  i_ep_rx_rdy   ,//
    output                 o_ep_rx_dval  ,//
    output [P_DSIZE-1:0]   o_ep_rx_data   //
);
    reg                pkt_fifo_wr;
    reg                pkt_fifo_wr_act;
    reg                pkt_fifo_wr_pktval;
    reg  [P_DSIZE-1:0] pkt_fifo_wr_data;
        
    reg                pkt_fifo_rd;
    reg                pkt_fifo_rd_dval;
    wire [P_DSIZE-1:0] pkt_fifo_rd_data;
    wire [P_ASIZE  :0] pkt_fifo_wr_num;


    wire               c_fifo_wr;
    wire [P_DSIZE-1:0] c_fifo_wr_data;
    wire               c_fifo_afull;
    reg                c_fifo_rd;
    reg                c_fifo_dval;
    wire [P_DSIZE-1:0] c_fifo_rd_data;

//==============================================================
//======usb rx
    always_ff @(posedge i_clk or posedge i_reset) begin
        if (i_reset) begin
            pkt_fifo_wr        <= 1'b0;
            pkt_fifo_wr_act    <= 1'b0;
            pkt_fifo_wr_pktval <= 1'b0;
            pkt_fifo_wr_data   <= '0;
        end
        else begin
            pkt_fifo_wr        <= i_usb_rxval    & (i_usb_endpt == P_ENDPOINT);
            pkt_fifo_wr_act    <= i_usb_rxact    & (i_usb_endpt == P_ENDPOINT);
            pkt_fifo_wr_pktval <= i_usb_rxpktval & (i_usb_endpt == P_ENDPOINT);
            pkt_fifo_wr_data   <= i_usb_rxdat;
        end
    end
//==============================================================
//======usb packet crc check fifo
    sync_rx_pkt_fifo  #(
         .DSIZE (P_DSIZE )
        ,.ASIZE (P_ASIZE )
    )sync_rx_pkt_fifo
    (
         .CLK   (i_clk               )
        ,.RSTn  (!i_reset            )
        ,.write (pkt_fifo_wr         )
        ,.iData (pkt_fifo_wr_data    )
        ,.pktval(pkt_fifo_wr_pktval  )
        ,.rxact (pkt_fifo_wr_act     )
        ,.read  (pkt_fifo_rd         )
        ,.oData (pkt_fifo_rd_data    )
        ,.wrnum (pkt_fifo_wr_num     )
        ,.full  (                    )
        ,.empty (pkt_fifo_empty      )
    );

    always_ff@(posedge i_clk, posedge i_reset) begin
        if (i_reset) begin
            pkt_fifo_rd <= 1'b0;
        end
        else begin
            if (pkt_fifo_empty||(c_fifo_afull)) begin
                pkt_fifo_rd <= 1'b0;
            end
            else begin
                pkt_fifo_rd <= 1'b1;
            end
        end
    end
    always@(posedge i_clk, posedge i_reset) begin
        if (i_reset) begin
            pkt_fifo_rd_dval <= 1'b0;
        end
        else begin
            pkt_fifo_rd_dval <= pkt_fifo_rd & (!pkt_fifo_empty);
        end
    end
//==============================================================
//======cross fifo
assign c_fifo_wr      = pkt_fifo_rd_dval;
assign c_fifo_wr_data = pkt_fifo_rd_data;
    clk_cross_fifo #(
       .DSIZE (8  )
      ,.ASIZE (6  )
      ,.AEMPT (1  )
      ,.AFULL (32 )
    )clk_cross_fifo
    (
         .WrClock    (i_clk         )
        ,.Reset      (i_reset       )
        ,.WrEn       (c_fifo_wr     )
        ,.Data       (c_fifo_wr_data)
        ,.AlmostFull (c_fifo_afull  )
        ,.Full       ()
        ,.RdClock    (i_ep_clk      )
        ,.RPReset    (i_reset       )
        ,.RdEn       (c_fifo_rd&i_ep_rx_rdy)
        ,.Q          (c_fifo_rd_data)
        ,.AlmostEmpty()
        ,.Empty      (c_fifo_empty  )
    );

    always@(posedge i_ep_clk, posedge i_reset) begin
        if (i_reset) begin
            c_fifo_rd <= 1'b0;
        end
        else begin
            if (c_fifo_rd||c_fifo_empty||(!i_ep_rx_rdy)) begin
                c_fifo_rd <= 1'b0;
            end
            else begin
                c_fifo_rd <= 1'b1;
            end
        end
    end
    always@(posedge i_ep_clk, posedge i_reset) begin
        if (i_reset) begin
            c_fifo_dval <= 1'b0;
        end
        else begin
            if (c_fifo_rd & (!c_fifo_empty)) begin
                c_fifo_dval <= 1'b1;
            end
            //else if (!i_ep_rx_rdy) begin
            //    c_fifo_dval <= c_fifo_dval;
            //end
            else begin
                c_fifo_dval <= 1'b0;
            end
        end
    end
    assign o_usb_rxrdy  = pkt_fifo_wr_num < P_AFULL;
    assign o_ep_rx_dval = c_fifo_dval;
    assign o_ep_rx_data = c_fifo_rd_data;

endmodule