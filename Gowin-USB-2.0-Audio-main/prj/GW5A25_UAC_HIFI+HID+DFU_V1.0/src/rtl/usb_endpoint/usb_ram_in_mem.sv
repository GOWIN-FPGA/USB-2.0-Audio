module usb_ram_in_mem
#(
     parameter PP_BUF_SIZE      = 1024
    ,parameter PP_BUF_ADDR_SIZE = $clog2 (PP_BUF_SIZE)
)
(
    input             clk                        ,
    input             rst_n                      ,
    input             enable                     ,
    input wire        transfer_in_mem_wr         ,
    input wire [PP_BUF_ADDR_SIZE - 1 : 0] transfer_in_mem_wr_addr,
    input wire [ 7:0] transfer_in_mem_wr_data    ,
    input wire        transfer_in_mem_commit     ,
    input wire [PP_BUF_ADDR_SIZE : 0] transfer_in_mem_commit_len ,
    output            transfer_in_mem_ready      ,
    output reg        transfer_in_done           ,

    input             usb_txact                  ,
    output            usb_txcork                 ,
    input             usb_txpop                  ,
    input             usb_txdone                 ,
    output reg [11:0] usb_txlen                  ,
    output reg [ 7:0] usb_txdata
);

// -----------------------------------------------------------
// Ping-pong RAM: two 4K x 8 buffers
// -----------------------------------------------------------
reg [7:0] ram [0:1][0:PP_BUF_SIZE-1];
reg [1:0] ram_has_data;
reg [PP_BUF_ADDR_SIZE:0] ram_len [0:1];
reg [PP_BUF_ADDR_SIZE:0] ram_len_cnt;
reg        wr_sel;
reg        rd_sel;
reg [PP_BUF_ADDR_SIZE - 1:0] rd_addr;
reg [PP_BUF_ADDR_SIZE - 1:0] rd_nxt_addr;

// ready when not both full
//always @(posedge clk or negedge rst_n) begin
//    if (!rst_n) begin
//        transfer_in_mem_ready <= 1'b0;
//    end else begin
//        transfer_in_mem_ready <= (ram_has_data != 2'b11);
//    end
//end
assign transfer_in_mem_ready = transfer_in_mem_commit ? 1'b0 : (ram_has_data != 2'b11);

// write side
always @(posedge clk) begin
    if (transfer_in_mem_wr) begin
        ram[wr_sel][transfer_in_mem_wr_addr] <= transfer_in_mem_wr_data;
    end
end

assign usb_txcork = (ram_has_data==0);
// commit logic
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ram_len[0]   <= 'd0;
        ram_len[1]   <= 'd0;
        wr_sel       <= 1'b0;
        rd_addr      <= 'd0;
        transfer_in_done <= 1'b0;
        usb_txdata   <= 'd0;
    end else begin
        transfer_in_done <= 1'b0;
        // consume data
        if (ram_has_data[rd_sel]) begin
            if (enable&usb_txact) begin
                if (usb_txpop) begin
                    rd_addr <= rd_addr + 12'd1;
                    usb_txdata <= ram[rd_sel][rd_addr+1];
                end
                if (usb_txdone && (rd_addr >= ram_len[rd_sel])) begin
                    rd_addr <= 12'd0;
                    transfer_in_done <= 1'b1;
                end
            end
            else begin
                usb_txdata <= ram[rd_sel][rd_addr];
            end
        end

        // accept commit into empty buffer
        if (transfer_in_mem_commit) begin
            if (!ram_has_data[wr_sel]) begin
                ram_len[wr_sel] <= transfer_in_mem_commit_len;
                wr_sel <= ~wr_sel;
            end
        end
    end
end

// tx control
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        usb_txlen  <= 12'd0;
        rd_sel     <= 1'b0;
    end
    else if (enable) begin
        if (usb_txact) begin
            if (usb_txdone) begin
                if (rd_addr >= ram_len[rd_sel]) begin
                    rd_sel <= !rd_sel;
                end
            end
        end
        else begin
            if (ram_len[rd_sel] >= 1024 + rd_addr) begin
                usb_txlen <= 1024;
            end
            else begin
                usb_txlen <= ram_len[rd_sel];
            end
        end
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ram_has_data[0] <= 1'b0;
        ram_has_data[1] <= 1'b0;
    end else begin
        // consume data
        if (ram_has_data[0]) begin
            if (enable&usb_txact&&(rd_sel==0)) begin
                if (usb_txdone && (rd_addr >= ram_len[0])) begin
                    ram_has_data[0] <= 1'b0;
                end
            end
        end
        else begin
            if ((wr_sel==0)&&transfer_in_mem_commit) begin
                if (transfer_in_mem_commit_len > 0) begin
                    ram_has_data[0] <= 1'b1;
                end
            end
        end
        if (ram_has_data[1]) begin
            if (enable&usb_txact&&(rd_sel==1)) begin
                if (usb_txdone && (rd_addr >= ram_len[1])) begin
                    ram_has_data[1] <= 1'b0;
                end
            end
        end
        else begin
            if ((wr_sel==1)&&transfer_in_mem_commit) begin
                if (transfer_in_mem_commit_len > 0) begin
                    ram_has_data[1] <= 1'b1;
                end
            end
        end

        // accept commit into empty buffer
    end
end
endmodule