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

use work.sbi_bfm_pkg.all;
use work.vvc_cmd_pkg.all;
use work.td_target_support_pkg.all;
use work.transaction_pkg.all;

--=================================================================================================
--=================================================================================================
--=================================================================================================
package vvc_methods_pkg is

  --===============================================================================================
  -- Types and constants for the SBI VVC
  --===============================================================================================
  constant C_VVC_NAME : string := "SBI_VVC";

  signal SBI_VVCT : t_vvc_target_record := set_vvc_target_defaults(C_VVC_NAME);
  alias THIS_VVCT : t_vvc_target_record is SBI_VVCT;
  alias t_bfm_config is t_sbi_bfm_config;

  -- Type found in UVVM-Util types_pkg
  constant C_SBI_INTER_BFM_DELAY_DEFAULT : t_inter_bfm_delay := (
    delay_type                         => NO_DELAY,
    delay_in_time                      => 0 ns,
    inter_bfm_delay_violation_severity => WARNING
  );

  type t_vvc_config is record
    inter_bfm_delay : t_inter_bfm_delay; -- Minimum delay between BFM accesses from the VVC. If parameter delay_type is set to NO_DELAY, BFM accesses will be back to back, i.e. no delay.
    bfm_config      : t_bfm_config;      -- Configuration for the BFM. See BFM quick reference.
  end record;

  constant C_SBI_VVC_CONFIG_DEFAULT : t_vvc_config := (
    inter_bfm_delay => C_SBI_INTER_BFM_DELAY_DEFAULT,
    bfm_config      => C_SBI_BFM_CONFIG_DEFAULT
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

  -- Transaction information to include in the wave view during simulation
  type t_transaction_info is record
    operation : t_operation;
    addr      : unsigned(C_VVC_CMD_ADDR_MAX_LENGTH - 1 downto 0);
    data      : std_logic_vector(C_VVC_CMD_DATA_MAX_LENGTH - 1 downto 0);
    msg       : string(1 to C_VVC_CMD_STRING_MAX_LENGTH);
  end record;

  type t_transaction_info_array is array (natural range <>) of t_transaction_info;

  constant C_TRANSACTION_INFO_DEFAULT : t_transaction_info := (
    operation => NO_OPERATION,
    addr      => (others => '0'),
    data      => (others => '0'),
    msg       => (others => ' ')
  );

  -- v3
  package protected_vvc_status_pkg is new uvvm_util.protected_generic_types_pkg
    generic map(t_generic_element => t_vvc_status,
                c_generic_default => C_VVC_STATUS_DEFAULT);
  use protected_vvc_status_pkg.all;
  shared variable shared_sbi_vvc_status : protected_vvc_status_pkg.t_prot_generic_array;
  alias shared_vvc_status is shared_sbi_vvc_status; -- This alias is for internal use in the VVC

  package protected_vvc_config_pkg is new uvvm_util.protected_generic_types_pkg
    generic map(t_generic_element => t_vvc_config,
                c_generic_default => C_SBI_VVC_CONFIG_DEFAULT);
  use protected_vvc_config_pkg.all;
  shared variable shared_sbi_vvc_config : protected_vvc_config_pkg.t_prot_generic_array;
  alias shared_vvc_config is shared_sbi_vvc_config; -- This alias is for internal use in the VVC

  package protected_msg_id_panel_pkg is new uvvm_util.protected_generic_types_pkg
    generic map(t_generic_element => t_msg_id_panel,
                c_generic_default => C_VVC_MSG_ID_PANEL_DEFAULT);
  use protected_msg_id_panel_pkg.all;
  shared variable shared_sbi_vvc_msg_id_panel : protected_msg_id_panel_pkg.t_prot_generic_array;
  alias shared_vvc_msg_id_panel is shared_sbi_vvc_msg_id_panel; -- This alias is for internal use in the VVC

  -- Scoreboard
  package sbi_sb_pkg is new bitvis_vip_scoreboard.generic_sb_pkg
    generic map(
      t_element         => std_logic_vector(C_VVC_CMD_DATA_MAX_LENGTH - 1 downto 0),
      element_match     => std_match,
      to_string_element => to_string);
  use sbi_sb_pkg.all;
  shared variable SBI_VVC_SB : sbi_sb_pkg.t_prot_generic_sb;

  --==========================================================================================
  -- Methods dedicated to this VVC
  -- - These procedures are called from the testbench in order for the VVC to execute
  --   BFM calls towards the given interface. The VVC interpreter will queue these calls
  --   and then the VVC executor will fetch the commands from the queue and handle the
  --   actual BFM execution.
  --   For details on how the BFM procedures work, see the QuickRef.
  --==========================================================================================

  --==========================================================================================
  -- Methods dedicated to this VVC
  -- - These procedures are called from the testbench in order for the VVC to execute
  --   BFM calls towards the given interface. The VVC interpreter will queue these calls
  --   and then the VVC executor will fetch the commands from the queue and handle the
  --   actual BFM execution.
  --   For details on how the BFM procedures work, see the QuickRef.
  --==========================================================================================

  procedure sbi_write(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant addr                : in unsigned;
    constant data                : in std_logic_vector;
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  procedure sbi_write(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant addr                : in unsigned;
    constant num_words           : in natural;
    constant randomisation       : in t_randomisation;
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  procedure sbi_read(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant addr                : in unsigned;
    constant data_routing        : in t_data_routing;
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  procedure sbi_read(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant addr                : in unsigned;
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  procedure sbi_check(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant addr                : in unsigned;
    constant data                : in std_logic_vector;
    constant msg                 : in string;
    constant alert_level         : in t_alert_level  := ERROR;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  procedure sbi_poll_until(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant addr                : in unsigned;
    constant data                : in std_logic_vector;
    constant msg                 : in string;
    constant max_polls           : in integer        := 100;
    constant timeout             : in time           := 1 us; -- To assure a given timeout
    constant alert_level         : in t_alert_level  := ERROR;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  --==============================================================================
  -- Transaction Info methods
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

  --==============================================================================
  -- Hierarchical VVC SB
  --==============================================================================
  function to_sb_result(
    constant data : in std_logic_vector
  ) return t_vvc_result;

  --==============================================================================
  -- VVC Scoreboard helper method
  --==============================================================================
  function pad_sbi_sb(
    constant data : in std_logic_vector
  ) return std_logic_vector;

end package vvc_methods_pkg;

package body vvc_methods_pkg is

  --==============================================================================
  -- Methods dedicated to this VVC
  -- Notes:
  --   - shared_vvc_cmd is initialised to C_VVC_CMD_DEFAULT, and also reset to this after every command
  --==============================================================================

  procedure sbi_write(
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
    variable v_msg_id_panel    : t_msg_id_panel                                             := shared_msg_id_panel.get(VOID);
    variable v_local_vvc_cmd   : t_vvc_cmd_record                                           := shared_vvc_cmd.get(vvc_instance_idx); -- v3
    variable v_normalised_addr : unsigned(v_local_vvc_cmd.addr'length - 1 downto 0)         := normalize_and_check(addr, v_local_vvc_cmd.addr, ALLOW_WIDER_NARROWER, "addr", "shared_vvc_cmd.addr", proc_call & " called with too wide address. " & add_msg_delimiter(msg));
    variable v_normalised_data : std_logic_vector(v_local_vvc_cmd.data'length - 1 downto 0) := normalize_and_check(data, v_local_vvc_cmd.data, ALLOW_WIDER_NARROWER, "data", "shared_vvc_cmd.data", proc_call & " called with too wide data. " & add_msg_delimiter(msg));
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

  procedure sbi_write(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant addr                : in unsigned;
    constant num_words           : in natural;
    constant randomisation       : in t_randomisation;
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant proc_name : string := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant proc_call : string := proc_name & "(" & to_string(VVCT, vvc_instance_idx) -- First part common for all
                                   & ", " & to_string(addr, HEX, AS_IS, INCL_RADIX) & ", RANDOM)";
    variable v_msg_id_panel    : t_msg_id_panel                                     := shared_msg_id_panel.get(VOID);
    variable v_local_vvc_cmd   : t_vvc_cmd_record                                   := shared_vvc_cmd.get(vvc_instance_idx); -- v3
    variable v_normalised_addr : unsigned(v_local_vvc_cmd.addr'length - 1 downto 0) := normalize_and_check(addr, v_local_vvc_cmd.addr, ALLOW_WIDER_NARROWER, "addr", "shared_vvc_cmd.addr", proc_call & " called with too wide address. " & add_msg_delimiter(msg));
  begin
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, proc_call, msg, QUEUED, WRITE);

    -- v3
    v_local_vvc_cmd                     := shared_vvc_cmd.get(vvc_instance_idx);
    v_local_vvc_cmd.addr                := v_normalised_addr;
    v_local_vvc_cmd.randomisation       := randomisation;
    v_local_vvc_cmd.num_words           := num_words;
    v_local_vvc_cmd.parent_msg_id_panel := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(VVCT, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure;

  procedure sbi_read(
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

    variable v_msg_id_panel    : t_msg_id_panel                                     := shared_msg_id_panel.get(VOID);
    variable v_local_vvc_cmd   : t_vvc_cmd_record                                   := shared_vvc_cmd.get(vvc_instance_idx); -- v3
    variable v_normalised_addr : unsigned(v_local_vvc_cmd.addr'length - 1 downto 0) := normalize_and_check(addr, v_local_vvc_cmd.addr, ALLOW_WIDER_NARROWER, "addr", "shared_vvc_cmd.addr", proc_call & " called with too wide address. " & add_msg_delimiter(msg));
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

  procedure sbi_read(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant addr                : in unsigned;
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
  begin
    sbi_read(VVCT, vvc_instance_idx, addr, NA, msg, scope, parent_msg_id_panel);
  end procedure;

  procedure sbi_check(
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
    variable v_msg_id_panel    : t_msg_id_panel                                             := shared_msg_id_panel.get(VOID);
    variable v_local_vvc_cmd   : t_vvc_cmd_record                                           := shared_vvc_cmd.get(vvc_instance_idx); -- v3
    variable v_normalised_addr : unsigned(v_local_vvc_cmd.addr'length - 1 downto 0)         := normalize_and_check(addr, v_local_vvc_cmd.addr, ALLOW_WIDER_NARROWER, "addr", "shared_vvc_cmd.addr", proc_call & " called with too wide address. " & add_msg_delimiter(msg));
    variable v_normalised_data : std_logic_vector(v_local_vvc_cmd.data'length - 1 downto 0) := normalize_and_check(data, v_local_vvc_cmd.data, ALLOW_WIDER_NARROWER, "data", "shared_vvc_cmd.data", proc_call & " called with too wide data. " & add_msg_delimiter(msg));
  begin
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
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

  procedure sbi_poll_until(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant addr                : in unsigned;
    constant data                : in std_logic_vector;
    constant msg                 : in string;
    constant max_polls           : in integer        := 100;
    constant timeout             : in time           := 1 us;
    constant alert_level         : in t_alert_level  := ERROR;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant proc_name : string := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant proc_call : string := proc_name & "(" & to_string(VVCT, vvc_instance_idx) -- First part common for all
                                   & ", " & to_string(addr, HEX, AS_IS, INCL_RADIX) & ", " & to_string(data, HEX, AS_IS, INCL_RADIX) & ")";
    variable v_msg_id_panel    : t_msg_id_panel                                             := shared_msg_id_panel.get(VOID);
    variable v_local_vvc_cmd   : t_vvc_cmd_record                                           := shared_vvc_cmd.get(vvc_instance_idx); -- v3
    variable v_normalised_addr : unsigned(v_local_vvc_cmd.addr'length - 1 downto 0)         := normalize_and_check(addr, v_local_vvc_cmd.addr, ALLOW_WIDER_NARROWER, "addr", "shared_vvc_cmd.addr", proc_call & " called with too wide address. " & add_msg_delimiter(msg));
    variable v_normalised_data : std_logic_vector(v_local_vvc_cmd.data'length - 1 downto 0) := normalize_and_check(data, v_local_vvc_cmd.data, ALLOW_WIDER_NARROWER, "data", "shared_vvc_cmd.data", proc_call & " called with too wide data. " & add_msg_delimiter(msg));
  begin
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, proc_call, msg, QUEUED, POLL_UNTIL);

    -- v3
    v_local_vvc_cmd                     := shared_vvc_cmd.get(vvc_instance_idx);
    v_local_vvc_cmd.addr                := v_normalised_addr;
    v_local_vvc_cmd.data                := v_normalised_data;
    v_local_vvc_cmd.max_polls           := max_polls;
    v_local_vvc_cmd.timeout             := timeout;
    v_local_vvc_cmd.alert_level         := alert_level;
    v_local_vvc_cmd.parent_msg_id_panel := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(VVCT, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure;

  function to_sb_result(
    constant data : in std_logic_vector
  ) return t_vvc_result is
    variable v_vvc_result : t_vvc_result := (others => '-');
  begin
    v_vvc_result(data'length - 1 downto 0) := data;
    return v_vvc_result;
  end function to_sb_result;

  --==============================================================================
  -- Transaction Info methods
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
      when WRITE | READ | CHECK =>
        v_transaction_info_group.bt.operation                                 := vvc_cmd.operation;
        v_transaction_info_group.bt.address(vvc_cmd.addr'length - 1 downto 0) := vvc_cmd.addr;
        v_transaction_info_group.bt.data(vvc_cmd.data'length - 1 downto 0)    := vvc_cmd.data;
        v_transaction_info_group.bt.vvc_meta.msg(1 to vvc_cmd.msg'length)     := vvc_cmd.msg;
        v_transaction_info_group.bt.vvc_meta.cmd_idx                          := vvc_cmd.cmd_idx;
        v_transaction_info_group.bt.transaction_status                        := IN_PROGRESS;
        vvc_transaction_info_group.set(v_transaction_info_group, instance_idx, channel);
        gen_pulse(vvc_transaction_info_trigger, 0 ns, "pulsing global vvc transaction info trigger", scope, ID_NEVER);

      when POLL_UNTIL =>
        v_transaction_info_group.ct.operation                                 := vvc_cmd.operation;
        v_transaction_info_group.ct.address(vvc_cmd.addr'length - 1 downto 0) := vvc_cmd.addr;
        v_transaction_info_group.ct.data(vvc_cmd.data'length - 1 downto 0)    := vvc_cmd.data;
        v_transaction_info_group.ct.randomisation                             := vvc_cmd.randomisation;
        v_transaction_info_group.ct.num_words                                 := vvc_cmd.num_words;
        v_transaction_info_group.ct.max_polls                                 := vvc_cmd.max_polls;
        v_transaction_info_group.ct.vvc_meta.msg(1 to vvc_cmd.msg'length)     := vvc_cmd.msg;
        v_transaction_info_group.ct.vvc_meta.cmd_idx                          := vvc_cmd.cmd_idx;
        v_transaction_info_group.ct.transaction_status                        := IN_PROGRESS;
        vvc_transaction_info_group.set(v_transaction_info_group, instance_idx, channel);
        gen_pulse(vvc_transaction_info_trigger, 0 ns, "pulsing global vvc transaction info trigger", scope, ID_NEVER);

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
      when WRITE | READ | CHECK =>
        v_transaction_info_group.bt := C_BASE_TRANSACTION_SET_DEFAULT;

      when POLL_UNTIL =>
        v_transaction_info_group.ct := C_COMPOUND_TRANSACTION_SET_DEFAULT;

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

  --==============================================================================
  -- VVC Scoreboard helper method
  --==============================================================================

  function pad_sbi_sb(
    constant data : in std_logic_vector
  ) return std_logic_vector is
  begin
    return pad_sb_slv(data, C_VVC_CMD_DATA_MAX_LENGTH);
  end function pad_sbi_sb;

end package body vvc_methods_pkg;
