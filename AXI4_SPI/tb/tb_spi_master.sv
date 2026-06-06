`timescale 1ns / 1ps

import uvm_pkg::*;
`include "uvm_macros.svh"

interface axi_spi_if(input logic clk);
    logic rstn;

    logic       miso;
    logic       sclk;
    logic       mosi;
    logic [1:0] cs_n;
    logic [7:0] slave0_miso_data;
    logic [7:0] slave1_miso_data;

    logic [3:0]  awaddr;
    logic [2:0]  awprot;
    logic        awvalid;
    logic        awready;
    logic [31:0] wdata;
    logic [3:0]  wstrb;
    logic        wvalid;
    logic        wready;
    logic [1:0]  bresp;
    logic        bvalid;
    logic        bready;

    logic [3:0]  araddr;
    logic [2:0]  arprot;
    logic        arvalid;
    logic        arready;
    logic [31:0] rdata;
    logic [1:0]  rresp;
    logic        rvalid;
    logic        rready;

    clocking drv_cb @(posedge clk);
        default input #1step output #1step;
        output awaddr, awprot, awvalid;
        input  awready;
        output wdata, wstrb, wvalid;
        input  wready;
        input  bresp, bvalid;
        output bready;
        output araddr, arprot, arvalid;
        input  arready;
        input  rdata, rresp, rvalid;
        output rready;
        output miso;
        input  sclk, mosi, cs_n;
    endclocking

    clocking mon_cb @(posedge clk);
        default input #1step;
        input rstn;
        input awaddr, awvalid, awready;
        input wdata, wstrb, wvalid, wready;
        input bresp, bvalid, bready;
        input araddr, arvalid, arready;
        input rdata, rresp, rvalid, rready;
        input miso, sclk, mosi, cs_n;
    endclocking

    task automatic init_signals();
        rstn    = 1'b0;
        miso    = 1'b0;
        slave0_miso_data = 8'h00;
        slave1_miso_data = 8'h00;
        awaddr  = 4'h0;
        awprot  = 3'h0;
        awvalid = 1'b0;
        wdata   = 32'h0;
        wstrb   = 4'hF;
        wvalid  = 1'b0;
        bready  = 1'b0;
        araddr  = 4'h0;
        arprot  = 3'h0;
        arvalid = 1'b0;
        rready  = 1'b0;
    endtask
endinterface

class axi_spi_seq_item extends uvm_sequence_item;
    rand bit        is_write;
    rand bit [3:0]  addr;
    rand bit [31:0] wdata;
         bit [31:0] rdata;

    `uvm_object_utils_begin(axi_spi_seq_item)
        `uvm_field_int(is_write, UVM_DEFAULT)
        `uvm_field_int(addr,     UVM_DEFAULT)
        `uvm_field_int(wdata,    UVM_DEFAULT)
        `uvm_field_int(rdata,    UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "axi_spi_seq_item");
        super.new(name);
    endfunction
endclass

class spi_expected_item extends uvm_sequence_item;
    bit [7:0] tx_data;
    bit [7:0] rx_data;
    bit       slave_sel;

    `uvm_object_utils_begin(spi_expected_item)
        `uvm_field_int(tx_data,   UVM_DEFAULT)
        `uvm_field_int(rx_data,   UVM_DEFAULT)
        `uvm_field_int(slave_sel, UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "spi_expected_item");
        super.new(name);
    endfunction
endclass

class spi_observed_item extends uvm_sequence_item;
    bit [7:0] mosi_data;
    bit       slave_sel;

    `uvm_object_utils_begin(spi_observed_item)
        `uvm_field_int(mosi_data, UVM_DEFAULT)
        `uvm_field_int(slave_sel, UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "spi_observed_item");
        super.new(name);
    endfunction
endclass

class spi_status_item extends uvm_sequence_item;
    bit [31:0] status;
    bit [7:0]  rx_data;
    bit        busy;
    bit        done;

    `uvm_object_utils_begin(spi_status_item)
        `uvm_field_int(status,  UVM_DEFAULT)
        `uvm_field_int(rx_data, UVM_DEFAULT)
        `uvm_field_int(busy,    UVM_DEFAULT)
        `uvm_field_int(done,    UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "spi_status_item");
        super.new(name);
    endfunction
endclass

class axi_spi_sequencer extends uvm_sequencer #(axi_spi_seq_item);
    `uvm_component_utils(axi_spi_sequencer)

    function new(string name = "axi_spi_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction
endclass

class axi_spi_driver extends uvm_driver #(axi_spi_seq_item);
    virtual axi_spi_if vif;

    `uvm_component_utils(axi_spi_driver)

    function new(string name = "axi_spi_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axi_spi_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("AXI_DRV", "virtual interface was not provided")
        end
    endfunction

    task run_phase(uvm_phase phase);
        axi_spi_seq_item tr;

        vif.init_signals();
        repeat (5) @(posedge vif.clk);
        vif.rstn <= 1'b1;
        repeat (2) @(posedge vif.clk);

        forever begin
            seq_item_port.get_next_item(tr);
            if (tr.is_write) begin
                axi_write(tr.addr, tr.wdata);
            end else begin
                axi_read(tr.addr, tr.rdata);
            end
            seq_item_port.item_done();
        end
    endtask

    task automatic axi_write(input bit [3:0] addr, input bit [31:0] data);
        @(vif.drv_cb);
        vif.drv_cb.awaddr  <= addr;
        vif.drv_cb.awprot  <= 3'h0;
        vif.drv_cb.awvalid <= 1'b1;
        vif.drv_cb.wdata   <= data;
        vif.drv_cb.wstrb   <= 4'hF;
        vif.drv_cb.wvalid  <= 1'b1;
        vif.drv_cb.bready  <= 1'b1;

        do begin
            @(vif.drv_cb);
        end while (!(vif.drv_cb.awready && vif.drv_cb.wready));

        vif.drv_cb.awvalid <= 1'b0;
        vif.drv_cb.wvalid  <= 1'b0;

        while (!vif.drv_cb.bvalid) begin
            @(vif.drv_cb);
        end

        vif.drv_cb.bready <= 1'b0;
        @(vif.drv_cb);
    endtask

    task automatic axi_read(input bit [3:0] addr, output bit [31:0] data);
        @(vif.drv_cb);
        vif.drv_cb.araddr  <= addr;
        vif.drv_cb.arprot  <= 3'h0;
        vif.drv_cb.arvalid <= 1'b1;
        vif.drv_cb.rready  <= 1'b1;

        do begin
            @(vif.drv_cb);
        end while (!vif.drv_cb.arready);

        vif.drv_cb.arvalid <= 1'b0;

        while (!vif.drv_cb.rvalid) begin
            @(vif.drv_cb);
        end

        data = vif.drv_cb.rdata;
        vif.drv_cb.rready <= 1'b0;
        @(vif.drv_cb);
    endtask
endclass

class spi_monitor extends uvm_monitor;
    virtual axi_spi_if vif;
    uvm_analysis_port #(spi_observed_item) ap;

    `uvm_component_utils(spi_monitor)

    function new(string name = "spi_monitor", uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axi_spi_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("SPI_MON", "virtual interface was not provided")
        end
    endfunction

    task run_phase(uvm_phase phase);
        spi_observed_item obs;
        bit [7:0] captured;
        int bit_idx;

        wait (vif.rstn === 1'b1);

        forever begin
            @(negedge vif.cs_n[0] or negedge vif.cs_n[1]);

            obs = spi_observed_item::type_id::create("obs");
            obs.slave_sel = (vif.cs_n[1] == 1'b0);
            captured = 8'h00;

            for (bit_idx = 7; bit_idx >= 0; bit_idx--) begin
                @(posedge vif.sclk);
                captured[bit_idx] = vif.mosi;
            end

            obs.mosi_data = captured;
            ap.write(obs);

            @(posedge vif.cs_n[obs.slave_sel]);
        end
    endtask
endclass

class spi_scoreboard extends uvm_scoreboard;
    uvm_tlm_analysis_fifo #(spi_expected_item) exp_fifo;
    uvm_tlm_analysis_fifo #(spi_observed_item) obs_fifo;
    uvm_tlm_analysis_fifo #(spi_status_item) status_fifo;

    int total_count;
    int pass_count;
    int fail_count;

    covergroup spi_cg with function sample(bit slave_sel, bit [7:0] tx_data, bit [7:0] rx_data);
        option.per_instance = 1;

        cp_slave: coverpoint slave_sel {
            bins slave0 = {1'b0};
            bins slave1 = {1'b1};
        }

        cp_tx_data: coverpoint tx_data {
            bins zero = {8'h00};
            bins ff   = {8'hFF};
            bins low  = {[8'h01:8'h3F]};
            bins mid  = {[8'h40:8'hBF]};
            bins high = {[8'hC0:8'hFE]};
        }

        cp_rx_data: coverpoint rx_data {
            bins zero = {8'h00};
            bins ff   = {8'hFF};
            bins low  = {[8'h01:8'h3F]};
            bins mid  = {[8'h40:8'hBF]};
            bins high = {[8'hC0:8'hFE]};
        }

        cross_slave_tx: cross cp_slave, cp_tx_data;
        cross_slave_rx: cross cp_slave, cp_rx_data;
    endgroup

    `uvm_component_utils(spi_scoreboard)

    function new(string name = "spi_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        exp_fifo    = new("exp_fifo", this);
        obs_fifo    = new("obs_fifo", this);
        status_fifo = new("status_fifo", this);
        spi_cg      = new();
    endfunction

    task run_phase(uvm_phase phase);
        spi_expected_item exp;
        spi_observed_item obs;
        spi_status_item   sts;
        bit               failed;

        forever begin
            exp_fifo.get(exp);
            obs_fifo.get(obs);
            status_fifo.get(sts);

            failed = 1'b0;
            total_count++;

            // Compare the expected transfer request with the actual SPI pins
            // and with the RX value exposed through the AXI STATUS register.
            if (obs.slave_sel !== exp.slave_sel) begin
                failed = 1'b1;
                `uvm_error("SPI_SCB", $sformatf(
                    "Slave mismatch expected=%0d observed=%0d",
                    exp.slave_sel, obs.slave_sel))
            end

            if (obs.mosi_data !== exp.tx_data) begin
                failed = 1'b1;
                `uvm_error("SPI_SCB", $sformatf(
                    "MOSI mismatch expected=0x%02h observed=0x%02h",
                    exp.tx_data, obs.mosi_data))
            end

            if (sts.busy !== 1'b0) begin
                failed = 1'b1;
                `uvm_error("SPI_SCB", $sformatf(
                    "STATUS busy is not clear STATUS=0x%08h", sts.status))
            end

            if (sts.rx_data !== exp.rx_data) begin
                failed = 1'b1;
                `uvm_error("SPI_SCB", $sformatf(
                    "RX mismatch expected=0x%02h observed=0x%02h STATUS=0x%08h",
                    exp.rx_data, sts.rx_data, sts.status))
            end

            if (!failed) begin
                pass_count++;
                spi_cg.sample(obs.slave_sel, obs.mosi_data, sts.rx_data);
                `uvm_info("SPI_SCB", $sformatf(
                    "PASS transfer=%0d slave=%0d MOSI=0x%02h RX=0x%02h STATUS=0x%08h",
                    total_count, obs.slave_sel, obs.mosi_data, sts.rx_data,
                    sts.status), UVM_LOW)
            end else begin
                fail_count++;
            end
        end
    endtask

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);

        if ((total_count != 0) && (fail_count == 0)) begin
            `uvm_info("SPI_SCB_SUMMARY", $sformatf(
                "FINAL PASS: total=%0d pass=%0d fail=%0d",
                total_count, pass_count, fail_count), UVM_NONE)
        end else begin
            `uvm_error("SPI_SCB_SUMMARY", $sformatf(
                "FINAL FAIL: total=%0d pass=%0d fail=%0d",
                total_count, pass_count, fail_count))
        end

        `uvm_info("SPI_COV", $sformatf(
            "FUNCTIONAL COVERAGE = %0.2f%%", spi_cg.get_coverage()), UVM_NONE)
    endfunction
endclass

class axi_spi_agent extends uvm_agent;
    axi_spi_sequencer sequencer;
    axi_spi_driver    driver;
    spi_monitor       monitor;

    `uvm_component_utils(axi_spi_agent)

    function new(string name = "axi_spi_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sequencer = axi_spi_sequencer::type_id::create("sequencer", this);
        driver    = axi_spi_driver::type_id::create("driver", this);
        monitor   = spi_monitor::type_id::create("monitor", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction
endclass

class axi_spi_env extends uvm_env;
    axi_spi_agent agent;
    spi_scoreboard scoreboard;

    `uvm_component_utils(axi_spi_env)

    function new(string name = "axi_spi_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent = axi_spi_agent::type_id::create("agent", this);
        scoreboard = spi_scoreboard::type_id::create("scoreboard", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.monitor.ap.connect(scoreboard.obs_fifo.analysis_export);
    endfunction
endclass

class axi_spi_base_sequence extends uvm_sequence #(axi_spi_seq_item);
    localparam bit [3:0] SPI_CTRL   = 4'h0;
    localparam bit [3:0] SPI_TXDATA = 4'h4;
    localparam bit [3:0] SPI_STATUS = 4'h8;
    localparam bit [3:0] SPI_CLKDIV = 4'hC;
    localparam int RANDOM_TRANSFER_COUNT = 1000;
    localparam bit [7:0] FIXED_CLK_DIV = 8'd4;

    uvm_tlm_analysis_fifo #(spi_expected_item) exp_fifo;
    uvm_tlm_analysis_fifo #(spi_status_item) status_fifo;
    virtual axi_spi_if vif;

    `uvm_object_utils(axi_spi_base_sequence)

    function new(string name = "axi_spi_base_sequence");
        super.new(name);
    endfunction

    task body();
        bit [31:0] status;
        bit        slave_sel;
        bit [7:0]  tx_data;
        bit [7:0]  rx_data;

        if ((exp_fifo == null) || (status_fifo == null) || (vif == null)) begin
            `uvm_fatal("AXI_SEQ", "scoreboard fifo was not provided")
        end

        axi_write(SPI_CLKDIV, {24'd0, FIXED_CLK_DIV});

        for (int i = 0; i < RANDOM_TRANSFER_COUNT; i++) begin
            slave_sel = $urandom_range(0, 1);
            tx_data   = $urandom_range(0, 255);
            rx_data   = $urandom_range(0, 255);

            do_transfer(slave_sel, tx_data, rx_data, status);
        end

        `uvm_info("AXI_SEQ", $sformatf(
            "Random smoke sequence completed: transfers=%0d fixed_clk_div=%0d",
            RANDOM_TRANSFER_COUNT, FIXED_CLK_DIV), UVM_LOW)
    endtask

    task automatic do_transfer(
        input  bit       slave_sel,
        input  bit [7:0] tx_data,
        input  bit [7:0] rx_data,
        output bit [31:0] status
    );
        spi_expected_item exp;
        bit [31:0] ctrl_hold;

        exp = spi_expected_item::type_id::create("exp");
        exp.slave_sel = slave_sel;
        exp.tx_data   = tx_data;
        exp.rx_data   = rx_data;
        exp_fifo.put(exp);

        if (slave_sel == 1'b0) begin
            vif.slave0_miso_data = rx_data;
        end else begin
            vif.slave1_miso_data = rx_data;
        end

        ctrl_hold = {30'd0, slave_sel, 1'b0};

        axi_write(SPI_TXDATA, {24'd0, tx_data});
        axi_write(SPI_CTRL,   ctrl_hold | 32'h1);
        axi_write(SPI_CTRL,   ctrl_hold);

        wait_status_busy_set(status);
        wait_status_idle(status);
        send_status_to_scoreboard(status);
    endtask

    task automatic wait_status_busy_set(output bit [31:0] status);
        int timeout;

        timeout = 10000;
        do begin
            axi_read(SPI_STATUS, status);
            timeout--;
        end while ((status[0] == 1'b0) && (timeout > 0));

        if (timeout == 0) begin
            `uvm_error("AXI_SEQ", "Timeout while waiting for busy set")
        end
    endtask

    task automatic wait_status_idle(output bit [31:0] status);
        int timeout;

        timeout = 10000;
        do begin
            axi_read(SPI_STATUS, status);
            timeout--;
        end while ((status[0] == 1'b1) && (timeout > 0));

        if (timeout == 0) begin
            `uvm_error("AXI_SEQ", "Timeout while waiting for busy clear")
        end
    endtask

    task automatic send_status_to_scoreboard(input bit [31:0] status);
        spi_status_item sts;

        sts = spi_status_item::type_id::create("sts");
        sts.status  = status;
        sts.busy    = status[0];
        sts.done    = status[1];
        sts.rx_data = status[15:8];
        status_fifo.put(sts);
    endtask

    task automatic axi_write(input bit [3:0] addr, input bit [31:0] data);
        axi_spi_seq_item tr;

        tr = axi_spi_seq_item::type_id::create("axi_write_tr");
        start_item(tr);
        tr.is_write = 1'b1;
        tr.addr     = addr;
        tr.wdata    = data;
        finish_item(tr);
    endtask

    task automatic axi_read(input bit [3:0] addr, output bit [31:0] data);
        axi_spi_seq_item tr;

        tr = axi_spi_seq_item::type_id::create("axi_read_tr");
        start_item(tr);
        tr.is_write = 1'b0;
        tr.addr     = addr;
        finish_item(tr);
        data = tr.rdata;
    endtask
endclass

class axi_spi_test extends uvm_test;
    axi_spi_env env;
    virtual axi_spi_if vif;

    `uvm_component_utils(axi_spi_test)

    function new(string name = "axi_spi_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = axi_spi_env::type_id::create("env", this);
        if (!uvm_config_db#(virtual axi_spi_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("AXI_TEST", "virtual interface was not provided")
        end
    endfunction

    task run_phase(uvm_phase phase);
        axi_spi_base_sequence seq;

        phase.raise_objection(this);

        seq = axi_spi_base_sequence::type_id::create("seq");
        seq.exp_fifo    = env.scoreboard.exp_fifo;
        seq.status_fifo = env.scoreboard.status_fifo;
        seq.vif         = vif;
        seq.start(env.agent.sequencer);

        #1000ns;
        phase.drop_objection(this);
    endtask
endclass

module tb_spi_master;
    logic clk;

    axi_spi_if vif(clk);

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    spi_master dut (
        .miso(vif.miso),
        .sclk(vif.sclk),
        .mosi(vif.mosi),
        .cs_n(vif.cs_n),

        .s00_axi_aclk(clk),
        .s00_axi_aresetn(vif.rstn),
        .s00_axi_awaddr(vif.awaddr),
        .s00_axi_awprot(vif.awprot),
        .s00_axi_awvalid(vif.awvalid),
        .s00_axi_awready(vif.awready),
        .s00_axi_wdata(vif.wdata),
        .s00_axi_wstrb(vif.wstrb),
        .s00_axi_wvalid(vif.wvalid),
        .s00_axi_wready(vif.wready),
        .s00_axi_bresp(vif.bresp),
        .s00_axi_bvalid(vif.bvalid),
        .s00_axi_bready(vif.bready),
        .s00_axi_araddr(vif.araddr),
        .s00_axi_arprot(vif.arprot),
        .s00_axi_arvalid(vif.arvalid),
        .s00_axi_arready(vif.arready),
        .s00_axi_rdata(vif.rdata),
        .s00_axi_rresp(vif.rresp),
        .s00_axi_rvalid(vif.rvalid),
        .s00_axi_rready(vif.rready)
    );

    task automatic drive_miso_byte(input bit [7:0] data);
        int bit_idx;

        for (bit_idx = 7; bit_idx >= 0; bit_idx--) begin
            vif.miso = data[bit_idx];
            @(negedge vif.sclk);
        end
    endtask

    initial begin
        forever begin
            @(negedge vif.cs_n[0] or negedge vif.cs_n[1]);

            if (vif.cs_n[0] == 1'b0) begin
                drive_miso_byte(vif.slave0_miso_data);
            end else begin
                drive_miso_byte(vif.slave1_miso_data);
            end

            wait (vif.cs_n == 2'b11);
            vif.miso = 1'b0;
        end
    end

    initial begin
        uvm_config_db#(virtual axi_spi_if)::set(null, "*", "vif", vif);
        run_test("axi_spi_test");
    end

    initial begin
        #50ms;
        `uvm_fatal("TB_TIMEOUT", "Simulation timeout")
    end
endmodule
