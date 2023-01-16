--================================================================================================================================
-- Copyright (c) 2020 by Bitvis AS.  All rights reserved.
-- You should have received a copy of the license file containing the Apache License (see LICENSE.TXT), if not,
-- contact Bitvis AS <support@bitvis.no>.
--
-- UVVM AND ANY PART THEREOF ARE PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO
-- THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS
-- OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
-- OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH UVVM OR THE USE OR OTHER DEALINGS IN UVVM.
--================================================================================================================================

---------------------------------------------------------------------------------------------
-- Description : See library quick reference (under 'doc') and README-file(s)
---------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library uvvm_vvc_framework;
use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

use work.support_pkg.all;

library bitvis_vip_sbi;
context bitvis_vip_sbi.vvc_context;

architecture SBI of hvvc_to_vvc_bridge is
begin

  p_executor : process
    constant c_data_words_width          : natural := hvvc_to_bridge.data_words(hvvc_to_bridge.data_words'low)'length;
    variable v_cmd_idx                   : integer;
    variable v_sbi_received_data         : bitvis_vip_sbi.vvc_cmd_pkg.t_vvc_result;
    variable v_dut_address               : unsigned(GC_DUT_IF_FIELD_CONFIG(GC_DUT_IF_FIELD_CONFIG'low)(GC_DUT_IF_FIELD_CONFIG(GC_DUT_IF_FIELD_CONFIG'low)'high).dut_address'range);
    variable v_dut_address_increment     : integer;
    variable v_dut_data_width            : positive;
    variable v_num_transfers             : integer;
    variable v_data_slv                  : std_logic_vector(GC_MAX_NUM_WORDS * c_data_words_width - 1 downto 0);
    variable v_dut_if_field_pos_is_first : boolean;
    variable v_dut_if_field_pos_is_last  : boolean;
    variable v_disabled_msg_id_int_wait  : boolean;
    variable v_disabled_msg_id_exe_wait  : boolean;
    variable v_sbi_vvc_msg_id_panel      : t_msg_id_panel; -- v3
    variable v_hvvc_msg_id_panel         : t_msg_id_panel; -- v3

    -- Converts a t_slv_array to a std_logic_vector (word endianness is LOWER_WORD_RIGHT)
    function convert_slv_array_to_slv(
      constant slv_array : t_slv_array
    ) return std_logic_vector is
      constant c_num_words : integer := slv_array'length;
      constant c_word_len  : integer := slv_array(slv_array'low)'length;
      variable v_slv       : std_logic_vector(c_num_words * c_word_len - 1 downto 0);
    begin
      for word_idx in 0 to c_num_words - 1 loop
        v_slv(c_word_len * (word_idx + 1) - 1 downto c_word_len * word_idx) := slv_array(word_idx);
      end loop;
      return v_slv;
    end function;

    -- Converts a std_logic_vector to a t_slv_array (word endianness is LOWER_WORD_RIGHT)
    function convert_slv_to_slv_array(
      constant slv      : std_logic_vector;
      constant word_len : integer
    ) return t_slv_array is
      constant c_num_words : integer := slv'length / word_len;
      variable v_slv_array : t_slv_array(0 to c_num_words - 1)(word_len - 1 downto 0);
    begin
      for word_idx in 0 to c_num_words - 1 loop
        v_slv_array(word_idx) := slv(word_len * (word_idx + 1) - 1 downto word_len * word_idx);
      end loop;
      return v_slv_array;
    end function;

    -- v3
    -- Disables a previously enabled msg_id in the VVC's shared config
    impure function disable_sbi_vvc_msg_id(
      constant msg_id : t_msg_id
    ) return boolean is
      variable v_disable_id   : boolean        := false;
      variable v_msg_id_panel : t_msg_id_panel := shared_sbi_vvc_msg_id_panel.get(GC_PHY_VVC_INSTANCE_IDX);
    begin
      if v_msg_id_panel(msg_id) = ENABLED then
        v_msg_id_panel(msg_id) := DISABLED;
        shared_sbi_vvc_msg_id_panel.set(v_msg_id_panel, GC_PHY_VVC_INSTANCE_IDX);
        v_disable_id           := true;
      end if;
      return v_disable_id;
    end function disable_sbi_vvc_msg_id;

    -- v3
    procedure enable_sbi_vvc_msg_id(
      constant msg_id : t_msg_id
    ) is
      variable v_msg_id_panel : t_msg_id_panel := shared_sbi_vvc_msg_id_panel.get(GC_PHY_VVC_INSTANCE_IDX);
    begin
      v_msg_id_panel(msg_id) := ENABLED;
      shared_sbi_vvc_msg_id_panel.set(v_msg_id_panel, GC_PHY_VVC_INSTANCE_IDX);
    end procedure enable_sbi_vvc_msg_id;

  begin
    loop

      -- Await cmd from the HVVC
      wait until hvvc_to_bridge.trigger = true;

      v_sbi_vvc_msg_id_panel := shared_sbi_vvc_msg_id_panel.get(GC_PHY_VVC_INSTANCE_IDX); -- v3
      v_hvvc_msg_id_panel    := hvvc_to_bridge.msg_id_panel; -- v3

      -- Check the field position in the packet
      v_dut_if_field_pos_is_first := hvvc_to_bridge.dut_if_field_pos = FIRST or hvvc_to_bridge.dut_if_field_pos = FIRST_AND_LAST;
      v_dut_if_field_pos_is_last  := hvvc_to_bridge.dut_if_field_pos = LAST or hvvc_to_bridge.dut_if_field_pos = FIRST_AND_LAST;

      if v_dut_if_field_pos_is_first then
        log(ID_NEW_HVVC_CMD_SEQ, "VVC is busy while executing an HVVC command", "SBI_VVC," & to_string(GC_PHY_VVC_INSTANCE_IDX), v_sbi_vvc_msg_id_panel); -- v3

        -- Disable the interpreter and executor waiting logs during the HVVC command
        v_disabled_msg_id_int_wait := disable_sbi_vvc_msg_id(ID_CMD_INTERPRETER_WAIT); -- v3
        v_disabled_msg_id_exe_wait := disable_sbi_vvc_msg_id(ID_CMD_EXECUTOR_WAIT); -- v3
      end if;

      -- Get the next DUT address from the config to write the data
      get_dut_address_config(GC_DUT_IF_FIELD_CONFIG, hvvc_to_bridge, v_dut_address, v_dut_address_increment);
      -- Get the next DUT data width from the config
      get_data_width_config(GC_DUT_IF_FIELD_CONFIG, hvvc_to_bridge, v_dut_data_width);

      -- Calculate number of transfers
      v_num_transfers := (hvvc_to_bridge.num_data_words * c_data_words_width) / v_dut_data_width;
      -- Extra transfer if data bits remainder
      if ((hvvc_to_bridge.num_data_words * c_data_words_width) rem v_dut_data_width) /= 0 then
        v_num_transfers := v_num_transfers + 1;
      end if;

      -- Execute command
      case hvvc_to_bridge.operation is

        when TRANSMIT =>
          -- Convert from t_slv_array to std_logic_vector (word endianness is LOWER_WORD_RIGHT)
          v_data_slv(hvvc_to_bridge.num_data_words * c_data_words_width - 1 downto 0) := convert_slv_array_to_slv(hvvc_to_bridge.data_words(0 to hvvc_to_bridge.num_data_words - 1));

          -- Loop through transfers
          for i in 0 to v_num_transfers - 1 loop
            sbi_write(SBI_VVCT, GC_PHY_VVC_INSTANCE_IDX, v_dut_address, v_data_slv(v_dut_data_width * (i + 1) - 1 downto v_dut_data_width * i),
                      "HVVC: Write data via SBI.", GC_SCOPE, v_hvvc_msg_id_panel); -- v3

            -- Enable the executor waiting log after receiving its last command
            if v_disabled_msg_id_exe_wait and v_dut_if_field_pos_is_last and i = v_num_transfers - 1 then
              enable_sbi_vvc_msg_id(ID_CMD_EXECUTOR_WAIT); -- v3
            end if;
            v_cmd_idx     := get_last_received_cmd_idx(SBI_VVCT, GC_PHY_VVC_INSTANCE_IDX, NA, GC_SCOPE);

            await_completion(SBI_VVCT, GC_PHY_VVC_INSTANCE_IDX, v_cmd_idx, GC_MAX_NUM_WORDS * GC_PHY_MAX_ACCESS_TIME, "HVVC: Wait for write to finish.", GC_SCOPE);

            v_dut_address := v_dut_address + v_dut_address_increment;
          end loop;

        when RECEIVE =>
          -- Loop through transfers
          for i in 0 to v_num_transfers - 1 loop
            sbi_read(SBI_VVCT, GC_PHY_VVC_INSTANCE_IDX, v_dut_address, "HVVC: Read data via SBI.", GC_SCOPE, v_hvvc_msg_id_panel); -- v3

            -- Enable the executor waiting log after receiving its last command
            if v_disabled_msg_id_exe_wait and v_dut_if_field_pos_is_last and i = v_num_transfers - 1 then
              enable_sbi_vvc_msg_id(ID_CMD_EXECUTOR_WAIT); -- v3
            end if;
            v_cmd_idx := get_last_received_cmd_idx(SBI_VVCT, GC_PHY_VVC_INSTANCE_IDX, NA, GC_SCOPE);

            await_completion(SBI_VVCT, GC_PHY_VVC_INSTANCE_IDX, v_cmd_idx, GC_MAX_NUM_WORDS * GC_PHY_MAX_ACCESS_TIME, "HVVC: Wait for read to finish.", GC_SCOPE);

            fetch_result(SBI_VVCT, GC_PHY_VVC_INSTANCE_IDX, v_cmd_idx, v_sbi_received_data, "HVVC: Fetching received data.", TB_ERROR, GC_SCOPE, v_hvvc_msg_id_panel); -- v3

            v_data_slv(v_dut_data_width * (i + 1) - 1 downto v_dut_data_width * i) := v_sbi_received_data(v_dut_data_width - 1 downto 0);
            v_dut_address                                                          := v_dut_address + v_dut_address_increment;
          end loop;

          -- Convert from std_logic_vector to t_slv_array (word endianness is LOWER_WORD_RIGHT)
          bridge_to_hvvc.data_words(0 to hvvc_to_bridge.num_data_words - 1) <= convert_slv_to_slv_array(v_data_slv(hvvc_to_bridge.num_data_words * c_data_words_width - 1 downto 0), c_data_words_width);

        when others =>
          alert(TB_ERROR, "Unsupported operation");

      end case;

      -- Enable the interpreter waiting log after receiving its last command
      if v_disabled_msg_id_int_wait and v_dut_if_field_pos_is_last then
        enable_sbi_vvc_msg_id(ID_CMD_INTERPRETER_WAIT); -- v3
      end if;

      gen_pulse(bridge_to_hvvc.trigger, 0 ns, "Pulsing bridge_to_hvvc trigger", GC_SCOPE, ID_NEVER);
    end loop;

  end process;

end architecture SBI;
