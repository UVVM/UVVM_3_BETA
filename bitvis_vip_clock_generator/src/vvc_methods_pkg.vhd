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
--========================================================================================================================
-- This VVC was generated with Bitvis VVC Generator
--========================================================================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library uvvm_vvc_framework;
use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

use work.vvc_cmd_pkg.all;
use work.td_target_support_pkg.all;

--========================================================================================================================
--========================================================================================================================
package vvc_methods_pkg is

  --========================================================================================================================
  -- Types and constants for the CLOCK_GENERATOR VVC
  --========================================================================================================================
  constant C_VVC_NAME : string := "CLOCK_GENERATOR_VVC";

  signal CLOCK_GENERATOR_VVCT : t_vvc_target_record := set_vvc_target_defaults(C_VVC_NAME);
  alias THIS_VVCT             : t_vvc_target_record is CLOCK_GENERATOR_VVCT;
  alias t_bfm_config is t_void_bfm_config;

  -- Type found in UVVM-Util types_pkg
  constant C_CLOCK_GENERATOR_INTER_BFM_DELAY_DEFAULT : t_inter_bfm_delay := (
    delay_type                         => NO_DELAY,
    delay_in_time                      => 0 ns,
    inter_bfm_delay_violation_severity => WARNING
  );

  type t_vvc_config is record
    inter_bfm_delay : t_inter_bfm_delay; -- Minimum delay between BFM accesses from the VVC. If parameter delay_type is set to NO_DELAY, BFM accesses will be back to back, i.e. no delay.
    bfm_config      : t_bfm_config;      -- Configuration for the BFM. See BFM quick reference.
    clock_name      : string(1 to 30);
    clock_period    : time;
    clock_high_time : time;
  end record;

  constant C_CLOCK_GENERATOR_VVC_CONFIG_DEFAULT : t_vvc_config := (
    inter_bfm_delay => C_CLOCK_GENERATOR_INTER_BFM_DELAY_DEFAULT,
    bfm_config      => C_VOID_BFM_CONFIG,
    clock_name      => ("Set clock name", others => NUL),
    clock_period    => 10 ns,
    clock_high_time => 5 ns
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
    msg       : string(1 to C_VVC_CMD_STRING_MAX_LENGTH);
    --<USER_INPUT> Fields that could be useful to track in the waveview can be placed in this record.
    -- Example:
    -- addr            : unsigned(C_VVC_CMD_ADDR_MAX_LENGTH-1 downto 0);
    -- data            : std_logic_vector(C_VVC_CMD_DATA_MAX_LENGTH-1 downto 0);
  end record;

  type t_transaction_info_array is array (natural range <>) of t_transaction_info;

  constant C_TRANSACTION_INFO_DEFAULT : t_transaction_info := (
    --<USER_INPUT> Set the data fields added to the t_transaction_info record to
    -- their default values here.
    -- Example:
    -- addr                => (others => '0'),
    -- data                => (others => '0'),
    operation => NO_OPERATION,
    msg       => (others => ' ')
  );

  -- v3
  package protected_vvc_status_pkg is new uvvm_util.protected_generic_types_pkg
    generic map(t_generic_element => t_vvc_status,
                c_generic_default => C_VVC_STATUS_DEFAULT);
  use protected_vvc_status_pkg.all;
  shared variable shared_clock_generator_vvc_status : protected_vvc_status_pkg.t_prot_generic_array;
  alias shared_vvc_status is shared_clock_generator_vvc_status; -- This alias is for internal use in the VVC

  package protected_vvc_config_pkg is new uvvm_util.protected_generic_types_pkg
    generic map(t_generic_element => t_vvc_config,
                c_generic_default => C_CLOCK_GENERATOR_VVC_CONFIG_DEFAULT);
  use protected_vvc_config_pkg.all;
  shared variable shared_clock_generator_vvc_config : protected_vvc_config_pkg.t_prot_generic_array;
  alias shared_vvc_config is shared_clock_generator_vvc_config; -- This alias is for internal use in the VVC

  package protected_msg_id_panel_pkg is new uvvm_util.protected_generic_types_pkg
    generic map(t_generic_element => t_msg_id_panel,
                c_generic_default => C_VVC_MSG_ID_PANEL_DEFAULT);
  use protected_msg_id_panel_pkg.all;
  shared variable shared_clock_generator_vvc_msg_id_panel : protected_msg_id_panel_pkg.t_prot_generic_array;
  alias shared_vvc_msg_id_panel is shared_clock_generator_vvc_msg_id_panel; -- This alias is for internal use in the VVC

  --==========================================================================================
  -- Methods dedicated to this VVC
  -- - These procedures are called from the testbench in order for the VVC to execute
  --   BFM calls towards the given interface. The VVC interpreter will queue these calls
  --   and then the VVC executor will fetch the commands from the queue and handle the
  --   actual BFM execution.
  --   For details on how the BFM procedures work, see the QuickRef.
  --==========================================================================================

  procedure start_clock(
    signal   VVCT             : inout t_vvc_target_record;
    constant vvc_instance_idx : in integer;
    constant msg              : in string;
    constant scope            : in string := C_VVC_CMD_SCOPE_DEFAULT
  );

  procedure stop_clock(
    signal   VVCT             : inout t_vvc_target_record;
    constant vvc_instance_idx : in integer;
    constant msg              : in string;
    constant scope            : in string := C_VVC_CMD_SCOPE_DEFAULT
  );

  procedure set_clock_period(
    signal   VVCT             : inout t_vvc_target_record;
    constant vvc_instance_idx : in integer;
    constant clock_period     : in time;
    constant msg              : in string;
    constant scope            : in string := C_VVC_CMD_SCOPE_DEFAULT
  );

  procedure set_clock_high_time(
    signal   VVCT             : inout t_vvc_target_record;
    constant vvc_instance_idx : in integer;
    constant clock_high_time  : in time;
    constant msg              : in string;
    constant scope            : in string := C_VVC_CMD_SCOPE_DEFAULT
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

end package vvc_methods_pkg;

package body vvc_methods_pkg is

  --========================================================================================================================
  -- Methods dedicated to this VVC
  --========================================================================================================================

  procedure start_clock(
    signal   VVCT             : inout t_vvc_target_record;
    constant vvc_instance_idx : in integer;
    constant msg              : in string;
    constant scope            : in string := C_VVC_CMD_SCOPE_DEFAULT
  ) is
    constant proc_name : string := "start_clock";
    constant proc_call : string := proc_name & "(" & to_string(VVCT, vvc_instance_idx) -- First part common for all
                                   & ")";
  begin
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, proc_call, msg, QUEUED, START_CLOCK);
    send_command_to_vvc(VVCT, scope => scope);
  end procedure start_clock;

  procedure stop_clock(
    signal   VVCT             : inout t_vvc_target_record;
    constant vvc_instance_idx : in integer;
    constant msg              : in string;
    constant scope            : in string := C_VVC_CMD_SCOPE_DEFAULT
  ) is
    constant proc_name : string := "stop_clock";
    constant proc_call : string := proc_name & "(" & to_string(VVCT, vvc_instance_idx) -- First part common for all
                                   & ")";
  begin
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, proc_call, msg, QUEUED, STOP_CLOCK);
    send_command_to_vvc(VVCT, scope => scope);
  end procedure stop_clock;

  procedure set_clock_period(
    signal   VVCT             : inout t_vvc_target_record;
    constant vvc_instance_idx : in integer;
    constant clock_period     : in time;
    constant msg              : in string;
    constant scope            : in string := C_VVC_CMD_SCOPE_DEFAULT
  ) is
    constant proc_name : string := "set_clock_period";
    constant proc_call : string := proc_name & "(" & to_string(VVCT, vvc_instance_idx) -- First part common for all
                                   & ", " & to_string(clock_period) & ")";
    variable v_local_vvc_cmd : t_vvc_cmd_record := shared_vvc_cmd.get(vvc_instance_idx); -- v3
  begin
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, proc_call, msg, QUEUED, SET_CLOCK_PERIOD);

    -- v3
    v_local_vvc_cmd              := shared_vvc_cmd.get(vvc_instance_idx);
    v_local_vvc_cmd.clock_period := clock_period;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx);

    send_command_to_vvc(VVCT, scope => scope);
  end procedure set_clock_period;

  procedure set_clock_high_time(
    signal   VVCT             : inout t_vvc_target_record;
    constant vvc_instance_idx : in integer;
    constant clock_high_time  : in time;
    constant msg              : in string;
    constant scope            : in string := C_VVC_CMD_SCOPE_DEFAULT
  ) is
    constant proc_name : string := "set_clock_high_time";
    constant proc_call : string := proc_name & "(" & to_string(VVCT, vvc_instance_idx) -- First part common for all
                                   & ", " & to_string(clock_high_time) & ")";
    variable v_local_vvc_cmd : t_vvc_cmd_record := shared_vvc_cmd.get(vvc_instance_idx); -- v3
  begin
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, proc_call, msg, QUEUED, SET_CLOCK_HIGH_TIME);

    -- v3
    v_local_vvc_cmd                 := shared_vvc_cmd.get(vvc_instance_idx);
    v_local_vvc_cmd.clock_high_time := clock_high_time;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx);

    send_command_to_vvc(VVCT, scope => scope);
  end procedure set_clock_high_time;

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
