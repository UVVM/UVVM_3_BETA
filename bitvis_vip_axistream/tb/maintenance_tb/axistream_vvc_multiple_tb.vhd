--================================================================================================================================
-- Copyright 2024 UVVM
-- Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0 and in the provided LICENSE.TXT.
--
-- Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on
-- an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and limitations under the License.
--================================================================================================================================
-- Note : Any functionality not explicitly described in the documentation is subject to change at any time
----------------------------------------------------------------------------------------------------------------------------------

------------------------------------------------------------------------------------------
-- Description   : See library quick reference (under 'doc') and README-file(s)
------------------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library uvvm_vvc_framework;
context uvvm_vvc_framework.ti_vvc_framework_context;

library bitvis_vip_axistream;
context bitvis_vip_axistream.vvc_context;

--hdlregression:tb
-- Test case entity
entity axistream_vvc_multiple_tb is
  generic(
    GC_TESTCASE      : string  := "UVVM";
    GC_DATA_WIDTH    : natural := 32;   -- number of bits in the AXI-Stream IF data vector
    GC_USER_WIDTH    : natural := 1;    -- number of bits in the AXI-Stream IF tuser vector
    GC_ID_WIDTH      : natural := 1;    -- number of bits in AXI-Stream IF tID
    GC_DEST_WIDTH    : natural := 1;    -- number of bits in AXI-Stream IF tDEST
    GC_INCLUDE_TUSER : boolean := true  -- If tuser is included in DUT's AXI interface
  );
end entity;

-- Test case architecture
architecture func of axistream_vvc_multiple_tb is

  --------------------------------------------------------------------------------
  -- Types and constants declarations
  --------------------------------------------------------------------------------
  constant C_CLK_PERIOD : time   := 10 ns;
  constant C_SCOPE      : string := C_TB_SCOPE_DEFAULT;

  constant C_MAX_BYTES      : natural   := 200; -- max bytes per packet to send
  constant C_DUT_FIFO_DEPTH : natural   := 4;
  --------------------------------------------------------------------------------
  -- Signal declarations
  --------------------------------------------------------------------------------
  signal clk                : std_logic := '0';
  signal areset             : std_logic := '0';
  signal clock_ena          : boolean   := false;

  -- The axistream interface is gathered in one record, so procedures that use the
  -- axistream interface have less arguments
  signal axistream_if_m : t_axistream_if(tdata(GC_DATA_WIDTH - 1 downto 0),
                                         tkeep((GC_DATA_WIDTH / 8) - 1 downto 0),
                                         tuser(GC_USER_WIDTH - 1 downto 0),
                                         tstrb((GC_DATA_WIDTH / 8) - 1 downto 0),
                                         tid(GC_ID_WIDTH - 1 downto 0),
                                         tdest(GC_DEST_WIDTH - 1 downto 0)
                                        );
  signal axistream_if_s : t_axistream_if(tdata(GC_DATA_WIDTH - 1 downto 0),
                                         tkeep((GC_DATA_WIDTH / 8) - 1 downto 0),
                                         tuser(GC_USER_WIDTH - 1 downto 0),
                                         tstrb((GC_DATA_WIDTH / 8) - 1 downto 0),
                                         tid(GC_ID_WIDTH - 1 downto 0),
                                         tdest(GC_DEST_WIDTH - 1 downto 0)
                                        );

begin
  -----------------------------
  -- Instantiate Testharness
  -----------------------------
  i_test_harness : entity work.axistream_th(struct_multiple_vvc)
    generic map(
      GC_DATA_WIDTH     => GC_DATA_WIDTH,
      GC_USER_WIDTH     => GC_USER_WIDTH,
      GC_ID_WIDTH       => GC_ID_WIDTH,
      GC_DEST_WIDTH     => GC_DEST_WIDTH,
      GC_DUT_FIFO_DEPTH => C_DUT_FIFO_DEPTH,
      GC_INCLUDE_TUSER  => GC_INCLUDE_TUSER
    )
    port map(
      clk                     => clk,
      areset                  => areset,
      axistream_if_m_VVC2FIFO => axistream_if_m,
      axistream_if_s_FIFO2VVC => axistream_if_s
    );

  i_ti_uvvm_engine : entity uvvm_vvc_framework.ti_uvvm_engine;

  -- Set up clock generator
  p_clock : clock_generator(clk, clock_ena, C_CLK_PERIOD, "axistream CLK");

  ------------------------------------------------
  -- PROCESS: p_main
  ------------------------------------------------
  p_main : process
    constant C_NUM_VVCS               : natural                          := 8;
    variable v_axistream_bfm_config   : t_axistream_bfm_config           := C_AXISTREAM_BFM_CONFIG_DEFAULT;
    variable v_start_time, v_end_time : time;
    variable v_elapsed_time           : time;
    variable v_elapsed_clk_cycles     : natural;
    variable v_idx                    : integer                          := 0;
    variable v_num_bytes              : integer                          := 0;
    variable v_num_words              : integer                          := 0;
    variable v_data_array             : t_slv_array(0 to C_MAX_BYTES - 1)(7 downto 0);
    variable v_user_array             : t_user_array(v_data_array'range) := (others => (others => '0'));
    variable v_strb_array             : t_strb_array(v_data_array'range) := (others => (others => '0'));
    variable v_id_array               : t_id_array(v_data_array'range)   := (others => (others => '0'));
    variable v_dest_array             : t_dest_array(v_data_array'range) := (others => (others => '0'));
    variable v_cmd_idx                : natural;
    variable v_fetch_is_accepted      : boolean;
    variable v_result_from_fetch      : bitvis_vip_axistream.vvc_cmd_pkg.t_vvc_result;
    variable v_vvc_config             : bitvis_vip_axistream.vvc_methods_support_pkg.t_vvc_config;
    variable v_vvc_list               : t_vvc_list;

    procedure cleanup (
      constant VOID : in t_void
    ) is
    begin
      log(ID_SEQUENCER, "Done.");
      for i in 0 to C_NUM_VVCS - 1 loop
        add_to_vvc_list(AXISTREAM_VVCT, i, v_vvc_list);
      end loop;
      await_completion(ALL_OF, v_vvc_list, 1 ms);
    end procedure;

  begin
    -- To avoid that log files from different test cases (run in separate
    -- simulations) overwrite each other.
    set_log_file_name(GC_TESTCASE & "_Log.txt");
    set_alert_file_name(GC_TESTCASE & "_Alert.txt");

    set_alert_stop_limit(TB_ERROR, 3);  -- Don't stop at Timeout tests

    await_uvvm_initialization(VOID);

    -- override default config with settings for this testbench
    v_axistream_bfm_config.clock_period             := C_CLK_PERIOD;
    v_axistream_bfm_config.max_wait_cycles          := 1000;
    v_axistream_bfm_config.max_wait_cycles_severity := error;
    v_axistream_bfm_config.check_packet_length      := true;

    -- Default: use same config for both the master and slave VVC
    for i in 0 to c_num_vvcs - 1 loop
      v_vvc_config            := shared_axistream_vvc_config.get(i);
      v_vvc_config.bfm_config := v_axistream_bfm_config;
      shared_axistream_vvc_config.set(v_vvc_config, i);
    end loop;

    -- Print the configuration to the log
    report_global_ctrl(VOID);
    report_msg_id_panel(VOID);

    -- Configure logging
    disable_log_msg(ID_POS_ACK);
    disable_log_msg(ID_UVVM_SEND_CMD);
    disable_log_msg(ID_UVVM_CMD_ACK);
    disable_log_msg(ID_AWAIT_COMPLETION);
    disable_log_msg(ID_AWAIT_COMPLETION_WAIT);
    disable_log_msg(ID_AWAIT_COMPLETION_END);
    disable_log_msg(AXISTREAM_VVCT, ALL_INSTANCES, ALL_MESSAGES);
    enable_log_msg(AXISTREAM_VVCT, ALL_INSTANCES, ID_PACKET_INITIATE);
    enable_log_msg(AXISTREAM_VVCT, ALL_INSTANCES, ID_PACKET_COMPLETE);

    log(ID_LOG_HDR, "Start Simulation of AXI-Stream");
    ------------------------------------------------------------
    clock_ena <= true;
    gen_pulse(areset, 10 * C_CLK_PERIOD, "Pulsing reset for 10 clock periods");

    ------------------------------------------------------------
    -- Generate some packets for later
    ------------------------------------------------------------
    v_num_bytes := 40;
    v_num_words := integer(ceil(real(v_num_bytes) / (real(GC_DATA_WIDTH) / 8.0)));
    for word in 0 to v_data_array'high loop
      v_data_array(word) := std_logic_vector(to_unsigned(word, v_data_array(0)'length));
      v_user_array(word) := std_logic_vector(to_unsigned(word, v_user_array(0)'length));
      v_strb_array(word) := std_logic_vector(to_unsigned(word, v_strb_array(0)'length));
      v_id_array(word)   := std_logic_vector(to_unsigned(word, v_id_array(0)'length));
      v_dest_array(word) := std_logic_vector(to_unsigned(word mod 16, v_dest_array(0)'length));
    end loop;

    ------------------------------------------------------------
    log(ID_LOG_HDR, "TC: insert_delay : time ");
    ------------------------------------------------------------
    v_start_time := now;
    log(ID_SEQUENCER, "start.");

    insert_delay(AXISTREAM_VVCT, 0, 100 ns, "insert_delay (time)");

    log(ID_SEQUENCER, "command sent.");
    for i in 0 to C_NUM_VVCS - 1 loop
      add_to_vvc_list(AXISTREAM_VVCT, i, v_vvc_list);
    end loop;
    await_completion(ALL_OF, v_vvc_list, 1 ms);

    log(ID_SEQUENCER, "await is done .");
    check_value((now - v_start_time), 100 ns, ERROR, "check insert_delay '", C_SCOPE, ID_SEQUENCER);

    ------------------------------------------------------------
    log(ID_LOG_HDR, "TC: insert_delay : integer ");
    ------------------------------------------------------------
    v_start_time := now;
    log(ID_SEQUENCER, "start.");

    insert_delay(AXISTREAM_VVCT, 0, 100, "insert_delay (integer)");

    log(ID_SEQUENCER, "command sent.");
    for i in 0 to C_NUM_VVCS - 1 loop
      add_to_vvc_list(AXISTREAM_VVCT, i, v_vvc_list);
    end loop;
    await_completion(ALL_OF, v_vvc_list, 1 ms);

    log(ID_SEQUENCER, "await is done .");
    check_value((now - v_start_time), 100 * C_CLK_PERIOD, ERROR, "check insert_delay '", C_SCOPE, ID_SEQUENCER);

    ------------------------------------------------------------
    log(ID_LOG_HDR, "TC: await_completion(ANY_OF): 2 VVCs");
    ------------------------------------------------------------
    axistream_transmit(AXISTREAM_VVCT, 0, v_data_array(0 to v_num_bytes), "transmit short packte");
    axistream_transmit(AXISTREAM_VVCT, 1, v_data_array(0 to 2 * v_num_bytes), "transmit long packet");

    v_start_time := now;
    add_to_vvc_list(AXISTREAM_VVCT, 0, v_vvc_list);
    add_to_vvc_list(AXISTREAM_VVCT, 1, v_vvc_list);
    await_completion(ANY_OF, v_vvc_list, 1 ms);

    v_elapsed_clk_cycles := (now - v_start_time) / (C_CLK_PERIOD);

    check_value(v_elapsed_clk_cycles, 1 + v_num_words, ERROR, "2 vvcs: checking that we waited long enough for the quickest VVC to finish", C_SCOPE, ID_SEQUENCER);

    cleanup(VOID);

    ------------------------------------------------------------
    log(ID_LOG_HDR, "TC: await_completion(ANY_OF): 3 VVCs");
    ------------------------------------------------------------
    axistream_transmit(AXISTREAM_VVCT, 0, v_data_array(0 to 2 * v_num_bytes), "transmit long packte");
    axistream_transmit(AXISTREAM_VVCT, 1, v_data_array(0 to v_num_bytes), "transmit short packet");
    axistream_transmit(AXISTREAM_VVCT, 2, v_data_array(0 to 3 * v_num_bytes), "transmit long packet");

    v_start_time := now;
    add_to_vvc_list(AXISTREAM_VVCT, 0, v_vvc_list);
    add_to_vvc_list(AXISTREAM_VVCT, 1, v_vvc_list);
    add_to_vvc_list(AXISTREAM_VVCT, 2, v_vvc_list);
    await_completion(ANY_OF, v_vvc_list, 1 ms);

    v_elapsed_clk_cycles := (now - v_start_time) / (C_CLK_PERIOD);

    check_value(v_elapsed_clk_cycles, 1 + v_num_words, ERROR, "3 vvcs: checking that we waited long enough for the quickest VVC to finish", C_SCOPE, ID_SEQUENCER);

    cleanup(VOID);

    ------------------------------------------------------------
    log(ID_LOG_HDR, "TC: await_completion(ANY_OF): 3 VVCs, one of them is already complete");
    ------------------------------------------------------------
    axistream_transmit(AXISTREAM_VVCT, 1, v_data_array(0 to v_num_bytes), "transmit packet");
    axistream_transmit(AXISTREAM_VVCT, 2, v_data_array(0 to 3 * v_num_bytes), "transmit long packet");

    v_start_time := now;
    add_to_vvc_list(AXISTREAM_VVCT, 0, v_vvc_list);
    add_to_vvc_list(AXISTREAM_VVCT, 1, v_vvc_list);
    add_to_vvc_list(AXISTREAM_VVCT, 2, v_vvc_list);
    await_completion(ANY_OF, v_vvc_list, 1 ms);

    v_elapsed_clk_cycles := (now - v_start_time) / (C_CLK_PERIOD);

    check_value(v_elapsed_clk_cycles, 0, ERROR, "3 vvcs: checking that we waited 0 time", C_SCOPE, ID_SEQUENCER);

    cleanup(VOID);

    ------------------------------------------------------------
    log(ID_LOG_HDR, "TC: await_completion(ANY_OF): 3 VVCs, two of them are already complete");
    ------------------------------------------------------------
    axistream_transmit(AXISTREAM_VVCT, 2, v_data_array(0 to 3 * v_num_bytes), "transmit long packet");

    v_start_time := now;
    add_to_vvc_list(AXISTREAM_VVCT, 0, v_vvc_list);
    add_to_vvc_list(AXISTREAM_VVCT, 1, v_vvc_list);
    add_to_vvc_list(AXISTREAM_VVCT, 2, v_vvc_list);
    await_completion(ANY_OF, v_vvc_list, 1 ms);

    v_elapsed_clk_cycles := (now - v_start_time) / (C_CLK_PERIOD);

    check_value(v_elapsed_clk_cycles, 0, ERROR, "3 vvcs: checking that we waited 0 time", C_SCOPE, ID_SEQUENCER);

    cleanup(VOID);

    ------------------------------------------------------------
    log(ID_LOG_HDR, "TC: await_completion(ANY_OF): all VVCs, all are already complete");
    ------------------------------------------------------------
    v_start_time := now;

    -- All VVCs:
    for i in 0 to C_NUM_VVCS - 1 loop
      add_to_vvc_list(AXISTREAM_VVCT, i, v_vvc_list);
    end loop;
    await_completion(ANY_OF, v_vvc_list, 1 ms);

    v_elapsed_clk_cycles := (now - v_start_time) / (C_CLK_PERIOD);

    check_value(v_elapsed_clk_cycles, 0, ERROR, "all vvcs: checking that we waited 0 time", C_SCOPE, ID_SEQUENCER);

    cleanup(VOID);

    ------------------------------------------------------------
    log(ID_LOG_HDR, "TC: await_completion(ANY_OF): all VVCs, multiple VVCs complete simultaneously ");
    ------------------------------------------------------------
    axistream_transmit(AXISTREAM_VVCT, 0, v_data_array(0 to 2 * v_num_bytes), "transmit long packet");
    for i in 1 to C_NUM_VVCS - 1 loop
      axistream_transmit(AXISTREAM_VVCT, i, v_data_array(0 to v_num_bytes), "transmit short packte");
    end loop;

    v_start_time := now;

    -- All VVCs:
    for i in 0 to C_NUM_VVCS - 1 loop
      add_to_vvc_list(AXISTREAM_VVCT, i, v_vvc_list);
    end loop;
    await_completion(ANY_OF, v_vvc_list, 1 ms);

    v_elapsed_clk_cycles := (now - v_start_time) / (C_CLK_PERIOD);

    check_value(v_elapsed_clk_cycles, 1 + v_num_words, ERROR, "all vvcs: checking that we waited shortest time", C_SCOPE, ID_SEQUENCER);

    cleanup(VOID);

    ------------------------------------------------------------
    log(ID_LOG_HDR, "TC: await_completion(ANY_OF): all VVCs, all VVCs complete simultaneously ");
    ------------------------------------------------------------
    for i in 0 to C_NUM_VVCS - 1 loop
      axistream_transmit(AXISTREAM_VVCT, i, v_data_array(0 to v_num_bytes), "transmit short packte");
    end loop;

    v_start_time := now;

    -- All VVCs:
    for i in 0 to C_NUM_VVCS - 1 loop
      add_to_vvc_list(AXISTREAM_VVCT, i, v_vvc_list);
    end loop;
    await_completion(ANY_OF, v_vvc_list, 1 ms);

    v_elapsed_clk_cycles := (now - v_start_time) / (C_CLK_PERIOD);

    check_value(v_elapsed_clk_cycles, 1 + v_num_words, ERROR, "all vvcs: checking that we waited shortest time", C_SCOPE, ID_SEQUENCER);

    cleanup(VOID);

    ------------------------------------------------------------
    log(ID_LOG_HDR, "TC: await_completion(ANY_OF) while VVCs are still busy from previous test, just to see what happens");
    ------------------------------------------------------------
    for i in 1 to C_NUM_VVCS - 1 loop
      axistream_transmit(AXISTREAM_VVCT, i, v_data_array(0 to 2 * v_num_bytes), "transmit long packte");
    end loop;

    v_start_time := now;
    -- All VVCs:
    for i in 0 to C_NUM_VVCS - 1 loop
      add_to_vvc_list(AXISTREAM_VVCT, i, v_vvc_list);
    end loop;
    await_completion(ANY_OF, v_vvc_list, 1 ms);

    cleanup(VOID);

    ------------------------------------------------------------
    log(ID_LOG_HDR, "TC: await_completion(ANY_OF) timeout, expect tb_ERROR ");
    ------------------------------------------------------------
    axistream_transmit(AXISTREAM_VVCT, 0, v_data_array(0 to 2 * v_num_bytes), "transmit long packet");
    axistream_transmit(AXISTREAM_VVCT, 1, v_data_array(0 to v_num_bytes), "transmit short packet that shall be waited for");

    v_start_time := now;

    add_to_vvc_list(AXISTREAM_VVCT, 0, v_vvc_list);
    add_to_vvc_list(AXISTREAM_VVCT, 1, v_vvc_list);
    await_completion(ANY_OF, v_vvc_list, 1 ns, msg => "timeout after 1 ns");

    increment_expected_alerts(TB_ERROR, 1);
    check_value((now - v_start_time), 1 ns, ERROR, "all vvcs: checking that we waited for 'timeout'", C_SCOPE, ID_SEQUENCER);

    cleanup(VOID);

    -----------------------------------------------------------------------------
    -- Ending the simulation
    -----------------------------------------------------------------------------
    wait for 1000 ns;                   -- to allow some time for completion
    report_alert_counters(FINAL);       -- Report final counters and print conclusion for simulation (Success/Fail)
    log(ID_LOG_HDR, "SIMULATION COMPLETED", C_SCOPE);

    -- Finish the simulation
    std.env.stop;
    wait;                               -- to stop completely

  end process p_main;
end architecture func;
