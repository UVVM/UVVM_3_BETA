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
entity axistream_vvc_tb is
  generic(
    GC_TESTCASE           : string  := "UVVM";
    GC_DATA_WIDTH         : natural := 32; -- number of bits in the AXI-Stream IF data vector
    GC_USER_WIDTH         : natural := 1; -- number of bits in the AXI-Stream IF tuser vector
    GC_ID_WIDTH           : natural := 1; -- number of bits in AXI-Stream IF tID
    GC_DEST_WIDTH         : natural := 1; -- number of bits in AXI-Stream IF tDEST
    GC_INCLUDE_TUSER      : boolean := true; -- If tuser, tstrb, tid, tdest is included in DUT's AXI interface
    GC_USE_SETUP_AND_HOLD : boolean := false -- use setup and hold times to synchronise the BFM
  );
end entity;

architecture func of axistream_vvc_tb is

  --------------------------------------------------------------------------------
  -- Types and constants declarations
  --------------------------------------------------------------------------------
  constant C_CLK_PERIOD : time   := 10 ns;
  constant C_SCOPE      : string := C_TB_SCOPE_DEFAULT;

  -- VVC idx
  constant C_FIFO2VVC_MASTER : natural := 0;
  constant C_FIFO2VVC_SLAVE  : natural := 1;
  constant C_VVC2VVC_MASTER  : natural := 2;
  constant C_VVC2VVC_SLAVE   : natural := 3;

  constant C_MAX_BYTES         : natural := 100; -- max bytes per packet to send
  constant C_MAX_BYTES_IN_WORD : natural := 4;
  constant C_DUT_FIFO_DEPTH    : natural := 4;
  --------------------------------------------------------------------------------
  -- Signal declarations
  --------------------------------------------------------------------------------
  signal clk                   : std_logic := '0';
  signal areset                : std_logic := '0';
  signal clock_ena             : boolean   := false;

  -- The axistream interface is gathered in one record
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
  i_test_harness : entity work.axistream_th(struct_vvc)
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
    constant C_BYTE                 : natural                            := 8;
    variable v_axistream_bfm_config : t_axistream_bfm_config             := C_AXISTREAM_BFM_CONFIG_DEFAULT;
    variable v_idx                  : integer                            := 0;
    variable v_num_bytes            : integer                            := 0;
    variable v_num_words            : integer                            := 0;
    variable v_user_array           : t_user_array(0 to C_MAX_BYTES - 1) := (others => (others => '0'));
    variable v_strb_array           : t_strb_array(0 to C_MAX_BYTES - 1) := (others => (others => '0'));
    variable v_id_array             : t_id_array(0 to C_MAX_BYTES - 1)   := (others => (others => '0'));
    variable v_dest_array           : t_dest_array(0 to C_MAX_BYTES - 1) := (others => (others => '0'));
    variable v_data_array_1_byte    : t_slv_array(0 to C_MAX_BYTES - 1)(1 * C_BYTE - 1 downto 0);
    variable v_data_array_2_byte    : t_slv_array(0 to C_MAX_BYTES - 1)(2 * C_BYTE - 1 downto 0);
    variable v_data_array_3_byte    : t_slv_array(0 to C_MAX_BYTES - 1)(3 * C_BYTE - 1 downto 0);
    variable v_data_array_4_byte    : t_slv_array(0 to C_MAX_BYTES - 1)(4 * C_BYTE - 1 downto 0);
    variable v_data_array           : t_slv_array(0 to C_MAX_BYTES - 1)(C_MAX_BYTES_IN_WORD * C_BYTE - 1 downto 0);
    variable v_data_array_as_slv    : std_logic_vector(C_MAX_BYTES_IN_WORD * C_BYTE - 1 downto 0);
    variable v_cmd_idx              : natural;
    variable v_result_from_fetch    : bitvis_vip_axistream.vvc_cmd_pkg.t_vvc_result;
    variable v_vvc_config           : bitvis_vip_axistream.vvc_methods_support_pkg.t_vvc_config;
    variable v_vvc_list             : t_vvc_list;
    variable v_alert_level          : t_alert_level;

    -- DUT ports towards VVC interface
    constant C_NUM_VVC_SIGNALS : natural := 8;
    alias dut_m_tdata  is << signal i_test_harness.i_axis_fifo.m_axis_tdata  : std_logic_vector >>;
    alias dut_m_tkeep  is << signal i_test_harness.i_axis_fifo.m_axis_tkeep  : std_logic_vector >>;
    alias dut_m_tuser  is << signal i_test_harness.i_axis_fifo.m_axis_tuser  : std_logic_vector >>;
    alias dut_m_tvalid is << signal i_test_harness.i_axis_fifo.m_axis_tvalid : std_logic >>;
    alias dut_m_tlast  is << signal i_test_harness.i_axis_fifo.m_axis_tlast  : std_logic >>;
    alias dut_m_tstrb  is << signal i_test_harness.dut_m_axis_tstrb          : std_logic_vector >>;
    alias dut_m_tid    is << signal i_test_harness.dut_m_axis_tid            : std_logic_vector >>;
    alias dut_m_tdest  is << signal i_test_harness.dut_m_axis_tdest          : std_logic_vector >>;

    -- Toggles all the signals in the VVC interface and checks that the expected alerts are generated
    procedure toggle_vvc_if (
      constant alert_level : in t_alert_level
    ) is
      variable v_num_expected_alerts : natural;
      variable v_rand                : t_rand;
    begin
      -- Number of total expected alerts: (number of signals tested individually + number of signals tested together) x 1 toggle
      if alert_level /= NO_ALERT then
        increment_expected_alerts_and_stop_limit(alert_level, (C_NUM_VVC_SIGNALS + C_NUM_VVC_SIGNALS) * 2);
      end if;
      for i in 0 to C_NUM_VVC_SIGNALS loop
        -- Force new value
        v_num_expected_alerts := get_alert_counter(alert_level);
        case i is
          when 0 => dut_m_tdata  <= force not dut_m_tdata;
                    dut_m_tkeep  <= force not dut_m_tkeep;
                    dut_m_tuser  <= force not dut_m_tuser;
                    dut_m_tvalid <= force not dut_m_tvalid;
                    dut_m_tlast  <= force not dut_m_tlast;
                    dut_m_tstrb  <= force not dut_m_tstrb;
                    dut_m_tid    <= force not dut_m_tid;
                    dut_m_tdest  <= force not dut_m_tdest;
          when 1 => dut_m_tdata  <= force not dut_m_tdata;
          when 2 => dut_m_tkeep  <= force not dut_m_tkeep;
          when 3 => dut_m_tuser  <= force not dut_m_tuser;
          when 4 => dut_m_tvalid <= force not dut_m_tvalid;
          when 5 => dut_m_tlast  <= force not dut_m_tlast;
          when 6 => dut_m_tstrb  <= force not dut_m_tstrb;
          when 7 => dut_m_tid    <= force not dut_m_tid;
          when 8 => dut_m_tdest  <= force not dut_m_tdest;
        end case;
        wait for v_rand.rand(ONLY, (C_LOG_TIME_BASE, C_LOG_TIME_BASE * 5, C_LOG_TIME_BASE * 10)); -- Hold the value a random time
        v_num_expected_alerts := 0 when alert_level = NO_ALERT else
                                 v_num_expected_alerts + C_NUM_VVC_SIGNALS when i = 0 else
                                 v_num_expected_alerts + 1;
        check_value(get_alert_counter(alert_level), v_num_expected_alerts, TB_NOTE, "Unwanted activity alert was expected", C_SCOPE, ID_NEVER);
        -- Set back original value
        v_num_expected_alerts := get_alert_counter(alert_level);
        case i is
          when 0 => dut_m_tdata  <= release;
                    dut_m_tkeep  <= release;
                    dut_m_tuser  <= release;
                    dut_m_tvalid <= release;
                    dut_m_tlast  <= release;
                    dut_m_tstrb  <= release;
                    dut_m_tid    <= release;
                    dut_m_tdest  <= release;
          when 1 => dut_m_tdata  <= release;
          when 2 => dut_m_tkeep  <= release;
          when 3 => dut_m_tuser  <= release;
          when 4 => dut_m_tvalid <= release;
          when 5 => dut_m_tlast  <= release;
          when 6 => dut_m_tstrb  <= release;
          when 7 => dut_m_tid    <= release;
          when 8 => dut_m_tdest  <= release;
        end case;
        wait for 0 ns; -- Wait two delta cycles so that the alert is triggered
        wait for 0 ns;
        wait for 0 ns; -- Wait an extra delta cycle so that the value is propagated from the non-record to the record signals
        v_num_expected_alerts := 0 when alert_level = NO_ALERT else
                                 v_num_expected_alerts + C_NUM_VVC_SIGNALS when i = 0 else
                                 v_num_expected_alerts + 1;
        wait for 0 ns; -- Wait another cycle to allow signals to propagate before checking them - Needed for Riviera Pro
        check_value(get_alert_counter(alert_level), v_num_expected_alerts, TB_NOTE, "Unwanted activity alert was expected", C_SCOPE, ID_NEVER);
      end loop;
    end procedure;

    ------------------------------------------------------
    -- overloading procedure
    ------------------------------------------------------
    procedure check_value(received           : t_slv_array(open)(7 downto 0);
                          expected           : t_slv_array;
                          num_bytes_received : natural;
                          msg                : string) is
      constant C_BYTE_ENDIANNESS   : t_byte_endianness := v_axistream_bfm_config.byte_endianness;
      constant C_BYTES_IN_WORD     : integer           := (expected(0)'length / 8);
      constant C_BYTE_ARRAY_LENGTH : integer           := (expected'length * C_BYTES_IN_WORD);
      variable v_expected          : t_slv_array(0 to C_BYTE_ARRAY_LENGTH - 1)(7 downto 0);
    begin
      v_expected := convert_slv_array_to_byte_array(expected, C_BYTE_ENDIANNESS);
      for byte_idx in 0 to num_bytes_received - 1 loop
        check_value(received(byte_idx) = v_expected(byte_idx), error, msg, C_SCOPE);
      end loop;
    end procedure;

    ------------------------------------------------------
    -- return a t_slv_array of given size with random data
    ------------------------------------------------------
    impure function get_slv_array(num_bytes : integer; bytes_in_word : integer) return t_slv_array is
      variable v_return_array : t_slv_array(0 to num_bytes - 1)((bytes_in_word * 8) - 1 downto 0);
    begin
      for byte in 0 to num_bytes - 1 loop
        v_return_array(byte) := random(v_return_array(byte)'length);
      end loop;
      return v_return_array;
    end function;

    ------------------------------------------------------
    -- transmit tuser = something. tstrb etc = default
    ------------------------------------------------------
    procedure VVC_master_to_VVC_slave_include_tuser(data_array : t_slv_array;
                                                    user_array : t_user_array) is
    begin
      axistream_transmit(AXISTREAM_VVCT, C_VVC2VVC_MASTER, data_array, user_array, "transmit VVC2VVC, tuser set, but default tstrb etc");
      axistream_expect(AXISTREAM_VVCT, C_VVC2VVC_SLAVE, data_array, user_array, "expect VVC2VVC, tuser set, but default tstrb etc");
    end procedure;

    ------------------------------------------------------
    -- transmit tuser tstrb etc is set (no defaults)
    ------------------------------------------------------
    procedure VVC_master_to_VVC_slave_no_defaults(data_array : t_slv_array;
                                                  user_array : t_user_array;
                                                  strb_array : t_strb_array;
                                                  id_array   : t_id_array;
                                                  dest_array : t_dest_array) is
    begin
      axistream_transmit(AXISTREAM_VVCT, C_VVC2VVC_MASTER, data_array, user_array, strb_array, id_array, dest_array, "transmit VVC2VVC, tuser tstrb etc are set");
      axistream_expect(AXISTREAM_VVCT, C_VVC2VVC_SLAVE, data_array, user_array, strb_array, id_array, dest_array, "expect VVC2VVC, tuser tstrb etc are set");
    end procedure;

    ------------------------------------------------------
    -- transmit and receive with check
    ------------------------------------------------------
    procedure VVC_master_to_VVC_slave_with_check(data_array : t_slv_array;
                                                 user_array : t_user_array) is
      variable v_num_bytes_sent      : integer := data_array'length * (data_array(0)'length / 8);
      variable v_numb_bytes_received : integer;
    begin
      -- transmit and receive
      axistream_transmit(AXISTREAM_VVCT, C_VVC2VVC_MASTER, data_array, user_array, "transmit before receive, Check that tuser is fetched correctly");
      axistream_receive(AXISTREAM_VVCT, C_VVC2VVC_SLAVE, "test axistream_receive / fetch_result (with tuser) ");

      v_cmd_idx := get_last_received_cmd_idx(AXISTREAM_VVCT, C_VVC2VVC_SLAVE);
      add_to_vvc_list(AXISTREAM_VVCT, C_VVC2VVC_MASTER, v_vvc_list);
      add_to_vvc_list(AXISTREAM_VVCT, C_VVC2VVC_SLAVE, v_vvc_list);
      await_completion(ALL_OF, v_vvc_list, 1 ms);

      -- check result
      fetch_result(AXISTREAM_VVCT, C_VVC2VVC_SLAVE, NA, v_cmd_idx, v_result_from_fetch, "Fetch result using the simple fetch_result overload");
      v_numb_bytes_received := v_result_from_fetch.data_length;
      check_value(v_result_from_fetch.data_array, data_array, v_numb_bytes_received, "Verifying that fetched data is as expected");

      check_value(v_result_from_fetch.data_length, v_num_bytes_sent, error, "Verifying that fetched data_length is as expected", C_SCOPE);
      for i in 0 to v_num_words - 1 loop
        check_value(v_result_from_fetch.user_array(i)(GC_USER_WIDTH - 1 downto 0) = user_array(i)(GC_USER_WIDTH - 1 downto 0), error, "Verifying that fetched tuser_array(" & to_string(i) & ") is as expected", C_SCOPE);
      end loop;
    end procedure;

    ------------------------------------------------------
    -- transmit and check that expect detects errors
    ------------------------------------------------------
    procedure VVC_master_to_VVC_slave_with_data_error(data_array : t_slv_array;
                                                      user_array : t_user_array) is
      variable v_idx        : integer;
      variable v_byte       : integer;
      variable v_data_array : t_slv_array(0 to data_array'length - 1)(data_array(0)'length - 1 downto 0) := data_array;
    begin
      increment_expected_alerts(warning, 1);
      axistream_transmit(AXISTREAM_VVCT, C_VVC2VVC_MASTER, data_array, user_array, "transmit, data wrong. bytes in word=" & to_string(data_array(0)'length / 8));
      v_idx                                                         := random(0, data_array'length - 1); -- pick index
      v_byte                                                        := random(1, data_array(0)'length / 8); -- pick byte
      v_data_array(v_idx)((v_byte * 8) - 1 downto (v_byte * 8) - 8) := not v_data_array(v_idx)((v_byte * 8) - 1 downto (v_byte * 8) - 8); -- invert byte
      axistream_expect(AXISTREAM_VVCT, C_VVC2VVC_SLAVE, v_data_array, user_array, "expect, data wrong. bytes in word=" & to_string(data_array(0)'length / 8), warning);
    end procedure;

    ------------------------------------------------------
    -- verify alert if the tuser is not what is expected
    ------------------------------------------------------
    procedure VVC_master_to_VVC_slave_tuser_error_check(data_array : t_slv_array;
                                                        user_array : t_user_array;
                                                        strb_array : t_strb_array;
                                                        id_array   : t_id_array;
                                                        dest_array : t_dest_array) is
      variable v_idx        : integer;
      variable v_user_array : t_user_array(0 to user_array'length - 1) := user_array;
    begin
      increment_expected_alerts(warning, 1);
      axistream_transmit(AXISTREAM_VVCT, C_VVC2VVC_MASTER, data_array, v_user_array, strb_array, id_array, dest_array, "transmit, tuser wrong.");
      v_idx               := random(0, v_user_array'length - 1);
      v_user_array(v_idx) := not user_array(v_idx); -- Provoke alert in axistream_expect()
      axistream_expect(AXISTREAM_VVCT, C_VVC2VVC_SLAVE, data_array, v_user_array, strb_array, id_array, dest_array, "expect, tuser wrong.", warning);
    end procedure;

    ------------------------------------------------------
    -- verify alert if the tstrb is not what is expected
    ------------------------------------------------------
    procedure VVC_master_to_VVC_slave_tstrb_error_check(data_array : t_slv_array;
                                                        user_array : t_user_array;
                                                        strb_array : t_strb_array;
                                                        id_array   : t_id_array;
                                                        dest_array : t_dest_array) is
      variable v_idx        : integer;
      variable v_strb_array : t_strb_array(0 to user_array'length - 1) := strb_array;
    begin
      increment_expected_alerts(warning, 1);
      axistream_transmit(AXISTREAM_VVCT, C_VVC2VVC_MASTER, data_array, user_array, v_strb_array, id_array, dest_array, "transmit, tstrb wrong.");
      v_idx               := random(0, v_strb_array'length - 1);
      v_strb_array(v_idx) := not v_strb_array(v_idx); -- Provoke alert in axistream_expect()
      axistream_expect(AXISTREAM_VVCT, C_VVC2VVC_SLAVE, data_array, user_array, v_strb_array, id_array, dest_array, "expect, tstrb wrong.", warning);
    end procedure;

    ------------------------------------------------------
    -- verify alert if the tid is not what is expected
    ------------------------------------------------------
    procedure VVC_master_to_VVC_slave_tid_error_check(data_array : t_slv_array;
                                                      user_array : t_user_array;
                                                      strb_array : t_strb_array;
                                                      id_array   : t_id_array;
                                                      dest_array : t_dest_array) is
      variable v_idx      : integer;
      variable v_id_array : t_id_array(0 to user_array'length - 1) := id_array;
    begin
      increment_expected_alerts(warning, 1);
      axistream_transmit(AXISTREAM_VVCT, C_VVC2VVC_MASTER, data_array, user_array, strb_array, v_id_array, dest_array, "transmit, tid wrong.");
      v_idx             := random(0, v_id_array'length - 1);
      v_id_array(v_idx) := not v_id_array(v_idx); -- Provoke alert in axistream_expect()
      axistream_expect(AXISTREAM_VVCT, C_VVC2VVC_SLAVE, data_array, user_array, strb_array, v_id_array, dest_array, "expect, tid wrong.", warning);
    end procedure;

    ------------------------------------------------------
    -- verify alert if the tdest is not what is expected
    ------------------------------------------------------
    procedure VVC_master_to_VVC_slave_tdest_error_check(data_array : t_slv_array;
                                                        user_array : t_user_array;
                                                        strb_array : t_strb_array;
                                                        id_array   : t_id_array;
                                                        dest_array : t_dest_array) is
      variable v_idx        : integer;
      variable v_dest_array : t_dest_array(0 to user_array'length - 1) := dest_array;
      variable v_id_array   : t_id_array(0 to user_array'length - 1)   := id_array;
    begin
      increment_expected_alerts(warning, 1);
      axistream_transmit(AXISTREAM_VVCT, C_VVC2VVC_MASTER, data_array, user_array, strb_array, id_array, dest_array, "transmit, tdest wrong.");
      v_idx               := random(0, v_dest_array'length - 1);
      v_dest_array(v_idx) := not v_dest_array(v_idx); -- Provoke alert in axistream_expect()
      v_id_array          := (others => (others => '-')); -- also test the use of don't care
      axistream_expect(AXISTREAM_VVCT, C_VVC2VVC_SLAVE, data_array, user_array, strb_array, v_id_array, v_dest_array, "expect, tdest wrong.", warning);
    end procedure;

    ------------------------------------------------------
    -- test receive/fetch result
    ------------------------------------------------------
    procedure VVC_master_to_VVC_slave_receive_and_check(data_array : t_slv_array) is
      variable v_num_bytes : integer := data_array'length * (data_array(0)'length / 8);
    begin
      axistream_transmit(AXISTREAM_VVCT, C_FIFO2VVC_MASTER, data_array, "transmit");
      axistream_receive(AXISTREAM_VVCT, C_FIFO2VVC_SLAVE, "test axistream_receive / fetch_result (without tuser) ");
      v_cmd_idx := get_last_received_cmd_idx(AXISTREAM_VVCT, C_FIFO2VVC_SLAVE);

      await_completion(AXISTREAM_VVCT, C_FIFO2VVC_SLAVE, 1 ms, "Wait for receive to finish");

      fetch_result(AXISTREAM_VVCT, C_FIFO2VVC_SLAVE, NA, v_cmd_idx, v_result_from_fetch, "Fetch result using the simple fetch_result overload");
      check_value(v_result_from_fetch.data_array, data_array, v_num_bytes, "Verifying that fetched data is as expected");
      check_value(v_result_from_fetch.data_length, v_num_bytes, error, "Verifying that fetched data_length is as expected", C_SCOPE, ID_SEQUENCER);
    end procedure;

    ------------------------------------------------------
    -- test transmit
    ------------------------------------------------------
    procedure VVC_master_to_VVC_slave_transmit_and_check(data_array : t_slv_array;
                                                         user_array : t_user_array;
                                                         strb_array : t_strb_array;
                                                         id_array   : t_id_array;
                                                         dest_array : t_dest_array;
                                                         i          : integer) is
      variable v_num_bytes       : integer                                      := data_array'length * (data_array(data_array'low)'length / 8);
      variable v_exp_data_array  : t_slv_array(data_array'range)(data_array(data_array'low)'range);
      variable v_num_words       : integer                                      := user_array'length;
      variable v_user_array      : t_user_array(user_array'length - 1 downto 0) := user_array;
      variable v_byte_endianness : t_byte_endianness                            := v_axistream_bfm_config.byte_endianness;
    begin
      -- VVC call
      -- tuser, tstrb etc = default
      axistream_transmit(AXISTREAM_VVCT, C_FIFO2VVC_MASTER, data_array, "transmit,i=" & to_string(i));
      axistream_expect(AXISTREAM_VVCT, C_FIFO2VVC_SLAVE, convert_slv_array_to_byte_array(data_array, v_byte_endianness), "expect,  i=" & to_string(i));

      if GC_INCLUDE_TUSER then
        -- tuser = something. tstrb etc = default
        axistream_transmit(AXISTREAM_VVCT, C_FIFO2VVC_MASTER, data_array, user_array, "transmit, tuser set,i=" & to_string(i));
        axistream_expect(AXISTREAM_VVCT, C_FIFO2VVC_SLAVE, convert_slv_array_to_byte_array(data_array, v_byte_endianness), user_array, "expect,   tuser set,i=" & to_string(i));

        -- test _receive, Check that tuser is fetched correctly
        axistream_transmit(AXISTREAM_VVCT, C_FIFO2VVC_MASTER, data_array, user_array, "transmit before receive, Check that tuser is fetched correctly,i=" & to_string(i));
        axistream_receive(AXISTREAM_VVCT, C_FIFO2VVC_SLAVE, "test axistream_receive / fetch_result (with tuser) ");
        v_cmd_idx := get_last_received_cmd_idx(AXISTREAM_VVCT, C_FIFO2VVC_SLAVE);
        add_to_vvc_list(AXISTREAM_VVCT, C_FIFO2VVC_MASTER, v_vvc_list);
        add_to_vvc_list(AXISTREAM_VVCT, C_FIFO2VVC_SLAVE, v_vvc_list);
        await_completion(ALL_OF, v_vvc_list, 1 ms);

        fetch_result(AXISTREAM_VVCT, C_FIFO2VVC_SLAVE, NA, v_cmd_idx, v_result_from_fetch, "Fetch result using the simple fetch_result overload");
        check_value(v_result_from_fetch.data_array, data_array, v_num_bytes, "Verifying that fetched data is as expected");
        check_value(v_result_from_fetch.data_length, v_num_bytes, error, "Verifying that fetched data_length is as expected", C_SCOPE);

        for i in 0 to v_num_words - 1 loop
          check_value(v_result_from_fetch.user_array(i)(GC_USER_WIDTH - 1 downto 0) = user_array(i)(GC_USER_WIDTH - 1 downto 0), error, "Verifying that fetched tuser_array(" & to_string(i) & ") is as expected", C_SCOPE);
        end loop;

        -- verify alert if the data is not what is expected
        increment_expected_alerts(warning, 1);
        axistream_transmit(AXISTREAM_VVCT, C_FIFO2VVC_MASTER, data_array, v_user_array, "transmit, data wrong ,i=" & to_string(i));
        v_idx                   := random(v_exp_data_array'low, v_exp_data_array'high);
        v_exp_data_array        := data_array;
        v_exp_data_array(v_idx) := not v_exp_data_array(v_idx);
        axistream_expect(AXISTREAM_VVCT, C_FIFO2VVC_SLAVE, v_exp_data_array, v_user_array, "expect, data wrong ,i=" & to_string(i), warning);

        -- verify alert if the tuser is not what is expected
        increment_expected_alerts(warning, 1);
        axistream_transmit(AXISTREAM_VVCT, C_FIFO2VVC_MASTER, data_array, v_user_array, "transmit, tuser wrong ,i=" & to_string(i));
        v_idx               := random(0, v_num_words - 1);
        v_user_array(v_idx) := not v_user_array(v_idx);
        axistream_expect(AXISTREAM_VVCT, C_FIFO2VVC_SLAVE, convert_slv_array_to_byte_array(data_array, v_byte_endianness), v_user_array, "expect, tuser wrong ,i=" & to_string(i), warning);
      end if;
    end procedure;

    ------------------------------------------------------
    -- verify alert if the 'tlast' is not where expected
    ------------------------------------------------------
    procedure VVC_master_to_VVC_slave_tlast_error_check(data_array : t_slv_array;
                                                        user_array : t_user_array;
                                                        strb_array : t_strb_array;
                                                        id_array   : t_id_array;
                                                        dest_array : t_dest_array;
                                                        numBytes   : integer;
                                                        i          : integer) is
      variable v_num_bytes : integer := numBytes;
    begin
      await_completion(AXISTREAM_VVCT, C_FIFO2VVC_SLAVE, 1 ms);
      axistream_transmit(AXISTREAM_VVCT, C_FIFO2VVC_MASTER, data_array, user_array, "transmit, tlast wrong,i=" & to_string(i));
      increment_expected_alerts(warning, 1);

      v_vvc_config                                    := shared_axistream_vvc_config.get(C_FIFO2VVC_SLAVE);
      v_vvc_config.bfm_config.protocol_error_severity := warning;
      shared_axistream_vvc_config.set(v_vvc_config, C_FIFO2VVC_SLAVE);

      v_num_bytes := v_num_bytes - 1;
      axistream_expect(AXISTREAM_VVCT, C_FIFO2VVC_SLAVE, data_array(0 to v_num_bytes - 1), user_array, "expect, tlast wrong ,i=" & to_string(i), NO_ALERT);
      -- due to the premature tlast, make an extra call to read the remaining (corrupt) packet
      axistream_expect(AXISTREAM_VVCT, C_FIFO2VVC_SLAVE, data_array(0 to v_num_bytes - 1), user_array, "expect, remaining data ,i=" & to_string(i), NO_ALERT);
      await_completion(AXISTREAM_VVCT, C_FIFO2VVC_SLAVE, 1 ms);

      -- Cleanup after test case
      v_vvc_config                                    := shared_axistream_vvc_config.get(C_FIFO2VVC_SLAVE);
      v_vvc_config.bfm_config.protocol_error_severity := error;
      shared_axistream_vvc_config.set(v_vvc_config, C_FIFO2VVC_SLAVE);
    end procedure;

    ------------------------------------------------------
    -- verify alert if data_array don't consist of N*bytes
    ------------------------------------------------------
    procedure VVC_master_to_VVC_slave_wrong_size(num_bytes : integer; num_bytes_in_word : integer; user_array : t_user_array) is
      variable v_short_byte_array  : t_slv_array(0 to num_bytes - 1)((num_bytes_in_word * C_BYTE) - 2 downto 0); -- size byte-1
      variable v_long_byte_array   : t_slv_array(0 to num_bytes - 1)((num_bytes_in_word * C_BYTE) downto 0); -- size byte+1
      variable v_normal_byte_array : t_slv_array(0 to num_bytes - 1)((num_bytes_in_word * C_BYTE) - 1 downto 0); -- size byte
    begin
      for byte in 0 to num_bytes - 1 loop
        v_short_byte_array(byte)  := random(v_short_byte_array(0)'length);
        v_long_byte_array(byte)   := random(v_long_byte_array(0)'length);
        v_normal_byte_array(byte) := random(v_normal_byte_array(0)'length);
      end loop;
      -- transmit data_array with short byte
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1);
      axistream_transmit(AXISTREAM_VVCT, C_FIFO2VVC_MASTER, v_short_byte_array, user_array, "transmit, short byte"); -- expect TB_ERROR
      -- transmit data_array with long byte
      increment_expected_alerts_and_stop_limit(TB_ERROR, 1);
      axistream_transmit(AXISTREAM_VVCT, C_FIFO2VVC_MASTER, v_long_byte_array, user_array, "transmit, long byte"); -- expect TB_ERROR
      -- transmit data_array of bytes
      axistream_transmit(AXISTREAM_VVCT, C_FIFO2VVC_MASTER, v_normal_byte_array, user_array, "transmit, normal byte"); -- expect no TB_ERROR
      -- clear VVC received data
      axistream_receive(AXISTREAM_VVCT, C_FIFO2VVC_SLAVE, "receive on VVC slave");
      await_completion(AXISTREAM_VVCT, C_FIFO2VVC_SLAVE, 1 ms);
    end procedure;

  begin
    -- To avoid that log files from different test cases (run in separate
    -- simulations) overwrite each other.
    set_log_file_name(GC_TESTCASE & "_Log.txt");
    set_alert_file_name(GC_TESTCASE & "_Alert.txt");

    await_uvvm_initialization(VOID);

    -- override default config with settings for this testbench
    v_axistream_bfm_config.max_wait_cycles          := 1000;
    v_axistream_bfm_config.max_wait_cycles_severity := error;
    v_axistream_bfm_config.check_packet_length      := true;
    v_axistream_bfm_config.byte_endianness          := LOWER_BYTE_RIGHT; -- LOWER_BYTE_LEFT
    if GC_USE_SETUP_AND_HOLD then
      v_axistream_bfm_config.clock_period := C_CLK_PERIOD;
      v_axistream_bfm_config.setup_time   := C_CLK_PERIOD / 4;
      v_axistream_bfm_config.hold_time    := C_CLK_PERIOD / 4;
      v_axistream_bfm_config.bfm_sync     := SYNC_WITH_SETUP_AND_HOLD;
    end if;

    -- Default: use same config for both the master and slave VVC
    v_vvc_config            := shared_axistream_vvc_config.get(C_FIFO2VVC_MASTER);
    v_vvc_config.bfm_config := v_axistream_bfm_config; -- vvc_methods_pkg
    shared_axistream_vvc_config.set(v_vvc_config, C_FIFO2VVC_MASTER);

    v_vvc_config            := shared_axistream_vvc_config.get(C_FIFO2VVC_SLAVE);
    v_vvc_config.bfm_config := v_axistream_bfm_config; -- vvc_methods_pkg
    shared_axistream_vvc_config.set(v_vvc_config, C_FIFO2VVC_SLAVE);

    v_vvc_config            := shared_axistream_vvc_config.get(C_VVC2VVC_MASTER);
    v_vvc_config.bfm_config := v_axistream_bfm_config; -- vvc_methods_pkg
    shared_axistream_vvc_config.set(v_vvc_config, C_VVC2VVC_MASTER);

    v_vvc_config            := shared_axistream_vvc_config.get(C_VVC2VVC_SLAVE);
    v_vvc_config.bfm_config := v_axistream_bfm_config; -- vvc_methods_pkg
    shared_axistream_vvc_config.set(v_vvc_config, C_VVC2VVC_SLAVE);

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

    -- Short packet test - transmit, receive and check test
    ------------------------------------------------------------
    log(ID_LOG_HDR, "TC: axistream VVC Master transmits short packet directly to VVC Slave");
    ------------------------------------------------------------
    v_data_array_1_byte(0) := (x"AA");
    v_data_array_2_byte(0) := (x"AABB");
    v_data_array_3_byte(0) := (x"AABBCC");
    v_data_array_4_byte(0) := (x"AABBCCDD");
    axistream_transmit(AXISTREAM_VVCT, C_VVC2VVC_MASTER, v_data_array_1_byte(0 to 0), "1 byte transmit VVC2VVC. Default tuser etc, i=" & to_string(0));
    axistream_expect(AXISTREAM_VVCT, C_VVC2VVC_SLAVE, v_data_array_1_byte(0 to 0), "1 byte expect  VVC2VVC. Default tuser etc, i=" & to_string(0));
    axistream_transmit(AXISTREAM_VVCT, C_VVC2VVC_MASTER, v_data_array_2_byte(0 to 0), "2 byte transmit VVC2VVC. Default tuser etc, i=" & to_string(0));
    axistream_expect(AXISTREAM_VVCT, C_VVC2VVC_SLAVE, v_data_array_2_byte(0 to 0), "2 byte expect  VVC2VVC. Default tuser etc, i=" & to_string(0));
    axistream_transmit(AXISTREAM_VVCT, C_VVC2VVC_MASTER, v_data_array_3_byte(0 to 0), "3 byte transmit VVC2VVC. Default tuser etc, i=" & to_string(0));
    axistream_expect(AXISTREAM_VVCT, C_VVC2VVC_SLAVE, v_data_array_3_byte(0 to 0), "3 byte expect  VVC2VVC. Default tuser etc, i=" & to_string(0));
    axistream_transmit(AXISTREAM_VVCT, C_VVC2VVC_MASTER, v_data_array_4_byte(0 to 0), "4 byte transmit VVC2VVC. Default tuser etc, i=" & to_string(0));
    axistream_expect(AXISTREAM_VVCT, C_VVC2VVC_SLAVE, v_data_array_4_byte(0 to 0), "4 byte expect  VVC2VVC. Default tuser etc, i=" & to_string(0));

    -- Short packet test wih SLV
    ------------------------------------------------------------
    log(ID_LOG_HDR, "TC: axistream VVC Master transmits short SLV packet directly to VVC Slave");
    ------------------------------------------------------------
    v_data_array_as_slv(31 downto 0) := x"AABBCCDD"; -- 4 bytes
    -- transmit and receive 0xAA
    axistream_transmit(AXISTREAM_VVCT, C_VVC2VVC_MASTER, v_data_array_as_slv(31 downto 24), "1 byte transmit VVC2VVC. Default tuser etc, i=" & to_string(0));
    axistream_expect(AXISTREAM_VVCT, C_VVC2VVC_SLAVE, v_data_array_1_byte(0), "1 byte expect  VVC2VVC. Default tuser etc, i=" & to_string(0));
    -- transmit and receive 0xAABB
    axistream_transmit(AXISTREAM_VVCT, C_VVC2VVC_MASTER, v_data_array_as_slv(31 downto 16), "1 byte transmit VVC2VVC. Default tuser etc, i=" & to_string(0));
    axistream_expect(AXISTREAM_VVCT, C_VVC2VVC_SLAVE, v_data_array_2_byte(0), "1 byte expect  VVC2VVC. Default tuser etc, i=" & to_string(0));
    -- transmit and receive 0xAABBCC
    axistream_transmit(AXISTREAM_VVCT, C_VVC2VVC_MASTER, v_data_array_as_slv(31 downto 8), "1 byte transmit VVC2VVC. Default tuser etc, i=" & to_string(0));
    axistream_expect(AXISTREAM_VVCT, C_VVC2VVC_SLAVE, v_data_array_3_byte(0), "1 byte expect  VVC2VVC. Default tuser etc, i=" & to_string(0));
    -- transmit and receive 0xAABBCCDD
    axistream_transmit(AXISTREAM_VVCT, C_VVC2VVC_MASTER, v_data_array_as_slv(31 downto 0), "1 byte transmit VVC2VVC. Default tuser etc, i=" & to_string(0));
    axistream_expect(AXISTREAM_VVCT, C_VVC2VVC_SLAVE, v_data_array_4_byte(0), "1 byte expect  VVC2VVC. Default tuser etc, i=" & to_string(0));

    -- Long packet test - transmit, receive and check test
    ------------------------------------------------------------
    log(ID_LOG_HDR, "TC: axistream VVC Master transmits long packet directly to VVC Slave");
    ------------------------------------------------------------
    for i in 1 to 5 loop
      v_num_bytes := random(1, C_MAX_BYTES);
      v_num_words := integer(ceil(real(v_num_bytes) / (real(GC_DATA_WIDTH) / 8.0)));

      for byte in 0 to v_num_bytes - 1 loop
        v_data_array_1_byte(byte) := random(v_data_array_1_byte(0)'length);
        v_data_array_2_byte(byte) := random(v_data_array_2_byte(0)'length);
        v_data_array_3_byte(byte) := random(v_data_array_3_byte(0)'length);
        v_data_array_4_byte(byte) := random(v_data_array_4_byte(0)'length);
      end loop;
      -- Make sure ready signal is toggled in various ways
      v_vvc_config                                  := shared_axistream_vvc_config.get(C_VVC2VVC_SLAVE);
      v_vvc_config.bfm_config.ready_low_at_word_num := random(0, v_num_words - 1);
      v_vvc_config.bfm_config.ready_low_duration    := random(0, 5);
      v_vvc_config.bfm_config.ready_default_value   := random(VOId);
      shared_axistream_vvc_config.set(v_vvc_config, C_VVC2VVC_SLAVE);

      -- transmit 1 byte byte array data and check data
      axistream_transmit(AXISTREAM_VVCT, C_VVC2VVC_MASTER, v_data_array_1_byte(0 to v_num_bytes - 1), "transmit VVC2VVC. Default tuser etc, i=" & to_string(i));
      axistream_expect(AXISTREAM_VVCT, C_VVC2VVC_SLAVE, v_data_array_1_byte(0 to v_num_bytes - 1), "expect  VVC2VVC. Default tuser etc, i=" & to_string(i));
      -- transmit 2 byte byte array data and check data
      axistream_transmit(AXISTREAM_VVCT, C_VVC2VVC_MASTER, v_data_array_2_byte(0 to v_num_bytes - 1), "transmit VVC2VVC. Default tuser etc, i=" & to_string(i));
      axistream_expect(AXISTREAM_VVCT, C_VVC2VVC_SLAVE, v_data_array_2_byte(0 to v_num_bytes - 1), "expect  VVC2VVC. Default tuser etc, i=" & to_string(i));
      -- transmit 3 byte byte array data and check data
      axistream_transmit(AXISTREAM_VVCT, C_VVC2VVC_MASTER, v_data_array_3_byte(0 to v_num_bytes - 1), "transmit VVC2VVC. Default tuser etc, i=" & to_string(i));
      axistream_expect(AXISTREAM_VVCT, C_VVC2VVC_SLAVE, v_data_array_3_byte(0 to v_num_bytes - 1), "expect  VVC2VVC. Default tuser etc, i=" & to_string(i));
      -- transmit 4 byte byte array data and check data
      axistream_transmit(AXISTREAM_VVCT, C_VVC2VVC_MASTER, v_data_array_4_byte(0 to v_num_bytes - 1), "transmit VVC2VVC. Default tuser etc, i=" & to_string(i));
      axistream_expect(AXISTREAM_VVCT, C_VVC2VVC_SLAVE, v_data_array_4_byte(0 to v_num_bytes - 1), "expect  VVC2VVC. Default tuser etc, i=" & to_string(i));
    end loop;

    -- Test transmit, receive and check with various parameters
    ------------------------------------------------------------
    log(ID_LOG_HDR, "TC: include tuser test. VVC Master transmits directly to VVC Slave");
    ------------------------------------------------------------
    -- run test with word size from 1 to 4 bytes
    for bytes_in_word in 1 to C_MAX_BYTES_IN_WORD loop
      v_num_bytes := random(1, C_MAX_BYTES / bytes_in_word);
      v_num_words := integer(ceil(real(v_num_bytes * bytes_in_word) / (real(GC_DATA_WIDTH) / 8.0)));

      for word in 0 to v_num_words - 1 loop
        v_user_array(word) := random(v_user_array(0)'length);
        v_strb_array(word) := random(v_strb_array(0)'length);
        v_id_array(word)   := random(v_id_array(0)'length);
        v_dest_array(word) := random(v_dest_array(0)'length);
      end loop;

      -- test: transmit and expect with tuser = something. tstrb etc = default
      VVC_master_to_VVC_slave_include_tuser(get_slv_array(v_num_bytes, bytes_in_word),
                                            v_user_array(0 to v_num_words - 1));
      -----------------------------------------------------------
      -- test: transmit and expect with tuser, tstrb etc is set (no defaults)
      VVC_master_to_VVC_slave_no_defaults(get_slv_array(v_num_bytes, bytes_in_word),
                                          v_user_array(0 to v_num_words - 1),
                                          v_strb_array(0 to v_num_words - 1),
                                          v_id_array(0 to v_num_words - 1),
                                          v_dest_array(0 to v_num_words - 1));
      -----------------------------------------------------------
      -- test: _receive, Check that tuser is fetched correctly
      VVC_master_to_VVC_slave_with_check(get_slv_array(v_num_bytes, bytes_in_word),
                                         v_user_array(0 to v_num_words - 1));
      -----------------------------------------------------------
      -- test: transmit and check that expect detects errors
      VVC_master_to_VVC_slave_with_data_error(get_slv_array(v_num_bytes, bytes_in_word),
                                              v_user_array(0 to v_num_words - 1));
      -----------------------------------------------------------
      -- test: verify alert if the tuser is not what is expected
      VVC_master_to_VVC_slave_tuser_error_check(get_slv_array(v_num_bytes, bytes_in_word),
                                                v_user_array(0 to v_num_words - 1),
                                                v_strb_array(0 to v_num_words - 1),
                                                v_id_array(0 to v_num_words - 1),
                                                v_dest_array(0 to v_num_words - 1));
      -----------------------------------------------------------
      -- test: verify alert if the tstrb is not what is expected
      VVC_master_to_VVC_slave_tstrb_error_check(get_slv_array(v_num_bytes, bytes_in_word),
                                                v_user_array(0 to v_num_words - 1),
                                                v_strb_array(0 to v_num_words - 1),
                                                v_id_array(0 to v_num_words - 1),
                                                v_dest_array(0 to v_num_words - 1));
      -----------------------------------------------------------
      -- test: verify alert if the tid is not what is expected
      VVC_master_to_VVC_slave_tid_error_check(get_slv_array(v_num_bytes, bytes_in_word),
                                              v_user_array(0 to v_num_words - 1),
                                              v_strb_array(0 to v_num_words - 1),
                                              v_id_array(0 to v_num_words - 1),
                                              v_dest_array(0 to v_num_words - 1));
      -----------------------------------------------------------
      -- test: verify alert if the tdest is not what is expected
      VVC_master_to_VVC_slave_tdest_error_check(get_slv_array(v_num_bytes, bytes_in_word),
                                                v_user_array(0 to v_num_words - 1),
                                                v_strb_array(0 to v_num_words - 1),
                                                v_id_array(0 to v_num_words - 1),
                                                v_dest_array(0 to v_num_words - 1));

      await_completion(AXISTREAM_VVCT, C_VVC2VVC_SLAVE, 1 ms, "Wait for receive to finish");
    end loop;

    ------------------------------------------------------------
    log(ID_LOG_HDR, "TC: axistream_receive and fetch_result ");
    ------------------------------------------------------------
    for bytes_in_word in 1 to C_MAX_BYTES_IN_WORD loop
      v_num_bytes := random(1, C_MAX_BYTES / bytes_in_word);
      VVC_master_to_VVC_slave_receive_and_check(get_slv_array(v_num_bytes, bytes_in_word));
    end loop;

    ------------------------------------------------------------
    log(ID_LOG_HDR, "TC: axistream transmit when tready=0 from DUT at start of transfer  ");
    ------------------------------------------------------------
    v_vvc_config                            := shared_axistream_vvc_config.get(C_FIFO2VVC_SLAVE);
    v_vvc_config.unwanted_activity_severity := NO_ALERT; -- Unwanted activity errors due to transmit with inactive slave
    shared_axistream_vvc_config.set(v_vvc_config, C_FIFO2VVC_SLAVE);
    -- Fill DUT FIFO to provoke tready=0
    v_num_bytes := 1;
    for i in 0 to C_DUT_FIFO_DEPTH - 1 loop
      v_data_array_1_byte(0) := std_logic_vector(to_unsigned(i, v_data_array_1_byte(0)'length));
      axistream_transmit(AXISTREAM_VVCT, C_FIFO2VVC_MASTER, v_data_array_1_byte(0 to v_num_bytes - 1), "transmit to fill DUT,i=" & to_string(i));
    end loop;
    await_completion(AXISTREAM_VVCT, C_FIFO2VVC_MASTER, 1 ms);
    wait for 100 ns;
    v_vvc_config                            := shared_axistream_vvc_config.get(C_FIFO2VVC_SLAVE);
    v_vvc_config.unwanted_activity_severity := C_AXISTREAM_VVC_CONFIG_DEFAULT.unwanted_activity_severity;
    shared_axistream_vvc_config.set(v_vvc_config, C_FIFO2VVC_SLAVE);

    -- DUT FIFO is now full. Schedule the transmit which will wait for tready until DUT is read from later
    v_data_array_1_byte(0) := x"D0";
    axistream_transmit(AXISTREAM_VVCT, C_FIFO2VVC_MASTER, v_data_array_1_byte(0 to v_num_bytes - 1), "start transmit while tready=0");

    -- Make DUT not full anymore. Check data from DUT equals transmitted data
    for i in 0 to C_DUT_FIFO_DEPTH - 1 loop
      v_data_array_1_byte(0) := std_logic_vector(to_unsigned(i, v_data_array_1_byte(0)'length));
      axistream_expect(AXISTREAM_VVCT, C_FIFO2VVC_SLAVE, v_data_array_1_byte(0 to v_num_bytes - 1), "expect ");
    end loop;

    v_data_array_1_byte(0) := x"D0";
    axistream_expect(AXISTREAM_VVCT, C_FIFO2VVC_SLAVE, v_data_array_1_byte(0 to v_num_bytes - 1), "expect ");
    wait for 100 ns;

    ------------------------------------------------------------
    log(ID_LOG_HDR, "TC: axistream transmits: ");
    ------------------------------------------------------------
    v_vvc_config                            := shared_axistream_vvc_config.get(C_FIFO2VVC_MASTER);
    v_vvc_config.inter_bfm_delay.delay_type := TIME_FINISH2START;
    shared_axistream_vvc_config.set(v_vvc_config, C_FIFO2VVC_MASTER);
    for i in 0 to 2 loop

      for bytes_in_word in 1 to C_MAX_BYTES_IN_WORD loop
        -- Various delay between each transmit
        v_vvc_config                               := shared_axistream_vvc_config.get(C_FIFO2VVC_MASTER);
        v_vvc_config.inter_bfm_delay.delay_in_time := i * C_CLK_PERIOD;
        shared_axistream_vvc_config.set(v_vvc_config, C_FIFO2VVC_MASTER);

        for i in 1 to 20 loop
          v_num_bytes := random(1, C_MAX_BYTES / bytes_in_word);
          v_num_words := integer(ceil(real(v_num_bytes * bytes_in_word) / (real(GC_DATA_WIDTH) / 8.0)));
          -- Generate packet data
          for word in 0 to v_num_words - 1 loop
            v_user_array(word) := std_logic_vector(to_unsigned(i + word, v_user_array(0)'length));
            v_strb_array(word) := std_logic_vector(to_unsigned(i + word, v_strb_array(0)'length));
            v_id_array(word)   := std_logic_vector(to_unsigned(i + word, v_id_array(0)'length));
            v_dest_array(word) := std_logic_vector(to_unsigned((i + word) mod 16, v_dest_array(0)'length));
          end loop;

          VVC_master_to_VVC_slave_transmit_and_check(get_slv_array(v_num_bytes, bytes_in_word),
                                                     v_user_array(0 to v_num_words - 1),
                                                     v_strb_array(0 to v_num_words - 1),
                                                     v_id_array(0 to v_num_words - 1),
                                                     v_dest_array(0 to v_num_words - 1),
                                                     i);
        end loop;

        -- Await completion on both VVCs
        add_to_vvc_list(AXISTREAM_VVCT, C_FIFO2VVC_MASTER, v_vvc_list);
        add_to_vvc_list(AXISTREAM_VVCT, C_FIFO2VVC_SLAVE, v_vvc_list);
        await_completion(ALL_OF, v_vvc_list, 1 ms);
        report_alert_counters(INTERMEDIATE); -- Report final counters and print conclusion for simulation (Success/Fail)

        -- verify alert if the 'tlast' is not where expected
        for i in 1 to 1 loop
          if GC_INCLUDE_TUSER then
            v_num_bytes := MAXIMUM(1, (GC_DATA_WIDTH / (8 * bytes_in_word))) + 1; -- So that v_num_bytes - 1 makes the tlast in previous clock cycle
            v_num_words := integer(ceil(real(v_num_bytes * bytes_in_word) / (real(GC_DATA_WIDTH) / 8.0)));
            VVC_master_to_VVC_slave_tlast_error_check(get_slv_array(v_num_bytes, bytes_in_word),
                                                      v_user_array(0 to v_num_words - 1),
                                                      v_strb_array(0 to v_num_words - 1),
                                                      v_id_array(0 to v_num_words - 1),
                                                      v_dest_array(0 to v_num_words - 1),
                                                      v_num_bytes, i);
          end if;
        end loop;
      end loop;
    end loop;

    ------------------------------------------------------------
    log(ID_LOG_HDR, "TC: Testing VVC transmit and expect with non-normalized slv_array");
    ------------------------------------------------------------
    v_data_array_1_byte(1 to 4) := (x"00", x"01", x"02", x"03");
    axistream_transmit(AXISTREAM_VVCT, C_FIFO2VVC_MASTER, v_data_array_1_byte(1 to 4), "transmit bytes 1 to 4");
    axistream_expect(AXISTREAM_VVCT, C_FIFO2VVC_SLAVE, v_data_array_1_byte(1 to 4), "expecting bytes 1 to 4");
    await_completion(AXISTREAM_VVCT, C_FIFO2VVC_SLAVE, 1 ms);

    ------------------------------------------------------------
    log(ID_LOG_HDR, "TC: check axistream VVC Master only transmits and VVC Slave only receives");
    ------------------------------------------------------------
    increment_expected_alerts_and_stop_limit(TB_ERROR, 1);
    axistream_transmit(AXISTREAM_VVCT, C_VVC2VVC_SLAVE, v_data_array_1_byte, "transmit from VVC slave");
    increment_expected_alerts_and_stop_limit(TB_ERROR, 1);
    axistream_receive(AXISTREAM_VVCT, C_VVC2VVC_MASTER, "receive on VVC master");
    increment_expected_alerts_and_stop_limit(TB_ERROR, 1);
    axistream_expect(AXISTREAM_VVCT, C_VVC2VVC_MASTER, v_data_array_1_byte, "expect on VVC master");

    axistream_transmit(AXISTREAM_VVCT, C_VVC2VVC_MASTER, v_data_array_1_byte, "transmit");
    axistream_expect(AXISTREAM_VVCT, C_VVC2VVC_SLAVE, v_data_array_1_byte, "expect ");
    await_completion(AXISTREAM_VVCT, C_VVC2VVC_SLAVE, 1 ms);

    -------------------------------------------------------------------------------------------
    log(ID_LOG_HDR, "TC: Test different configurations of ready default value with ready low");
    -------------------------------------------------------------------------------------------
    for i in 0 to 3 loop
      v_vvc_config                                  := shared_axistream_vvc_config.get(C_FIFO2VVC_SLAVE);
      v_vvc_config.bfm_config.ready_default_value   := '0' when i < 2 else '1';
      v_vvc_config.bfm_config.ready_low_at_word_num := 0 when (i mod 2 = 0) else 2;
      v_vvc_config.bfm_config.ready_low_duration    := 1;
      shared_axistream_vvc_config.set(v_vvc_config, C_FIFO2VVC_SLAVE);

      v_vvc_config                                  := shared_axistream_vvc_config.get(C_VVC2VVC_SLAVE);
      v_vvc_config.bfm_config.ready_default_value   := '0' when i < 2 else '1';
      v_vvc_config.bfm_config.ready_low_at_word_num := 0 when (i mod 2 = 0) else 2;
      v_vvc_config.bfm_config.ready_low_duration    := 1;
      shared_axistream_vvc_config.set(v_vvc_config, C_VVC2VVC_SLAVE);

      axistream_transmit(AXISTREAM_VVCT, C_FIFO2VVC_MASTER, v_data_array_1_byte(0 to 0), "transmit 1 byte");
      axistream_transmit(AXISTREAM_VVCT, C_FIFO2VVC_MASTER, v_data_array_1_byte(0 to 0), "transmit 1 byte");
      axistream_transmit(AXISTREAM_VVCT, C_FIFO2VVC_MASTER, v_data_array_1_byte(0 to 3), "transmit 4 bytes");
      axistream_transmit(AXISTREAM_VVCT, C_FIFO2VVC_MASTER, v_data_array_1_byte(0 to 3), "transmit 4 bytes");
      axistream_expect(AXISTREAM_VVCT, C_FIFO2VVC_SLAVE, v_data_array_1_byte(0 to 0), "expect 1 byte");
      axistream_expect(AXISTREAM_VVCT, C_FIFO2VVC_SLAVE, v_data_array_1_byte(0 to 0), "expect 1 byte");
      axistream_expect(AXISTREAM_VVCT, C_FIFO2VVC_SLAVE, v_data_array_1_byte(0 to 3), "expect 4 bytes");
      axistream_expect(AXISTREAM_VVCT, C_FIFO2VVC_SLAVE, v_data_array_1_byte(0 to 3), "expect 4 bytes");
      await_completion(AXISTREAM_VVCT, C_FIFO2VVC_SLAVE, 1 ms);

      axistream_transmit(AXISTREAM_VVCT, C_VVC2VVC_MASTER, v_data_array_1_byte(0 to 0), "transmit 1 byte");
      axistream_transmit(AXISTREAM_VVCT, C_VVC2VVC_MASTER, v_data_array_1_byte(0 to 0), "transmit 1 byte");
      axistream_transmit(AXISTREAM_VVCT, C_VVC2VVC_MASTER, v_data_array_1_byte(0 to 3), "transmit 4 bytes");
      axistream_transmit(AXISTREAM_VVCT, C_VVC2VVC_MASTER, v_data_array_1_byte(0 to 3), "transmit 4 bytes");
      axistream_expect(AXISTREAM_VVCT, C_VVC2VVC_SLAVE, v_data_array_1_byte(0 to 0), "expect 1 byte");
      axistream_expect(AXISTREAM_VVCT, C_VVC2VVC_SLAVE, v_data_array_1_byte(0 to 0), "expect 1 byte");
      axistream_expect(AXISTREAM_VVCT, C_VVC2VVC_SLAVE, v_data_array_1_byte(0 to 3), "expect 4 bytes");
      axistream_expect(AXISTREAM_VVCT, C_VVC2VVC_SLAVE, v_data_array_1_byte(0 to 3), "expect 4 bytes");
      await_completion(AXISTREAM_VVCT, C_VVC2VVC_SLAVE, 1 ms);
    end loop;

    --------------------------------------------------------------------------
    log(ID_LOG_HDR, "TC: Test random configurations of valid and ready low");
    --------------------------------------------------------------------------
    for i in 0 to 59 loop
      if i < 20 then
        v_vvc_config                                  := shared_axistream_vvc_config.get(C_FIFO2VVC_MASTER);
        v_vvc_config.bfm_config.valid_low_at_word_num := random(0, 5);
        v_vvc_config.bfm_config.valid_low_duration    := random(0, 5);
        shared_axistream_vvc_config.set(v_vvc_config, C_FIFO2VVC_MASTER);

        v_vvc_config                                  := shared_axistream_vvc_config.get(C_VVC2VVC_MASTER);
        v_vvc_config.bfm_config.valid_low_at_word_num := random(0, 5);
        v_vvc_config.bfm_config.valid_low_duration    := random(0, 5);
        shared_axistream_vvc_config.set(v_vvc_config, C_VVC2VVC_MASTER);

        v_vvc_config                                  := shared_axistream_vvc_config.get(C_FIFO2VVC_SLAVE);
        v_vvc_config.bfm_config.ready_low_at_word_num := random(0, 5);
        v_vvc_config.bfm_config.ready_low_duration    := random(0, 5);
        shared_axistream_vvc_config.set(v_vvc_config, C_FIFO2VVC_SLAVE);

        v_vvc_config                                  := shared_axistream_vvc_config.get(C_VVC2VVC_SLAVE);
        v_vvc_config.bfm_config.ready_low_at_word_num := random(0, 5);
        v_vvc_config.bfm_config.ready_low_duration    := random(0, 5);
        shared_axistream_vvc_config.set(v_vvc_config, C_VVC2VVC_SLAVE);

      else
        v_vvc_config                                  := shared_axistream_vvc_config.get(C_FIFO2VVC_MASTER);
        v_vvc_config.bfm_config.valid_low_at_word_num := C_MULTIPLE_RANDOM;
        v_vvc_config.bfm_config.valid_low_duration    := C_RANDOM;
        shared_axistream_vvc_config.set(v_vvc_config, C_FIFO2VVC_MASTER);

        v_vvc_config                                  := shared_axistream_vvc_config.get(C_VVC2VVC_MASTER);
        v_vvc_config.bfm_config.valid_low_at_word_num := C_MULTIPLE_RANDOM;
        v_vvc_config.bfm_config.valid_low_duration    := C_RANDOM;
        shared_axistream_vvc_config.set(v_vvc_config, C_VVC2VVC_MASTER);

        v_vvc_config                                  := shared_axistream_vvc_config.get(C_FIFO2VVC_SLAVE);
        v_vvc_config.bfm_config.ready_low_at_word_num := C_MULTIPLE_RANDOM;
        v_vvc_config.bfm_config.ready_low_duration    := C_RANDOM;
        shared_axistream_vvc_config.set(v_vvc_config, C_FIFO2VVC_SLAVE);

        v_vvc_config                                  := shared_axistream_vvc_config.get(C_VVC2VVC_SLAVE);
        v_vvc_config.bfm_config.ready_low_at_word_num := C_MULTIPLE_RANDOM;
        v_vvc_config.bfm_config.ready_low_duration    := C_RANDOM;
        shared_axistream_vvc_config.set(v_vvc_config, C_VVC2VVC_SLAVE);

        if i < 30 then
          -- Probability of multiple random is zero
          v_vvc_config                                           := shared_axistream_vvc_config.get(C_FIFO2VVC_MASTER);
          v_vvc_config.bfm_config.valid_low_multiple_random_prob := 0.0;
          v_vvc_config.bfm_config.valid_low_max_random_duration  := 20;
          shared_axistream_vvc_config.set(v_vvc_config, C_FIFO2VVC_MASTER);

          v_vvc_config                                           := shared_axistream_vvc_config.get(C_VVC2VVC_MASTER);
          v_vvc_config.bfm_config.valid_low_multiple_random_prob := 0.0;
          v_vvc_config.bfm_config.valid_low_max_random_duration  := 20;
          shared_axistream_vvc_config.set(v_vvc_config, C_VVC2VVC_MASTER);

          v_vvc_config                                           := shared_axistream_vvc_config.get(C_FIFO2VVC_SLAVE);
          v_vvc_config.bfm_config.ready_low_multiple_random_prob := 0.0;
          v_vvc_config.bfm_config.ready_low_max_random_duration  := 20;
          shared_axistream_vvc_config.set(v_vvc_config, C_FIFO2VVC_SLAVE);

          v_vvc_config                                           := shared_axistream_vvc_config.get(C_VVC2VVC_SLAVE);
          v_vvc_config.bfm_config.ready_low_multiple_random_prob := 0.0;
          v_vvc_config.bfm_config.ready_low_max_random_duration  := 20;
          shared_axistream_vvc_config.set(v_vvc_config, C_VVC2VVC_SLAVE);

        elsif i < 40 then
          -- Probability of multiple random is low and max random duration is high
          v_vvc_config                                           := shared_axistream_vvc_config.get(C_FIFO2VVC_MASTER);
          v_vvc_config.bfm_config.valid_low_multiple_random_prob := 0.1;
          v_vvc_config.bfm_config.valid_low_max_random_duration  := 20;
          shared_axistream_vvc_config.set(v_vvc_config, C_FIFO2VVC_MASTER);

          v_vvc_config                                           := shared_axistream_vvc_config.get(C_VVC2VVC_MASTER);
          v_vvc_config.bfm_config.valid_low_multiple_random_prob := 0.1;
          v_vvc_config.bfm_config.valid_low_max_random_duration  := 20;
          shared_axistream_vvc_config.set(v_vvc_config, C_VVC2VVC_MASTER);

          v_vvc_config                                           := shared_axistream_vvc_config.get(C_FIFO2VVC_SLAVE);
          v_vvc_config.bfm_config.ready_low_multiple_random_prob := 0.1;
          v_vvc_config.bfm_config.ready_low_max_random_duration  := 20;
          shared_axistream_vvc_config.set(v_vvc_config, C_FIFO2VVC_SLAVE);

          v_vvc_config                                           := shared_axistream_vvc_config.get(C_VVC2VVC_SLAVE);
          v_vvc_config.bfm_config.ready_low_multiple_random_prob := 0.1;
          v_vvc_config.bfm_config.ready_low_max_random_duration  := 20;
          shared_axistream_vvc_config.set(v_vvc_config, C_VVC2VVC_SLAVE);

        elsif i < 50 then
          -- Probability of multiple random is 50/50 and max random duration is low
          v_vvc_config                                           := shared_axistream_vvc_config.get(C_FIFO2VVC_MASTER);
          v_vvc_config.bfm_config.valid_low_multiple_random_prob := 0.5;
          v_vvc_config.bfm_config.valid_low_max_random_duration  := 5;
          shared_axistream_vvc_config.set(v_vvc_config, C_FIFO2VVC_MASTER);

          v_vvc_config                                           := shared_axistream_vvc_config.get(C_VVC2VVC_MASTER);
          v_vvc_config.bfm_config.valid_low_multiple_random_prob := 0.5;
          v_vvc_config.bfm_config.valid_low_max_random_duration  := 5;
          shared_axistream_vvc_config.set(v_vvc_config, C_VVC2VVC_MASTER);

          v_vvc_config                                           := shared_axistream_vvc_config.get(C_FIFO2VVC_SLAVE);
          v_vvc_config.bfm_config.ready_low_multiple_random_prob := 0.5;
          v_vvc_config.bfm_config.ready_low_max_random_duration  := 5;
          shared_axistream_vvc_config.set(v_vvc_config, C_FIFO2VVC_SLAVE);

          v_vvc_config                                           := shared_axistream_vvc_config.get(C_VVC2VVC_SLAVE);
          v_vvc_config.bfm_config.ready_low_multiple_random_prob := 0.5;
          v_vvc_config.bfm_config.ready_low_max_random_duration  := 5;
          shared_axistream_vvc_config.set(v_vvc_config, C_VVC2VVC_SLAVE);

        else
          -- Probability of multiple random is 100% (every cycle) and max random duration is 1
          v_vvc_config                                           := shared_axistream_vvc_config.get(C_FIFO2VVC_MASTER);
          v_vvc_config.bfm_config.valid_low_multiple_random_prob := 1.0;
          v_vvc_config.bfm_config.valid_low_max_random_duration  := 1;
          shared_axistream_vvc_config.set(v_vvc_config, C_FIFO2VVC_MASTER);

          v_vvc_config                                           := shared_axistream_vvc_config.get(C_VVC2VVC_MASTER);
          v_vvc_config.bfm_config.valid_low_multiple_random_prob := 1.0;
          v_vvc_config.bfm_config.valid_low_max_random_duration  := 1;
          shared_axistream_vvc_config.set(v_vvc_config, C_VVC2VVC_MASTER);

          v_vvc_config                                           := shared_axistream_vvc_config.get(C_FIFO2VVC_SLAVE);
          v_vvc_config.bfm_config.ready_low_multiple_random_prob := 1.0;
          v_vvc_config.bfm_config.ready_low_max_random_duration  := 1;
          shared_axistream_vvc_config.set(v_vvc_config, C_FIFO2VVC_SLAVE);

          v_vvc_config                                           := shared_axistream_vvc_config.get(C_VVC2VVC_SLAVE);
          v_vvc_config.bfm_config.ready_low_multiple_random_prob := 1.0;
          v_vvc_config.bfm_config.ready_low_max_random_duration  := 1;
          shared_axistream_vvc_config.set(v_vvc_config, C_VVC2VVC_SLAVE);
        end if;
      end if;
      axistream_transmit(AXISTREAM_VVCT, C_FIFO2VVC_MASTER, v_data_array_1_byte(0 to 15), "transmit 16 bytes");
      axistream_expect(AXISTREAM_VVCT, C_FIFO2VVC_SLAVE, v_data_array_1_byte(0 to 15), "expect 16 bytes");
      await_completion(AXISTREAM_VVCT, C_FIFO2VVC_SLAVE, 1 ms);

      axistream_transmit(AXISTREAM_VVCT, C_VVC2VVC_MASTER, v_data_array_1_byte(0 to 15), "transmit 16 bytes");
      axistream_expect(AXISTREAM_VVCT, C_VVC2VVC_SLAVE, v_data_array_1_byte(0 to 15), "expect 16 bytes");
      await_completion(AXISTREAM_VVCT, C_VVC2VVC_SLAVE, 1 ms);
    end loop;

    ------------------------------------------------------------
    log(ID_LOG_HDR, "TC: sanity check ");
    ------------------------------------------------------------
    for bytes_in_word in 1 to C_MAX_BYTES_IN_WORD loop
      v_num_bytes := random(1, C_MAX_BYTES / bytes_in_word);
      v_num_words := integer(ceil(real(v_num_bytes * bytes_in_word) / (real(GC_DATA_WIDTH) / 8.0)));

      for word in 0 to v_num_words - 1 loop
        v_user_array(word) := std_logic_vector(to_unsigned(word, v_user_array(0)'length));
      end loop;

      VVC_master_to_VVC_slave_wrong_size(v_num_bytes, bytes_in_word, v_user_array);
    end loop;

    ------------------------------------------------------------------------------------------------------------------------------
    log(ID_LOG_HDR, "Testing Unwanted Activity Detection in VVC", C_SCOPE);
    ------------------------------------------------------------------------------------------------------------------------------
    for i in 0 to 2 loop
      -- Test different alert severity configurations
      if i = 0 then
        v_alert_level := C_AXISTREAM_VVC_CONFIG_DEFAULT.unwanted_activity_severity;
      elsif i = 1 then
        v_alert_level := FAILURE;
      else
        v_alert_level := NO_ALERT;
      end if;
      log(ID_SEQUENCER, "Setting unwanted_activity_severity to " & to_upper(to_string(v_alert_level)), C_SCOPE);
      v_vvc_config                            := shared_axistream_vvc_config.get(C_FIFO2VVC_MASTER);
      v_vvc_config.unwanted_activity_severity := v_alert_level;
      shared_axistream_vvc_config.set(v_vvc_config, C_FIFO2VVC_MASTER);
      v_vvc_config                            := shared_axistream_vvc_config.get(C_FIFO2VVC_SLAVE);
      v_vvc_config.unwanted_activity_severity := v_alert_level;
      shared_axistream_vvc_config.set(v_vvc_config, C_FIFO2VVC_SLAVE);

      log(ID_SEQUENCER, "Testing normal data transmission", C_SCOPE);
      for byte in 0 to 15 loop
        v_data_array_1_byte(byte) := random(v_data_array_1_byte(0)'length);
      end loop;
      axistream_transmit(AXISTREAM_VVCT, C_FIFO2VVC_MASTER, v_data_array_1_byte(0 to 15), "Transmit data");
      axistream_expect(AXISTREAM_VVCT, C_FIFO2VVC_SLAVE, v_data_array_1_byte(0 to 15), "Expect data");
      await_completion(AXISTREAM_VVCT, C_FIFO2VVC_SLAVE, 1 ms);

      -- Test with and without a time gap between await_completion and unexpected data transmission
      if i = 0 then
        log(ID_SEQUENCER, "Wait 100 ns", C_SCOPE);
        wait for 100 ns;
      end if;

      log(ID_SEQUENCER, "Testing unexpected data transmission", C_SCOPE);
      toggle_vvc_if(v_alert_level);
    end loop;

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
