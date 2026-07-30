module usb_ram_out_mem #(
     parameter PP_BUF_SIZE      = 1024
    ,parameter PP_BUF_ADDR_SIZE = $clog2 (PP_BUF_SIZE)
)
(
    input             clk                        ,
    input             rst_n                      ,
    input             enable                     ,
    input             usb_rxact                  ,
    input             usb_rxval                  ,
    input             usb_rxfin                  ,
    input  [7:0]      usb_rxdata                 ,
    output reg        usb_rxrdy                  ,

    output wire         transfer_out_mem_has_data,
    output wire [PP_BUF_ADDR_SIZE:0]  transfer_out_mem_len     ,
    output reg  [7:0]  transfer_out_mem_rd_data ,

    input  wire [PP_BUF_ADDR_SIZE - 1:0]  transfer_out_mem_rd_addr ,
    input  wire         transfer_out_mem_clr
);

reg [7:0] ram [0:1][0:PP_BUF_SIZE - 1];
reg [1:0] ram_has_data;
reg       wr_sel;
reg       rd_sel;
reg [PP_BUF_ADDR_SIZE - 1:0] wr_addr;
reg [PP_BUF_ADDR_SIZE :0] wr_len [0:1];

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        usb_rxrdy <= 1'b0;
    end else begin
        usb_rxrdy <= (ram_has_data != 2'b11);
    end
end

// write receive data
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        wr_addr <= 'd0;
        wr_len[0] <= 'd0;
        wr_len[1] <= 'd0;
    end else if (enable) begin
        if ((!ram_has_data[wr_sel]) && usb_rxact) begin
            if (usb_rxval) begin
                ram[wr_sel][wr_addr] <= usb_rxdata;
                wr_addr <= wr_addr + 12'd1;
            end
            if (usb_rxfin) begin
                wr_addr <= 12'd0;
                wr_len[wr_sel] <= wr_addr;
            end
        end
    end
end

assign transfer_out_mem_has_data = transfer_out_mem_clr ? 1'b0 : ram_has_data[rd_sel];
assign transfer_out_mem_len = {4'd0, wr_len[rd_sel]};
// has_data/clear control and read side selection
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        transfer_out_mem_rd_data <= 'd0;
    end else begin
        transfer_out_mem_rd_data <= ram[rd_sel][transfer_out_mem_rd_addr];
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ram_has_data <= 2'b00;
        rd_sel <= 1'b0;
        wr_sel <= 1'b0;
    end else begin
        if (ram_has_data[0]) begin
            if (transfer_out_mem_clr && (rd_sel==0)) begin
                ram_has_data[0] <= 1'b0;
                rd_sel <= ~rd_sel;
            end
        end
        else begin
            if ((wr_sel==0) && usb_rxact && enable) begin
                if (usb_rxfin) begin
                    if (wr_addr != 12'd0) begin
                        ram_has_data[wr_sel] <= 1'b1;
                        wr_sel <= ~wr_sel;
                    end
                end
            end
        end
        if (ram_has_data[1]) begin
            if (transfer_out_mem_clr && (rd_sel==1)) begin
                ram_has_data[1] <= 1'b0;
                rd_sel <= ~rd_sel;
            end
        end
        else begin
            if ((wr_sel==1) && usb_rxact && enable) begin
                if (usb_rxfin) begin
                    if (wr_addr != 12'd0) begin
                        ram_has_data[1] <= 1'b1;
                        wr_sel <= ~wr_sel;
                    end
                end
            end
        end
    end
end
endmodule
