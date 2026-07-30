// `default_nettype none

module usb_desc #(
    parameter bit [15:0] VENDORID       = 16'h0403,
    parameter bit [15:0] PRODUCTID      = 16'h6010,
    parameter bit [15:0] DFU_PRODUCTID  = 16'hFE01, // DFU模式专属PID
    parameter bit [15:0] VERSIONBCD     = 16'h0100
)
(
    input  wire          CLK,
    input  wire          RESET,

    input  wire          i_dfu_mode,

    input  wire  [15:0]  i_descrom_raddr,
    output logic [ 7:0]  o_descrom_rdat,
    input  wire  [ 7:0]  i_desc_index_o,
    input  wire  [ 7:0]  i_desc_type_o,
    
    output logic [15:0]  o_desc_dev_addr,
    output logic [15:0]  o_desc_dev_len,
    output logic [15:0]  o_desc_qual_addr,
    output logic [15:0]  o_desc_qual_len,
    output logic [15:0]  o_desc_fscfg_addr,
    output logic [15:0]  o_desc_fscfg_len,
    output logic [15:0]  o_desc_hscfg_addr,
    output logic [15:0]  o_desc_hscfg_len,
    output logic [15:0]  o_desc_hidrpt_addr,
    output logic [15:0]  o_desc_hidrpt_len,
    output logic [15:0]  o_desc_oscfg_addr,
    output logic [15:0]  o_desc_strlang_addr,
    output logic [15:0]  o_desc_strvendor_addr,
    output logic [15:0]  o_desc_strvendor_len,
    output logic [15:0]  o_desc_strproduct_addr,
    output logic [15:0]  o_desc_strproduct_len,
    output logic [15:0]  o_desc_strserial_addr,
    output logic [15:0]  o_desc_strserial_len,
    output logic         o_descrom_have_strings
);

    // =========================================================================
    // 1. 参数头文件（主要为地址）
    // =========================================================================
    `include "usb_desc_params.vh"

    // =========================================================================
    // 2. 描述符ROM (拟设计BSRAM，但由于USB IP addr 原因， 此处仍然使用LUT)
    // =========================================================================
    logic [7:0] descrom [0 : ROM_LEN-1];

    initial begin

    `ifdef HIFI_ONLY 
        $readmemh("usb_desc_2CN_HIFI.hex", descrom);
    `else
        $readmemh("usb_desc_2CN_HIFI+HID+DFU.hex", descrom);
    `endif
    
    end

    // =========================================================================
    // 3. 数据读取
    // =========================================================================
    logic [7:0] rom_data_raw;
    // 当地址 i_descrom_raddr 变化时，rom_data_raw 会在 "同一周期" 内立刻变化
    assign rom_data_raw = descrom[i_descrom_raddr];




    // 第二方案，usb_device_ctr addr提前。此处使用BRAM格式。需要搭配特殊USB_device_ctr IP
    // logic [7:0]  rom_data_raw;
    // logic [15:0] raddr_reg;

    // always_ff @(posedge CLK) begin
    //     rom_data_raw <= descrom[i_descrom_raddr];
    //     raddr_reg    <= i_descrom_raddr; // 锁存当前读取地址用于后续拦截逻辑
    // end


    // =========================================================================
    // 4. 地址拦截
    // =========================================================================
    always_comb begin
        case (i_descrom_raddr)
        // case (raddr_reg)
            16'd8:   o_descrom_rdat = VENDORID[7:0];     // idVendor L
            16'd9:   o_descrom_rdat = VENDORID[15:8];    // idVendor H
            16'd10:  o_descrom_rdat = PRODUCTID[7:0];    // idProduct L
            16'd11:  o_descrom_rdat = PRODUCTID[15:8];   // idProduct H
            16'd12:  o_descrom_rdat = VERSIONBCD[7:0];   // bcdDevice L
            16'd13:  o_descrom_rdat = VERSIONBCD[15:8];  // bcdDevice H

// DFU下载模式
            DESC_DFUMODE_DEV_ADDR + 16'd8:  o_descrom_rdat = VENDORID[7:0];
            DESC_DFUMODE_DEV_ADDR + 16'd9:  o_descrom_rdat = VENDORID[15:8];
            DESC_DFUMODE_DEV_ADDR + 16'd10: o_descrom_rdat = DFU_PRODUCTID[7:0];
            DESC_DFUMODE_DEV_ADDR + 16'd11: o_descrom_rdat = DFU_PRODUCTID[15:8];
            DESC_DFUMODE_DEV_ADDR + 16'd12: o_descrom_rdat = VERSIONBCD[7:0];
            DESC_DFUMODE_DEV_ADDR + 16'd13: o_descrom_rdat = VERSIONBCD[15:8];

            default: o_descrom_rdat = rom_data_raw;      //
        endcase
    end

    // =========================================================================
    // 5. IO输出
    // =========================================================================
    assign o_desc_dev_addr        = i_dfu_mode ? DESC_DFUMODE_DEV_ADDR : DESC_DEV_ADDR; 
    assign o_desc_dev_len         = i_dfu_mode ? DESC_DFUMODE_DEV_LEN  : DESC_DEV_LEN;

    assign o_desc_qual_addr       = DESC_QUAL_ADDR;
    assign o_desc_qual_len        = DESC_QUAL_LEN;
    assign o_desc_fscfg_addr      = DESC_FSCFG_ADDR;
    assign o_desc_fscfg_len       = DESC_FSCFG_LEN;

    assign o_desc_hscfg_addr      = i_dfu_mode ? DESC_DFUMODE_CFG_ADDR : DESC_HSCFG_ADDR;
    assign o_desc_hscfg_len       = i_dfu_mode ? DESC_DFUMODE_CFG_LEN  : DESC_HSCFG_LEN;

    assign o_desc_oscfg_addr      = DESC_OSCFG_ADDR;
    assign o_desc_hidrpt_addr     = DESC_HIDRPT_ADDR;
    assign o_desc_hidrpt_len      = DESC_HIDRPT_LEN;
    assign o_desc_strlang_addr    = DESC_STRLANG_ADDR;
    assign o_desc_strvendor_addr  = DESC_STRVENDOR_ADDR;
    assign o_desc_strvendor_len   = DESC_STRVENDOR_LEN;
    assign o_desc_strproduct_addr = DESC_STRPRODUCT_ADDR;
    assign o_desc_strproduct_len  = DESC_STRPRODUCT_LEN;
    assign o_descrom_have_strings = HAVE_STRINGS;

    // =========================================================================
    // 6. 字符串
    // =========================================================================
    // i_desc_index_o
    always_comb begin
        case (i_desc_index_o)
            8'd3: begin
                o_desc_strserial_addr = DESC_STRSERIAL_ADDR;
                o_desc_strserial_len  = DESC_STRSERIAL_LEN;
            end
            8'd4: begin
                o_desc_strserial_addr = DESC_STR4_ADDR;
                o_desc_strserial_len  = DESC_STR4_LEN;
            end
            8'd5: begin
                o_desc_strserial_addr = DESC_STR5_ADDR;
                o_desc_strserial_len  = DESC_STR5_LEN;
            end
            8'd6: begin
                o_desc_strserial_addr = DESC_STR6_ADDR;
                o_desc_strserial_len  = DESC_STR6_LEN;
            end
            default: begin
                o_desc_strserial_addr = DESC_STR6_ADDR;
                o_desc_strserial_len  = DESC_STR6_LEN;
            end
        endcase
    end

endmodule