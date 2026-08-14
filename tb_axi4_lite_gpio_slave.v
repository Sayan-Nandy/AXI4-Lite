`timescale 1ns/1ps

module tb_axi4_lite_gpio_slave;

    parameter DATA_WIDTH = 32;
    parameter ADDR_WIDTH = 4;
    parameter STRB_WIDTH = DATA_WIDTH / 8;

    reg                         CLK;
    reg                         RESET_N;

    reg  [ADDR_WIDTH-1:0]       WA_ADDR;
    reg                         WA_VALID;
    wire                        WA_READY;

    reg  [DATA_WIDTH-1:0]       W_DATA;
    reg  [STRB_WIDTH-1:0]       W_STRB;
    reg                         W_VALID;
    wire                        W_READY;

    wire [1:0]                  B_RESP;
    wire                        B_VALID;
    reg                         B_READY;

    reg  [ADDR_WIDTH-1:0]       RA_ADDR;
    reg                         RA_VALID;
    wire                        RA_READY;

    wire [DATA_WIDTH-1:0]       R_DATA;
    wire [1:0]                  R_RESP;
    wire                        R_VALID;
    reg                         R_READY;

    wire [DATA_WIDTH-1:0]       gpio_out;
    wire [DATA_WIDTH-1:0]       gpio_dir;
    reg  [DATA_WIDTH-1:0]       gpio_in;

    integer errors;
    integer tests;

    localparam [ADDR_WIDTH-1:0] ADDR_DATA   = 4'h0;
    localparam [ADDR_WIDTH-1:0] ADDR_DIR    = 4'h4;
    localparam [ADDR_WIDTH-1:0] ADDR_STATUS = 4'h8;
    localparam [ADDR_WIDTH-1:0] ADDR_BAD    = 4'hC;

    // ----------------------------------------------------------------
    // DUT
    // ----------------------------------------------------------------
    axi4_lite_gpio_slave #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .CLK    (CLK),
        .RESET_N (RESET_N),

        .WA_ADDR  (WA_ADDR),
        .WA_VALID (WA_VALID),
        .WA_READY (WA_READY),

        .W_DATA   (W_DATA),
        .W_STRB   (W_STRB),
        .W_VALID  (W_VALID),
        .W_READY  (W_READY),

        .B_RESP   (B_RESP),
        .B_VALID  (B_VALID),
        .B_READY  (B_READY),

        .RA_ADDR  (RA_ADDR),
        .RA_VALID (RA_VALID),
        .RA_READY (RA_READY),

        .R_DATA   (R_DATA),
        .R_RESP   (R_RESP),
        .R_VALID  (R_VALID),
        .R_READY  (R_READY),

        .gpio_out      (gpio_out),
        .gpio_dir      (gpio_dir),
        .gpio_in       (gpio_in)
    );

    // ----------------------------------------------------------------
    // Clock: 100 MHz
    // ----------------------------------------------------------------
    initial CLK = 1'b0;
    always #5 CLK = ~CLK;

    // ----------------------------------------------------------------
    // Helpers
    // ----------------------------------------------------------------
    task fail_test;
        input [255:0] msg;
        begin
            errors = errors + 1;
            $display("[FAIL] %0s", msg);
        end
    endtask

    task pass_test;
        input [255:0] msg;
        begin
            tests = tests + 1;
            $display("[PASS] %0s", msg);
        end
    endtask

    task check_equal;
        input [DATA_WIDTH-1:0] actual;
        input [DATA_WIDTH-1:0] expected;
        input [255:0] name;
        begin
            tests = tests + 1;
            if (actual !== expected) begin
                errors = errors + 1;
                $display("[FAIL] %0s: expected 0x%08h, got 0x%08h",
                         name, expected, actual);
            end
            else begin
                $display("[PASS] %0s = 0x%08h", name, actual);
            end
        end
    endtask

    task check_resp;
        input [1:0] actual;
        input [1:0] expected;
        input [255:0] name;
        begin
            tests = tests + 1;
            if (actual !== expected) begin
                errors = errors + 1;
                $display("[FAIL] %0s: expected %b, got %b",
                         name, expected, actual);
            end
            else begin
                $display("[PASS] %0s response = %b", name, actual);
            end
        end
    endtask

    // ----------------------------------------------------------------
    // AXI write: AW and W presented together
    // ----------------------------------------------------------------
    task axi_write;
        input [ADDR_WIDTH-1:0] addr;
        input [DATA_WIDTH-1:0] data;
        input [STRB_WIDTH-1:0] strb;
        input [1:0] expected_resp;
        integer timeout;
        begin
            WA_ADDR  = addr;
            WA_VALID = 1'b1;
            W_DATA   = data;
            W_STRB   = strb;
            W_VALID  = 1'b1;

            timeout = 0;
            while (!(WA_READY && W_READY)) begin
                @(posedge CLK);
                timeout = timeout + 1;
                if (timeout > 20) begin
                    fail_test("axi_write: AW/W READY timeout");
                    WA_VALID = 1'b0;
                    W_VALID  = 1'b0;
                    disable axi_write;
                end
            end

            @(posedge CLK);
            WA_VALID = 1'b0;
            W_VALID  = 1'b0;

            timeout = 0;
            while (!B_VALID) begin
                @(posedge CLK);
                timeout = timeout + 1;
                if (timeout > 20) begin
                    fail_test("axi_write: BVALID timeout");
                    disable axi_write;
                end
            end

            check_resp(B_RESP, expected_resp, "write response");

            // Deliberately hold BREADY low for one cycle to verify
            // that BVALID remains asserted until the handshake.
            B_READY = 1'b0;
            @(posedge CLK);
            tests = tests + 1;
            if (!B_VALID) begin
                errors = errors + 1;
                $display("[FAIL] BVALID did not remain asserted while BREADY=0");
            end

            B_READY = 1'b1;
            @(posedge CLK);
            B_READY = 1'b0;
        end
    endtask

    // ----------------------------------------------------------------
    // AXI write: AW first, W several cycles later
    // ----------------------------------------------------------------
    task axi_write_aw_first;
        input [ADDR_WIDTH-1:0] addr;
        input [DATA_WIDTH-1:0] data;
        input [STRB_WIDTH-1:0] strb;
        integer timeout;
        begin
            WA_ADDR  = addr;
            WA_VALID = 1'b1;
            W_VALID  = 1'b0;
            W_STRB   = strb;
            W_DATA   = data;

            timeout = 0;
            while (!WA_READY) begin
                @(posedge CLK);
                timeout = timeout + 1;
                if (timeout > 20) begin
                    fail_test("AW-first write: AWREADY timeout");
                    disable axi_write_aw_first;
                end
            end

            @(posedge CLK);
            WA_VALID = 1'b0;

            // Deliberately separate AW and W by two clock cycles.
            repeat (2) @(posedge CLK);

            W_VALID = 1'b1;

            timeout = 0;
            while (!W_READY) begin
                @(posedge CLK);
                timeout = timeout + 1;
                if (timeout > 20) begin
                    fail_test("AW-first write: WREADY timeout");
                    W_VALID = 1'b0;
                    disable axi_write_aw_first;
                end
            end

            @(posedge CLK);
            W_VALID = 1'b0;

            timeout = 0;
            while (!B_VALID) begin
                @(posedge CLK);
                timeout = timeout + 1;
                if (timeout > 20) begin
                    fail_test("AW-first write: BVALID timeout");
                    disable axi_write_aw_first;
                end
            end

            check_resp(B_RESP, 2'b00, "AW-first write response");

            B_READY = 1'b1;
            @(posedge CLK);
            B_READY = 1'b0;
        end
    endtask

    // ----------------------------------------------------------------
    // AXI write: W first, AW later
    // ----------------------------------------------------------------
    task axi_write_w_first;
        input [ADDR_WIDTH-1:0] addr;
        input [DATA_WIDTH-1:0] data;
        input [STRB_WIDTH-1:0] strb;
        integer timeout;
        begin
            W_DATA   = data;
            W_STRB   = strb;
            W_VALID  = 1'b1;
            WA_VALID = 1'b0;

            timeout = 0;
            while (!W_READY) begin
                @(posedge CLK);
                timeout = timeout + 1;
                if (timeout > 20) begin
                    fail_test("W-first write: WREADY timeout");
                    disable axi_write_w_first;
                end
            end

            @(posedge CLK);
            W_VALID = 1'b0;

            repeat (2) @(posedge CLK);

            WA_ADDR  = addr;
            WA_VALID = 1'b1;

            timeout = 0;
            while (!WA_READY) begin
                @(posedge CLK);
                timeout = timeout + 1;
                if (timeout > 20) begin
                    fail_test("W-first write: AWREADY timeout");
                    WA_VALID = 1'b0;
                    disable axi_write_w_first;
                end
            end

            @(posedge CLK);
            WA_VALID = 1'b0;

            timeout = 0;
            while (!B_VALID) begin
                @(posedge CLK);
                timeout = timeout + 1;
                if (timeout > 20) begin
                    fail_test("W-first write: BVALID timeout");
                    disable axi_write_w_first;
                end
            end

            check_resp(B_RESP, 2'b00, "W-first write response");

            B_READY = 1'b1;
            @(posedge CLK);
            B_READY = 1'b0;
        end
    endtask

    // ----------------------------------------------------------------
    // AXI read
    // ----------------------------------------------------------------
    task axi_read;
        input  [ADDR_WIDTH-1:0] addr;
        output [DATA_WIDTH-1:0] data;
        output [1:0] resp;
        integer timeout;
        begin
            RA_ADDR  = addr;
            RA_VALID = 1'b1;
            R_READY  = 1'b1;

            timeout = 0;
            while (!RA_READY) begin
                @(posedge CLK);
                timeout = timeout + 1;
                if (timeout > 20) begin
                    fail_test("axi_read: ARREADY timeout");
                    RA_VALID = 1'b0;
                    R_READY  = 1'b0;
                    data = {DATA_WIDTH{1'bx}};
                    resp = 2'bxx;
                    disable axi_read;
                end
            end

            @(posedge CLK);
            RA_VALID = 1'b0;

            timeout = 0;
            while (!R_VALID) begin
                @(posedge CLK);
                timeout = timeout + 1;
                if (timeout > 20) begin
                    fail_test("axi_read: RVALID timeout");
                    data = {DATA_WIDTH{1'bx}};
                    resp = 2'bxx;
                    R_READY = 1'b0;
                    disable axi_read;
                end
            end

            data = R_DATA;
            resp = R_RESP;

            @(posedge CLK);
            R_READY = 1'b0;
        end
    endtask

    reg [DATA_WIDTH-1:0] rdata;
    reg [1:0]            rresp;

    // ----------------------------------------------------------------
    // Test sequence
    // ----------------------------------------------------------------
    initial begin
        errors = 0;
        tests  = 0;

        RESET_N = 1'b0;

        WA_ADDR  = 'b0;
        WA_VALID = 1'b0;

        W_DATA   = 'b0;
        W_STRB   = 'b0;
        W_VALID  = 1'b0;

        B_READY  = 1'b0;

        RA_ADDR  = 'b0;
        RA_VALID = 1'b0;

        R_READY  = 1'b0;

        gpio_in      = 'b0;

        // Reset
        repeat (4) @(posedge CLK);
        RESET_N = 1'b1;
        repeat (2) @(posedge CLK);

        $display("");
        $display("==============================================");
        $display(" AXI4-Lite GPIO SLAVE TESTBENCH");
        $display("==============================================");

        // ------------------------------------------------------------
        // 1. Basic DATA write/read
        // ------------------------------------------------------------
        axi_write(ADDR_DATA, 32'hA5A5_5A5A, 4'b1111, 2'b00);

        axi_read(ADDR_DATA, rdata, rresp);
        check_equal(rdata, 32'hA5A5_5A5A, "DATA register readback");
        check_resp(rresp, 2'b00, "DATA register read");

        check_equal(gpio_out, 32'hA5A5_5A5A, "gpio_out");

        // ------------------------------------------------------------
        // 2. Basic DIR write/read
        // ------------------------------------------------------------
        axi_write(ADDR_DIR, 32'hFFFF_00FF, 4'b1111, 2'b00);

        axi_read(ADDR_DIR, rdata, rresp);
        check_equal(rdata, 32'hFFFF_00FF, "DIR register readback");
        check_equal(gpio_dir, 32'hFFFF_00FF, "gpio_dir");

        // ------------------------------------------------------------
        // 3. Byte write strobes
        // Existing value: FFFF00FF
        // Write only bytes 1 and 3 with 12 and 34.
        // Expected: 34FF12FF.
        // ------------------------------------------------------------
        axi_write(ADDR_DIR, 32'h34AA_12BB, 4'b1010, 2'b00);

        axi_read(ADDR_DIR, rdata, rresp);
        check_equal(rdata, 32'h34FF_12FF, "WSTRB byte-write behavior");

        // ------------------------------------------------------------
        // 4. AW arrives first
        // ------------------------------------------------------------
        axi_write_aw_first(ADDR_DATA, 32'h1122_3344, 4'b1111);

        axi_read(ADDR_DATA, rdata, rresp);
        check_equal(rdata, 32'h1122_3344, "AW-first write readback");

        // ------------------------------------------------------------
        // 5. W arrives first
        // ------------------------------------------------------------
        axi_write_w_first(ADDR_DATA, 32'h5566_7788, 4'b1111);

        axi_read(ADDR_DATA, rdata, rresp);
        check_equal(rdata, 32'h5566_7788, "W-first write readback");

        // ------------------------------------------------------------
        // 6. GPIO input synchronizer
        // ------------------------------------------------------------
        gpio_in = 32'hCAFE_BABE;

        // Two synchronizer stages.
        repeat (3) @(posedge CLK);

        axi_read(ADDR_STATUS, rdata, rresp);
        check_equal(rdata, 32'hCAFE_BABE, "GPIO STATUS read");
        check_resp(rresp, 2'b00, "STATUS read");

        // ------------------------------------------------------------
        // 7. Invalid read address
        // ------------------------------------------------------------
        axi_read(ADDR_BAD, rdata, rresp);
        check_equal(rdata, 32'h0000_0000, "invalid read data");
        check_resp(rresp, 2'b10, "invalid read response");

        // ------------------------------------------------------------
        // 8. Invalid write address
        // ------------------------------------------------------------
        axi_write(ADDR_BAD, 32'hDEAD_BEEF, 4'b1111, 2'b10);

        // ------------------------------------------------------------
        // Final
        // ------------------------------------------------------------
        repeat (3) @(posedge CLK);

        $display("");
        $display("==============================================");
        $display(" TESTS CHECKED : %0d", tests);
        $display(" ERRORS         : %0d", errors);

        if (errors == 0) begin
            $display(" RESULT         : PASS");
        end
        else begin
            $display(" RESULT         : FAIL");
        end

        $display("==============================================");
        $display("");

        $finish;
    end

    // ----------------------------------------------------------------
    // VCD waveform
    // ----------------------------------------------------------------
    initial begin
        $dumpfile("axi4_lite_gpio_slave_tb.vcd");
        $dumpvars(0, tb_axi4_lite_gpio_slave);
    end

endmodule
