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
use work.axistream_bfm_pkg.all;
use work.td_target_support_pkg.all;

package vvc_methods_support_pkg is

  --==========================================================================================
  -- Types and constants for the AXISTREAM VVC
  --==========================================================================================
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
    inter_bfm_delay            : t_inter_bfm_delay; -- Minimum delay between BFM accesses from the VVC. If parameter delay_type is set to NO_DELAY, BFM accesses will be back to back, i.e. no delay.
    bfm_config                 : t_bfm_config; -- Configuration for the BFM. See BFM quick reference.
    unwanted_activity_severity : t_alert_level; -- Severity of alert to be initiated if unwanted activity on the DUT outputs is detected
  end record;

  constant C_AXISTREAM_VVC_CONFIG_DEFAULT : t_vvc_config := (
    inter_bfm_delay            => C_AXISTREAM_INTER_BFM_DELAY_DEFAULT,
    bfm_config                 => C_AXISTREAM_BFM_CONFIG_DEFAULT,
    unwanted_activity_severity => C_UNWANTED_ACTIVITY_SEVERITY
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
    t_generic_element  => t_vvc_status,
    c_generic_default  => C_VVC_STATUS_DEFAULT,
    c_max_instance_num => C_VVC_MAX_INSTANCE_NUM
  );

----------------------------------------------------------------------
-- Protected type: t_vvc_config
----------------------------------------------------------------------
library uvvm_util;
use work.vvc_methods_support_pkg.all;
use work.vvc_transaction_pkg.all;

package protected_vvc_config_pkg is new uvvm_util.protected_generic_types_pkg
  generic map(
    t_generic_element  => t_vvc_config,
    c_generic_default  => C_AXISTREAM_VVC_CONFIG_DEFAULT,
    c_max_instance_num => C_VVC_MAX_INSTANCE_NUM
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
    t_generic_element  => t_msg_id_panel,
    c_generic_default  => C_VVC_MSG_ID_PANEL_DEFAULT,
    c_max_instance_num => C_VVC_MAX_INSTANCE_NUM
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

use work.axistream_bfm_pkg.all;
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

  shared variable shared_axistream_vvc_status       : work.protected_vvc_status_pkg.t_generic_array;
  shared variable shared_axistream_vvc_config       : work.protected_vvc_config_pkg.t_generic_array;
  shared variable shared_axistream_vvc_msg_id_panel : work.protected_msg_id_panel_pkg.t_generic_array;

  alias shared_vvc_status       is shared_axistream_vvc_status;       -- This alias is for internal use in the VVC
  alias shared_vvc_config       is shared_axistream_vvc_config;       -- This alias is for internal use in the VVC
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
    constant scope                        : in string := C_VVC_CMD_SCOPE_DEFAULT) is
    variable v_transaction_info_group : t_transaction_group := vvc_transaction_info_group.get(instance_idx, channel);
  begin
    case vvc_cmd.operation is
      when TRANSMIT | RECEIVE | EXPECT =>
        v_transaction_info_group.bt.operation          := vvc_cmd.operation;
        v_transaction_info_group.bt.data_array         := vvc_cmd.data_array;
        v_transaction_info_group.bt.data_length        := vvc_cmd.data_array_length;
        v_transaction_info_group.bt.user_array         := vvc_cmd.user_array;
        v_transaction_info_group.bt.strb_array         := vvc_cmd.strb_array;
        v_transaction_info_group.bt.id_array           := vvc_cmd.id_array;
        v_transaction_info_group.bt.dest_array         := vvc_cmd.dest_array;
        v_transaction_info_group.bt.vvc_meta.msg       := vvc_cmd.msg;
        v_transaction_info_group.bt.vvc_meta.cmd_idx   := vvc_cmd.cmd_idx;
        v_transaction_info_group.bt.transaction_status := transaction_status;
        vvc_transaction_info_group.set(v_transaction_info_group, instance_idx, channel);
        gen_pulse(vvc_transaction_info_trigger, 0 ns, "pulsing global vvc_transaction_info trigger", scope, ID_NEVER);

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
    constant scope                        : in string := C_VVC_CMD_SCOPE_DEFAULT) is
    variable v_transaction_info_group : t_transaction_group := vvc_transaction_info_group.get(instance_idx, channel);
  begin
    case vvc_cmd.operation is
      when RECEIVE =>
        v_transaction_info_group.bt.data_array         := vvc_result.data_array;
        v_transaction_info_group.bt.data_length        := vvc_result.data_length;
        v_transaction_info_group.bt.user_array         := vvc_result.user_array;
        v_transaction_info_group.bt.strb_array         := vvc_result.strb_array;
        v_transaction_info_group.bt.id_array           := vvc_result.id_array;
        v_transaction_info_group.bt.dest_array         := vvc_result.dest_array;
        v_transaction_info_group.bt.transaction_status := transaction_status;
        vvc_transaction_info_group.set(v_transaction_info_group, instance_idx, channel);
        gen_pulse(vvc_transaction_info_trigger, 0 ns, "pulsing global vvc_transaction_info trigger", scope, ID_NEVER);

      when others =>
        alert(TB_ERROR, "VVC operation does not update vvc_result", scope);
    end case;

    wait for 0 ns;
  end procedure set_global_vvc_transaction_info;

  procedure reset_vvc_transaction_info(
    variable vvc_transaction_info_group : inout work.protected_transaction_group_pkg.t_generic_array; -- v3 t_transaction_group;
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

end package body vvc_methods_pkg;
