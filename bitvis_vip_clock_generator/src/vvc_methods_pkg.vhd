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
use uvvm_util.types_pkg.all;
use work.td_target_support_pkg.all;

package vvc_methods_support_pkg is

  --==========================================================================================
  -- Types and constants for the CLOCK_GENERATOR VVC
  --==========================================================================================
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

end package vvc_methods_support_pkg;

--================================================================================================================================
--  Generic package instantiations
--================================================================================================================================
----------------------------------------------------------------------
-- Protected type: t_vvc_status
----------------------------------------------------------------------
library uvvm_util;
use work.vvc_methods_support_pkg.all;
use work.vvc_cmd_pkg.all;

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
use work.vvc_cmd_pkg.all;

package protected_vvc_config_pkg is new uvvm_util.protected_generic_types_pkg
  generic map(
    t_generic_element  => t_vvc_config,
    c_generic_default  => C_CLOCK_GENERATOR_VVC_CONFIG_DEFAULT,
    c_max_instance_num => C_VVC_MAX_INSTANCE_NUM
  );

----------------------------------------------------------------------
-- Protected type: t_msg_id_panel
----------------------------------------------------------------------
library uvvm_util;
use uvvm_util.types_pkg.all;
use uvvm_util.adaptations_pkg.all;
use work.vvc_cmd_pkg.all;

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

use work.vvc_cmd_pkg.all;
use work.vvc_cmd_shared_variables_pkg.all;
use work.td_target_support_pkg.all;
use work.vvc_methods_support_pkg.all;
use work.protected_vvc_status_pkg.all;
use work.protected_vvc_config_pkg.all;
use work.protected_msg_id_panel_pkg.all;

package vvc_methods_pkg is

  shared variable shared_clock_generator_vvc_status       : work.protected_vvc_status_pkg.t_generic_array;
  shared variable shared_clock_generator_vvc_config       : work.protected_vvc_config_pkg.t_generic_array;
  shared variable shared_clock_generator_vvc_msg_id_panel : work.protected_msg_id_panel_pkg.t_generic_array;

  alias shared_vvc_status       is shared_clock_generator_vvc_status;       -- This alias is for internal use in the VVC
  alias shared_vvc_config       is shared_clock_generator_vvc_config;       -- This alias is for internal use in the VVC
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

end package vvc_methods_pkg;

package body vvc_methods_pkg is

  --==========================================================================================
  -- Methods dedicated to this VVC
  --==========================================================================================

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

end package body vvc_methods_pkg;
