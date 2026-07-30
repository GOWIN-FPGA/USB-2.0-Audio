// =====================================================================
// module name: spi_flash_controller
// description: SPI Flash Controller with 4KB SRAM Cache for RMW (Read-Modify-Write)
// support: GD25Q64ESIG (64M-bit) SPI Flash
// =====================================================================

module spi_flash_controller #(
    parameter CLK_DIV = 1 // SPI clock divider (sys_clk / (2*CLK_DIV))
)(
    input  logic         clk,
    input  logic         rst_n,

    input  logic         is_dfu_mode,  // 1 DFU 0UMS
    // --- UMS_top handshake signals ---
    input  logic [31:0] spi_lba,      // 512-Byte Sector address (Logical Block Address)
    // READ10 Interface
    input  logic         spi_rd_req,
    output logic         spi_rd_ack,
    // WRITE10 Interface
    input  logic         spi_wr_req,
    output logic         spi_wr_ack,
    input  logic         spi_wr_flush, // Force write to flash (last LBA in 4KB or WRITE10 command)

    // --- UMS_top R/W Data Port (Port B) ---
    // Read Data Path
    output logic         spi_buf_we,
    output logic [8:0]   spi_buf_addr,
    output logic [7:0]   spi_buf_wdata,
    // Write Data Path
    input  logic [7:0]   spi_buf_rdata,

    // --- SPI Physical Interface (W25Q128FV) ---
    output logic         spi_cs_n,
    output logic         spi_clk,
    output logic         spi_mosi,
    input  logic         spi_miso
);

    // ==========================================
    // 1. SPI PHY Instance
    // ==========================================
    logic       phy_tx_req;
    logic [7:0] phy_tx_data;
    logic       phy_ready;
    logic [7:0] phy_rx_data;

    spi_phy #(
        .CLK_DIV(CLK_DIV)
    ) u_spi_phy (
        .clk        (clk),
        .rst_n      (rst_n),
        .tx_req     (phy_tx_req),
        .tx_data    (phy_tx_data),
        .ready      (phy_ready),
        .rx_data    (phy_rx_data),
        .spi_clk    (spi_clk),
        .spi_mosi   (spi_mosi),
        .spi_miso   (spi_miso)
    );

    // ==========================================
    // 2. 4KB Internal SRAM (For Read-Modify-Write)
    // ==========================================
    logic [7:0]  sram_4k [0:4095];
    logic [11:0] sram_4k_addr;
    logic        sram_4k_we;
    logic [7:0]  sram_4k_rdata;
    wire  [7:0]  sram_4k_wdata; 

    // Block RAM inference - Write-First behavior
    always_ff @(posedge clk) begin
        if (sram_4k_we) begin
            sram_4k[sram_4k_addr] <= sram_4k_wdata;
            sram_4k_rdata         <= sram_4k_wdata; 
        end else begin
            sram_4k_rdata         <= sram_4k[sram_4k_addr];
        end
    end

    // ==========================================
    // 3. Address Calculation Logic
    // ==========================================
    // Reserve the first 1MB for the FS file 
    // DFU mode ==> 0x000_000  working.fs
    // UMS mode ==> 0x200_000  mass storage

    wire [23:0] FLASH_OFFSET = is_dfu_mode ? 24'h00_0000 : // DFU 更新 fs的地址，默认为0x00
                                             24'h20_0000 ; // UMS 存放地址，     默认为0x20

    wire [23:0] logical_addr_512B = {spi_lba[14:0], 9'd0};  
    wire [23:0] logical_addr_4KB  = {spi_lba[14:3], 12'd0};

    // Physical start address of the 512B block requested by UMS
    wire [23:0] addr_512B  = logical_addr_512B + FLASH_OFFSET; 
    // Physical start address of the 4KB sector containing the current LBA
    wire [23:0] addr_4KB   = logical_addr_4KB  + FLASH_OFFSET; 
    // Offset of the requested LBA within the 4KB cache
    wire [11:0] offset_4KB  = {spi_lba[2:0], 9'd0};   

    logic [23:0] cached_4k_addr; // Stores the physical address of the 4KB sector currently in SRAM
    logic        cache_valid;    // High if SRAM contains valid data for 'cached_4k_addr'

    // ==========================================
    // 4. State Machine Definitions
    // ==========================================
    typedef enum logic [3:0] {
        ST_IDLE          = 4'd0,
        ST_READ_512      = 4'd1, // Read 512B directly from Flash to UMS
        ST_READ_CACHE    = 4'd2, // Read from SRAM to UMS (Cache Hit)
        ST_RMW_READ_4K   = 4'd3, // Read 4KB Sector from Flash into SRAM
        ST_RMW_MODIFY    = 4'd4, // Overwrite 512B in SRAM with UMS data
        ST_RMW_ERASE     = 4'd5, // Sector Erase (4KB) on Flash
        ST_RMW_PROG      = 4'd6, // Page Program (256B x 16) from SRAM to Flash
        ST_WAIT_WIP      = 4'd7, // Poll Write-In-Progress bit from Status Register
        ST_DONE          = 4'd8,
        ST_CLEAR_4K      = 4'd9
    } state_t;

    state_t state, ret_state;

    logic [15:0] seq_step; 

    // SRAM Data Mux: Input from UMS during modification, else from Flash PHY
    // assign sram_4k_wdata = (state == ST_RMW_MODIFY) ? spi_buf_rdata : phy_rx_data;
    assign sram_4k_wdata =  (state == ST_CLEAR_4K) ? 8'hFF :                                //DFU
                        (state == ST_RMW_MODIFY && seq_step == 0) ? (is_dfu_mode ? 8'hFF : phy_rx_data) :    //状态过渡期，为了保证最后一个数据的稳定
                        (state == ST_RMW_MODIFY) ? spi_buf_rdata : 
                        phy_rx_data;         //UMS

    // UMS Buffer Mux: Output from SRAM cache on hit, else pass-through Flash PHY
    assign spi_buf_wdata = (state == ST_READ_CACHE) ? sram_4k_rdata : phy_rx_data;

    // ==========================================
    // 5. Main Control FSM
    // ==========================================
    typedef enum logic [1:0] {PHY_IDLE, PHY_WAIT_BUSY, PHY_WAIT_DONE} phy_ctrl_t;
    phy_ctrl_t p_state;

   
    logic [3:0]  page_idx; // 0~15 index for 16 pages (256B each) in a 4KB sector

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= ST_IDLE;
            ret_state       <= ST_IDLE;
            p_state         <= PHY_IDLE;
            spi_cs_n        <= 1'b1;
            spi_rd_ack      <= 1'b0;
            spi_wr_ack      <= 1'b0;
            phy_tx_req      <= 1'b0;
            phy_tx_data     <= 8'h00;
            seq_step        <= 16'd0;
            page_idx        <= 4'd0;
            
            spi_buf_we      <= 1'b0;
            sram_4k_we      <= 1'b0;
            cached_4k_addr  <= 24'hFF_FFFF;
            cache_valid     <= 1'b0;
        end else begin
            // Default pulse clearing
            spi_buf_we <= 1'b0; 
            sram_4k_we <= 1'b0;

            case (state)
                // --------------------------------------------------
                ST_IDLE: begin
                    spi_cs_n   <= 1'b1;
                    spi_rd_ack <= 1'b0;
                    spi_wr_ack <= 1'b0;
                    seq_step   <= 16'd0;
                    page_idx   <= 4'd0;
                    
                    if (spi_rd_req) begin
                        if (cache_valid && cached_4k_addr == addr_4KB) begin
                            state <= ST_READ_CACHE; // Cache Hit: Read directly from SRAM
                        end else begin
                            state <= ST_READ_512;   // Cache Miss: Read from physical Flash
                        end
                    end 
                    else if (spi_wr_req) begin
                        if (cache_valid && cached_4k_addr == addr_4KB) begin
                            state <= ST_RMW_MODIFY; // Cache Hit: Skip Read, modify SRAM directly
                        end 
                        else begin
                            if(is_dfu_mode)     state <= ST_CLEAR_4K   ;// DFU模式 ：默认全为FF
                            else                state <= ST_RMW_READ_4K;// UMS模式 ：正常读取flash内数据
                        end
                    end
                end

                // --------------------------------------------------
                // ST_READ_CACHE: Stream 512B from internal SRAM to UMS
                // --------------------------------------------------
                ST_READ_CACHE: begin
                    if (seq_step < 512) begin
                        sram_4k_addr <= offset_4KB + seq_step;
                    end
                    
                    if (seq_step >= 1 && seq_step <= 512) begin
                        spi_buf_we   <= 1'b1;
                        spi_buf_addr <= seq_step - 1;
                    end
                    
                    seq_step <= seq_step + 1'b1;
                    
                    if (seq_step == 513) begin
                        seq_step <= 16'd0;
                        state    <= ST_DONE;
                    end
                end

                // --------------------------------------------------
                // ST_READ_512: Stream 512B from Physical Flash to UMS
                // --------------------------------------------------
                ST_READ_512: begin
                    spi_cs_n <= 1'b0;
                    
                    if (p_state == PHY_IDLE) begin
                        phy_tx_req <= 1'b1;
                        case (seq_step)
                            0: phy_tx_data <= 8'h03; // Read Data Command
                            1: phy_tx_data <= addr_512B[23:16];
                            2: phy_tx_data <= addr_512B[15:8];
                            3: phy_tx_data <= addr_512B[7:0];
                            default: phy_tx_data <= 8'h00;
                        endcase
                        p_state <= PHY_WAIT_BUSY;
                    end 
                    else if (p_state == PHY_WAIT_BUSY && !phy_ready) begin
                        phy_tx_req <= 1'b0;
                        p_state <= PHY_WAIT_DONE;
                    end 
                    else if (p_state == PHY_WAIT_DONE && phy_ready) begin
                        p_state <= PHY_IDLE;
                        seq_step <= seq_step + 1'b1;
                        
                        if (seq_step >= 4 && seq_step < 516) begin
                            spi_buf_we   <= 1'b1;
                            spi_buf_addr <= seq_step - 4;
                            // spi_buf_wdata assigned via combinational logic (phy_rx_data)
                        end
                        
                        if (seq_step == 515) begin
                            spi_cs_n <= 1'b1;
                            state    <= ST_DONE;
                        end
                    end
                end

                // --------------------------------------------------
                // RMW Step 1: Read entire 4KB sector into internal SRAM.
                // Prevents data loss when host writes only 512B to an erased 4KB sector.
                // --------------------------------------------------
                ST_RMW_READ_4K: begin
                    spi_cs_n <= 1'b0;
                    if (p_state == PHY_IDLE) begin
                        phy_tx_req <= 1'b1;
                        case (seq_step)
                            0: phy_tx_data <= 8'h03; 
                            1: phy_tx_data <= addr_4KB[23:16];
                            2: phy_tx_data <= addr_4KB[15:8];
                            3: phy_tx_data <= addr_4KB[7:0];
                            default: phy_tx_data <= 8'h00;
                        endcase
                        p_state <= PHY_WAIT_BUSY;
                    end 
                    else if (p_state == PHY_WAIT_BUSY && !phy_ready) begin
                        phy_tx_req <= 1'b0;
                        p_state <= PHY_WAIT_DONE;
                    end 
                    else if (p_state == PHY_WAIT_DONE && phy_ready) begin
                        p_state <= PHY_IDLE;
                        seq_step <= seq_step + 1'b1;
                        
                        if (seq_step >= 4 && seq_step < 4100) begin
                            sram_4k_we   <= 1'b1;
                            sram_4k_addr <= seq_step - 4;
                        end
                        
                        // Finished reading 4096 bytes
                        if (seq_step == 4099) begin
                            spi_cs_n       <= 1'b1;
                            seq_step       <= 16'd0;
                            cached_4k_addr <= addr_4KB; // Update cache tag
                            cache_valid    <= 1'b1;     // Mark cache as valid
                            state          <= ST_RMW_MODIFY;
                        end
                    end
                end
        
                ST_CLEAR_4K: begin
                    sram_4k_we   <= 1'b1;
                    sram_4k_addr <= seq_step[11:0]; 
                    if (seq_step == 16'd4095) begin
                        seq_step       <= 16'd0;
                        cached_4k_addr <= addr_4KB;
                        cache_valid    <= 1'b1;
                        state          <= ST_RMW_MODIFY; // 填完0xFF后，无缝衔接进入数据写入阶段
                    end else begin
                        seq_step <= seq_step + 1'b1;
                    end
                end


                // --------------------------------------------------
                // RMW Step 2: Transfer 512B from UMS to SRAM at specific offset
                // --------------------------------------------------
                ST_RMW_MODIFY: begin
                    if (seq_step < 512) begin
                        spi_buf_addr <= seq_step;
                    end
                    
                    if (is_dfu_mode) begin
                        if (seq_step >= 0 && seq_step <= 511) begin
                            sram_4k_we   <= 1'b1;
                            sram_4k_addr <= offset_4KB + seq_step;
                        end 
                    end 
                    else begin
                        if (seq_step >= 1 && seq_step <= 512) begin
                            sram_4k_we   <= 1'b1;
                            sram_4k_addr <= offset_4KB + (seq_step - 1);
                        end 
                    end
                    
                    seq_step <= seq_step + 1'b1;
                    
                    // if (seq_step == 16'd513 ) begin
                    if (seq_step == (is_dfu_mode ? 16'd512 : 16'd513)) begin
                        seq_step <= 16'd0;
                        // Lazy Write Mechanism: Flush to physical flash only at sector boundaries or on request
                        if (spi_lba[2:0] == 3'b111 || spi_wr_flush) begin
                            state <= ST_RMW_ERASE;
                        end else begin
                            state <= ST_DONE; // Fast return to host while keeping data in SRAM
                        end
                    end
                end

                // --------------------------------------------------
                // RMW Step 3: 4KB Sector Erase
                // --------------------------------------------------
                ST_RMW_ERASE: begin
                    if (p_state == PHY_IDLE) begin
                        case (seq_step)
                            0: begin spi_cs_n <= 1'b0; phy_tx_data <= 8'h06; phy_tx_req <= 1'b1; end // WREN (Write Enable)
                            1,2,3,4: begin spi_cs_n <= 1'b1; phy_tx_req <= 1'b0; end // [Fix]: Mandatory CS high delay (Tshsl)
                            5: begin spi_cs_n <= 1'b0; phy_tx_data <= 8'h20; phy_tx_req <= 1'b1; end // SE (Sector Erase)
                            6: begin phy_tx_data <= addr_4KB[23:16]; phy_tx_req <= 1'b1; end
                            7: begin phy_tx_data <= addr_4KB[15:8];  phy_tx_req <= 1'b1; end
                            8: begin phy_tx_data <= addr_4KB[7:0];   phy_tx_req <= 1'b1; end
                        endcase
                        
                        // Step 1-4 are pure idle delays, do not trigger PHY
                        if (seq_step >= 1 && seq_step <= 4) begin
                            seq_step <= seq_step + 1'b1; 
                        end else begin
                            p_state <= PHY_WAIT_BUSY;
                        end
                    end
                    else if (p_state == PHY_WAIT_BUSY && !phy_ready) begin
                        phy_tx_req <= 1'b0;
                        p_state <= PHY_WAIT_DONE;
                    end
                    else if (p_state == PHY_WAIT_DONE && phy_ready) begin
                        p_state <= PHY_IDLE;
                        seq_step <= seq_step + 1'b1;
                        
                        if (seq_step == 8) begin 
                            spi_cs_n  <= 1'b1;
                            // [Fix]: Initialize seq_step to 2 to enforce entry delay in WAIT_WIP
                            seq_step  <= 16'd2; 
                            ret_state <= ST_RMW_PROG;
                            state     <= ST_WAIT_WIP;
                        end
                    end
                end

                // --------------------------------------------------
                // RMW Step 4: Loop 16 times, Page Programming 256 bytes each
                // --------------------------------------------------
                ST_RMW_PROG: begin
                    if (p_state == PHY_IDLE) begin
                        case (seq_step)
                            0: begin spi_cs_n <= 1'b0; phy_tx_data <= 8'h06; phy_tx_req <= 1'b1; end // WREN
                            1,2,3,4: begin spi_cs_n <= 1'b1; phy_tx_req <= 1'b0; end // CS recovery delay
                            5: begin spi_cs_n <= 1'b0; phy_tx_data <= 8'h02; phy_tx_req <= 1'b1; end // PP (Page Program)
                            6: begin phy_tx_data <= addr_4KB[23:16]; phy_tx_req <= 1'b1; end         // High 8-bit
                            7: begin phy_tx_data <= {addr_4KB[15:12],page_idx};  phy_tx_req <= 1'b1; end // Sector Addr + Page Index
                            8: begin 
                                phy_tx_data <= 8'h00;                                                // Byte Addr (Page start at 0)
                                phy_tx_req <= 1'b1; 
                                sram_4k_addr <= {page_idx, 8'd0}; // Pre-fetch first byte
                            end
                            default: begin
                                phy_tx_data <= sram_4k_rdata;        phy_tx_req <= 1'b1; 
                                if (seq_step < 264) begin 
                                    sram_4k_addr <= {page_idx, 8'd0} + (seq_step - 8); 
                                end
                            end
                        endcase
                        
                        if (seq_step >= 1 && seq_step <= 4) begin
                            seq_step <= seq_step + 1'b1;
                        end else begin
                            p_state <= PHY_WAIT_BUSY;
                        end
                    end
                    else if (p_state == PHY_WAIT_BUSY && !phy_ready) begin
                        phy_tx_req <= 1'b0;
                        p_state <= PHY_WAIT_DONE;
                    end
                    else if (p_state == PHY_WAIT_DONE && phy_ready) begin
                        p_state <= PHY_IDLE;
                        seq_step <= seq_step + 1'b1;
                        
                        if (seq_step == 264) begin
                            spi_cs_n <= 1'b1;
                            seq_step <= 16'd2; // Setup entry delay for WAIT_WIP
                            
                            if (page_idx == 15) begin
                                ret_state <= ST_DONE; // 16 pages completed
                            end else begin
                                page_idx  <= page_idx + 1'b1;
                                ret_state <= ST_RMW_PROG; // Next page
                            end
                            state <= ST_WAIT_WIP;
                        end
                    end
                end

                // --------------------------------------------------
                // Common State: Poll WIP (Write In Progress) bit
                // Following industry standard: Toggling CS for repeated status polling
                // --------------------------------------------------
                ST_WAIT_WIP: begin
                    // seq_step 0: Send 05h (Read Status Register)
                    // seq_step 1: Clock in Status Register value
                    // seq_step 2~8: Mandatory CS high idle delay between polls

                    if (seq_step >= 2) begin
                        spi_cs_n <= 1'b1; // Ensure CS high for recovery/polling interval
                        seq_step <= seq_step + 1'b1;
                        
                        if (seq_step == 8) begin // After 7 clock cycles delay
                            if (phy_rx_data[0] == 1'b1) begin // WIP bit is still 1
                                seq_step <= 16'd0; // Still busy, restart 05h polling cycle
                            end else begin
                                seq_step <= 16'd0; // Idle, operation finished
                                state    <= ret_state;
                            end
                        end
                    end 
                    else begin
                        spi_cs_n <= 1'b0; // Pull CS low to initiate poll
                        
                        if (p_state == PHY_IDLE) begin
                            phy_tx_req <= 1'b1;
                            if (seq_step == 0) phy_tx_data <= 8'h05; // Step 0: Command 05h
                            else               phy_tx_data <= 8'h00; // Step 1: Dummy for RX
                            
                            p_state <= PHY_WAIT_BUSY;
                        end
                        else if (p_state == PHY_WAIT_BUSY && !phy_ready) begin
                            phy_tx_req <= 1'b0;
                            p_state <= PHY_WAIT_DONE;
                        end
                        else if (p_state == PHY_WAIT_DONE && phy_ready) begin
                            p_state <= PHY_IDLE;
                            
                            if (seq_step == 0) begin
                                seq_step <= 16'd1; // Proceed to Read Step
                            end else begin
                                spi_cs_n <= 1'b1;  // Immediately pull CS high after reading status
                                seq_step <= 16'd2; // Proceed to delay/evaluation
                            end
                        end
                    end
                end

                // --------------------------------------------------
                // ST_DONE: Handshake Completion
                // --------------------------------------------------
                ST_DONE: begin
                    if (spi_rd_req) spi_rd_ack <= 1'b1;
                    if (spi_wr_req) spi_wr_ack <= 1'b1;
                    
                    if (!spi_rd_req && !spi_wr_req) begin
                        spi_rd_ack <= 1'b0;
                        spi_wr_ack <= 1'b0;
                        state      <= ST_IDLE;
                    end
                end
            endcase
        end
    end

endmodule