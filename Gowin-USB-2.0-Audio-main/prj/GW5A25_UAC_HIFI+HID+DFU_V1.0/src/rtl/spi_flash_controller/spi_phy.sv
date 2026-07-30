module spi_phy #(
    parameter CLK_DIV = 1
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       tx_req,     
    input  logic [7:0] tx_data,    
    output logic       ready,      
    output logic [7:0] rx_data,    
    output logic       spi_clk,
    output logic       spi_mosi,
    input  logic       spi_miso
);
    typedef enum logic [1:0] {IDLE, SHIFT, DONE} phy_state_t;
    phy_state_t state, next_state;

    logic [7:0] tx_shift_reg;
    logic [7:0] rx_shift_reg;
    logic [2:0] bit_cnt;        
    logic [7:0] clk_div_cnt;    
    logic       spi_clk_reg;

    assign spi_clk = spi_clk_reg;
    assign spi_mosi = tx_shift_reg[7]; 
    assign rx_data  = rx_shift_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else state <= next_state;
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE:  if (tx_req) next_state = SHIFT;
            SHIFT: if (bit_cnt == 3'd7 && clk_div_cnt == CLK_DIV - 1 && spi_clk_reg == 1'b1) next_state = DONE;
            DONE:  next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_shift_reg <= 8'h00;
            rx_shift_reg <= 8'h00;
            bit_cnt      <= 3'd0;
            clk_div_cnt  <= 8'd0;
            spi_clk_reg  <= 1'b0;
            ready        <= 1'b1;
        end else begin
            case (state)
                IDLE: begin
                    spi_clk_reg <= 1'b0; bit_cnt <= 3'd0; clk_div_cnt <= 8'd0; ready <= 1'b1;
                    if (tx_req) begin tx_shift_reg <= tx_data; ready <= 1'b0; end
                end
                SHIFT: begin
                    if (clk_div_cnt == CLK_DIV - 1) begin
                        clk_div_cnt <= 8'd0;
                        spi_clk_reg <= ~spi_clk_reg; 
                        if (spi_clk_reg == 1'b0) rx_shift_reg <= {rx_shift_reg[6:0], spi_miso};
                        else begin tx_shift_reg <= {tx_shift_reg[6:0], 1'b0}; bit_cnt <= bit_cnt + 1'b1; end
                    end else clk_div_cnt <= clk_div_cnt + 1'b1;
                end
                DONE: begin spi_clk_reg <= 1'b0; ready <= 1'b1; end
            endcase
        end
    end
endmodule