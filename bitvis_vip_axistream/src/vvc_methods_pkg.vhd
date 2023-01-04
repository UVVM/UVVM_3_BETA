--================================================================================================================================
-- Copyright 2020 Bitvis
-- Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0 and in the provided LICENSE.TXT.
--
-- Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on
-- an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and limitations under the License.
--================================================================================================================================
-- Note : Any functionality not explicitly described in the documentation is subject to change at any time
----------------------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library uvvm_vvc_framework;
use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

use work.axistream_bfm_pkg.all;
use work.vvc_cmd_pkg.all;
use work.td_target_support_pkg.all;
use work.transaction_pkg.all;

--========================================================================================================================
--========================================================================================================================
package vvc_methods_pkg is

  --========================================================================================================================
  -- Types and constants for the AXISTREAM VVC
  --========================================================================================================================
  constant C_VVC_NAME : string := "AXISTREAM_VVC";

  signal AXISTREAM_VVCT : t_vvc_target_record := set_vvc_target_defaults(C_VVC_NAME);
  alias THIS_VVCT       : t_vvc_target_record is AXISTREAM_VVCT;
  alias t_bfm_config is t_axistream_bfm_config;

  -- Type found in UVVM-Util types_pkg
  constant C_AXISTREAM_INTER_BFM_DELAY_DEFAULT : t_inter_bfm_delay := (
    delay_type                         => NO_DELAY,
    delay_in_time                      => 0 ns,
    inter_bfm_delay_violation_severity => warning
  );

  type t_vvc_config is record
    inter_bfm_delay                       : t_inter_bfm_delay;      -- Minimum delay between BFM accesses from the VVC. If parameter delay_type is set to NO_DELAY, BFM accesses will be back to back, i.e. no delay.
    cmd_queue_count_max                   : natural;                -- Maximum pending number in command queue before queue is full. Adding additional commands will result in an ERROR.
    cmd_queue_count_threshold             : natural;                -- An alert with severity 'cmd_queue_count_threshold_severity' will be issued if command queue exceeds this count. Used for early warning if command queue is almost full. Will be ignored if set to 0.
    cmd_queue_count_threshold_severity    : t_alert_level;          -- Severity of alert to be initiated if exceeding cmd_queue_count_threshold
    result_queue_count_max                : natural;                -- Maximum number of unfetched results before result_queue is full.
    result_queue_count_threshold_severity : t_alert_level;          -- An alert with severity 'result_queue_count_threshold_severity' will be issued if command queue exceeds this count. Used for early warning if result queue is almost full. Will be ignored if set to 0.
    result_queue_count_threshold          : natural;                -- Severity of alert to be initiated if exceeding result_queue_count_threshold
    bfm_config                            : t_axistream_bfm_config; -- Configuration for the BFM. See BFM quick reference
  end record;

  constant C_AXISTREAM_VVC_CONFIG_DEFAULT : t_vvc_config := (
    inter_bfm_delay                       => C_AXISTREAM_INTER_BFM_DELAY_DEFAULT,
    cmd_queue_count_max                   => C_CMD_QUEUE_COUNT_MAX,
    cmd_queue_count_threshold             => C_CMD_QUEUE_COUNT_THRESHOLD,
    cmd_queue_count_threshold_severity    => C_CMD_QUEUE_COUNT_THRESHOLD_SEVERITY,
    result_queue_count_max                => C_RESULT_QUEUE_COUNT_MAX,
    result_queue_count_threshold_severity => C_RESULT_QUEUE_COUNT_THRESHOLD_SEVERITY,
    result_queue_count_threshold          => C_RESULT_QUEUE_COUNT_THRESHOLD,
    bfm_config                            => C_AXISTREAM_BFM_CONFIG_DEFAULT
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

  type t_transaction_info is record
    operation      : t_operation;
    numPacketsSent : natural;
    msg            : string(1 to C_VVC_CMD_STRING_MAX_LENGTH);
  end record;

  type t_transaction_info_array is array (natural range <>) of t_transaction_info;

  constant C_TRANSACTION_INFO_DEFAULT : t_transaction_info := (
    operation      => NO_OPERATION,
    numPacketsSent => 0,
    msg            => (others => ' ')
  );

  -- v3
  package protected_vvc_status_pkg is new uvvm_util.protected_generic_types_pkg
    generic map(t_generic_element => t_vvc_status,
                c_generic_default => C_VVC_STATUS_DEFAULT);
  use protected_vvc_status_pkg.all;
  shared variable shared_axistream_vvc_status : protected_vvc_status_pkg.t_prot_generic_array;
  alias shared_vvc_status is shared_axistream_vvc_status; -- This alias is for internal use in the VVC

  package protected_vvc_config_pkg is new uvvm_util.protected_generic_types_pkg
    generic map(t_generic_element => t_vvc_config,
                c_generic_default => C_AXISTREAM_VVC_CONFIG_DEFAULT);
  use protected_vvc_config_pkg.all;
  shared variable shared_axistream_vvc_config : protected_vvc_config_pkg.t_prot_generic_array;
  alias shared_vvc_config is shared_axistream_vvc_config; -- This alias is for internal use in the VVC

  package protected_msg_id_panel_pkg is new uvvm_util.protected_generic_types_pkg
    generic map(t_generic_element => t_msg_id_panel,
                c_generic_default => C_VVC_MSG_ID_PANEL_DEFAULT);
  use protected_msg_id_panel_pkg.all;
  shared variable shared_axistream_vvc_msg_id_panel : protected_msg_id_panel_pkg.t_prot_generic_array;
  alias shared_vvc_msg_id_panel is shared_axistream_vvc_msg_id_panel; -- This alias is for internal use in the VVC

  --==========================================================================================
  -- Methods dedicated to this VVC 
  -- - These procedures are called from the testbench in order for the VVC to execute
  --   BFM calls towards the given interface. The VVC interpreter will queue these calls
  --   and then the VVC executor will fetch the commands from the queue and handle the
  --   actual BFM execution.
  --   For details on how the BFM procedures work, see the QuickRef.
  --==========================================================================================

  --------------------------------------------------------
  --
  -- AXIStream Transmit
  --
  --------------------------------------------------------
  procedure axistream_transmit(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant data_array          : in t_slv_array;
    constant user_array          : in t_user_array; -- If you need support for more bits per data byte, edit axistream_bfm_pkg.t_user_array
    constant strb_array          : in t_strb_array; -- If you need support for more bits per data byte, edit axistream_bfm_pkg.t_strb_array
    constant id_array            : in t_id_array;   -- If you need support for more bits per data byte, edit axistream_bfm_pkg.t_id_array
    constant dest_array          : in t_dest_array; -- If you need support for more bits per data byte, edit axistream_bfm_pkg.t_dest_array
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );
  procedure axistream_transmit(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant data_array          : in std_logic_vector;
    constant user_array          : in t_user_array; -- If you need support for more bits per data byte, edit axistream_bfm_pkg.t_user_array
    constant strb_array          : in t_strb_array; -- If you need support for more bits per data byte, edit axistream_bfm_pkg.t_strb_array
    constant id_array            : in t_id_array;   -- If you need support for more bits per data byte, edit axistream_bfm_pkg.t_id_array
    constant dest_array          : in t_dest_array; -- If you need support for more bits per data byte, edit axistream_bfm_pkg.t_dest_array
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  procedure axistream_transmit(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant data_array          : in t_slv_array;
    constant user_array          : in t_user_array; -- If you need support for more bits per data byte, edit axistream_bfm_pkg.t_user_array
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );
  procedure axistream_transmit(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant data_array          : in std_logic_vector;
    constant user_array          : in t_user_array; -- If you need support for more bits per data byte, edit axistream_bfm_pkg.t_user_array
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  procedure axistream_transmit(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant data_array          : in t_slv_array;
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );
  procedure axistream_transmit(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant data_array          : in std_logic_vector;
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  --------------------------------------------------------
  --
  -- AXIStream Receive
  --
  --------------------------------------------------------
  procedure axistream_receive(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant data_routing        : in t_data_routing;
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );
  procedure axistream_receive(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  --------------------------------------------------------
  --
  -- AXIStream Expect
  --
  --------------------------------------------------------
  procedure axistream_expect(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant data_array          : in t_slv_array;
    constant user_array          : in t_user_array;
    constant strb_array          : in t_strb_array;
    constant id_array            : in t_id_array;
    constant dest_array          : in t_dest_array;
    constant msg                 : in string;
    constant alert_level         : in t_alert_level  := error;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );
  procedure axistream_expect(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant data_array          : in std_logic_vector;
    constant user_array          : in t_user_array;
    constant strb_array          : in t_strb_array;
    constant id_array            : in t_id_array;
    constant dest_array          : in t_dest_array;
    constant msg                 : in string;
    constant alert_level         : in t_alert_level  := error;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  procedure axistream_expect(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant data_array          : in t_slv_array;
    constant user_array          : in t_user_array;
    constant msg                 : in string;
    constant alert_level         : in t_alert_level  := error;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );
  procedure axistream_expect(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant data_array          : in std_logic_vector;
    constant user_array          : in t_user_array;
    constant msg                 : in string;
    constant alert_level         : in t_alert_level  := error;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  procedure axistream_expect(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant data_array          : in t_slv_array;
    constant msg                 : in string;
    constant alert_level         : in t_alert_level  := error;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );
  procedure axistream_expect(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant data_array          : in std_logic_vector;
    constant msg                 : in string;
    constant alert_level         : in t_alert_level  := error;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  --==============================================================================
  -- Transaction info methods
  --==============================================================================
  procedure set_global_vvc_transaction_info(
    signal   vvc_transaction_info_trigger : inout std_logic;
    variable vvc_transaction_info_group   : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx                 : in natural;
    constant channel                      : in t_channel;
    constant vvc_cmd                      : in t_vvc_cmd_record;
    constant vvc_config                   : in t_vvc_config;
    constant scope                        : in string := C_VVC_CMD_SCOPE_DEFAULT);

  procedure reset_vvc_transaction_info(
    variable vvc_transaction_info_group : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx               : in natural;
    constant channel                    : in t_channel;
    constant vvc_cmd                    : in t_vvc_cmd_record);

  --==============================================================================
  -- VVC Activity
  --==============================================================================
  procedure update_vvc_activity_register(signal   global_trigger_vvc_activity_register : inout std_logic;
                                         variable vvc_status                           : inout protected_vvc_status_pkg.t_prot_generic_array;
                                         constant instance_idx                         : in natural;
                                         constant channel                              : in t_channel;
                                         constant activity                             : in t_activity;
                                         constant entry_num_in_vvc_activity_register   : in integer;
                                         constant last_cmd_idx_executed                : in natural;
                                         constant command_queue_is_empty               : in boolean;
                                         constant scope                                : in string := C_VVC_NAME);

end package vvc_methods_pkg;

package body vvc_methods_pkg is

  --========================================================================================================================
  -- Methods dedicated to this VVC
  --========================================================================================================================

  --------------------------------------------------------
  --
  -- AXIStream Transmit
  --
  --------------------------------------------------------
  procedure axistream_transmit(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant data_array          : in t_slv_array;
    constant user_array          : in t_user_array; -- If you need support for more bits per data byte, edit axistream_bfm_pkg.t_user_array
    constant strb_array          : in t_strb_array; -- If you need support for more bits per data byte, edit axistream_bfm_pkg.t_strb_array
    constant id_array            : in t_id_array;   -- If you need support for more bits per data byte, edit axistream_bfm_pkg.t_id_array
    constant dest_array          : in t_dest_array; -- If you need support for more bits per data byte, edit axistream_bfm_pkg.t_dest_array
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant C_DATA_ARRAY_BYTES_PER_WORD : natural := data_array(data_array'low)'length / 8;
    constant C_PROC_NAME : string := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant C_PROC_CALL : string := C_PROC_NAME & "(" & to_string(VVCT, vvc_instance_idx) -- First part common for all
                                     & ", " & to_string(data_array'length) & " words[" & to_string(C_DATA_ARRAY_BYTES_PER_WORD*8) & "b])";

    variable v_local_vvc_cmd   : t_vvc_cmd_record := shared_vvc_cmd.get(vvc_instance_idx);
    variable v_msg_id_panel    : t_msg_id_panel   := shared_msg_id_panel.get(VOID);
    variable v_vvc_config      : t_vvc_config     := shared_vvc_config.get(vvc_instance_idx);
    variable v_data_byte_array : t_slv_array(0 to (data_array'length*C_DATA_ARRAY_BYTES_PER_WORD)-1)(7 downto 0);
    variable v_check_ok        : boolean          := true;
  begin
    v_check_ok := v_check_ok and check_value(data_array'length > 0, TB_ERROR, "Sanity check: data_array length must be > 0", scope, ID_NEVER, shared_vvc_msg_id_panel.get(vvc_instance_idx), C_PROC_CALL); -- Sanity check to avoid confusing fatal error
    v_check_ok := v_check_ok and check_value(data_array(data_array'low)'length mod 8 = 0, TB_ERROR, "Sanity check: Check that data_array word is N*byte", scope, ID_NEVER, shared_vvc_msg_id_panel.get(vvc_instance_idx), C_PROC_CALL);
    if not(v_check_ok) then
      return;
    end if;

    -- Convert SLV with variable word-width to byte-width
    v_data_byte_array := convert_slv_array_to_byte_array(data_array, v_vvc_config.bfm_config.byte_endianness);

    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, C_PROC_CALL, msg, QUEUED, TRANSMIT);

    -- v3
    -- Generate cmd record
    v_local_vvc_cmd                                         := shared_vvc_cmd.get(vvc_instance_idx);
    v_local_vvc_cmd.data_array(0 to v_data_byte_array'high) := v_data_byte_array;
    v_local_vvc_cmd.user_array(0 to user_array'high)        := user_array;
    v_local_vvc_cmd.strb_array(0 to strb_array'high)        := strb_array;
    v_local_vvc_cmd.id_array(0 to id_array'high)            := id_array;
    v_local_vvc_cmd.dest_array(0 to dest_array'high)        := dest_array;
    v_local_vvc_cmd.data_array_length                       := v_data_byte_array'length;
    v_local_vvc_cmd.user_array_length                       := user_array'length;
    v_local_vvc_cmd.strb_array_length                       := strb_array'length;
    v_local_vvc_cmd.id_array_length                         := id_array'length;
    v_local_vvc_cmd.dest_array_length                       := dest_array'length;
    v_local_vvc_cmd.parent_msg_id_panel                     := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(VVCT, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure;

  -- SLV overload
  procedure axistream_transmit(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant data_array          : in std_logic_vector;
    constant user_array          : in t_user_array; -- If you need support for more bits per data byte, edit axistream_bfm_pkg.t_user_array
    constant strb_array          : in t_strb_array; -- If you need support for more bits per data byte, edit axistream_bfm_pkg.t_strb_array
    constant id_array            : in t_id_array;   -- If you need support for more bits per data byte, edit axistream_bfm_pkg.t_id_array
    constant dest_array          : in t_dest_array; -- If you need support for more bits per data byte, edit axistream_bfm_pkg.t_dest_array
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    variable v_data_array : t_slv_array(0 to 0)(data_array'length - 1 downto 0);
  begin
    v_data_array(0) := data_array;
    axistream_transmit(VVCT, vvc_instance_idx, v_data_array, user_array, strb_array, id_array, dest_array, msg, scope, parent_msg_id_panel);
  end procedure;

  -- Overload with default values for strb_array, id_array and dest_array
  procedure axistream_transmit(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant data_array          : in t_slv_array;
    constant user_array          : in t_user_array; -- If you need support for more bits per data byte, edit axistream_bfm_pkg.t_user_array
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    -- Default user data : We don't know C_USER_ARRAY length (how many words to send), so assume worst case: tdata = 8 bits (one data_array byte per word)
    constant C_STRB_ARRAY : t_strb_array(0 to C_VVC_CMD_DATA_MAX_WORDS - 1) := (others => (others => '0'));
    constant C_ID_ARRAY   : t_id_array(0 to C_VVC_CMD_DATA_MAX_WORDS - 1)   := (others => (others => '0'));
    constant C_DEST_ARRAY : t_dest_array(0 to C_VVC_CMD_DATA_MAX_WORDS - 1) := (others => (others => '0'));
  begin
    axistream_transmit(VVCT, vvc_instance_idx, data_array, user_array, C_STRB_ARRAY, C_ID_ARRAY, C_DEST_ARRAY, msg, scope, parent_msg_id_panel);
  end procedure;

  -- SLV overload with default values for strb_array, id_array and dest_array
  procedure axistream_transmit(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant data_array          : in std_logic_vector;
    constant user_array          : in t_user_array; -- If you need support for more bits per data byte, edit axistream_bfm_pkg.t_user_array
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    -- Default user data : We don't know C_USER_ARRAY length (how many words to send), so assume worst case: tdata = 8 bits (one data_array byte per word)
    constant C_STRB_ARRAY : t_strb_array(0 to C_VVC_CMD_DATA_MAX_WORDS - 1) := (others => (others => '0'));
    constant C_ID_ARRAY   : t_id_array(0 to C_VVC_CMD_DATA_MAX_WORDS - 1)   := (others => (others => '0'));
    constant C_DEST_ARRAY : t_dest_array(0 to C_VVC_CMD_DATA_MAX_WORDS - 1) := (others => (others => '0'));
  begin
    axistream_transmit(VVCT, vvc_instance_idx, data_array, user_array, C_STRB_ARRAY, C_ID_ARRAY, C_DEST_ARRAY, msg, scope, parent_msg_id_panel);
  end procedure;

  -- Overload with default values for user_array, strb_array, id_array and dest_array
  procedure axistream_transmit(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant data_array          : in t_slv_array;
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    -- Default user data : We don't know C_USER_ARRAY length (how many words to send), so assume tdata = 8 bits (one data_array byte per word)
    constant C_USER_ARRAY : t_user_array(0 to C_VVC_CMD_DATA_MAX_WORDS - 1) := (others => (others => '0'));
  begin
    -- Use another overload to fill in the rest
    axistream_transmit(VVCT, vvc_instance_idx, data_array, C_USER_ARRAY, msg, scope, parent_msg_id_panel);
  end procedure;

  -- SLV overload with default values for user_array, strb_array, id_array and dest_array
  procedure axistream_transmit(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant data_array          : in std_logic_vector;
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    -- Default user data : We don't know C_USER_ARRAY length (how many words to send), so assume tdata = 8 bits (one data_array byte per word)
    constant C_USER_ARRAY : t_user_array(0 to C_VVC_CMD_DATA_MAX_WORDS - 1) := (others => (others => '0'));
  begin
    -- Use another overload to fill in the rest
    axistream_transmit(VVCT, vvc_instance_idx, data_array, C_USER_ARRAY, msg, scope, parent_msg_id_panel);
  end procedure;

  --------------------------------------------------------
  --
  -- AXIStream Receive
  --
  --------------------------------------------------------
  procedure axistream_receive(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant data_routing        : in t_data_routing;
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant C_PROC_NAME : string := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant C_PROC_CALL : string := C_PROC_NAME & "()";

    variable v_local_vvc_cmd : t_vvc_cmd_record := shared_vvc_cmd.get(vvc_instance_idx);
    variable v_msg_id_panel  : t_msg_id_panel   := shared_msg_id_panel.get(VOID);
  begin
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, C_PROC_CALL, msg, QUEUED, RECEIVE);

    -- v3
    v_local_vvc_cmd                     := shared_vvc_cmd.get(vvc_instance_idx);
    v_local_vvc_cmd.parent_msg_id_panel := parent_msg_id_panel;
    v_local_vvc_cmd.data_routing        := data_routing;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(VVCT, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure;

  -- Overload without data_routing
  procedure axistream_receive(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
  begin
    axistream_receive(VVCT, vvc_instance_idx, NA, msg, scope, parent_msg_id_panel);
  end procedure;

  --------------------------------------------------------
  --
  -- AXIStream Expect
  -- Expect, receive and compare to specified data_array, user_array, strb_array, id_array, dest_array
  --
  --------------------------------------------------------
  procedure axistream_expect(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant data_array          : in t_slv_array;
    constant user_array          : in t_user_array;
    constant strb_array          : in t_strb_array;
    constant id_array            : in t_id_array;
    constant dest_array          : in t_dest_array;
    constant msg                 : in string;
    constant alert_level         : in t_alert_level  := error;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant C_DATA_ARRAY_BYTES_PER_WORD : natural := data_array(data_array'low)'length / 8;
    constant C_PROC_NAME : string := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant C_PROC_CALL : string := C_PROC_NAME & "(" & to_string(VVCT, vvc_instance_idx) -- First part common for all
                                     & ", " & to_string(data_array'length) & " words[" & to_string(C_DATA_ARRAY_BYTES_PER_WORD*8) & "b])";

    variable v_local_vvc_cmd   : t_vvc_cmd_record := shared_vvc_cmd.get(vvc_instance_idx);
    variable v_msg_id_panel    : t_msg_id_panel   := shared_msg_id_panel.get(VOID);
    variable v_vvc_config      : t_vvc_config     := shared_axistream_vvc_config.get(vvc_instance_idx);
    variable v_data_byte_array : t_slv_array(0 to (data_array'length*C_DATA_ARRAY_BYTES_PER_WORD)-1)(7 downto 0);
    variable v_check_ok        : boolean          := true;
  begin
    v_check_ok := v_check_ok and check_value(data_array'length > 0, TB_ERROR, "Sanity check: data_array length must be > 0", scope, ID_NEVER, shared_vvc_msg_id_panel.get(vvc_instance_idx), C_PROC_CALL); -- Sanity check to avoid confusing fatal error
    v_check_ok := v_check_ok and check_value(data_array(data_array'low)'length mod 8 = 0, TB_ERROR, "Sanity check: Check that data_array word is N*byte", scope, ID_NEVER, shared_vvc_msg_id_panel.get(vvc_instance_idx), C_PROC_CALL);
    if not(v_check_ok) then
      return;
    end if;

    -- Convert SLV with variable word-width to byte-width
    v_data_byte_array := convert_slv_array_to_byte_array(data_array, v_vvc_config.bfm_config.byte_endianness);

    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, C_PROC_CALL, msg, QUEUED, EXPECT);

    -- v3
    -- Generate cmd record
    v_local_vvc_cmd                                         := shared_vvc_cmd.get(vvc_instance_idx);
    v_local_vvc_cmd.data_array(0 to v_data_byte_array'high) := v_data_byte_array;
    v_local_vvc_cmd.user_array(0 to user_array'high)        := user_array; -- user_array Length = data_array_length
    v_local_vvc_cmd.strb_array(0 to strb_array'high)        := strb_array;
    v_local_vvc_cmd.id_array(0 to id_array'high)            := id_array;
    v_local_vvc_cmd.dest_array(0 to dest_array'high)        := dest_array;
    v_local_vvc_cmd.data_array_length                       := v_data_byte_array'length;
    v_local_vvc_cmd.user_array_length                       := user_array'length;
    v_local_vvc_cmd.strb_array_length                       := strb_array'length;
    v_local_vvc_cmd.id_array_length                         := id_array'length;
    v_local_vvc_cmd.dest_array_length                       := dest_array'length;
    v_local_vvc_cmd.alert_level                             := alert_level;
    v_local_vvc_cmd.parent_msg_id_panel                     := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(VVCT, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure;

  -- SLV overload
  procedure axistream_expect(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant data_array          : in std_logic_vector;
    constant user_array          : in t_user_array;
    constant strb_array          : in t_strb_array;
    constant id_array            : in t_id_array;
    constant dest_array          : in t_dest_array;
    constant msg                 : in string;
    constant alert_level         : in t_alert_level  := error;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    variable v_data_array : t_slv_array(0 to 0)(data_array'length - 1 downto 0);
  begin
    v_data_array(0) := data_array;
    axistream_expect(VVCT, vvc_instance_idx, v_data_array, user_array, strb_array, id_array, dest_array, msg, alert_level, scope, parent_msg_id_panel);
  end procedure;

  -- Overload with default values for strb_array, id_array and dest_array (will be set to don't care)
  procedure axistream_expect(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant data_array          : in t_slv_array;
    constant user_array          : in t_user_array;
    constant msg                 : in string;
    constant alert_level         : in t_alert_level  := error;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    -- Default expected strb, id, dest
    -- Don't know #bytes in AXIStream tdata, so *_array length is unknown.
    -- Make the array as short as possible for best simulation time during the check performed in the BFM.
    constant C_STRB_ARRAY : t_strb_array(0 downto 0) := (others => (others => '-'));
    constant C_ID_ARRAY   : t_id_array(0 downto 0)   := (others => (others => '-'));
    constant C_DEST_ARRAY : t_dest_array(0 downto 0) := (others => (others => '-'));
  begin
    axistream_expect(VVCT, vvc_instance_idx, data_array, user_array, C_STRB_ARRAY, C_ID_ARRAY, C_DEST_ARRAY, msg, alert_level, scope, parent_msg_id_panel);
  end procedure;

  -- SLV overload with default values for strb_array, id_array and dest_array (will be set to don't care)
  procedure axistream_expect(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant data_array          : in std_logic_vector;
    constant user_array          : in t_user_array;
    constant msg                 : in string;
    constant alert_level         : in t_alert_level  := error;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    -- Default expected strb, id, dest
    -- Don't know #bytes in AXIStream tdata, so *_array length is unknown.
    -- Make the array as short as possible for best simulation time during the check performed in the BFM.
    constant C_STRB_ARRAY : t_strb_array(0 downto 0) := (others => (others => '-'));
    constant C_ID_ARRAY   : t_id_array(0 downto 0)   := (others => (others => '-'));
    constant C_DEST_ARRAY : t_dest_array(0 downto 0) := (others => (others => '-'));
  begin
    axistream_expect(VVCT, vvc_instance_idx, data_array, user_array, C_STRB_ARRAY, C_ID_ARRAY, C_DEST_ARRAY, msg, alert_level, scope, parent_msg_id_panel);
  end procedure;

  -- Overload with default values for user_array, strb_array, id_array and dest_array (will be set to don't care)
  procedure axistream_expect(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant data_array          : in t_slv_array;
    constant msg                 : in string;
    constant alert_level         : in t_alert_level  := error;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    -- Default user data
    -- Don't know #bytes in AXIStream tdata, so user_array length is unknown.
    -- Make the array as short as possible for best simulation time during the check performed in the BFM.
    constant C_USER_ARRAY : t_user_array(0 downto 0) := (others => (others => '-'));
  begin
    -- Use another overload to fill in the rest: strb_array, id_array, dest_array
    axistream_expect(VVCT, vvc_instance_idx, data_array, C_USER_ARRAY, msg, alert_level, scope, parent_msg_id_panel);
  end procedure;

  -- SLV overload with default values for user_array, strb_array, id_array and dest_array (will be set to don't care)
  procedure axistream_expect(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant data_array          : in std_logic_vector;
    constant msg                 : in string;
    constant alert_level         : in t_alert_level  := error;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs 
  ) is
    -- Default user data
    -- Don't know #bytes in AXIStream tdata, so user_array length is unknown.
    -- Make the array as short as possible for best simulation time during the check performed in the BFM.
    constant C_USER_ARRAY : t_user_array(0 downto 0) := (others => (others => '-'));
  begin
    -- Use another overload to fill in the rest: strb_array, id_array, dest_array
    axistream_expect(VVCT, vvc_instance_idx, data_array, C_USER_ARRAY, msg, alert_level, scope, parent_msg_id_panel);
  end procedure;

  --==============================================================================
  -- Transaction info methods
  --==============================================================================
  procedure set_global_vvc_transaction_info(
    signal   vvc_transaction_info_trigger : inout std_logic;
    variable vvc_transaction_info_group   : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx                 : in natural;
    constant channel                      : in t_channel;
    constant vvc_cmd                      : in t_vvc_cmd_record;
    constant vvc_config                   : in t_vvc_config;
    constant scope                        : in string := C_VVC_CMD_SCOPE_DEFAULT) is
    variable v_transaction_info_group : t_transaction_group := vvc_transaction_info_group.get(instance_idx, channel);
  begin
    case vvc_cmd.operation is
      when TRANSMIT | RECEIVE | EXPECT =>
        v_transaction_info_group.bt.operation                             := vvc_cmd.operation;
        v_transaction_info_group.bt.data_array                            := vvc_cmd.data_array;
        v_transaction_info_group.bt.data_length                           := vvc_cmd.data_array_length;
        v_transaction_info_group.bt.user_array                            := vvc_cmd.user_array;
        v_transaction_info_group.bt.strb_array                            := vvc_cmd.strb_array;
        v_transaction_info_group.bt.id_array                              := vvc_cmd.id_array;
        v_transaction_info_group.bt.dest_array                            := vvc_cmd.dest_array;
        v_transaction_info_group.bt.vvc_meta.msg(1 to vvc_cmd.msg'length) := vvc_cmd.msg;
        v_transaction_info_group.bt.vvc_meta.cmd_idx                      := vvc_cmd.cmd_idx;
        v_transaction_info_group.bt.transaction_status                    := IN_PROGRESS;
        vvc_transaction_info_group.set(v_transaction_info_group, instance_idx, channel);
        gen_pulse(vvc_transaction_info_trigger, 0 ns, "pulsing global vvc_transaction_info trigger", scope, ID_NEVER);
      when others =>
        alert(TB_ERROR, "VVC operation not recognized");
    end case;

    wait for 0 ns;
  end procedure set_global_vvc_transaction_info;

  procedure reset_vvc_transaction_info(
    variable vvc_transaction_info_group : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx               : in natural;
    constant channel                    : in t_channel;
    constant vvc_cmd                    : in t_vvc_cmd_record) is
    variable v_transaction_info_group : t_transaction_group := vvc_transaction_info_group.get(instance_idx, channel);
  begin
    case vvc_cmd.operation is
      when TRANSMIT | RECEIVE | EXPECT =>
        v_transaction_info_group.bt := C_BASE_TRANSACTION_SET_DEFAULT;
      when others =>
        null;
    end case;
    vvc_transaction_info_group.set(v_transaction_info_group, instance_idx, channel);

    wait for 0 ns;
  end procedure reset_vvc_transaction_info;

  --==============================================================================
  -- VVC Activity
  --==============================================================================
  procedure update_vvc_activity_register(signal   global_trigger_vvc_activity_register : inout std_logic;
                                         variable vvc_status                           : inout protected_vvc_status_pkg.t_prot_generic_array;
                                         constant instance_idx                         : in natural;
                                         constant channel                              : in t_channel;
                                         constant activity                             : in t_activity;
                                         constant entry_num_in_vvc_activity_register   : in integer;
                                         constant last_cmd_idx_executed                : in natural;
                                         constant command_queue_is_empty               : in boolean;
                                         constant scope                                : in string := C_VVC_NAME) is
    variable v_activity   : t_activity   := activity;
    variable v_vvc_status : t_vvc_status := vvc_status.get(instance_idx, channel);
  begin
    -- Update vvc_status after a command has finished (during same delta cycle the activity register is updated)
    if activity = INACTIVE then
      v_vvc_status.previous_cmd_idx := last_cmd_idx_executed;
      v_vvc_status.current_cmd_idx  := 0;
    end if;
    vvc_status.set(v_vvc_status, instance_idx, channel);

    if v_activity = INACTIVE and not (command_queue_is_empty) then
      v_activity := ACTIVE;
    end if;
    shared_vvc_activity_register.priv_report_vvc_activity(vvc_idx               => entry_num_in_vvc_activity_register,
                                                          activity              => v_activity,
                                                          last_cmd_idx_executed => last_cmd_idx_executed);
    if global_trigger_vvc_activity_register /= 'L' then
      wait until global_trigger_vvc_activity_register = 'L';
    end if;
    gen_pulse(global_trigger_vvc_activity_register, 0 ns, "pulsing global trigger for vvc activity register", scope, ID_NEVER);
  end procedure;

end package body vvc_methods_pkg;
