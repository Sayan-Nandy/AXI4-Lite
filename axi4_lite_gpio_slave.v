module axi4_lite_gpio_slave #(
    parameter integer DATA_WIDTH = 32,
    parameter integer ADDR_WIDTH = 4
)(
    // ---------------------------------------------------------
    // SYSTEM SIGNALS
    // ---------------------------------------------------------
    input  wire                              CLK,
    input  wire                              RESET_N, // Active LOW

    // ---------------------------------------------------------
    // WRITE ADDRESS CHANNEL (WA_)
    // ---------------------------------------------------------
    input  wire [ADDR_WIDTH-1:0]             WA_ADDR,
    input  wire                              WA_VALID,
    output reg                               WA_READY,

    // ---------------------------------------------------------
    // WRITE DATA CHANNEL (W)
    // ---------------------------------------------------------
    input  wire [DATA_WIDTH-1:0]             W_DATA,
    input  wire [(DATA_WIDTH/8)-1:0]         W_STRB,
    input  wire                              W_VALID,
    output reg                               W_READY,

    // ---------------------------------------------------------
    // WRITE RESPONSE CHANNEL (B)
    // ---------------------------------------------------------
    output reg  [1:0]                        B_RESP,
    output reg                               B_VALID,
    input  wire                              B_READY,

    // ---------------------------------------------------------
    // READ ADDRESS CHANNEL (AR)
    // ---------------------------------------------------------
    input  wire [ADDR_WIDTH-1:0]             RA_ADDR,
    input  wire                              RA_VALID,
    output reg                               RA_READY,

    // ---------------------------------------------------------
    // READ DATA CHANNEL (R)
    // ---------------------------------------------------------
    output reg  [DATA_WIDTH-1:0]             R_DATA,
    output reg  [1:0]                        R_RESP,
    output reg                               R_VALID,
    input  wire                              R_READY,

    // ---------------------------------------------------------
    // PHYSICAL PERIPHERAL PINS
    // ---------------------------------------------------------
    output wire [DATA_WIDTH-1:0]             gpio_out,
    output wire [DATA_WIDTH-1:0]             gpio_dir,
    input  wire [DATA_WIDTH-1:0]             gpio_in
);

    localparam integer STRB_WIDTH = DATA_WIDTH / 8;

    // ---------------------------------------------------------
    // MEMORY MAP
    // ---------------------------------------------------------
    localparam [ADDR_WIDTH-1:0] ADDR_DATA   = 4'h0;
    localparam [ADDR_WIDTH-1:0] ADDR_DIR    = 4'h4;
    localparam [ADDR_WIDTH-1:0] ADDR_STATUS = 4'h8;

    // ---------------------------------------------------------
    // AXI RESPONSE CODES
    // ---------------------------------------------------------
    localparam [1:0] RESP_OKAY   = 2'b00;
    localparam [1:0] RESP_SLVERR = 2'b10;

    // ---------------------------------------------------------
    // INTERNAL SLAVE REGISTERS
    // ---------------------------------------------------------
    reg [DATA_WIDTH-1:0] slv_data_reg;
    reg [DATA_WIDTH-1:0] slv_dir_reg;

    // ---------------------------------------------------------
    // HARDWARE PIN ASSIGNMENTS
    // ---------------------------------------------------------
    assign gpio_out = slv_data_reg;
    assign gpio_dir = slv_dir_reg;


    /*
    ============================================================
                         WRITE DOMAIN
    ============================================================
    */

    // ---------------------------------------------------------
    // AW/W CHANNEL STORAGE
    //
    // AXI4-Lite allows AW and W to arrive independently.
    // Therefore we must remember each channel separately.
    // ---------------------------------------------------------

    reg                         wa_received;
    reg                         w_received;

    // Memory elements to store Write address, input data and strobe respectively

    reg [ADDR_WIDTH-1:0]        waaddr_reg;     
    reg [DATA_WIDTH-1:0]        wdata_reg;
    reg [STRB_WIDTH-1:0]        wstrb_reg;


    // ---------------------------------------------------------
    // READY GENERATION
    //
    // One outstanding write is supported.
    // Do not accept another write while BVALID is pending.
    // ---------------------------------------------------------

    always @(*) begin

        if (!RESET_N) begin
            WA_READY = 1'b0;
            W_READY  = 1'b0;
        end
        else begin
            WA_READY = !wa_received && !B_VALID;
    // (An address has already been accepted and is waiting for its corresponding write data) AND (if a previous write response isn't queued)    
        
            W_READY  = !w_received  && !B_VALID;
    // (Data has already been accepted and is waiting for its corresponding address) AND (if a previous write response isn't queued)
        end

    end


    // ---------------------------------------------------------
    // AXI HANDSHAKES
    // ---------------------------------------------------------

    wire wa_handshake;
    wire w_handshake;

    assign wa_handshake = WA_VALID && WA_READY;     //Address handshake
    assign w_handshake  = W_VALID  && W_READY;      //Data handshake


    // ---------------------------------------------------------
    // WRITE COMPLETION
    //
    // The expression also considers a handshake occurring
    // during the current clock edge.
    // ---------------------------------------------------------

    wire write_complete;

    assign write_complete =
        (wa_received || wa_handshake) &&    //Address is already stored or arrives now
        (w_received  || w_handshake);       //Data is already stored or arrives now


    // ---------------------------------------------------------
    // SELECT THE ADDRESS/DATA/STROBES TO USE FOR THIS WRITE
    //
    // If a value was already captured, use the stored value.
    // Otherwise use the value arriving on the current handshake.
    // ---------------------------------------------------------

    wire [ADDR_WIDTH-1:0] write_addr;
    wire [DATA_WIDTH-1:0] write_data;
    wire [STRB_WIDTH-1:0] write_strb;

    assign write_addr = wa_received ? waaddr_reg : WA_ADDR;
    assign write_data = w_received  ? wdata_reg  : W_DATA;
    assign write_strb = w_received  ? wstrb_reg  : W_STRB;


    // ---------------------------------------------------------
    // ADDRESS VALIDITY
    // ---------------------------------------------------------

    wire waddr_valid;

    assign waddr_valid =
        (write_addr == ADDR_DATA) ||        //Either Data
        (write_addr == ADDR_DIR);           // Or Dir


    // ---------------------------------------------------------
    // WRITE DATA + WRITE RESPONSE
    // ---------------------------------------------------------

    integer i;

    always @(posedge CLK or negedge RESET_N) begin

        if (!RESET_N) begin

            wa_received <= 1'b0;
            w_received  <= 1'b0;

            waaddr_reg  <= {ADDR_WIDTH{1'b0}};
            wdata_reg   <= {DATA_WIDTH{1'b0}};
            wstrb_reg   <= {STRB_WIDTH{1'b0}};

            slv_data_reg <= {DATA_WIDTH{1'b0}};
            slv_dir_reg  <= {DATA_WIDTH{1'b0}};

            B_VALID <= 1'b0;
            B_RESP  <= RESP_OKAY;

        end
        else begin

            // -------------------------------------------------
            // Capture AW independently
            // -------------------------------------------------
            if (wa_handshake) begin
                waaddr_reg  <= WA_ADDR;
                wa_received <= 1'b1;
            end


            // -------------------------------------------------
            // Capture W independently
            // -------------------------------------------------
            if (w_handshake) begin
                wdata_reg   <= W_DATA;
                wstrb_reg   <= W_STRB;
                w_received  <= 1'b1;
            end


            // -------------------------------------------------
            // Complete write when BOTH address and data exist
            // -------------------------------------------------
            if (write_complete) begin

                case (write_addr)

                    // -----------------------------------------
                    // DATA REGISTER
                    // -----------------------------------------
                    ADDR_DATA: begin

                        for (i = 0; i < STRB_WIDTH; i = i + 1) begin

                            if (write_strb[i]) begin                                // Using STRB as byte select
                                slv_data_reg[8*i +: 8] <= write_data[8*i +: 8];
                            end

                        end

                        B_RESP <= RESP_OKAY;

                    end


                    // -----------------------------------------
                    // DIRECTION REGISTER
                    // -----------------------------------------
                    ADDR_DIR: begin

                        for (i = 0; i < STRB_WIDTH; i = i + 1) begin

                            if (write_strb[i]) begin
                                slv_dir_reg[8*i +: 8] <= write_data[8*i +: 8];
                            end

                        end

                        B_RESP <= RESP_OKAY;

                    end


                    // -----------------------------------------
                    // INVALID ADDRESS
                    // -----------------------------------------
                    default: begin
                        B_RESP <= RESP_SLVERR;
                    end

                endcase


                // Response is now available
                B_VALID <= 1'b1;

                // Clear the captured transaction
                wa_received <= 1'b0;
                w_received  <= 1'b0;

            end


            // -------------------------------------------------
            // WRITE RESPONSE HANDSHAKE
            // -------------------------------------------------
            else if (B_VALID && B_READY) begin      //Write response sent
                B_VALID <= 1'b0;
            end

        end

    end


    /*
    ============================================================
                          READ DOMAIN
    ============================================================
    */

    // ---------------------------------------------------------
    // READ ADDRESS READY
    //
    // Only one read response is allowed to be outstanding.
    // ---------------------------------------------------------

    always @(*) begin

        if (!RESET_N)
            RA_READY = 1'b0;
        else
            RA_READY = !R_VALID;    //If a read is ongoing, don't take another address

    end


    // ---------------------------------------------------------
    // READ ADDRESS HANDSHAKE
    // ---------------------------------------------------------

    wire ra_handshake;

    assign ra_handshake = RA_VALID && RA_READY;


    // ---------------------------------------------------------
    // READ ADDRESS VALIDITY
    // ---------------------------------------------------------

    wire raddr_valid;

    assign raddr_valid =
        (RA_ADDR == ADDR_DATA)   ||
        (RA_ADDR == ADDR_DIR)    ||
        (RA_ADDR == ADDR_STATUS);


    // ---------------------------------------------------------
    // GPIO INPUT SYNCHRONIZER
    //
    // gpio_in is external to CLK domain.
    // ---------------------------------------------------------

    reg [DATA_WIDTH-1:0] gpio_in_sync_1;
    reg [DATA_WIDTH-1:0] gpio_in_sync_2;

    always @(posedge CLK or negedge RESET_N) begin

        if (!RESET_N) begin

            gpio_in_sync_1 <= {DATA_WIDTH{1'b0}};
            gpio_in_sync_2 <= {DATA_WIDTH{1'b0}};

        end
        else begin

            gpio_in_sync_1 <= gpio_in;
            gpio_in_sync_2 <= gpio_in_sync_1;

        end

    end


    // ---------------------------------------------------------
    // READ DATA + READ RESPONSE
    // ---------------------------------------------------------

    always @(posedge CLK or negedge RESET_N) begin

        if (!RESET_N) begin

            R_VALID <= 1'b0;
            R_RESP  <= RESP_OKAY;
            R_DATA  <= {DATA_WIDTH{1'b0}};

        end
        else begin

            // -------------------------------------------------
            // New read transaction
            // -------------------------------------------------
            if (ra_handshake) begin

                R_VALID <= 1'b1;        //Read data ready

                case (RA_ADDR)

                    ADDR_DATA: begin
                        R_DATA <= slv_data_reg;
                        R_RESP <= RESP_OKAY;
                    end

                    ADDR_DIR: begin
                        R_DATA <= slv_dir_reg;
                        R_RESP <= RESP_OKAY;
                    end

                    ADDR_STATUS: begin
                        R_DATA <= gpio_in_sync_2;
                        R_RESP <= RESP_OKAY;
                    end

                    default: begin
                        R_DATA <= {DATA_WIDTH{1'b0}};
                        R_RESP <= RESP_SLVERR;
                    end

                endcase

            end


            // -------------------------------------------------
            // Read response consumed
            // -------------------------------------------------
            else if (R_VALID && R_READY) begin      //Read done
                R_VALID <= 1'b0;
            end

        end

    end

endmodule