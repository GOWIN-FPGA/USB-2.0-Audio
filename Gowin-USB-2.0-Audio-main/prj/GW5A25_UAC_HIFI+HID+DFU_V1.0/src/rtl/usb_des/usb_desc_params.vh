// =========================================================================
// usb_desc_params.vh
// =========================================================================

// Optional description of manufacturer (max 126 characters).
parameter VENDORSTR = "Gowinsemi";
parameter VENDORSTR_LEN = 9;
// Optional description of product (max 126 characters).
parameter PRODUCTSTR = "USB Composite Device";
parameter PRODUCTSTR_LEN = 20;
// Optional product serial number (max 126 characters).
parameter SERIALSTR = "TEST";
parameter SERIALSTR_LEN = 4;

//STRING
parameter STR4           = "UAC HIFI 2CN";
parameter STR4_LEN       = 12;
parameter STR5           = "HID Interface";
parameter STR5_LEN       = 13;
parameter STR6           = "DFU Runtime";
parameter STR6_LEN       = 11;

// 核心描述符地址与长度
localparam bit [15:0] DESC_DEV_ADDR  = 16'd0;
localparam bit [15:0] DESC_DEV_LEN   = 16'd18;

localparam bit [15:0] DESC_QUAL_ADDR = 16'd20;
localparam bit [15:0] DESC_QUAL_LEN  = 16'd10;

localparam bit [15:0] DESC_FSCFG_ADDR = 16'd32;
localparam bit [15:0] DESC_FSCFG_LEN  = 16'd9;

localparam bit [15:0] DESC_HSCFG_ADDR = DESC_FSCFG_ADDR + DESC_FSCFG_LEN;

   `ifdef HIFI_ONLY 
localparam bit [15:0] DESC_HSCFG_LEN  = 16'd311;
    `else
localparam bit [15:0] DESC_HSCFG_LEN  = 16'd361;
    `endif
// ------------------------------------------------------------------------


localparam bit [15:0] DESC_OSCFG_ADDR = DESC_HSCFG_ADDR + DESC_HSCFG_LEN;
localparam bit [15:0] DESC_OSCFG_LEN  = 16'd1;

//HID
localparam bit [15:0] DESC_HIDRPT_ADDR = DESC_OSCFG_ADDR + DESC_OSCFG_LEN;
localparam bit [15:0] DESC_HIDRPT_LEN  = 16'd27;

// 字符串描述符地址与长度
localparam bit [15:0] DESC_STRLANG_ADDR     = DESC_HIDRPT_ADDR + DESC_HIDRPT_LEN;

localparam bit [15:0] DESC_STRVENDOR_ADDR   = DESC_STRLANG_ADDR + 4;
localparam bit [15:0] DESC_STRVENDOR_LEN    = 16'd2 + 2*VENDORSTR_LEN;

localparam bit [15:0] DESC_STRPRODUCT_ADDR  = DESC_STRVENDOR_ADDR + DESC_STRVENDOR_LEN;
localparam bit [15:0] DESC_STRPRODUCT_LEN   = 16'd2 + 2*PRODUCTSTR_LEN;

localparam bit [15:0] DESC_STRSERIAL_ADDR   = DESC_STRPRODUCT_ADDR + DESC_STRPRODUCT_LEN;
localparam bit [15:0] DESC_STRSERIAL_LEN    = 16'd2 + 2*SERIALSTR_LEN;

localparam bit [15:0] DESC_STR4_ADDR        = DESC_STRSERIAL_ADDR + DESC_STRSERIAL_LEN;
localparam bit [15:0] DESC_STR4_LEN         = 16'd2 + 2*STR4_LEN;

localparam bit [15:0] DESC_STR5_ADDR        = DESC_STR4_ADDR + DESC_STR4_LEN;
localparam bit [15:0] DESC_STR5_LEN         = 16'd2 + 2*STR5_LEN;

localparam bit [15:0] DESC_STR6_ADDR        = DESC_STR5_ADDR + DESC_STR5_LEN;
localparam bit [15:0] DESC_STR6_LEN         = 16'd2 + 2*STR6_LEN;

// -------------------- DFU 下载模式专属描述符 ---------------------------
localparam bit [15:0] DESC_DFUMODE_DEV_ADDR = DESC_STR6_ADDR + DESC_STR6_LEN;
localparam bit [15:0] DESC_DFUMODE_DEV_LEN  = 16'd18;

localparam bit [15:0] DESC_DFUMODE_CFG_ADDR = DESC_DFUMODE_DEV_ADDR + DESC_DFUMODE_DEV_LEN;
localparam bit [15:0] DESC_DFUMODE_CFG_LEN  = 16'd27;

localparam bit [15:0] DESC_END_ADDR         = DESC_DFUMODE_CFG_ADDR + DESC_DFUMODE_CFG_LEN;
localparam bit        HAVE_STRINGS          = (VENDORSTR_LEN > 0 || PRODUCTSTR_LEN > 0 || SERIALSTR_LEN > 0);
localparam bit [15:0] ROM_LEN               = (HAVE_STRINGS)? DESC_END_ADDR : DESC_STRLANG_ADDR ;

