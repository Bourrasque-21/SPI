import uvm_pkg::*;
`include "uvm_macros.svh"


interface spi_if (
    input logic clk,
    input logic rst
);

    // DUT control side
    logic       start;
    logic [7:0] tx_data;
    logic [7:0] clk_div;
    logic       cpol;
    logic       cpha;

    // DUT status side
    logic [7:0] rx_data;
    logic       busy;
    logic       done;

    // SPI pins
    logic       sclk;
    logic       mosi;
    logic       miso;
    logic       cs_n;

    clocking drv_cb @(posedge clk);
        default input #1step output #1step;
        output start, tx_data, clk_div, cpol, cpha;
        input rx_data, busy, done, sclk, mosi, cs_n;
    endclocking

    clocking mon_cb @(posedge clk);
        default input #1step;
        input start, tx_data, clk_div, cpol, cpha;
        input rx_data, busy, done;
        input sclk, mosi, miso, cs_n;
    endclocking

    task automatic init_signals();
        start   = 1'b0;
        tx_data = 8'h00;
        clk_div = 8'd4;
        cpol    = 1'b0;
        cpha    = 1'b0;
    endtask
endinterface  //spi_if


class spi_seq_item extends uvm_sequence_item;
    rand bit [7:0] tx_data;
    rand bit [7:0] clk_div;
    rand bit       cpol;
    rand bit       cpha;

    bit      [7:0] captured_mosi;
    bit      [7:0] rx_data;

    constraint clk_div_c {
        clk_div inside {8'd1, 8'd3, 8'd4, 8'd9, 8'd24, 8'd49, 8'd99};
    }

    `uvm_object_utils_begin(spi_seq_item)
        `uvm_field_int(tx_data, UVM_DEFAULT)
        `uvm_field_int(clk_div, UVM_DEFAULT)
        `uvm_field_int(cpol, UVM_DEFAULT)
        `uvm_field_int(cpha, UVM_DEFAULT)
        `uvm_field_int(captured_mosi, UVM_DEFAULT)
        `uvm_field_int(rx_data, UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "spi_seq_item");
        super.new(name);
    endfunction
endclass


class spi_sequencer extends uvm_sequencer #(spi_seq_item);
    `uvm_component_utils(spi_sequencer)

    function new(string name = "spi_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction
endclass


class spi_driver extends uvm_driver #(spi_seq_item);
    virtual spi_if vif;

    `uvm_component_utils(spi_driver)

    function new(string name = "spi_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual spi_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("SPI_DRV",
                       "virtual interface was not provided to spi_driver")
        end
    endfunction

    task run_phase(uvm_phase phase);
        spi_seq_item tr;

        vif.init_signals();
        wait (vif.rst === 1'b0);
        @(vif.drv_cb);

        forever begin
            seq_item_port.get_next_item(tr);

            drive_command(tr);
            wait_for_done(tr.clk_div);

            `uvm_info("SPI_DRV", $sformatf(
                      "Drove SPI transfer mode=%0d tx=0x%02h",
                      {
                          tr.cpol, tr.cpha
                      },
                      tr.tx_data
                      ), UVM_MEDIUM)

            seq_item_port.item_done();
        end
    endtask

    task automatic drive_command(input spi_seq_item tr);
        @(vif.drv_cb);
        vif.drv_cb.tx_data <= tr.tx_data;
        vif.drv_cb.clk_div <= tr.clk_div;
        vif.drv_cb.cpol    <= tr.cpol;
        vif.drv_cb.cpha    <= tr.cpha;
        vif.drv_cb.start   <= 1'b1;

        @(vif.drv_cb);
        vif.drv_cb.start <= 1'b0;
    endtask

    task automatic wait_for_done(input bit [7:0] clk_div);
        int unsigned timeout_cycles;

        timeout_cycles = (clk_div + 1) * 40;
        repeat (timeout_cycles) begin
            @(vif.drv_cb);
            if (vif.drv_cb.done === 1'b1) begin
                return;
            end
        end

        `uvm_fatal("SPI_DRV_TIMEOUT",
                   $sformatf("Timed out waiting for done. clk_div=%0d",
                             clk_div))
    endtask
endclass


class spi_monitor extends uvm_monitor;
    virtual spi_if vif;
    uvm_analysis_port #(spi_seq_item) item_ap;

    `uvm_component_utils(spi_monitor)

    function new(string name = "spi_monitor", uvm_component parent = null);
        super.new(name, parent);
        item_ap = new("item_ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual spi_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("SPI_MON",
                       "virtual interface was not provided to spi_monitor")
        end
    endfunction

    task automatic wait_sample_edge(input bit cpol, input bit cpha);
        if (!cpha) begin
            if (cpol) @(negedge vif.sclk);
            else @(posedge vif.sclk);
        end else begin
            if (cpol) @(posedge vif.sclk);
            else @(negedge vif.sclk);
        end
    endtask

    task run_phase(uvm_phase phase);
        spi_seq_item       tr;
        bit          [7:0] sampled_mosi;
        bit                sample_cpol;
        bit                sample_cpha;
        bit          [7:0] exp_tx_data;
        bit          [7:0] exp_clk_div;

        wait (vif.rst === 1'b0);

        forever begin
            @(negedge vif.cs_n);
            if (vif.rst) begin
                continue;
            end

            sample_cpol  = vif.cpol;
            sample_cpha  = vif.cpha;
            exp_tx_data  = vif.tx_data;
            exp_clk_div  = vif.clk_div;
            sampled_mosi = '0;
            for (int i = 0; i < 8; i++) begin
                wait_sample_edge(sample_cpol, sample_cpha);
                sampled_mosi = {sampled_mosi[6:0], vif.mosi};
            end

            repeat ((exp_clk_div + 1) * 40) begin
                @(posedge vif.clk);
                if (vif.done === 1'b1) begin
                    break;
                end
            end

            if (vif.done !== 1'b1) begin
                `uvm_fatal("SPI_MON_TIMEOUT",
                           $sformatf("Timed out waiting for done. clk_div=%0d",
                                     exp_clk_div))
            end

            tr               = spi_seq_item::type_id::create("mon_tr");
            tr.tx_data       = exp_tx_data;
            tr.clk_div       = exp_clk_div;
            tr.cpol          = sample_cpol;
            tr.cpha          = sample_cpha;
            tr.captured_mosi = sampled_mosi;
            tr.rx_data       = vif.rx_data;
            item_ap.write(tr);

            `uvm_info("SPI_MON", $sformatf(
                      "Observed SPI completion mode=%0d tx=0x%02h mosi=0x%02h rx=0x%02h",
                      {
                          tr.cpol, tr.cpha
                      },
                      tr.tx_data,
                      tr.captured_mosi,
                      tr.rx_data
                      ), UVM_MEDIUM)
        end
    endtask
endclass


class spi_scoreboard extends uvm_scoreboard;
    uvm_tlm_analysis_fifo #(spi_seq_item) mon_fifo;
    int unsigned txn_count;
    int unsigned match_count;
    int unsigned mismatch_count;

    `uvm_component_utils(spi_scoreboard)

    function new(string name = "spi_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        mon_fifo = new("mon_fifo", this);
    endfunction

    task run_phase(uvm_phase phase);
        spi_seq_item tr;

        forever begin
            mon_fifo.get(tr);

            txn_count++;

            if ((tr.tx_data !== tr.captured_mosi) ||
                    (tr.tx_data !== tr.rx_data)) begin
                mismatch_count++;
                `uvm_error(
                    "SPI_SCB",
                    $sformatf(
                        "SPI mismatch mode=%0d tx=0x%02h captured_mosi=0x%02h rx_data=0x%02h",
                        {tr.cpol, tr.cpha}, tr.tx_data, tr.captured_mosi,
                        tr.rx_data))
            end else begin
                match_count++;
                `uvm_info("SPI_SCB", $sformatf(
                          "SPI match mode=%0d tx=0x%02h mosi=0x%02h rx=0x%02h",
                          {
                              tr.cpol, tr.cpha
                          },
                          tr.tx_data,
                          tr.captured_mosi,
                          tr.rx_data
                          ), UVM_LOW)
            end
        end
    endtask

    function void check_phase(uvm_phase phase);
        super.check_phase(phase);

        if (txn_count == 0) begin
            `uvm_error("SPI_SCB", "No completed SPI transactions were observed")
        end

        if (mismatch_count != 0) begin
            `uvm_error("SPI_SCB", $sformatf("Detected %0d SPI mismatches",
                                            mismatch_count))
        end
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("SPI_SCB", $sformatf(
                  {
                      "SPI report summary:\n",
                      "  total       : %0d\n",
                      "  pass        : %0d\n",
                      "  fail        : %0d"
                  },
                  txn_count,
                  match_count,
                  mismatch_count
                  ), UVM_LOW)
    endfunction

endclass

class spi_coverage extends uvm_subscriber #(spi_seq_item);
    bit [1:0] sampled_mode;
    bit [7:0] sampled_clk_div;
    bit [7:0] sampled_tx_data;

    covergroup spi_cg;
        option.per_instance = 1;

        cp_mode: coverpoint sampled_mode {
            bins mode0 = {2'b00};
            bins mode1 = {2'b01};
            bins mode2 = {2'b10};
            bins mode3 = {2'b11};
        }

        cp_clk_div: coverpoint sampled_clk_div {
            bins div_25m = {8'd1};
            bins div_12p5m = {8'd3};
            bins div_10m = {8'd4};
            bins div_5m = {8'd9};
            bins div_2m = {8'd24};
            bins div_1m = {8'd49};
            bins div_500k = {8'd99};
        }

        cp_pattern: coverpoint sampled_tx_data {
            bins zero = {8'h00};
            bins ones = {8'hFF};
            bins alt_a = {8'hAA};
            bins alt_5 = {8'h55};
            bins low = {[8'h01 : 8'h1F]};
            bins mid = {[8'h20 : 8'hDF]};
            bins high = {[8'hE0 : 8'hFE]};
        }

        cross_mode_clk_div: cross cp_mode, cp_clk_div;
        cross_mode_pattern: cross cp_mode, cp_pattern;
    endgroup

    `uvm_component_utils(spi_coverage)

    function new(string name = "spi_coverage", uvm_component parent = null);
        super.new(name, parent);
        spi_cg = new();
    endfunction

    function void write(spi_seq_item t);
        sampled_mode    = {t.cpol, t.cpha};
        sampled_clk_div = t.clk_div;
        sampled_tx_data = t.tx_data;
        spi_cg.sample();
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("SPI_COV", $sformatf(
                  {
                      "\n======SPI coverage summary=====\n",
                      "  mode              : %0.2f%%\n",
                      "  clk_div           : %0.2f%%\n",
                      "  pattern           : %0.2f%%\n",
                      "  mode x clk_div    : %0.2f%%\n",
                      "  mode x pattern    : %0.2f%%\n",
                      "  total             : %0.2f%%"
                  },
                  spi_cg.cp_mode.get_coverage(),
                  spi_cg.cp_clk_div.get_coverage(),
                  spi_cg.cp_pattern.get_coverage(),
                  spi_cg.cross_mode_clk_div.get_coverage(),
                  spi_cg.cross_mode_pattern.get_coverage(),
                  spi_cg.get_coverage()
                  ), UVM_LOW)
    endfunction
endclass


class spi_agent extends uvm_agent;
    spi_sequencer sequencer;
    spi_driver    driver;
    spi_monitor   monitor;

    `uvm_component_utils(spi_agent)

    function new(string name = "spi_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        monitor = spi_monitor::type_id::create("monitor", this);

        if (get_is_active() == UVM_ACTIVE) begin
            sequencer = spi_sequencer::type_id::create("sequencer", this);
            driver    = spi_driver::type_id::create("driver", this);
        end
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (get_is_active() == UVM_ACTIVE) begin
            driver.seq_item_port.connect(sequencer.seq_item_export);
        end
    endfunction
endclass


class spi_env extends uvm_env;
    spi_agent      agent;
    spi_coverage   coverage;
    spi_scoreboard scoreboard;

    `uvm_component_utils(spi_env)

    function new(string name = "spi_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent = spi_agent::type_id::create("agent", this);
        coverage = spi_coverage::type_id::create("coverage", this);
        scoreboard = spi_scoreboard::type_id::create("scoreboard", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.monitor.item_ap.connect(coverage.analysis_export);
        agent.monitor.item_ap.connect(scoreboard.mon_fifo.analysis_export);
    endfunction
endclass





//==================================================
//
//                    SEQUENCE
//
//==================================================


class spi_smoke_sequence extends uvm_sequence #(spi_seq_item);
    `uvm_object_utils(spi_smoke_sequence)

    rand int unsigned num_items;

    function new(string name = "spi_smoke_sequence");
        super.new(name);
        num_items = 300;
    endfunction

    task body();
        spi_seq_item tr;

        for (int i = 0; i < num_items; i++) begin
            tr = spi_seq_item::type_id::create($sformatf("tr_%0d", i));
            start_item(tr);
            if (!tr.randomize()) begin
                `uvm_fatal("SPI_SEQ", "Failed to randomize spi_seq_item")
            end
            finish_item(tr);
        end
    endtask
endclass


class spi_aa55_sequence extends spi_smoke_sequence;
    `uvm_object_utils(spi_aa55_sequence)

    function new(string name = "spi_aa55_sequence");
        super.new(name);
    endfunction

    task body();
        spi_seq_item tr;
        bit [7:0] tx_patterns[2] = '{8'hAA, 8'h55};

        for (int i = 0; i < num_items; i++) begin
            tr = spi_seq_item::type_id::create($sformatf("tr_%0d", i));
            start_item(tr);
            if (!tr.randomize() with {tx_data == tx_patterns[i%2];}) begin
                `uvm_fatal("SPI_SEQ",
                           "Failed to randomize spi_seq_item for AA55 sequence")
            end
            finish_item(tr);
        end
    endtask
endclass




//==================================================
// 
//                       TEST
//
//==================================================


class spi_test extends uvm_test;
    `uvm_component_utils(spi_test)

    spi_env env;

    function new(string name = "spi_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(uvm_active_passive_enum)::set(this, "env.agent",
                                                     "is_active", UVM_ACTIVE);
        env = spi_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
        spi_smoke_sequence seq;

        phase.raise_objection(this);

        seq = spi_aa55_sequence::type_id::create("seq");
        `uvm_info("SPI_TEST", "Starting SPI sequence", UVM_LOW)
        seq.start(env.agent.sequencer);

        phase.drop_objection(this);
    endtask
endclass

//==================================================


module tb_uvm_spi_master_top;
    logic clk;
    logic rst;

    spi_if vif (
        .clk(clk),
        .rst(rst)
    );

    spi_master dut (
        .clk    (clk),
        .rst    (rst),
        .start  (vif.start),
        .tx_data(vif.tx_data),
        .clk_div(vif.clk_div),
        .rx_data(vif.rx_data),
        .busy   (vif.busy),
        .done   (vif.done),
        .cpol   (vif.cpol),
        .cpha   (vif.cpha),
        .sclk   (vif.sclk),
        .mosi   (vif.mosi),
        .miso   (vif.miso),
        .cs_n   (vif.cs_n)
    );

    always #5 clk = ~clk;

    assign vif.miso = vif.mosi;


    initial begin
        clk = 1'b0;
    end

    initial begin
        rst = 1'b1;
        vif.init_signals();
        repeat (3) @(posedge clk);
        rst = 1'b0;
    end

    initial begin
        uvm_config_db#(virtual spi_if)::set(null, "*", "vif", vif);
        run_test("spi_test");
    end

    initial begin
        $fsdbDumpfile("novas.fsdb");
        $fsdbDumpvars(0, tb_uvm_spi_master_top, "+all");
    end
endmodule

