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

------------------------------------------------------------------------------------------
-- Description   : See library quick reference (under 'doc') and README-file(s)
------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library uvvm_vvc_framework;
use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library bitvis_vip_scoreboard;
use bitvis_vip_scoreboard.generic_sb_support_pkg.all;

use work.axilite_bfm_pkg.all;
use work.vvc_cmd_pkg.all;
use work.td_target_support_pkg.all;
use work.transaction_pkg.all;

--=================================================================================================
--=================================================================================================
--=================================================================================================
package vvc_methods_pkg is

  --===============================================================================================
  -- Types and constants for the AXILITE VVC 
  --===============================================================================================
  constant C_VVC_NAME : string := "AXILITE_VVC";

  signal AXILITE_VVCT : t_vvc_target_record := set_vvc_target_defaults(C_VVC_NAME);
  alias THIS_VVCT     : t_vvc_target_record is AXILITE_VVCT;
  alias t_bfm_config is t_axilite_bfm_config;

  type t_executor_result is record
    cmd_idx           : natural;        -- from UVVM handshake mechanism
    data              : std_logic_vector(127 downto 0);
    value_is_new      : boolean;        -- turn true/false for put/fetch
    fetch_is_accepted : boolean;
  end record;

  type t_executor_result_array is array (natural range <>) of t_executor_result;

  -- Type found in UVVM-Util types_pkg
  constant C_AXILITE_INTER_BFM_DELAY_DEFAULT : t_inter_bfm_delay := (
    delay_type                         => NO_DELAY,
    delay_in_time                      => 0 ns,
    inter_bfm_delay_violation_severity => WARNING
  );

  type t_vvc_config is record
    inter_bfm_delay                  : t_inter_bfm_delay; -- Minimum delay between BFM accesses from the VVC. If parameter delay_type is set to NO_DELAY, BFM accesses will be back to back, i.e. no delay.
    bfm_config                       : t_bfm_config;      -- Configuration for the BFM. See BFM quick reference.
    force_single_pending_transaction : boolean;           -- Waits until the previous transaction is completed before starting the next one
  end record;

  constant C_AXILITE_VVC_CONFIG_DEFAULT : t_vvc_config := (
    inter_bfm_delay                  => C_AXILITE_INTER_BFM_DELAY_DEFAULT,
    bfm_config                       => C_AXILITE_BFM_CONFIG_DEFAULT,
    force_single_pending_transaction => false
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

  -- Transaction information for the wave view during simulation
  type t_transaction_info is record
    operation   : t_operation;
    addr        : unsigned(C_VVC_CMD_ADDR_MAX_LENGTH - 1 downto 0);
    data        : std_logic_vector(C_VVC_CMD_DATA_MAX_LENGTH - 1 downto 0);
    byte_enable : std_logic_vector(C_VVC_CMD_BYTE_ENABLE_MAX_LENGTH - 1 downto 0);
    msg         : string(1 to C_VVC_CMD_STRING_MAX_LENGTH);
  end record;

  type t_transaction_info_array is array (natural range <>) of t_transaction_info;

  constant C_TRANSACTION_INFO_DEFAULT : t_transaction_info := (
    operation   => NO_OPERATION,
    addr        => (others => '0'),
    data        => (others => '0'),
    byte_enable => (others => '1'),
    msg         => (others => ' ')
  );

  -- v3
  package protected_vvc_status_pkg is new uvvm_util.protected_generic_types_pkg
    generic map(t_generic_element => t_vvc_status,
                c_generic_default => C_VVC_STATUS_DEFAULT);
  use protected_vvc_status_pkg.all;
  shared variable shared_axilite_vvc_status : protected_vvc_status_pkg.t_prot_generic_array;
  alias shared_vvc_status is shared_axilite_vvc_status; -- This alias is for internal use in the VVC

  package protected_vvc_config_pkg is new uvvm_util.protected_generic_types_pkg
    generic map(t_generic_element => t_vvc_config,
                c_generic_default => C_AXILITE_VVC_CONFIG_DEFAULT);
  use protected_vvc_config_pkg.all;
  shared variable shared_axilite_vvc_config : protected_vvc_config_pkg.t_prot_generic_array;
  alias shared_vvc_config is shared_axilite_vvc_config; -- This alias is for internal use in the VVC

  package protected_msg_id_panel_pkg is new uvvm_util.protected_generic_types_pkg
    generic map(t_generic_element => t_msg_id_panel,
                c_generic_default => C_VVC_MSG_ID_PANEL_DEFAULT);
  use protected_msg_id_panel_pkg.all;
  shared variable shared_axilite_vvc_msg_id_panel : protected_msg_id_panel_pkg.t_prot_generic_array;
  alias shared_vvc_msg_id_panel is shared_axilite_vvc_msg_id_panel; -- This alias is for internal use in the VVC

  -- Scoreboard
  package axilite_sb_pkg is new bitvis_vip_scoreboard.generic_sb_pkg
    generic map(t_element         => std_logic_vector(C_VVC_CMD_DATA_MAX_LENGTH - 1 downto 0),
                element_match     => std_match,
                to_string_element => to_string);
  use axilite_sb_pkg.all;
  shared variable AXILITE_VVC_SB : axilite_sb_pkg.t_prot_generic_sb;

  --==========================================================================================
  -- Methods dedicated to this VVC 
  -- - These procedures are called from the testbench in order for the VVC to execute
  --   BFM calls towards the given interface. The VVC interpreter will queue these calls
  --   and then the VVC executor will fetch the commands from the queue and handle the
  --   actual BFM execution.
  --   For details on how the BFM procedures work, see the QuickRef.
  --==========================================================================================

  procedure axilite_write(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant addr                : in unsigned;
    constant data                : in std_logic_vector;
    constant byte_enable         : in std_logic_vector;
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  procedure axilite_write(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant addr                : in unsigned;
    constant data                : in std_logic_vector;
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  procedure axilite_read(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant addr                : in unsigned;
    constant data_routing        : in t_data_routing;
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  procedure axilite_read(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant addr                : in unsigned;
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  procedure axilite_check(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant addr                : in unsigned;
    constant data                : in std_logic_vector;
    constant msg                 : in string;
    constant alert_level         : in t_alert_level  := ERROR;
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
    constant scope                        : in string := C_VVC_CMD_SCOPE_DEFAULT
  );

  procedure set_arw_vvc_transaction_info(
    signal   vvc_transaction_info_trigger : inout std_logic;
    variable vvc_transaction_info_group   : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx                 : in natural;
    constant channel                      : in t_channel;
    constant vvc_cmd                      : in t_vvc_cmd_record;
    constant vvc_config                   : in t_vvc_config;
    constant scope                        : in string := C_VVC_CMD_SCOPE_DEFAULT
  );

  procedure set_w_vvc_transaction_info(
    signal   vvc_transaction_info_trigger : inout std_logic;
    variable vvc_transaction_info_group   : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx                 : in natural;
    constant channel                      : in t_channel;
    constant vvc_cmd                      : in t_vvc_cmd_record;
    constant vvc_config                   : in t_vvc_config;
    constant scope                        : in string := C_VVC_CMD_SCOPE_DEFAULT
  );

  procedure set_b_vvc_transaction_info(
    signal   vvc_transaction_info_trigger : inout std_logic;
    variable vvc_transaction_info_group   : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx                 : in natural;
    constant channel                      : in t_channel;
    constant vvc_cmd                      : in t_vvc_cmd_record;
    constant vvc_config                   : in t_vvc_config;
    constant scope                        : in string := C_VVC_CMD_SCOPE_DEFAULT
  );

  procedure set_r_vvc_transaction_info(
    signal   vvc_transaction_info_trigger : inout std_logic;
    variable vvc_transaction_info_group   : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx                 : in natural;
    constant channel                      : in t_channel;
    constant vvc_cmd                      : in t_vvc_cmd_record;
    constant vvc_config                   : in t_vvc_config;
    constant scope                        : in string := C_VVC_CMD_SCOPE_DEFAULT
  );

  procedure reset_vvc_transaction_info(
    variable vvc_transaction_info_group : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx               : in natural;
    constant channel                    : in t_channel;
    constant vvc_cmd                    : in t_vvc_cmd_record
  );

  procedure reset_arw_vvc_transaction_info(
    variable vvc_transaction_info_group : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx               : in natural;
    constant channel                    : in t_channel;
    constant vvc_cmd                    : in t_vvc_cmd_record
  );

  procedure reset_w_vvc_transaction_info(
    variable vvc_transaction_info_group : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx               : in natural;
    constant channel                    : in t_channel
  );

  procedure reset_b_vvc_transaction_info(
    variable vvc_transaction_info_group : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx               : in natural;
    constant channel                    : in t_channel
  );

  procedure reset_r_vvc_transaction_info(
    variable vvc_transaction_info_group : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx               : in natural;
    constant channel                    : in t_channel
  );

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

  --==============================================================================
  -- VVC Scoreboard helper method
  --==============================================================================
  function pad_axilite_sb(
    constant data : in std_logic_vector
  ) return std_logic_vector;

end package vvc_methods_pkg;

package body vvc_methods_pkg is

  --==============================================================================
  -- Methods dedicated to this VVC
  -- Notes:
  --   - shared_vvc_cmd is initialised to C_VVC_CMD_DEFAULT, and also reset to this after every command
  --==============================================================================

  procedure axilite_write(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant addr                : in unsigned;
    constant data                : in std_logic_vector;
    constant byte_enable         : in std_logic_vector;
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant proc_name : string := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant proc_call : string := proc_name & "(" & to_string(VVCT, vvc_instance_idx) -- First part common for all
                                   & ", " & to_string(addr, HEX, AS_IS, INCL_RADIX) & ", " & to_string(data, HEX, AS_IS, INCL_RADIX) & ", " & to_string(byte_enable, BIN, AS_IS, INCL_RADIX) & ")";
    variable v_local_vvc_cmd       : t_vvc_cmd_record                                                  := shared_vvc_cmd.get(vvc_instance_idx);
    variable v_normalised_addr     : unsigned(v_local_vvc_cmd.addr'length - 1 downto 0)                := normalize_and_check(addr, v_local_vvc_cmd.addr, ALLOW_WIDER_NARROWER, "addr", "shared_vvc_cmd.addr", proc_call & " called with too wide address. " & add_msg_delimiter(msg));
    variable v_normalised_data     : std_logic_vector(v_local_vvc_cmd.data'length - 1 downto 0)        := normalize_and_check(data, v_local_vvc_cmd.data, ALLOW_WIDER_NARROWER, "data", "shared_vvc_cmd.data", proc_call & " called with too wide data. " & add_msg_delimiter(msg));
    variable v_normalised_byte_ena : std_logic_vector(v_local_vvc_cmd.byte_enable'length - 1 downto 0) := normalize_and_check(byte_enable, v_local_vvc_cmd.byte_enable, ALLOW_WIDER_NARROWER, "byte_enable", "shared_vvc_cmd.byte_enable", proc_call & " called with too wide byte_enable. " & add_msg_delimiter(msg));
    variable v_msg_id_panel        : t_msg_id_panel                                                    := shared_msg_id_panel.get(VOID);
  begin
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, proc_call, msg, QUEUED, WRITE);

    -- v3
    v_local_vvc_cmd                     := shared_vvc_cmd.get(vvc_instance_idx);
    v_local_vvc_cmd.addr                := v_normalised_addr;
    v_local_vvc_cmd.data                := v_normalised_data;
    v_local_vvc_cmd.byte_enable         := v_normalised_byte_ena;
    v_local_vvc_cmd.parent_msg_id_panel := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(VVCT, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure;

  procedure axilite_write(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant addr                : in unsigned;
    constant data                : in std_logic_vector;
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant proc_name : string := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant proc_call : string := proc_name & "(" & to_string(VVCT, vvc_instance_idx) -- First part common for all
                                   & ", " & to_string(addr, HEX, AS_IS, INCL_RADIX) & ", " & to_string(data, HEX, AS_IS, INCL_RADIX) & ")";
    variable v_local_vvc_cmd   : t_vvc_cmd_record                                           := shared_vvc_cmd.get(vvc_instance_idx);
    variable v_normalised_addr : unsigned(v_local_vvc_cmd.addr'length - 1 downto 0)         := normalize_and_check(addr, v_local_vvc_cmd.addr, ALLOW_WIDER_NARROWER, "addr", "shared_vvc_cmd.addr", proc_call & " called with too wide address. " & add_msg_delimiter(msg));
    variable v_normalised_data : std_logic_vector(v_local_vvc_cmd.data'length - 1 downto 0) := normalize_and_check(data, v_local_vvc_cmd.data, ALLOW_WIDER_NARROWER, "data", "shared_vvc_cmd.data", proc_call & " called with too wide data. " & add_msg_delimiter(msg));
    variable v_msg_id_panel    : t_msg_id_panel                                             := shared_msg_id_panel.get(VOID);
  begin
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, proc_call, msg, QUEUED, WRITE);

    -- v3
    v_local_vvc_cmd                     := shared_vvc_cmd.get(vvc_instance_idx);
    v_local_vvc_cmd.addr                := v_normalised_addr;
    v_local_vvc_cmd.data                := v_normalised_data;
    v_local_vvc_cmd.parent_msg_id_panel := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(VVCT, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure;

  procedure axilite_read(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant addr                : in unsigned;
    constant data_routing        : in t_data_routing;
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant proc_name : string := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant proc_call : string := proc_name & "(" & to_string(VVCT, vvc_instance_idx) -- First part common for all
                                   & ", " & to_string(addr, HEX, AS_IS, INCL_RADIX) & ")";
    variable v_local_vvc_cmd   : t_vvc_cmd_record                                   := shared_vvc_cmd.get(vvc_instance_idx);
    variable v_normalised_addr : unsigned(v_local_vvc_cmd.addr'length - 1 downto 0) := normalize_and_check(addr, v_local_vvc_cmd.addr, ALLOW_WIDER_NARROWER, "addr", "shared_vvc_cmd.addr", msg);
    variable v_msg_id_panel    : t_msg_id_panel                                     := shared_msg_id_panel.get(VOID);
  begin
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, proc_call, msg, QUEUED, READ);

    -- v3
    v_local_vvc_cmd                     := shared_vvc_cmd.get(vvc_instance_idx);
    v_local_vvc_cmd.addr                := v_normalised_addr;
    v_local_vvc_cmd.data_routing        := data_routing;
    v_local_vvc_cmd.parent_msg_id_panel := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(VVCT, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure;

  procedure axilite_read(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant addr                : in unsigned;
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
  begin
    axilite_read(VVCT, vvc_instance_idx, addr, NA, msg, scope, parent_msg_id_panel);
  end procedure;

  procedure axilite_check(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant addr                : in unsigned;
    constant data                : in std_logic_vector;
    constant msg                 : in string;
    constant alert_level         : in t_alert_level  := ERROR;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant proc_name : string := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant proc_call : string := proc_name & "(" & to_string(VVCT, vvc_instance_idx) -- First part common for all
                                   & ", " & to_string(addr, HEX, AS_IS, INCL_RADIX) & ", " & to_string(data, HEX, AS_IS, INCL_RADIX) & ")";
    variable v_local_vvc_cmd   : t_vvc_cmd_record                                           := shared_vvc_cmd.get(vvc_instance_idx);
    variable v_normalised_addr : unsigned(v_local_vvc_cmd.addr'length - 1 downto 0)         := normalize_and_check(addr, v_local_vvc_cmd.addr, ALLOW_WIDER_NARROWER, "addr", "shared_vvc_cmd.addr", proc_call & " called with too wide address. " & add_msg_delimiter(msg));
    variable v_normalised_data : std_logic_vector(v_local_vvc_cmd.data'length - 1 downto 0) := normalize_and_check(data, v_local_vvc_cmd.data, ALLOW_WIDER_NARROWER, "data", "shared_vvc_cmd.data", proc_call & " called with too wide data. " & add_msg_delimiter(msg));
    variable v_msg_id_panel    : t_msg_id_panel                                             := shared_msg_id_panel.get(VOID);
  begin
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, proc_call, msg, QUEUED, CHECK);

    -- v3
    v_local_vvc_cmd                     := shared_vvc_cmd.get(vvc_instance_idx);
    v_local_vvc_cmd.addr                := v_normalised_addr;
    v_local_vvc_cmd.data                := v_normalised_data;
    v_local_vvc_cmd.alert_level         := alert_level;
    v_local_vvc_cmd.parent_msg_id_panel := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(VVCT, std.env.resolution_limit, scope, v_msg_id_panel);
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
    constant scope                        : in string := C_VVC_CMD_SCOPE_DEFAULT
  ) is
    variable v_transaction_info_group : t_transaction_group := vvc_transaction_info_group.get(instance_idx, channel);
  begin
    case vvc_cmd.operation is
      when WRITE =>
        v_transaction_info_group.bt_wr.operation                             := vvc_cmd.operation;
        v_transaction_info_group.bt_wr.vvc_meta.msg(1 to vvc_cmd.msg'length) := vvc_cmd.msg;
        v_transaction_info_group.bt_wr.vvc_meta.cmd_idx                      := vvc_cmd.cmd_idx;
        v_transaction_info_group.bt_wr.transaction_status                    := IN_PROGRESS;
      when READ | CHECK =>
        v_transaction_info_group.bt_rd.operation                             := vvc_cmd.operation;
        v_transaction_info_group.bt_rd.vvc_meta.msg(1 to vvc_cmd.msg'length) := vvc_cmd.msg;
        v_transaction_info_group.bt_rd.vvc_meta.cmd_idx                      := vvc_cmd.cmd_idx;
        v_transaction_info_group.bt_rd.transaction_status                    := IN_PROGRESS;
      when others =>
        alert(TB_ERROR, "VVC operation not recognized");
    end case;

    vvc_transaction_info_group.set(v_transaction_info_group, instance_idx, channel);
    gen_pulse(vvc_transaction_info_trigger, 0 ns, "pulsing global vvc transaction info trigger", scope, ID_NEVER);
    wait for 0 ns;
  end procedure set_global_vvc_transaction_info;

  procedure set_arw_vvc_transaction_info(
    signal   vvc_transaction_info_trigger : inout std_logic;
    variable vvc_transaction_info_group   : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx                 : in natural;
    constant channel                      : in t_channel;
    constant vvc_cmd                      : in t_vvc_cmd_record;
    constant vvc_config                   : in t_vvc_config;
    constant scope                        : in string := C_VVC_CMD_SCOPE_DEFAULT
  ) is
    variable v_transaction_info_group : t_transaction_group := vvc_transaction_info_group.get(instance_idx, channel);
  begin
    case vvc_cmd.operation is
      when WRITE =>
        v_transaction_info_group.st_aw.operation                             := vvc_cmd.operation;
        v_transaction_info_group.st_aw.arwaddr                               := vvc_cmd.addr;
        v_transaction_info_group.st_aw.vvc_meta.msg(1 to vvc_cmd.msg'length) := vvc_cmd.msg;
        v_transaction_info_group.st_aw.vvc_meta.cmd_idx                      := vvc_cmd.cmd_idx;
        v_transaction_info_group.st_aw.transaction_status                    := IN_PROGRESS;
      when READ | CHECK =>
        v_transaction_info_group.st_ar.operation                             := vvc_cmd.operation;
        v_transaction_info_group.st_ar.arwaddr                               := vvc_cmd.addr;
        v_transaction_info_group.st_ar.vvc_meta.msg(1 to vvc_cmd.msg'length) := vvc_cmd.msg;
        v_transaction_info_group.st_ar.vvc_meta.cmd_idx                      := vvc_cmd.cmd_idx;
        v_transaction_info_group.st_ar.transaction_status                    := IN_PROGRESS;
      when others =>
        alert(TB_ERROR, "VVC operation not recognized");
    end case;

    vvc_transaction_info_group.set(v_transaction_info_group, instance_idx, channel);
    gen_pulse(vvc_transaction_info_trigger, 0 ns, "pulsing global vvc transaction info trigger", scope, ID_NEVER);
    wait for 0 ns;
  end procedure set_arw_vvc_transaction_info;

  procedure set_w_vvc_transaction_info(
    signal   vvc_transaction_info_trigger : inout std_logic;
    variable vvc_transaction_info_group   : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx                 : in natural;
    constant channel                      : in t_channel;
    constant vvc_cmd                      : in t_vvc_cmd_record;
    constant vvc_config                   : in t_vvc_config;
    constant scope                        : in string := C_VVC_CMD_SCOPE_DEFAULT
  ) is
    variable v_transaction_info_group : t_transaction_group := vvc_transaction_info_group.get(instance_idx, channel);
  begin
    v_transaction_info_group.st_w.operation                             := vvc_cmd.operation;
    v_transaction_info_group.st_w.wdata                                 := vvc_cmd.data;
    v_transaction_info_group.st_w.wstrb                                 := vvc_cmd.byte_enable;
    v_transaction_info_group.st_w.vvc_meta.msg(1 to vvc_cmd.msg'length) := vvc_cmd.msg;
    v_transaction_info_group.st_w.vvc_meta.cmd_idx                      := vvc_cmd.cmd_idx;
    v_transaction_info_group.st_w.transaction_status                    := IN_PROGRESS;

    vvc_transaction_info_group.set(v_transaction_info_group, instance_idx, channel);
    gen_pulse(vvc_transaction_info_trigger, 0 ns, "pulsing global vvc transaction info trigger", scope, ID_NEVER);
    wait for 0 ns;
  end procedure set_w_vvc_transaction_info;

  procedure set_b_vvc_transaction_info(
    signal   vvc_transaction_info_trigger : inout std_logic;
    variable vvc_transaction_info_group   : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx                 : in natural;
    constant channel                      : in t_channel;
    constant vvc_cmd                      : in t_vvc_cmd_record;
    constant vvc_config                   : in t_vvc_config;
    constant scope                        : in string := C_VVC_CMD_SCOPE_DEFAULT
  ) is
    variable v_transaction_info_group : t_transaction_group := vvc_transaction_info_group.get(instance_idx, channel);
  begin
    v_transaction_info_group.st_b.operation                             := vvc_cmd.operation;
    v_transaction_info_group.st_b.vvc_meta.msg(1 to vvc_cmd.msg'length) := vvc_cmd.msg;
    v_transaction_info_group.st_b.vvc_meta.cmd_idx                      := vvc_cmd.cmd_idx;
    v_transaction_info_group.st_b.transaction_status                    := IN_PROGRESS;

    vvc_transaction_info_group.set(v_transaction_info_group, instance_idx, channel);
    gen_pulse(vvc_transaction_info_trigger, 0 ns, "pulsing global vvc transaction info trigger", scope, ID_NEVER);
    wait for 0 ns;
  end procedure set_b_vvc_transaction_info;

  procedure set_r_vvc_transaction_info(
    signal   vvc_transaction_info_trigger : inout std_logic;
    variable vvc_transaction_info_group   : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx                 : in natural;
    constant channel                      : in t_channel;
    constant vvc_cmd                      : in t_vvc_cmd_record;
    constant vvc_config                   : in t_vvc_config;
    constant scope                        : in string := C_VVC_CMD_SCOPE_DEFAULT
  ) is
    variable v_transaction_info_group : t_transaction_group := vvc_transaction_info_group.get(instance_idx, channel);
  begin
    v_transaction_info_group.st_r.operation                             := vvc_cmd.operation;
    v_transaction_info_group.st_r.rdata                                 := vvc_cmd.data;
    v_transaction_info_group.st_r.vvc_meta.msg(1 to vvc_cmd.msg'length) := vvc_cmd.msg;
    v_transaction_info_group.st_r.vvc_meta.cmd_idx                      := vvc_cmd.cmd_idx;
    v_transaction_info_group.st_r.transaction_status                    := IN_PROGRESS;

    vvc_transaction_info_group.set(v_transaction_info_group, instance_idx, channel);
    gen_pulse(vvc_transaction_info_trigger, 0 ns, "pulsing global vvc transaction info trigger", scope, ID_NEVER);
    wait for 0 ns;
  end procedure set_r_vvc_transaction_info;

  procedure reset_vvc_transaction_info(
    variable vvc_transaction_info_group : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx               : in natural;
    constant channel                    : in t_channel;
    constant vvc_cmd                    : in t_vvc_cmd_record
  ) is
    variable v_transaction_info_group : t_transaction_group := vvc_transaction_info_group.get(instance_idx, channel);
  begin
    case vvc_cmd.operation is
      when WRITE =>
        if vvc_cmd.cmd_idx = v_transaction_info_group.bt_wr.vvc_meta.cmd_idx then
          v_transaction_info_group.bt_wr := C_BASE_TRANSACTION_SET_DEFAULT;
          vvc_transaction_info_group.set(v_transaction_info_group, instance_idx, channel);
        end if;
      when READ | CHECK =>
        if vvc_cmd.cmd_idx = v_transaction_info_group.bt_rd.vvc_meta.cmd_idx then
          v_transaction_info_group.bt_rd := C_BASE_TRANSACTION_SET_DEFAULT;
          vvc_transaction_info_group.set(v_transaction_info_group, instance_idx, channel);
        end if;
      when others =>
        null;
    end case;
    wait for 0 ns;
  end procedure reset_vvc_transaction_info;

  procedure reset_arw_vvc_transaction_info(
    variable vvc_transaction_info_group : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx               : in natural;
    constant channel                    : in t_channel;
    constant vvc_cmd                    : in t_vvc_cmd_record
  ) is
    variable v_transaction_info_group : t_transaction_group := vvc_transaction_info_group.get(instance_idx, channel);
  begin
    case vvc_cmd.operation is
      when WRITE =>
        v_transaction_info_group.st_aw := C_ARW_TRANSACTION_DEFAULT;
        vvc_transaction_info_group.set(v_transaction_info_group, instance_idx, channel);
      when READ | CHECK =>
        v_transaction_info_group.st_ar := C_ARW_TRANSACTION_DEFAULT;
        vvc_transaction_info_group.set(v_transaction_info_group, instance_idx, channel);
      when others =>
        null;
    end case;
    wait for 0 ns;
  end procedure reset_arw_vvc_transaction_info;

  procedure reset_w_vvc_transaction_info(
    variable vvc_transaction_info_group : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx               : in natural;
    constant channel                    : in t_channel
  ) is
    variable v_transaction_info_group : t_transaction_group := vvc_transaction_info_group.get(instance_idx, channel);
  begin
    v_transaction_info_group.st_w := C_W_TRANSACTION_DEFAULT;
    vvc_transaction_info_group.set(v_transaction_info_group, instance_idx, channel);
  end procedure reset_w_vvc_transaction_info;

  procedure reset_b_vvc_transaction_info(
    variable vvc_transaction_info_group : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx               : in natural;
    constant channel                    : in t_channel
  ) is
    variable v_transaction_info_group : t_transaction_group := vvc_transaction_info_group.get(instance_idx, channel);
  begin
    v_transaction_info_group.st_b := C_B_TRANSACTION_DEFAULT;
    vvc_transaction_info_group.set(v_transaction_info_group, instance_idx, channel);
  end procedure reset_b_vvc_transaction_info;

  procedure reset_r_vvc_transaction_info(
    variable vvc_transaction_info_group : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx               : in natural;
    constant channel                    : in t_channel
  ) is
    variable v_transaction_info_group : t_transaction_group := vvc_transaction_info_group.get(instance_idx, channel);
  begin
    v_transaction_info_group.st_r := C_R_TRANSACTION_DEFAULT;
    vvc_transaction_info_group.set(v_transaction_info_group, instance_idx, channel);
  end procedure reset_r_vvc_transaction_info;

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

  --==============================================================================
  -- VVC Scoreboard helper method
  --==============================================================================

  function pad_axilite_sb(
    constant data : in std_logic_vector
  ) return std_logic_vector is
  begin
    return pad_sb_slv(data, C_VVC_CMD_DATA_MAX_LENGTH);
  end function pad_axilite_sb;

end package body vvc_methods_pkg;

