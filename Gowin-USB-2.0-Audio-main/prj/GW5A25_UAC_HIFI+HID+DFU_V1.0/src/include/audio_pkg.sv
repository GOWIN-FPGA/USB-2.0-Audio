package audio_pkg;
    localparam bit [31:0] SAMPLE_RATE_32    = 32'h00007D00;
    localparam bit [31:0] SAMPLE_RATE_44_1  = 32'h0000AC44;
    localparam bit [31:0] SAMPLE_RATE_48    = 32'h0000BB80;
    localparam bit [31:0] SAMPLE_RATE_64    = 32'h0000FA00;
    localparam bit [31:0] SAMPLE_RATE_88_2  = 32'h00015888;
    localparam bit [31:0] SAMPLE_RATE_96    = 32'h00017700;
    localparam bit [31:0] SAMPLE_RATE_128   = 32'h0001F400;
    localparam bit [31:0] SAMPLE_RATE_176_4 = 32'h0002B110;
    localparam bit [31:0] SAMPLE_RATE_192   = 32'h0002EE00;
    localparam bit [31:0] SAMPLE_RATE_352_8 = 32'h00056220;
    localparam bit [31:0] SAMPLE_RATE_384   = 32'h0005DC00;
    localparam bit [31:0] SAMPLE_RATE_705_6 = 32'h000AC440;
    localparam bit [31:0] SAMPLE_RATE_768   = 32'h000BB800;

    localparam bit [7:0]  DOP_PACKET_CODE0      = 8'h05 ;
    localparam bit [7:0]  DOP_PACKET_CODE1      = 8'hFA ;

endpackage