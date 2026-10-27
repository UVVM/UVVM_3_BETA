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

---------------------------------------------------------------------------------------------
-- Description : See library quick reference (under 'doc') and README-file(s)
---------------------------------------------------------------------------------------------

--================================================================================================================================
--  Support package
--================================================================================================================================
library uvvm_util;
use uvvm_util.adaptations_pkg.all;
use uvvm_util.types_pkg.all;
use work.avalon_st_bfm_pkg.all;
use work.td_target_support_pkg.all;

package vvc_methods_support_pkg is

  --==========================================================================================
  -- Types and constants for the AVALON_ST VVC
  --==========================================================================================
  constant C_VVC_NAME : string := "AVALON_ST_VVC";

  signal AVALON_ST_VVCT : t_vvc_target_record := set_vvc_target_defaults(C_VVC_NAME);
  alias THIS_VVCT       : t_vvc_target_record is AVALON_ST_VVCT;
  alias t_bfm_config is t_avalon_st_bfm_config;

  -- Type found in UVVM-Util types_pkg
  constant C_AVALON_ST_INTER_BFM_DELAY_DEFAULT : t_inter_bfm_delay := (
    delay_type                         => NO_DELAY,
    delay_in_time                      => 0 ns,
    inter_bfm_delay_violation_severity => WARNING
  );

  -- Record for configuring the severity of unwanted transaction detection for each monitored DUT output
  type t_avalon_st_unwanted_transaction is record
    channel         : t_alert_level;
    data            : t_alert_level;
    data_error      : t_alert_level;
    valid           : t_alert_level;
    empty           : t_alert_level;
    end_of_packet   : t_alert_level;
    start_of_packet : t_alert_level;
  end record t_avalon_st_unwanted_transaction;

  constant C_AVALON_ST_UNWANTED_TRANSACTION : t_avalon_st_unwanted_transaction := (
    channel         => NO_ALERT,
    data            => NO_ALERT,
    data_error      => NO_ALERT,
    valid           => ERROR,
    empty           => NO_ALERT,
    end_of_packet   => NO_ALERT,
    start_of_packet => NO_ALERT
  );

  type t_vvc_config is record
    inter_bfm_delay                       : t_inter_bfm_delay; -- Minimum delay between BFM accesses from the VVC. If parameter delay_type is set to NO_DELAY, BFM accesses will be back to back, i.e. no delay.
    bfm_config                            : t_bfm_config;      -- Configuration for the BFM. See BFM quick reference.
    ready_latency                         : natural;           -- Number of cycles between ready assertion and valid assertion
    unwanted_transaction_checking_enabled : boolean; -- Enable unwanted transaction checking
    unwanted_transaction_severity         : t_avalon_st_unwanted_transaction; -- Severity of alert to be initiated if unwanted transaction on the DUT outputs is detected
  end record;

  constant C_AVALON_ST_VVC_CONFIG_DEFAULT : t_vvc_config := (
    inter_bfm_delay                       => C_AVALON_ST_INTER_BFM_DELAY_DEFAULT,
    bfm_config                            => C_AVALON_ST_BFM_CONFIG_DEFAULT,
    ready_latency                         => 0,
    unwanted_transaction_checking_enabled => C_UNWANTED_TRANSACTION_CHECKING_DEFAULT,
    unwanted_transaction_severity         => C_AVALON_ST_UNWANTED_TRANSACTION
  );

  type t_vvc_status is record
    current_cmd_idx  : natural;
    previous_cmd_idx : natural;
    pending_cmd_cnt  : natural;
  end record;

  constant C_VVC_STATUS_DEFAULT : t_vvc_status := (
    current_cmd_idx  => 0,
    previous_cmd_idx => 0,
    pending_cmd_cnt  => 0
  );

end package vvc_methods_support_pkg;

--================================================================================================================================
--  Generic package instantiations
--================================================================================================================================
----------------------------------------------------------------------
-- Protected type: t_vvc_status
----------------------------------------------------------------------
library uvvm_util;
use work.vvc_methods_support_pkg.all;
use work.vvc_transaction_pkg.all;

package protected_vvc_status_pkg is new uvvm_util.protected_generic_types_pkg
  generic map(
    t_generic_element   => t_vvc_status,
    GC_GENERIC_DEFAULT  => C_VVC_STATUS_DEFAULT,
    GC_MAX_INSTANCE_NUM => C_VVC_MAX_INSTANCE_NUM
  );

----------------------------------------------------------------------
-- Protected type: t_vvc_config
----------------------------------------------------------------------
library uvvm_util;
use work.vvc_methods_support_pkg.all;
use work.vvc_transaction_pkg.all;

package protected_vvc_config_pkg is new uvvm_util.protected_generic_types_pkg
  generic map(
    t_generic_element   => t_vvc_config,
    GC_GENERIC_DEFAULT  => C_AVALON_ST_VVC_CONFIG_DEFAULT,
    GC_MAX_INSTANCE_NUM => C_VVC_MAX_INSTANCE_NUM
  );

----------------------------------------------------------------------
-- Protected type: t_msg_id_panel
----------------------------------------------------------------------
library uvvm_util;
use uvvm_util.types_pkg.all;
use uvvm_util.adaptations_pkg.all;
use work.vvc_transaction_pkg.all;

package protected_msg_id_panel_pkg is new uvvm_util.protected_generic_types_pkg
  generic map(
    t_generic_element   => t_msg_id_panel,
    GC_GENERIC_DEFAULT  => C_VVC_MSG_ID_PANEL_DEFAULT,
    GC_MAX_INSTANCE_NUM => C_VVC_MAX_INSTANCE_NUM
  );

--================================================================================================================================
--  VVC methods package
--================================================================================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library uvvm_vvc_framework;
use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

use work.avalon_st_bfm_pkg.all;
use work.vvc_transaction_pkg.all;
use work.protected_transaction_group_pkg.all;
use work.vvc_cmd_pkg.all;
use work.vvc_cmd_shared_variables_pkg.all;
use work.td_target_support_pkg.all;
use work.vvc_methods_support_pkg.all;
use work.protected_vvc_status_pkg.all;
use work.protected_vvc_config_pkg.all;
use work.protected_msg_id_panel_pkg.all;

package vvc_methods_pkg is

  shared variable shared_avalon_st_vvc_status       : work.protected_vvc_status_pkg.t_generic_array;
  shared variable shared_avalon_st_vvc_config       : work.protected_vvc_config_pkg.t_generic_array;
  shared variable shared_avalon_st_vvc_msg_id_panel : work.protected_msg_id_panel_pkg.t_generic_array;

  alias shared_vvc_status       is shared_avalon_st_vvc_status;       -- This alias is for internal use in the VVC
  alias shared_vvc_config       is shared_avalon_st_vvc_config;       -- This alias is for internal use in the VVC
  alias shared_vvc_msg_id_panel is shared_avalon_st_vvc_msg_id_panel; -- This alias is for internal use in the VVC

  --==========================================================================================
  -- Methods dedicated to this VVC
  -- - These procedures are called from the testbench in order for the VVC to execute
  --   BFM calls towards the given interface. The VVC interpreter will queue these calls
  --   and then the VVC executor will fetch the commands from the queue and handle the
  --   actual BFM execution.
  --==========================================================================================
  ---------------------------------------------------------------------------------------------
  -- Avalon-ST Transmit
  ---------------------------------------------------------------------------------------------
  procedure avalon_st_transmit(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant channel_value       : in std_logic_vector;
    constant data_array          : in t_slv_array;
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  procedure avalon_st_transmit(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant data_array          : in t_slv_array;
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  ---------------------------------------------------------------------------------------------
  -- Avalon-ST Receive
  ---------------------------------------------------------------------------------------------
  procedure avalon_st_receive(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant data_array_len      : in natural;
    constant data_word_size      : in natural;
    constant data_routing        : in t_data_routing;
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL; -- Only intended for usage by parent HVVCs
    constant ext_proc_call       : in string         := ""
  );

  procedure avalon_st_receive(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant data_array_len      : in natural;
    constant data_word_size      : in natural;
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  procedure avalon_st_receive(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant data_word_size      : in natural;
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  ---------------------------------------------------------------------------------------------
  -- Avalon-ST Expect
  ---------------------------------------------------------------------------------------------
  procedure avalon_st_expect(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant channel_exp         : in std_logic_vector;
    constant data_exp            : in t_slv_array;
    constant msg                 : in string;
    constant alert_level         : in t_alert_level  := error;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  procedure avalon_st_expect(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant data_exp            : in t_slv_array;
    constant msg                 : in string;
    constant alert_level         : in t_alert_level  := error;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  --==========================================================================================
  -- Transaction info methods
  --==========================================================================================
  procedure set_global_vvc_transaction_info(
    signal   vvc_transaction_info_trigger : inout std_logic;
    variable vvc_transaction_info_group   : inout work.protected_transaction_group_pkg.t_generic_array; -- v3 t_transaction_group;
    constant instance_idx                 : in natural;
    constant channel                      : in t_channel;
    constant vvc_cmd                      : in t_vvc_cmd_record;
    constant vvc_config                   : in t_vvc_config;
    constant transaction_status           : in t_transaction_status;
    constant scope                        : in string := C_VVC_CMD_SCOPE_DEFAULT);

  procedure set_global_vvc_transaction_info(
    signal   vvc_transaction_info_trigger : inout std_logic;
    variable vvc_transaction_info_group   : inout work.protected_transaction_group_pkg.t_generic_array; -- v3 t_transaction_group;
    constant instance_idx                 : in natural;
    constant channel                      : in t_channel;
    constant vvc_cmd                      : in t_vvc_cmd_record;
    constant vvc_result                   : in t_vvc_result;
    constant transaction_status           : in t_transaction_status;
    constant scope                        : in string := C_VVC_CMD_SCOPE_DEFAULT);

  procedure reset_vvc_transaction_info(
    variable vvc_transaction_info_group : inout work.protected_transaction_group_pkg.t_generic_array; -- v3 t_transaction_group;
    constant instance_idx               : in natural;
    constant channel                    : in t_channel;
    constant vvc_cmd                    : in t_vvc_cmd_record);

end package vvc_methods_pkg;

package body vvc_methods_pkg is

  --==========================================================================================
  -- Methods dedicated to this VVC
  --==========================================================================================
  ---------------------------------------------------------------------------------------------
  -- Avalon-ST Transmit
  ---------------------------------------------------------------------------------------------
  procedure avalon_st_transmit(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant channel_value       : in std_logic_vector;
    constant data_array          : in t_slv_array;
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant C_PROC_NAME : string := "avalon_st_transmit";
    constant C_PROC_CALL : string := C_PROC_NAME & "(" & to_string(VVCT, vvc_instance_idx) -- First part common for all
                                     & ", " & to_string(data_array'length) & " words, ch:" & to_string(channel_value, DEC, KEEP_LEADING_0) & ")";
    constant C_DATA_WORD_SIZE  : natural                                                                := data_array(data_array'low)'length;
    variable v_local_vvc_cmd   : t_vvc_cmd_record                                                       := shared_vvc_cmd.get(vvc_instance_idx);
    variable v_normalized_chan : std_logic_vector(C_VVC_CMD_CHAN_MAX_LENGTH - 1 downto 0)               := normalize_and_check(channel_value, v_local_vvc_cmd.channel_value, ALLOW_NARROWER, "channel", "shared_vvc_cmd.channel", C_PROC_CALL & ". " & msg);
    variable v_normalized_data : t_slv_array(0 to data_array'length - 1)(C_DATA_WORD_SIZE - 1 downto 0) := data_array;
    variable v_msg_id_panel    : t_msg_id_panel                                                         := shared_msg_id_panel.get(VOID);
  begin
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, C_PROC_CALL, msg, QUEUED, TRANSMIT);

    -- v3
    v_local_vvc_cmd                      := shared_vvc_cmd.get(vvc_instance_idx);
    v_local_vvc_cmd.channel_value        := v_normalized_chan;
    for i in 0 to v_normalized_data'high loop
      v_local_vvc_cmd.data_array(i)(C_DATA_WORD_SIZE - 1 downto 0) := v_normalized_data(i);
    end loop;
    v_local_vvc_cmd.data_array_length    := v_normalized_data'length;
    v_local_vvc_cmd.data_array_word_size := C_DATA_WORD_SIZE;
    v_local_vvc_cmd.parent_msg_id_panel  := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(VVCT, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure;

  procedure avalon_st_transmit(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant data_array          : in t_slv_array;
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant C_CHANNEL_VALUE : std_logic_vector(C_VVC_CMD_CHAN_MAX_LENGTH - 1 downto 0) := (others => '0');
  begin
    avalon_st_transmit(VVCT, vvc_instance_idx, C_CHANNEL_VALUE, data_array, msg, scope, parent_msg_id_panel);
  end procedure;

  ---------------------------------------------------------------------------------------------
  -- Avalon-ST Receive
  ---------------------------------------------------------------------------------------------
  procedure avalon_st_receive(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant data_array_len      : in natural;
    constant data_word_size      : in natural;
    constant data_routing        : in t_data_routing;
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL; -- Only intended for usage by parent HVVCs
    constant ext_proc_call       : in string         := ""
  ) is
    constant C_PROC_NAME       : string := "avalon_st_receive";
    constant C_PROC_CALL       : string := C_PROC_NAME & "(" & to_string(VVCT, vvc_instance_idx) -- First part common for all
                                           & ", " & to_upper(to_string(data_routing)) & ")";
    constant C_LOCAL_PROC_CALL : string := return_string1_if_true_otherwise_string2(C_PROC_CALL, ext_proc_call, ext_proc_call = "");
    variable v_local_vvc_cmd   : t_vvc_cmd_record := shared_vvc_cmd.get(vvc_instance_idx);
    variable v_msg_id_panel    : t_msg_id_panel   := shared_msg_id_panel.get(VOID);
  begin
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, C_LOCAL_PROC_CALL, msg, QUEUED, RECEIVE);

    -- v3
    v_local_vvc_cmd                      := shared_vvc_cmd.get(vvc_instance_idx);
    v_local_vvc_cmd.data_array_length    := data_array_len;
    v_local_vvc_cmd.data_array_word_size := data_word_size;
    v_local_vvc_cmd.parent_msg_id_panel  := parent_msg_id_panel;
    v_local_vvc_cmd.data_routing         := data_routing;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(VVCT, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure;

  procedure avalon_st_receive(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant data_array_len      : in natural;
    constant data_word_size      : in natural;
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant C_PROC_NAME : string := "avalon_st_receive";
    constant C_PROC_CALL : string := C_PROC_NAME & "(" & to_string(VVCT, vvc_instance_idx) -- First part common for all
                                     & ")";
  begin
    -- call overloaded procedure
    avalon_st_receive(VVCT, vvc_instance_idx, data_array_len, data_word_size, TO_BUFFER, msg, scope, parent_msg_id_panel, C_PROC_CALL);
  end procedure;

  procedure avalon_st_receive(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant data_word_size      : in natural;
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant C_PROC_NAME            : string := "avalon_st_receive";
    constant C_PROC_CALL            : string := C_PROC_NAME & "(" & to_string(VVCT, vvc_instance_idx) -- First part common for all
                                                & ")";
    constant C_UNKNOWN_DATA_LENGTH  : natural := C_VVC_CMD_DATA_MAX_WORDS +1;
  begin
    -- Check if bfm is configured for packet transfer, this overload is only allowed for packet transfers (requires end_of_packet)
    if shared_vvc_config.get(vvc_instance_idx).bfm_config.use_packet_transfer = false then
      alert(TB_ERROR, "Overload of avalon_st_receive() without data_array_len-parameter is not allowed for stream transfer");
    else
      -- Call overloaded procedure, using max words +1 as data_array_len
      avalon_st_receive(VVCT, vvc_instance_idx, C_UNKNOWN_DATA_LENGTH, data_word_size, TO_BUFFER, msg, scope, parent_msg_id_panel, C_PROC_CALL);
    end if;
  end procedure;

  ---------------------------------------------------------------------------------------------
  -- Avalon-ST Expect
  ---------------------------------------------------------------------------------------------
  procedure avalon_st_expect(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant channel_exp         : in std_logic_vector;
    constant data_exp            : in t_slv_array;
    constant msg                 : in string;
    constant alert_level         : in t_alert_level  := error;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant C_PROC_NAME : string := "avalon_st_expect";
    constant C_PROC_CALL : string := C_PROC_NAME & "(" & to_string(VVCT, vvc_instance_idx) -- First part common for all
                                     & ", " & to_string(data_exp'length) & " words, ch:" & to_string(channel_exp, DEC, KEEP_LEADING_0) & ")";
    constant C_DATA_WORD_SIZE  : natural                                                              := data_exp(data_exp'low)'length;
    variable v_local_vvc_cmd   : t_vvc_cmd_record                                                     := shared_vvc_cmd.get(vvc_instance_idx);
    variable v_normalized_chan : std_logic_vector(C_VVC_CMD_CHAN_MAX_LENGTH - 1 downto 0)             := normalize_and_check(channel_exp, v_local_vvc_cmd.channel_value, ALLOW_NARROWER, "channel", "shared_vvc_cmd.channel", C_PROC_CALL & ". " & msg);
    variable v_normalized_data : t_slv_array(0 to data_exp'length - 1)(C_DATA_WORD_SIZE - 1 downto 0) := data_exp;
    variable v_msg_id_panel    : t_msg_id_panel                                                       := shared_msg_id_panel.get(VOID);
  begin
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, C_PROC_CALL, msg, QUEUED, EXPECT);

    -- v3
    v_local_vvc_cmd                      := shared_vvc_cmd.get(vvc_instance_idx);
    v_local_vvc_cmd.channel_value        := v_normalized_chan;
    for i in 0 to v_normalized_data'high loop
      v_local_vvc_cmd.data_array(i)(C_DATA_WORD_SIZE - 1 downto 0) := v_normalized_data(i);
    end loop;
    v_local_vvc_cmd.data_array_length    := v_normalized_data'length;
    v_local_vvc_cmd.data_array_word_size := C_DATA_WORD_SIZE;
    v_local_vvc_cmd.alert_level          := alert_level;
    v_local_vvc_cmd.parent_msg_id_panel  := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(VVCT, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure;

  procedure avalon_st_expect(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant data_exp            : in t_slv_array;
    constant msg                 : in string;
    constant alert_level         : in t_alert_level  := error;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant C_CHANNEL_EXP : std_logic_vector(C_VVC_CMD_CHAN_MAX_LENGTH - 1 downto 0) := (others => '0');
  begin
    avalon_st_expect(VVCT, vvc_instance_idx, C_CHANNEL_EXP, data_exp, msg, alert_level, scope, parent_msg_id_panel);
  end procedure;

  --==========================================================================================
  -- Transaction info methods
  --==========================================================================================
  procedure set_global_vvc_transaction_info(
    signal   vvc_transaction_info_trigger : inout std_logic;
    variable vvc_transaction_info_group   : inout work.protected_transaction_group_pkg.t_generic_array; -- v3 t_transaction_group;
    constant instance_idx                 : in natural;
    constant channel                      : in t_channel;
    constant vvc_cmd                      : in t_vvc_cmd_record;
    constant vvc_config                   : in t_vvc_config;
    constant transaction_status           : in t_transaction_status;
    constant scope                        : in string := C_VVC_CMD_SCOPE_DEFAULT
  ) is
    variable v_transaction_info_group : t_transaction_group := vvc_transaction_info_group.get(instance_idx, channel);
  begin
    case vvc_cmd.operation is
      when TRANSMIT | RECEIVE | EXPECT =>
        v_transaction_info_group.bt.operation          := vvc_cmd.operation;
        v_transaction_info_group.bt.channel_value      := vvc_cmd.channel_value;
        v_transaction_info_group.bt.data_array         := vvc_cmd.data_array;
        v_transaction_info_group.bt.num_words          := vvc_cmd.data_array_length;
        v_transaction_info_group.bt.word_length        := vvc_cmd.data_array_word_size;
        v_transaction_info_group.bt.vvc_meta.msg       := vvc_cmd.msg;
        v_transaction_info_group.bt.vvc_meta.cmd_idx   := vvc_cmd.cmd_idx;
        v_transaction_info_group.bt.transaction_status := transaction_status;

        vvc_transaction_info_group.set(v_transaction_info_group, instance_idx, channel);
        gen_pulse(vvc_transaction_info_trigger, 0 ns, "pulsing global vvc transaction info trigger", scope, ID_NEVER);

      when others =>
        alert(TB_ERROR, "VVC operation not recognized", scope);
    end case;

    wait for 0 ns;
  end procedure set_global_vvc_transaction_info;

  procedure set_global_vvc_transaction_info(
    signal   vvc_transaction_info_trigger : inout std_logic;
    variable vvc_transaction_info_group   : inout work.protected_transaction_group_pkg.t_generic_array; -- v3 t_transaction_group;
    constant instance_idx                 : in natural;
    constant channel                      : in t_channel;
    constant vvc_cmd                      : in t_vvc_cmd_record;
    constant vvc_result                   : in t_vvc_result;
    constant transaction_status           : in t_transaction_status;
    constant scope                        : in string := C_VVC_CMD_SCOPE_DEFAULT
  ) is
    variable v_transaction_info_group : t_transaction_group := vvc_transaction_info_group.get(instance_idx, channel);
  begin
    case vvc_cmd.operation is
      when RECEIVE =>
        v_transaction_info_group.bt.channel_value      := vvc_result.channel_value;
        v_transaction_info_group.bt.data_array         := vvc_result.data_array;
        v_transaction_info_group.bt.num_words          := vvc_result.data_array_length;
        v_transaction_info_group.bt.word_length        := vvc_result.data_array_word_size;
        v_transaction_info_group.bt.transaction_status := transaction_status;

        vvc_transaction_info_group.set(v_transaction_info_group, instance_idx, channel);
        gen_pulse(vvc_transaction_info_trigger, 0 ns, "pulsing global vvc transaction info trigger", scope, ID_NEVER);

      when others =>
        alert(TB_ERROR, "VVC operation does not update vvc_result", scope);
    end case;

    wait for 0 ns;
  end procedure set_global_vvc_transaction_info;

  procedure reset_vvc_transaction_info(
    variable vvc_transaction_info_group : inout work.protected_transaction_group_pkg.t_generic_array; -- v3 t_transaction_group;
    constant instance_idx               : in natural;
    constant channel                    : in t_channel;
    constant vvc_cmd                    : in t_vvc_cmd_record
  ) is
    variable v_transaction_info_group : t_transaction_group := vvc_transaction_info_group.get(instance_idx, channel);
  begin
    case vvc_cmd.operation is
      when TRANSMIT | RECEIVE | EXPECT =>
        v_transaction_info_group.bt := C_BASE_TRANSACTION_SET_DEFAULT;
        vvc_transaction_info_group.set(v_transaction_info_group, instance_idx, channel);

      when others =>
        null;
    end case;

    wait for 0 ns;
  end procedure reset_vvc_transaction_info;

end package body vvc_methods_pkg;
