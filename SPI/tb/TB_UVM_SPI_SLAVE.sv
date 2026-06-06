import uvm_pkg::*;
`include "uvm_macros.svh"


interface spi_slave_if (
    input logic clk,
    input logic rst
);
    logic [7:0] tx_data;
    logic [7:0] rx_data;
    logic       valid;

    logic       sclk;
    logic       mosi;
    logic       miso;
    logic       cs_n;

    task automatic init_signals();
        tx_data = 8'h00;
        sclk    = 1'b0;
        mosi    = 1'b0;
        cs_n    = 1'b1;
    endtask
endinterface


class spi_slave_seq_item extends uvm_sequence_item;
    rand bit [7:0] tx_data;
    rand int unsigned half_period_cycles;

    bit [7:0] captured_miso;
    bit [7:0] rx_data;

    constraint half_period_c {half_period_cycles inside {3, 4, 5, 8, 10};}

    `uvm_object_utils_begin(spi_slave_seq_item)
        `uvm_field_int(tx_data, UVM_DEFAULT)
        `uvm_field_int(half_period_cycles, UVM_DEFAULT)
        `uvm_field_int(captured_miso, UVM_DEFAULT)
        `uvm_field_int(rx_data, UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "spi_slave_seq_item");
        super.new(name);
    endfunction
endclass


class spi_slave_sequencer extends uvm_sequencer #(spi_slave_seq_item);
    `uvm_component_utils(spi_slave_sequencer)

    function new(string name = "spi_slave_sequencer",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction
endclass


class spi_slave_driver extends uvm_driver #(spi_slave_seq_item);
    virtual spi_slave_if vif;

    `uvm_component_utils(spi_slave_driver)

    function new(string name = "spi_slave_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual spi_slave_if)::get(
                this, "", "vif", vif
            )) begin
            `uvm_fatal("SPI_SLV_DRV",
                       "virtual interface was not provided to spi_slave_driver")
        end
    endfunction

    task run_phase(uvm_phase phase);
        spi_slave_seq_item tr;

        vif.init_signals();
        wait (vif.rst === 1'b0);
        repeat (2) @(posedge vif.clk);

        forever begin
            seq_item_port.get_next_item(tr);
            drive_transfer(tr);
            seq_item_port.item_done();
        end
    endtask

    task automatic drive_transfer(input spi_slave_seq_item tr);
        bit saw_valid;

        saw_valid = 1'b0;

        vif.cs_n    <= 1'b1;
        vif.sclk    <= 1'b0;
        vif.mosi    <= 1'b0;
        vif.tx_data <= tr.tx_data;

        // Keep CS high long enough for the slave to preload tx_data onto MISO.
        repeat (3) @(posedge vif.clk);

        vif.cs_n <= 1'b0;
        repeat (tr.half_period_cycles) @(posedge vif.clk);

        for (int i = 7; i >= 0; i--) begin
            vif.mosi <= tr.tx_data[i];

            // MOSI must be stable before the sampling edge in mode 0.
            repeat (tr.half_period_cycles) @(posedge vif.clk);
            vif.sclk <= 1'b1;

            repeat (tr.half_period_cycles) begin
                @(posedge vif.clk);
                if (vif.valid === 1'b1) begin
                    saw_valid = 1'b1;
                end
            end

            vif.sclk <= 1'b0;
        end

        if (!saw_valid) begin
            repeat ((tr.half_period_cycles * 4) + 8) begin
                @(posedge vif.clk);
                if (vif.valid === 1'b1) begin
                    saw_valid = 1'b1;
                    break;
                end
            end
        end

        vif.cs_n <= 1'b1;
        vif.mosi <= 1'b0;
        repeat (2) @(posedge vif.clk);

        if (!saw_valid) begin
            `uvm_fatal(
                "SPI_SLV_DRV_TIMEOUT",
                $sformatf(
                    "Timed out waiting for valid. tx=0x%02h half_period=%0d",
                    tr.tx_data, tr.half_period_cycles))
        end

        `uvm_info("SPI_SLV_DRV",
                  $sformatf(
                      "Drove SPI slave transfer tx=0x%02h half_period=%0d",
                      tr.tx_data, tr.half_period_cycles), UVM_MEDIUM)
    endtask
endclass


class spi_slave_monitor extends uvm_monitor;
    virtual spi_slave_if vif;
    uvm_analysis_port #(spi_slave_seq_item) item_ap;

    `uvm_component_utils(spi_slave_monitor)

    function new(string name = "spi_slave_monitor",
                 uvm_component parent = null);
        super.new(name, parent);
        item_ap = new("item_ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual spi_slave_if)::get(
                this, "", "vif", vif
            )) begin
            `uvm_fatal(
                "SPI_SLV_MON",
                "virtual interface was not provided to spi_slave_monitor")
        end
    endfunction

    task run_phase(uvm_phase phase);
        spi_slave_seq_item tr;
        bit [7:0] captured_miso;
        bit [7:0] sample_tx_data;
        int unsigned sample_half_period;
        int unsigned timeout_cycles;

        wait (vif.rst === 1'b0);

        forever begin
            @(negedge vif.cs_n);
            if (vif.rst) begin
                continue;
            end

            sample_tx_data = vif.tx_data;
            captured_miso = '0;
            sample_half_period = 0;

            @(posedge vif.sclk);
            captured_miso = {captured_miso[6:0], vif.miso};

            // Measure the SCLK high half-period in clk cycles.
            fork
                begin
                    forever begin
                        @(posedge vif.clk);
                        sample_half_period++;
                    end
                end
                begin
                    @(negedge vif.sclk);
                end
            join_any
            disable fork;

            for (int i = 1; i < 8; i++) begin
                @(posedge vif.sclk);
                captured_miso = {captured_miso[6:0], vif.miso};
            end

            timeout_cycles = 128;
            repeat (timeout_cycles) begin
                @(posedge vif.clk);
                if (vif.valid === 1'b1) begin
                    break;
                end
            end

            if (vif.valid !== 1'b1) begin
                `uvm_fatal(
                    "SPI_SLV_MON_TIMEOUT",
                    "Timed out waiting for valid after slave transaction")
            end

            tr = spi_slave_seq_item::type_id::create("mon_tr");
            tr.tx_data = sample_tx_data;
            tr.half_period_cycles = sample_half_period;
            tr.captured_miso = captured_miso;
            tr.rx_data = vif.rx_data;
            item_ap.write(tr);

            `uvm_info("SPI_SLV_MON", $sformatf(
                      "Observed SPI slave transfer tx=0x%02h half_period=%0d miso=0x%02h rx=0x%02h",
                      tr.tx_data,
                      tr.half_period_cycles,
                      tr.captured_miso,
                      tr.rx_data
                      ), UVM_MEDIUM)
        end
    endtask
endclass


class spi_slave_scoreboard extends uvm_scoreboard;
    uvm_tlm_analysis_fifo #(spi_slave_seq_item) mon_fifo;
    int unsigned txn_count;
    int unsigned match_count;
    int unsigned mismatch_count;

    `uvm_component_utils(spi_slave_scoreboard)

    function new(string name = "spi_slave_scoreboard",
                 uvm_component parent = null);
        super.new(name, parent);
        mon_fifo = new("mon_fifo", this);
    endfunction

    task run_phase(uvm_phase phase);
        spi_slave_seq_item tr;

        forever begin
            mon_fifo.get(tr);

            txn_count++;

            if ((tr.tx_data !== tr.captured_miso) ||
                    (tr.tx_data !== tr.rx_data)) begin
                mismatch_count++;
                `uvm_error(
                    "SPI_SLV_SCB",
                    $sformatf(
                        "SPI slave mismatch tx=0x%02h captured_miso=0x%02h rx_data=0x%02h",
                        tr.tx_data, tr.captured_miso, tr.rx_data))
            end else begin
                match_count++;
                `uvm_info("SPI_SLV_SCB", $sformatf(
                          "SPI slave match tx=0x%02h miso=0x%02h rx=0x%02h",
                          tr.tx_data,
                          tr.captured_miso,
                          tr.rx_data
                          ), UVM_LOW)
            end
        end
    endtask

    function void check_phase(uvm_phase phase);
        super.check_phase(phase);

        if (txn_count == 0) begin
            `uvm_error("SPI_SLV_SCB",
                       "No completed SPI slave transactions were observed")
        end

        if (mismatch_count != 0) begin
            `uvm_error("SPI_SLV_SCB", $sformatf(
                                          "Detected %0d SPI slave mismatches",
                                          mismatch_count))
        end
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("SPI_SLV_SCB", $sformatf(
                  {
                      "SPI slave scoreboard summary:\n",
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


class spi_slave_coverage extends uvm_subscriber #(spi_slave_seq_item);
    `uvm_component_utils(spi_slave_coverage)

    bit [7:0] sampled_tx_data;
    int unsigned sampled_half_period;

    covergroup spi_slave_cg;

        cp_pattern: coverpoint sampled_tx_data {
            bins zero = {8'h00};
            bins ones = {8'hFF};
            bins alt_a = {8'hAA};
            bins alt_5 = {8'h55};
            bins low = {[8'h01 : 8'h1F]};
            bins mid = {[8'h20 : 8'hDF]};
            bins high = {[8'hE0 : 8'hFE]};
        }

        cp_half_period: coverpoint sampled_half_period {
            bins hp3 = {3};
            bins hp4 = {4};
            bins hp5 = {5};
            bins hp8 = {8};
            bins hp10 = {10};
        }

        cross_pattern_half_period: cross cp_pattern, cp_half_period;
    endgroup

    function new(string name = "spi_slave_coverage",
                 uvm_component parent = null);
        super.new(name, parent);
        spi_slave_cg = new();
    endfunction

    function void write(spi_slave_seq_item t);
        sampled_tx_data     = t.tx_data;
        sampled_half_period = t.half_period_cycles;
        spi_slave_cg.sample();
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("SPI_SLV_COV", $sformatf(
                  {
                      "=======SPI coverage summary=======\n",
                      "  pattern               : %0.2f%%\n",
                      "  half_period           : %0.2f%%\n",
                      "  pattern x half_period : %0.2f%%\n",
                      "  total                 : %0.2f%%"
                  },
                  spi_slave_cg.cp_pattern.get_coverage(),
                  spi_slave_cg.cp_half_period.get_coverage(),
                  spi_slave_cg.cross_pattern_half_period.get_coverage(),
                  spi_slave_cg.get_coverage()
                  ), UVM_LOW)
    endfunction
endclass


class spi_slave_agent extends uvm_agent;
    spi_slave_sequencer sequencer;
    spi_slave_driver    driver;
    spi_slave_monitor   monitor;

    `uvm_component_utils(spi_slave_agent)

    function new(string name = "spi_slave_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        monitor = spi_slave_monitor::type_id::create("monitor", this);

        if (get_is_active() == UVM_ACTIVE) begin
            sequencer = spi_slave_sequencer::type_id::create("sequencer", this);
            driver = spi_slave_driver::type_id::create("driver", this);
        end
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (get_is_active() == UVM_ACTIVE) begin
            driver.seq_item_port.connect(sequencer.seq_item_export);
        end
    endfunction
endclass


class spi_slave_env extends uvm_env;
    spi_slave_agent      agent;
    spi_slave_scoreboard scoreboard;
    spi_slave_coverage   coverage;

    `uvm_component_utils(spi_slave_env)

    function new(string name = "spi_slave_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent      = spi_slave_agent::type_id::create("agent", this);
        scoreboard = spi_slave_scoreboard::type_id::create("scoreboard", this);
        coverage   = spi_slave_coverage::type_id::create("coverage", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.monitor.item_ap.connect(scoreboard.mon_fifo.analysis_export);
        agent.monitor.item_ap.connect(coverage.analysis_export);
    endfunction
endclass




//==================================================
//
//                    SEQUENCE
//
//==================================================


class spi_slave_smoke_sequence extends uvm_sequence #(spi_slave_seq_item);
    `uvm_object_utils(spi_slave_smoke_sequence)

    int unsigned num_items;

    function new(string name = "spi_slave_smoke_sequence");
        super.new(name);
        num_items = 100;
    endfunction

    task body();
        spi_slave_seq_item tr;

        for (int i = 0; i < num_items; i++) begin
            tr = spi_slave_seq_item::type_id::create($sformatf("tr_%0d", i));
            start_item(tr);
            if (!tr.randomize()) begin
                `uvm_fatal("SPI_SLV_SEQ",
                           "Failed to randomize spi_slave_seq_item")
            end
            finish_item(tr);
        end
    endtask
endclass


class spi_slave_aa55_sequence extends spi_slave_smoke_sequence;
    `uvm_object_utils(spi_slave_aa55_sequence)

    function new(string name = "spi_slave_aa55_sequence");
        super.new(name);
    endfunction

    task body();
        spi_slave_seq_item tr;
        bit [7:0] patterns[2] = '{8'hAA, 8'h55};

        for (int i = 0; i < num_items; i++) begin
            tr = spi_slave_seq_item::type_id::create($sformatf("tr_%0d", i));
            start_item(tr);
            if (!tr.randomize() with {tx_data == patterns[i%2];}) begin
                `uvm_fatal(
                    "SPI_SLV_SEQ",
                    "Failed to randomize spi_slave_seq_item for AA55 sequence")
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

class spi_slave_test extends uvm_test;
    spi_slave_env env;

    `uvm_component_utils(spi_slave_test)

    function new(string name = "spi_slave_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(uvm_active_passive_enum)::set(this, "env.agent",
                                                     "is_active", UVM_ACTIVE);
        env = spi_slave_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
        spi_slave_smoke_sequence seq;

        phase.raise_objection(this);

        seq = spi_slave_smoke_sequence::type_id::create("seq");
        `uvm_info("SPI_SLV_TEST", "Starting SPI slave smoke sequence", UVM_LOW)
        seq.start(env.agent.sequencer);

        phase.drop_objection(this);
    endtask
endclass


module tb_uvm_spi_slave_top;
    logic clk;
    logic rst;

    spi_slave_if vif (
        .clk(clk),
        .rst(rst)
    );

    spi_slave dut (
        .clk    (clk),
        .rst    (rst),
        .tx_data(vif.tx_data),
        .rx_data(vif.rx_data),
        .valid  (vif.valid),
        .sclk   (vif.sclk),
        .mosi   (vif.mosi),
        .miso   (vif.miso),
        .cs_n   (vif.cs_n)
    );

    always #5 clk = ~clk;

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
        uvm_config_db#(virtual spi_slave_if)::set(null, "*", "vif", vif);
        run_test("spi_slave_test");
    end

    initial begin
        $fsdbDumpfile("novas.fsdb");
        $fsdbDumpvars(0, tb_uvm_spi_slave_top, "+all");
    end
endmodule
