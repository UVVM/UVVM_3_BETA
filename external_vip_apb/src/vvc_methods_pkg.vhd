--================================================================================================================================
-- Copyright 2026 UVVM
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

--================================================================================================================================
--  Support package
--================================================================================================================================
library uvvm_util;
use uvvm_util.adaptations_pkg.all;
use uvvm_util.types_pkg.all;
use work.apb_bfm_pkg.all;
use work.td_target_support_pkg.all;

package vvc_methods_support_pkg is

  --==========================================================================================
  -- Types and constants for the APB VVC
  --==========================================================================================
  constant C_VVC_NAME : string := "APB_VVC";

  signal APB_VVCT : t_vvc_target_record := set_vvc_target_defaults(C_VVC_NAME);
  alias THIS_VVCT : t_vvc_target_record is APB_VVCT;
  alias t_bfm_config is t_APB_bfm_config;

  constant C_APB_INTER_BFM_DELAY_DEFAULT : t_inter_bfm_delay := (
    delay_type                         => NO_DELAY,
    delay_in_time                      => 0 ns,
    inter_bfm_delay_violation_severity => warning
  );

  -- Record for configuring the severity of unwanted transaction detection for each monitored DUT output
  type t_apb_unwanted_transaction is record
    prdata  : t_alert_level;
    pslverr : t_alert_level;
  end record t_apb_unwanted_transaction;

  constant C_APB_UNWANTED_TRANSACTION : t_apb_unwanted_transaction := (
    prdata  => NO_ALERT,
    pslverr => ERROR
  );

  type t_vvc_config is record
    inter_bfm_delay                       : t_inter_bfm_delay; -- Minimum delay between BFM accesses from the VVC. If parameter delay_type is set to NO_DELAY, BFM accesses will be back to back, i.e. no delay.
    bfm_config                            : t_bfm_config;      -- Configuration for the BFM. See BFM quick reference.
    unwanted_transaction_checking_enabled : boolean; -- Enable unwanted transaction checking
    unwanted_transaction_severity         : t_apb_unwanted_transaction; -- Severity of alert to be initiated if unwanted transaction on the DUT output is detected
  end record;

  constant C_APB_VVC_CONFIG_DEFAULT : t_vvc_config := (
    inter_bfm_delay                       => C_APB_INTER_BFM_DELAY_DEFAULT,
    bfm_config                            => C_APB_BFM_CONFIG_DEFAULT,
    unwanted_transaction_checking_enabled => C_UNWANTED_TRANSACTION_CHECKING_DEFAULT,
    unwanted_transaction_severity         => C_APB_UNWANTED_TRANSACTION
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
    GC_GENERIC_DEFAULT  => C_APB_VVC_CONFIG_DEFAULT,
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

use work.apb_bfm_pkg.all;
use work.vvc_cmd_pkg.all;
use work.td_target_support_pkg.all;
use work.vvc_transaction_pkg.all;
use work.protected_transaction_group_pkg.all;
use work.vvc_cmd_shared_variables_pkg.all;
use work.vvc_methods_support_pkg.all;
use work.protected_vvc_status_pkg.all;
use work.protected_vvc_config_pkg.all;
use work.protected_msg_id_panel_pkg.all;
use work.vvc_sb_pkg.all;

package vvc_methods_pkg is

  shared variable shared_apb_vvc_status       : work.protected_vvc_status_pkg.t_generic_array;
  shared variable shared_apb_vvc_config       : work.protected_vvc_config_pkg.t_generic_array;
  shared variable shared_apb_vvc_msg_id_panel : work.protected_msg_id_panel_pkg.t_generic_array;

  --===============================================================================================
  -- Types and constants for the APB VVC
  --===============================================================================================
  alias shared_vvc_config is shared_apb_vvc_config; -- This alias is for internal use in the VVC
  alias shared_vvc_status is shared_apb_vvc_status; -- This alias is for internal use in the VVC
  shared variable apb_vvc_sb : t_generic_sb;

  alias shared_vvc_msg_id_panel is shared_APB_vvc_msg_id_panel; -- This alias is for internal use in the VVC

  --==========================================================================================
  -- Methods dedicated to this VVC
  -- - These procedures are called from the testbench in order for the VVC to execute
  --   BFM calls towards the given interface. The VVC interpreter will queue these calls
  --   and then the VVC executor will fetch the commands from the queue and handle the
  --   actual BFM execution.
  --   For details on how the BFM procedures work, see the QuickRef.
  --==========================================================================================

  procedure apb_write(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant addr                : in unsigned;
    constant data                : in std_logic_vector;
    constant byte_enable         : in std_logic_vector;
    constant protection          : in std_logic_vector(2 downto 0);
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  procedure apb_write(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant addr                : in unsigned;
    constant data                : in std_logic_vector;
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  procedure apb_read(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant addr                : in unsigned;
    constant protection          : in std_logic_vector(2 downto 0);
    constant data_routing        : in t_data_routing;
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  procedure apb_read(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant addr                : in unsigned;
    constant protection          : in std_logic_vector(2 downto 0);
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  procedure apb_read(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant addr                : in unsigned;
    constant data_routing        : in t_data_routing;
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  procedure apb_read(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant addr                : in unsigned;
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  procedure apb_check(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant addr                : in unsigned;
    constant data                : in std_logic_vector;
    constant protection          : in std_logic_vector(2 downto 0);
    constant msg                 : in string;
    constant alert_level         : in t_alert_level  := ERROR;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  procedure apb_check(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant addr                : in unsigned;
    constant data                : in std_logic_vector;
    constant msg                 : in string;
    constant alert_level         : in t_alert_level  := ERROR;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  procedure apb_poll_until(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant addr                : in unsigned;
    constant data                : in std_logic_vector;
    constant protection          : in std_logic_vector(2 downto 0);
    constant msg                 : in string;
    constant max_polls           : in integer        := 100;
    constant timeout             : in time           := 1 us; -- To assure a given timeout
    constant alert_level         : in t_alert_level  := ERROR;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  procedure apb_poll_until(
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
    variable vvc_transaction_info_group   : inout work.protected_transaction_group_pkg.t_generic_array;
    constant instance_idx                 : in natural;
    constant channel                      : in t_channel;
    constant vvc_cmd                      : in t_vvc_cmd_record;
    constant vvc_config                   : in t_vvc_config;
    constant transaction_status           : in t_transaction_status;
    constant scope                        : in string := C_VVC_CMD_SCOPE_DEFAULT
  );

  procedure set_global_vvc_transaction_info(
    signal   vvc_transaction_info_trigger : inout std_logic;
    variable vvc_transaction_info_group   : inout work.protected_transaction_group_pkg.t_generic_array;
    constant instance_idx                 : in natural;
    constant channel                      : in t_channel;
    constant vvc_cmd                      : in t_vvc_cmd_record;
    constant vvc_result                   : in t_vvc_result;
    constant transaction_status           : in t_transaction_status;
    constant scope                        : in string := C_VVC_CMD_SCOPE_DEFAULT
  );

  procedure reset_vvc_transaction_info(
    variable vvc_transaction_info_group : inout work.protected_transaction_group_pkg.t_generic_array;
    constant instance_idx               : in natural;
    constant channel                    : in t_channel;
    constant vvc_cmd                    : in t_vvc_cmd_record
  );

end package vvc_methods_pkg;

package body vvc_methods_pkg is

  --==============================================================================
  -- Methods dedicated to this VVC
  -- Notes:
  --   - shared_vvc_cmd is initialised to C_VVC_CMD_DEFAULT, and also reset to this after every command
  --==============================================================================
  procedure apb_write(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant addr                : in unsigned;
    constant data                : in std_logic_vector;
    constant byte_enable         : in std_logic_vector;
    constant protection          : in std_logic_vector(2 downto 0);
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant C_PROC_NAME : string := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant C_PROC_CALL : string := C_PROC_NAME & "(" & to_string(VVCT, vvc_instance_idx) -- First part common for all
                                     & ", " & to_string(addr, HEX, AS_IS, INCL_RADIX) & ")";
    variable v_msg_id_panel    : t_msg_id_panel                                            := shared_msg_id_panel.get(VOID);
    variable v_local_vvc_cmd   : t_vvc_cmd_record := shared_vvc_cmd.get(vvc_instance_idx);
    variable v_normalised_addr : unsigned(v_local_vvc_cmd.addr'length - 1 downto 0) := normalize_and_check(addr, v_local_vvc_cmd.addr, ALLOW_WIDER_NARROWER, "addr", "shared_vvc_cmd.addr", C_PROC_CALL & " called with too wide address. " & add_msg_delimiter(msg));
    variable v_normalised_data : std_logic_vector(v_local_vvc_cmd.data'length - 1 downto 0) := normalize_and_check(data, v_local_vvc_cmd.data, ALLOW_WIDER_NARROWER, "data", "shared_vvc_cmd.data", C_PROC_CALL & " called with too wide data. " & add_msg_delimiter(msg));
    variable v_normalised_byte_enable : std_logic_vector(v_local_vvc_cmd.byte_enable'length - 1 downto 0) := normalize_and_check(byte_enable, v_local_vvc_cmd.byte_enable, ALLOW_WIDER_NARROWER, "byte_enable", "shared_vvc_cmd.byte_enable", C_PROC_CALL & " called with too wide byte_enable. " & add_msg_delimiter(msg));

  begin
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, C_PROC_CALL, msg, QUEUED, WRITE);
    v_local_vvc_cmd                     := shared_vvc_cmd.get(vvc_instance_idx);
    v_local_vvc_cmd.addr                := v_normalised_addr;
    v_local_vvc_cmd.data                := v_normalised_data;
    v_local_vvc_cmd.byte_enable         := v_normalised_byte_enable;
    v_local_vvc_cmd.protection          := protection;
    v_local_vvc_cmd.parent_msg_id_panel := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(VVCT, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure apb_write;

  procedure apb_write(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant addr                : in unsigned;
    constant data                : in std_logic_vector;
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant C_DEFAULT_BYTE_ENABLE : std_logic_vector((data'length / 8) - 1 downto 0) := (others => '1');
    constant C_DEFAULT_PROTECTION  : std_logic_vector(2 downto 0)                     := (others => '0');
  begin
    apb_write(VVCT, vvc_instance_idx, addr, data, C_DEFAULT_BYTE_ENABLE, C_DEFAULT_PROTECTION, msg, scope, parent_msg_id_panel);
  end procedure apb_write;

  procedure apb_read(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant addr                : in unsigned;
    constant protection          : in std_logic_vector(2 downto 0);
    constant data_routing        : in t_data_routing;
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant C_PROC_NAME : string := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant C_PROC_CALL : string := C_PROC_NAME & "(" & to_string(VVCT, vvc_instance_idx) -- First part common for all
                                     & ", " & to_string(addr, HEX, AS_IS, INCL_RADIX) & ")";
    variable v_msg_id_panel    : t_msg_id_panel                                    := shared_msg_id_panel.get(VOID);
    variable v_local_vvc_cmd   : t_vvc_cmd_record := shared_vvc_cmd.get(vvc_instance_idx);
    variable v_normalised_addr : unsigned(v_local_vvc_cmd.addr'length - 1 downto 0) := normalize_and_check(addr, v_local_vvc_cmd.addr, ALLOW_WIDER_NARROWER, "addr", "shared_vvc_cmd.addr", C_PROC_CALL & " called with too wide address. " & add_msg_delimiter(msg));

  begin
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, C_PROC_CALL, msg, QUEUED, READ);
    v_local_vvc_cmd                      := shared_vvc_cmd.get(vvc_instance_idx);
    v_local_vvc_cmd.addr                := v_normalised_addr;
    v_local_vvc_cmd.protection          := protection;
    v_local_vvc_cmd.data_routing        := data_routing;
    v_local_vvc_cmd.parent_msg_id_panel := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(VVCT, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure apb_read;

  procedure apb_read(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant addr                : in unsigned;
    constant protection          : in std_logic_vector(2 downto 0);
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
  begin
    apb_read(VVCT, vvc_instance_idx, addr, protection, NA, msg, scope, parent_msg_id_panel);
  end procedure apb_read;

  procedure apb_read(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant addr                : in unsigned;
    constant data_routing        : in t_data_routing;
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant C_DEFAULT_PROTECTION  : std_logic_vector(2 downto 0) := (others => '0');
  begin
    apb_read(VVCT, vvc_instance_idx, addr, C_DEFAULT_PROTECTION, data_routing, msg, scope, parent_msg_id_panel);
  end procedure apb_read;

  procedure apb_read(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant addr                : in unsigned;
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant C_DEFAULT_PROTECTION  : std_logic_vector(2 downto 0) := (others => '0');
  begin
    apb_read(VVCT, vvc_instance_idx, addr, C_DEFAULT_PROTECTION, NA, msg, scope, parent_msg_id_panel);
  end procedure apb_read;

  procedure apb_check(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant addr                : in unsigned;
    constant data                : in std_logic_vector;
    constant protection          : in std_logic_vector(2 downto 0);
    constant msg                 : in string;
    constant alert_level         : in t_alert_level  := ERROR;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant C_PROC_NAME : string := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant C_PROC_CALL : string := C_PROC_NAME & "(" & to_string(VVCT, vvc_instance_idx) -- First part common for all
                                     & ", " & to_string(addr, HEX, AS_IS, INCL_RADIX) & ")";
    variable v_msg_id_panel    : t_msg_id_panel                                            := shared_msg_id_panel.get(VOID);
    variable v_local_vvc_cmd   : t_vvc_cmd_record := shared_vvc_cmd.get(vvc_instance_idx);
    variable v_normalised_addr : unsigned(v_local_vvc_cmd.addr'length - 1 downto 0) := normalize_and_check(addr, v_local_vvc_cmd.addr, ALLOW_WIDER_NARROWER, "addr", "shared_vvc_cmd.addr", C_PROC_CALL & " called with too wide address. " & add_msg_delimiter(msg));
    variable v_normalised_data : std_logic_vector(v_local_vvc_cmd.data'length - 1 downto 0) := normalize_and_check(data, v_local_vvc_cmd.data, ALLOW_WIDER_NARROWER, "data", "shared_vvc_cmd.data", C_PROC_CALL & " called with too wide data. " & add_msg_delimiter(msg));

  begin
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, C_PROC_CALL, msg, QUEUED, CHECK);
    v_local_vvc_cmd                      := shared_vvc_cmd.get(vvc_instance_idx);
    v_local_vvc_cmd.addr                := v_normalised_addr;
    v_local_vvc_cmd.data                := v_normalised_data;
    v_local_vvc_cmd.protection          := protection;
    v_local_vvc_cmd.alert_level         := alert_level;
    v_local_vvc_cmd.parent_msg_id_panel := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(VVCT, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure apb_check;

  procedure apb_check(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant addr                : in unsigned;
    constant data                : in std_logic_vector;
    constant msg                 : in string;
    constant alert_level         : in t_alert_level  := ERROR;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant C_DEFAULT_PROTECTION  : std_logic_vector(2 downto 0) := (others => '0');
  begin
    apb_check(VVCT, vvc_instance_idx, addr, data, C_DEFAULT_PROTECTION, msg, alert_level, scope, parent_msg_id_panel);
  end procedure apb_check;

  procedure apb_poll_until(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant addr                : in unsigned;
    constant data                : in std_logic_vector;
    constant protection          : in std_logic_vector(2 downto 0);
    constant msg                 : in string;
    constant max_polls           : in integer        := 100;
    constant timeout             : in time           := 1 us;
    constant alert_level         : in t_alert_level  := ERROR;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant C_PROC_NAME : string := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant C_PROC_CALL : string := C_PROC_NAME & "(" & to_string(VVCT, vvc_instance_idx) -- First part common for all
                                     & ", " & to_string(addr, HEX, AS_IS, INCL_RADIX) & ", " & to_string(data, HEX, AS_IS, INCL_RADIX) & ")";
    variable v_local_vvc_cmd   : t_vvc_cmd_record := shared_vvc_cmd.get(vvc_instance_idx);
    variable v_normalised_addr : unsigned(v_local_vvc_cmd.addr'length - 1 downto 0)         := normalize_and_check(addr, v_local_vvc_cmd.addr, ALLOW_WIDER_NARROWER, "addr", "shared_vvc_cmd.addr", C_PROC_CALL & " called with too wide address. " & add_msg_delimiter(msg));
    variable v_normalised_data : std_logic_vector(v_local_vvc_cmd.data'length - 1 downto 0) := normalize_and_check(data, v_local_vvc_cmd.data, ALLOW_WIDER_NARROWER, "data", "shared_vvc_cmd.data", C_PROC_CALL & " called with too wide data. " & add_msg_delimiter(msg));
    variable v_msg_id_panel    : t_msg_id_panel                                            := shared_msg_id_panel.get(VOID);
  begin
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, C_PROC_CALL, msg, QUEUED, POLL_UNTIL);
    v_local_vvc_cmd                      := shared_vvc_cmd.get(vvc_instance_idx);
    v_local_vvc_cmd.addr                := v_normalised_addr;
    v_local_vvc_cmd.data                := v_normalised_data;
    v_local_vvc_cmd.protection          := protection;
    v_local_vvc_cmd.max_polls           := max_polls;
    v_local_vvc_cmd.timeout             := timeout;
    v_local_vvc_cmd.alert_level         := alert_level;
    v_local_vvc_cmd.parent_msg_id_panel := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(VVCT, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure apb_poll_until;

  procedure apb_poll_until(
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
    constant C_DEFAULT_PROTECTION  : std_logic_vector(2 downto 0) := (others => '0');
  begin
    apb_poll_until(VVCT, vvc_instance_idx, addr, data, C_DEFAULT_PROTECTION, msg, max_polls, timeout, alert_level, scope, parent_msg_id_panel);
  end procedure apb_poll_until;

  --==============================================================================
  -- Transaction Info methods
  --==============================================================================
  procedure set_global_vvc_transaction_info(
    signal   vvc_transaction_info_trigger : inout std_logic;
    variable vvc_transaction_info_group   : inout work.protected_transaction_group_pkg.t_generic_array;
    constant instance_idx                 : in natural;
    constant channel                      : in t_channel;
    constant vvc_cmd                      : in t_vvc_cmd_record;
    constant vvc_config                   : in t_vvc_config;
    constant transaction_status           : in t_transaction_status;
    constant scope                        : in string := C_VVC_CMD_SCOPE_DEFAULT) is
    variable v_transaction_info_group : t_transaction_group := vvc_transaction_info_group.get(instance_idx, channel);
  begin
    case vvc_cmd.operation is
      when WRITE | READ | CHECK =>
        v_transaction_info_group.bt.operation          := vvc_cmd.operation;
        v_transaction_info_group.bt.address            := vvc_cmd.addr;
        v_transaction_info_group.bt.data               := vvc_cmd.data;
        v_transaction_info_group.bt.vvc_meta.msg       := vvc_cmd.msg;
        v_transaction_info_group.bt.vvc_meta.cmd_idx   := vvc_cmd.cmd_idx;
        v_transaction_info_group.bt.transaction_status := transaction_status;
        vvc_transaction_info_group.set(v_transaction_info_group, instance_idx, channel);
        gen_pulse(vvc_transaction_info_trigger, 0 ns, "pulsing global vvc transaction info trigger", scope, ID_NEVER);

      when POLL_UNTIL =>
        v_transaction_info_group.ct.operation          := vvc_cmd.operation;
        v_transaction_info_group.ct.address            := vvc_cmd.addr;
        v_transaction_info_group.ct.data               := vvc_cmd.data;
        v_transaction_info_group.ct.max_polls          := vvc_cmd.max_polls;
        v_transaction_info_group.ct.vvc_meta.msg       := vvc_cmd.msg;
        v_transaction_info_group.ct.vvc_meta.cmd_idx   := vvc_cmd.cmd_idx;
        v_transaction_info_group.ct.transaction_status := transaction_status;
        vvc_transaction_info_group.set(v_transaction_info_group, instance_idx, channel);
        gen_pulse(vvc_transaction_info_trigger, 0 ns, "pulsing global vvc transaction info trigger", scope, ID_NEVER);

      when others =>
        alert(TB_ERROR, "VVC operation not recognized", scope);
    end case;

    wait for 0 ns;
  end procedure set_global_vvc_transaction_info;

  procedure set_global_vvc_transaction_info(
    signal   vvc_transaction_info_trigger : inout std_logic;
    variable vvc_transaction_info_group   : inout work.protected_transaction_group_pkg.t_generic_array;
    constant instance_idx                 : in natural;
    constant channel                      : in t_channel;
    constant vvc_cmd                      : in t_vvc_cmd_record;
    constant vvc_result                   : in t_vvc_result;
    constant transaction_status           : in t_transaction_status;
    constant scope                        : in string := C_VVC_CMD_SCOPE_DEFAULT) is
    variable v_transaction_info_group : t_transaction_group := vvc_transaction_info_group.get(instance_idx, channel);
  begin
    case vvc_cmd.operation is
      when READ =>
        v_transaction_info_group.bt.data               := vvc_result;
        v_transaction_info_group.bt.transaction_status := transaction_status;
        vvc_transaction_info_group.set(v_transaction_info_group, instance_idx, channel);
        gen_pulse(vvc_transaction_info_trigger, 0 ns, "pulsing global vvc transaction info trigger", scope, ID_NEVER);

      when others =>
        alert(TB_ERROR, "VVC operation does not update vvc_result", scope);
    end case;

    wait for 0 ns;
  end procedure set_global_vvc_transaction_info;

  procedure reset_vvc_transaction_info(
    variable vvc_transaction_info_group : inout work.protected_transaction_group_pkg.t_generic_array;
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

end package body vvc_methods_pkg;
