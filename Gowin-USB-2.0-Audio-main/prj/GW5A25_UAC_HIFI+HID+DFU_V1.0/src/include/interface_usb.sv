interface ep_mem_out_if;
    logic           transfer_out_mem_has_data  ;
    logic [10:0]    transfer_out_mem_len       ;
    logic [7:0]     transfer_out_mem_rd_data   ;
    logic [9:0]     transfer_out_mem_rd_addr   ;
    logic           transfer_out_mem_clr       ;
    modport ep ( output     transfer_out_mem_has_data 
                ,output     transfer_out_mem_len      
                ,output     transfer_out_mem_rd_data  
                ,input      transfer_out_mem_rd_addr  
                ,input      transfer_out_mem_clr      );
endinterface

interface ep_mem_in_if;
    logic           transfer_in_mem_wr          ;
    logic [15:0]    transfer_in_mem_wr_addr     ;
    logic [7:0]     transfer_in_mem_wr_data     ;
    logic           transfer_in_mem_commit      ;
    logic [15:0]    transfer_in_mem_commit_len  ;
    logic           transfer_in_mem_ready       ;
    logic           transfer_in_done            ;

    modport ep ( input  transfer_in_mem_wr        
                ,input  transfer_in_mem_wr_addr   
                ,input  transfer_in_mem_wr_data   
                ,input  transfer_in_mem_commit    
                ,input  transfer_in_mem_commit_len
                ,output transfer_in_mem_ready     
                ,output transfer_in_done          
                );
endinterface

//==============================================================================
//==============================================================================

interface ep_fifo_out_if;
    logic       i_rx_clk;
    logic       i_rx_rdy;
    logic       o_rx_dval;
    logic [7:0] o_rx_data;
    modport ep (input   i_rx_clk, 
                input   i_rx_rdy, 
                output  o_rx_dval,
                output  o_rx_data   );
endinterface

interface ep_fifo_in_if;
    logic        i_tx_clk;
    logic [11:0] i_tx_max;
    logic [11:0] i_tx_nor;
    logic [11:0] i_tx_min;
    logic        i_tx_dval;
    logic [7:0]  i_tx_data;

    logic        o_tx_full;
    logic        o_tx_alfull;
    logic        o_tx_alempty;

    modport ep (input i_tx_clk, 
                input i_tx_max, 
                input i_tx_nor, 
                input i_tx_min, 
                input i_tx_dval, 
                input i_tx_data,    
                output o_tx_full, o_tx_alfull, o_tx_alempty
                );
endinterface