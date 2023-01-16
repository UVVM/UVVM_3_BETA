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
--
-- Note: This package will be compiled into every single VVC library.
--       As the type t_vvc_target_record is already compiled into every single VVC library,
--       the type definition will be unique for every library, and thus result in a unique
--       procedure signature for every VVC. Hence the shared variable shared_vvc_cmd will
--       refer to only the shared variable defined in the given library.
------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library std;
use std.textio.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library uvvm_vvc_framework;
use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;
use uvvm_vvc_framework.ti_protected_types_pkg.t_prot_vvc_list;

use work.vvc_cmd_pkg.all;               -- shared_vvc_response, t_vvc_result
use work.td_target_support_pkg.all;

package td_vvc_framework_common_methods_pkg is

  --======================================================================
  -- Common Methods
  --======================================================================

  procedure add_to_vvc_list(
    signal   vvc_target       : inout t_vvc_target_record;
    constant vvc_instance_idx : in integer;
    constant vvc_channel      : in t_channel;
    variable vvc_list         : inout t_prot_vvc_list
  );

  procedure add_to_vvc_list(
    signal   vvc_target       : inout t_vvc_target_record;
    constant vvc_instance_idx : in integer;
    variable vvc_list         : inout t_prot_vvc_list
  );

  -------------------------------------------
  -- await_completion
  -------------------------------------------
  -- VVC interpreter IMMEDIATE command
  -- - Awaits completion of all commands in the queue for the specified VVC, or
  --   until timeout.
  procedure await_completion(
    signal   vvc_target          : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant vvc_channel         : in t_channel;
    constant timeout             : in time;
    constant msg                 : in string         := "";
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT
  );

  -------------------------------------------
  -- await_completion
  -------------------------------------------
  -- See description above
  procedure await_completion(
    signal   vvc_target          : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant timeout             : in time;
    constant msg                 : in string         := "";
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT
  );

  -------------------------------------------
  -- await_completion
  -------------------------------------------
  -- VVC interpreter IMMEDIATE command
  -- - Awaits completion of the specified command 'wanted_idx' in the queue for the specified VVC, or
  --   until timeout.
  procedure await_completion(
    signal   vvc_target          : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant vvc_channel         : in t_channel;
    constant wanted_idx          : in integer;
    constant timeout             : in time;
    constant msg                 : in string         := "";
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT
  );

  -------------------------------------------
  -- await_completion
  -------------------------------------------
  -- See description above
  procedure await_completion(
    signal   vvc_target          : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant wanted_idx          : in integer;
    constant timeout             : in time;
    constant msg                 : in string         := "";
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT
  );

  -------------------------------------------
  -- disable_log_msg
  -------------------------------------------
  -- VVC interpreter IMMEDIATE command
  -- - Disables the specified msg_id for the VVC
  procedure disable_log_msg(
    signal   vvc_target          : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant vvc_channel         : in t_channel;
    constant msg_id              : in t_msg_id;
    constant msg                 : in string         := "";
    constant quietness           : in t_quietness    := NON_QUIET;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
  );

  -------------------------------------------
  -- disable_log_msg
  -------------------------------------------
  -- See description above
  procedure disable_log_msg(
    signal   vvc_target          : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant msg_id              : in t_msg_id;
    constant msg                 : in string         := "";
    constant quietness           : in t_quietness    := NON_QUIET;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
  );

  -------------------------------------------
  -- enable_log_msg
  -------------------------------------------
  -- VVC interpreter IMMEDIATE command
  -- - Enables the specified msg_id for the VVC
  procedure enable_log_msg(
    signal   vvc_target          : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant vvc_channel         : in t_channel;
    constant msg_id              : in t_msg_id;
    constant msg                 : in string         := "";
    constant quietness           : in t_quietness    := NON_QUIET;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
  );

  -------------------------------------------
  -- enable_log_msg
  -------------------------------------------
  -- See description above
  procedure enable_log_msg(
    signal   vvc_target          : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant msg_id              : in t_msg_id;
    constant msg                 : in string         := "";
    constant quietness           : in t_quietness    := NON_QUIET;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
  );

  -------------------------------------------
  -- flush_command_queue
  -------------------------------------------
  -- VVC interpreter IMMEDIATE command
  -- - Flushes the command queue of the specified VVC
  procedure flush_command_queue(
    signal   vvc_target          : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant vvc_channel         : in t_channel;
    constant msg                 : in string         := "";
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
  );

  -------------------------------------------
  -- flush_command_queue
  -------------------------------------------
  -- See description above
  procedure flush_command_queue(
    signal   vvc_target          : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant msg                 : in string         := "";
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
  );

  -------------------------------------------
  -- fetch_result
  -------------------------------------------
  -- VVC interpreter IMMEDIATE command
  -- - Fetches result from a VVC
  -- - Requires that result is available (i.e. already executed in respective VVC)
  -- - Logs with ID ID_UVVM_CMD_RESULT
  -- The 'result' parameter is of type t_vvc_result to
  -- support that the BFM returns something other than a std_logic_vector.
  procedure fetch_result(
    signal   vvc_target          : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant vvc_channel         : in t_channel;
    constant wanted_idx          : in integer;
    variable result              : out t_vvc_result;
    variable fetch_is_accepted   : out boolean;
    constant msg                 : in string         := "";
    constant alert_level         : in t_alert_level  := TB_ERROR;
    constant caller_name         : in string         := "base_procedure";
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
  );
  -- -- Same as above but without fetch_is_accepted.
  -- -- Will trigger alert with alert_level if not OK.
  procedure fetch_result(
    signal   vvc_target          : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant vvc_channel         : in t_channel;
    constant wanted_idx          : in integer;
    variable result              : out t_vvc_result;
    constant msg                 : in string         := "";
    constant alert_level         : in t_alert_level  := TB_ERROR;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
  );
  -- -- - This version does not use vvc_channel.
  -- -- - Fetches result from a VVC
  -- -- - Requires that result is available (i.e. already executed in respective VVC)
  -- -- - Logs with ID ID_UVVM_CMD_RESULT
  procedure fetch_result(
    signal   vvc_target          : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant wanted_idx          : in integer;
    variable result              : out t_vvc_result;
    variable fetch_is_accepted   : out boolean;
    constant msg                 : in string         := "";
    constant alert_level         : in t_alert_level  := TB_ERROR;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
  );
  -- -- Same as above but without fetch_is_accepted.
  -- -- Will trigger alert with alert_level if not OK.
  procedure fetch_result(
    signal   vvc_target          : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant wanted_idx          : in integer;
    variable result              : out t_vvc_result;
    constant msg                 : in string         := "";
    constant alert_level         : in t_alert_level  := TB_ERROR;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
  );

  -------------------------------------------
  -- insert_delay
  -------------------------------------------
  -- VVC executor QUEUED command
  -- - Inserts delay for 'delay' clock cycles
  procedure insert_delay(
    signal   vvc_target          : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant vvc_channel         : in t_channel;
    constant delay               : in natural; -- in clock cycles
    constant msg                 : in string         := "";
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
  );

  -------------------------------------------
  -- insert_delay
  -------------------------------------------
  -- See description above
  procedure insert_delay(
    signal   vvc_target          : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant delay               : in natural; -- in clock cycles
    constant msg                 : in string         := "";
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
  );

  -------------------------------------------
  -- insert_delay
  -------------------------------------------
  -- VVC executor QUEUED command
  -- - Inserts delay for a given time
  procedure insert_delay(
    signal   vvc_target          : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant vvc_channel         : in t_channel;
    constant delay               : in time;
    constant msg                 : in string         := "";
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
  );

  -------------------------------------------
  -- insert_delay
  -------------------------------------------
  -- See description above
  procedure insert_delay(
    signal   vvc_target          : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant delay               : in time;
    constant msg                 : in string         := "";
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
  );

  -------------------------------------------
  -- terminate_current_command
  -------------------------------------------
  -- VVC interpreter IMMEDIATE command
  -- - Terminates the current command being processed in the VVC executor
  procedure terminate_current_command(
    signal   vvc_target          : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant vvc_channel         : in t_channel;
    constant msg                 : in string         := "";
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
  );
  -- Overload without VVC channel
  procedure terminate_current_command(
    signal   vvc_target          : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant msg                 : in string         := "";
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
  );

  -------------------------------------------
  -- terminate_all_commands
  -------------------------------------------
  -- VVC interpreter IMMEDIATE command
  -- - Terminates the current command being processed in the VVC executor, and
  --   flushes the command queue
  procedure terminate_all_commands(
    signal   vvc_target          : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant vvc_channel         : in t_channel;
    constant msg                 : in string         := "";
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
  );
  -- Overload without VVC channel
  procedure terminate_all_commands(
    signal   vvc_target          : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant msg                 : in string         := "";
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
  );

  -- Returns the index of the last queued command
  impure function get_last_received_cmd_idx(
    signal   vvc_target       : in t_vvc_target_record;
    constant vvc_instance_idx : in integer;
    constant vvc_channel      : in t_channel := NA;
    constant scope            : in string    := C_VVC_CMD_SCOPE_DEFAULT
  ) return natural;

end package td_vvc_framework_common_methods_pkg;

package body td_vvc_framework_common_methods_pkg is

  --=========================================================================================
  --  Methods
  --=========================================================================================

  -- NOTE: ALL VVCs using this td_vvc_framework_common_methods_pkg package MUST have the following declared in their local transaction_pkg.
  --       - The enumerated t_operation  (e.g. AWAIT_COMPLETION, ENABLE_LOG_MSG, etc.)
  --       Any VVC based on an older version of td_vvc_framework_common_methods_pkg must - if new operators have been introduced in td_vvc_framework_common_methods_pkg either
  --       a) include the new operator(s) in its t_operation, or
  --       b) change the use-reference to an older common_methods package.

  procedure add_to_vvc_list(
    signal   vvc_target       : inout t_vvc_target_record;
    constant vvc_instance_idx : in integer;
    constant vvc_channel      : in t_channel;
    variable vvc_list         : inout t_prot_vvc_list
  ) is
  begin
    vvc_list.add(vvc_target.vvc_name, vvc_instance_idx, vvc_channel);
  end procedure add_to_vvc_list;

  procedure add_to_vvc_list(
    signal   vvc_target       : inout t_vvc_target_record;
    constant vvc_instance_idx : in integer;
    variable vvc_list         : inout t_prot_vvc_list
  ) is
  begin
    vvc_list.add(vvc_target.vvc_name, vvc_instance_idx, NA);
  end procedure add_to_vvc_list;

  -------------------------------------------
  -- await_completion
  -------------------------------------------
  -- VVC interpreter IMMEDIATE command
  -- - Awaits completion of all commands in the queue for the specified VVC, or
  --   until timeout.
  procedure await_completion(
    signal   vvc_target          : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant vvc_channel         : in t_channel;
    constant timeout             : in time;
    constant msg                 : in string         := "";
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT
  ) is
    variable v_vvc_list : t_prot_vvc_list;
  begin
    v_vvc_list.add(vvc_target.vvc_name, vvc_instance_idx, vvc_channel);
    await_completion(ALL_OF, v_vvc_list, timeout, CLEAR_LIST, msg, scope);
  end procedure await_completion;

  -------------------------------------------
  -- await_completion
  -------------------------------------------
  -- See description above
  procedure await_completion(
    signal   vvc_target          : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant timeout             : in time;
    constant msg                 : in string         := "";
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT
  ) is
    variable v_vvc_list : t_prot_vvc_list;
  begin
    v_vvc_list.add(vvc_target.vvc_name, vvc_instance_idx, NA);
    await_completion(ALL_OF, v_vvc_list, timeout, CLEAR_LIST, msg, scope);
  end procedure await_completion;

  -------------------------------------------
  -- await_completion
  -------------------------------------------
  -- VVC interpreter IMMEDIATE command
  -- - Awaits completion of the specified command 'wanted_idx' in the queue for the specified VVC, or
  --   until timeout.
  procedure await_completion(
    signal   vvc_target          : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant vvc_channel         : in t_channel;
    constant wanted_idx          : in integer;
    constant timeout             : in time;
    constant msg                 : in string         := "";
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT
  ) is
    variable v_vvc_list : t_prot_vvc_list;
  begin
    v_vvc_list.add(vvc_target.vvc_name, vvc_instance_idx, vvc_channel);
    await_completion(ALL_OF, v_vvc_list, wanted_idx, timeout, CLEAR_LIST, msg, scope);
  end procedure await_completion;

  -------------------------------------------
  -- await_completion
  -------------------------------------------
  -- See description above
  procedure await_completion(
    signal   vvc_target          : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant wanted_idx          : in integer;
    constant timeout             : in time;
    constant msg                 : in string         := "";
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT
  ) is
    variable v_vvc_list : t_prot_vvc_list;
  begin
    v_vvc_list.add(vvc_target.vvc_name, vvc_instance_idx, NA);
    await_completion(ALL_OF, v_vvc_list, wanted_idx, timeout, CLEAR_LIST, msg, scope);
  end procedure await_completion;

  -------------------------------------------
  -- disable_log_msg
  -------------------------------------------
  procedure disable_log_msg(
    signal   vvc_target          : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant vvc_channel         : in t_channel;
    constant msg_id              : in t_msg_id;
    constant msg                 : in string         := "";
    constant quietness           : in t_quietness    := NON_QUIET;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
  ) is
    constant proc_name : string := "disable_log_msg";
    constant proc_call : string := proc_name & "(" & to_string(vvc_target, vvc_instance_idx, vvc_channel) -- First part common for all
                                   & ", " & to_upper(to_string(msg_id)) & ")";
    variable v_msg_id_panel  : t_msg_id_panel := shared_msg_id_panel.get(VOID);
    variable v_local_vvc_cmd : t_vvc_cmd_record;
  begin
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(vvc_target, vvc_instance_idx, vvc_channel, proc_call, msg, IMMEDIATE, DISABLE_LOG_MSG);

    -- v3
    v_local_vvc_cmd                     := shared_vvc_cmd.get(vvc_instance_idx, vvc_channel);
    v_local_vvc_cmd.msg_id              := msg_id;
    v_local_vvc_cmd.quietness           := quietness;
    v_local_vvc_cmd.parent_msg_id_panel := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx, vvc_channel);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(vvc_target, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure;

  procedure disable_log_msg(
    signal   vvc_target          : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant msg_id              : in t_msg_id;
    constant msg                 : in string         := "";
    constant quietness           : in t_quietness    := NON_QUIET;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
  ) is
  begin
    disable_log_msg(vvc_target, vvc_instance_idx, NA, msg_id, msg, quietness, scope, parent_msg_id_panel);
  end procedure;

  procedure enable_log_msg(
    signal   vvc_target          : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant vvc_channel         : in t_channel;
    constant msg_id              : in t_msg_id;
    constant msg                 : in string         := "";
    constant quietness           : in t_quietness    := NON_QUIET;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
  ) is
    constant proc_name : string := "enable_log_msg";
    constant proc_call : string := proc_name & "(" & to_string(vvc_target, vvc_instance_idx, vvc_channel) -- First part common for all
                                   & ", " & to_upper(to_string(msg_id)) & ")";
    variable v_msg_id_panel  : t_msg_id_panel := shared_msg_id_panel.get(VOID);
    variable v_local_vvc_cmd : t_vvc_cmd_record;
  begin
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(vvc_target, vvc_instance_idx, vvc_channel, proc_call, msg, IMMEDIATE, ENABLE_LOG_MSG);

    -- v3
    v_local_vvc_cmd                     := shared_vvc_cmd.get(vvc_instance_idx, vvc_channel);
    v_local_vvc_cmd.msg_id              := msg_id;
    v_local_vvc_cmd.quietness           := quietness;
    v_local_vvc_cmd.parent_msg_id_panel := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx, vvc_channel);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(vvc_target, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure;

  procedure enable_log_msg(
    signal   vvc_target          : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant msg_id              : in t_msg_id;
    constant msg                 : in string         := "";
    constant quietness           : in t_quietness    := NON_QUIET;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
  ) is
  begin
    enable_log_msg(vvc_target, vvc_instance_idx, NA, msg_id, msg, quietness, scope, parent_msg_id_panel);
  end procedure;

  procedure flush_command_queue(
    signal   vvc_target          : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant vvc_channel         : in t_channel;
    constant msg                 : in string         := "";
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
  ) is
    constant proc_name       : string         := "flush_command_queue";
    constant proc_call       : string         := proc_name & "(" & to_string(vvc_target, vvc_instance_idx, vvc_channel) & ")";
    variable v_msg_id_panel  : t_msg_id_panel := shared_msg_id_panel.get(VOID);
    variable v_local_vvc_cmd : t_vvc_cmd_record;
  begin
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(vvc_target, vvc_instance_idx, vvc_channel, proc_call, msg, IMMEDIATE, FLUSH_COMMAND_QUEUE);

    -- v3
    v_local_vvc_cmd                     := shared_vvc_cmd.get(vvc_instance_idx, vvc_channel);
    v_local_vvc_cmd.parent_msg_id_panel := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx, vvc_channel);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(vvc_target, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure;

  procedure flush_command_queue(
    signal   vvc_target          : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant msg                 : in string         := "";
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
  ) is
  begin
    flush_command_queue(vvc_target, vvc_instance_idx, NA, msg, scope, parent_msg_id_panel);
  end procedure;

  -- Requires that result is available (i.e. already executed in respective VVC)
  -- The four next procedures are overloads for when 'result' is of type work.vvc_cmd_pkg.t_vvc_result
  procedure fetch_result(
    signal   vvc_target          : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant vvc_channel         : in t_channel;
    constant wanted_idx          : in integer;
    variable result              : out t_vvc_result;
    variable fetch_is_accepted   : out boolean;
    constant msg                 : in string         := "";
    constant alert_level         : in t_alert_level  := TB_ERROR;
    constant caller_name         : in string         := "base_procedure";
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
  ) is
    constant proc_name : string := "fetch_result";
    constant proc_call : string := proc_name & "(" & to_string(vvc_target, vvc_instance_idx, vvc_channel) -- First part common for all
                                   & ", " & to_string(wanted_idx) & ")";
    variable v_msg_id_panel  : t_msg_id_panel := shared_msg_id_panel.get(VOID);
    variable v_local_vvc_cmd : t_vvc_cmd_record;
    variable v_vvc_response  : t_vvc_response;
  begin
    await_semaphore_in_delta_cycles(shared_response_semaphore);
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(vvc_target, vvc_instance_idx, vvc_channel, proc_call, msg, IMMEDIATE, FETCH_RESULT);

    -- v3
    v_local_vvc_cmd                      := shared_vvc_cmd.get(vvc_instance_idx, vvc_channel);
    v_local_vvc_cmd.gen_integer_array(0) := wanted_idx;
    v_local_vvc_cmd.parent_msg_id_panel  := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx, vvc_channel);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(vvc_target, std.env.resolution_limit, scope, v_msg_id_panel);
    -- Post process
    v_vvc_response    := shared_vvc_response.get(vvc_instance_idx, vvc_channel); -- v3
    result            := v_vvc_response.result;
    fetch_is_accepted := v_vvc_response.fetch_is_accepted;
    if caller_name = "base_procedure" then
      log(ID_UVVM_CMD_RESULT, proc_call & ": Legal=>" & to_string(v_vvc_response.fetch_is_accepted) & ", Result=>" & to_string(result) & format_command_idx(shared_cmd_idx.get(VOID)), scope, v_msg_id_panel); -- Get and ack the new command
    end if;
    release_semaphore(shared_response_semaphore);
  end procedure;

  procedure fetch_result(
    signal   vvc_target          : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant vvc_channel         : in t_channel;
    constant wanted_idx          : in integer;
    variable result              : out t_vvc_result;
    constant msg                 : in string         := "";
    constant alert_level         : in t_alert_level  := TB_ERROR;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
  ) is
    variable v_fetch_is_accepted : boolean;
    variable v_msg_id_panel      : t_msg_id_panel := shared_msg_id_panel.get(VOID);
    constant proc_name           : string         := "fetch_result";
    constant proc_call           : string         := proc_name & "(" & to_string(vvc_target, vvc_instance_idx, vvc_channel) -- First part common for all
                                                     & ", " & to_string(wanted_idx) & ")";
  begin
    fetch_result(vvc_target, vvc_instance_idx, vvc_channel, wanted_idx, result, v_fetch_is_accepted, msg, alert_level, proc_name & "_with_check_of_ok", scope, parent_msg_id_panel);
    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    if v_fetch_is_accepted then
      log(ID_UVVM_CMD_RESULT, proc_call & ": Legal=>" & to_string(v_fetch_is_accepted) & ", Result=>" & to_string(result) & format_command_idx(shared_cmd_idx.get(VOID)), scope, v_msg_id_panel); -- Get and ack the new command
    else
      alert(alert_level, "fetch_result(" & to_string(wanted_idx) & "): " & add_msg_delimiter(msg) & "." & " Failed. Trying to fetch result from not yet executed command or from command with no result stored.  " & format_command_idx(shared_cmd_idx.get(VOID)), scope);
    end if;
  end procedure;

  procedure fetch_result(
    signal   vvc_target          : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant wanted_idx          : in integer;
    variable result              : out t_vvc_result;
    variable fetch_is_accepted   : out boolean;
    constant msg                 : in string         := "";
    constant alert_level         : in t_alert_level  := TB_ERROR;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
  ) is
  begin
    fetch_result(vvc_target, vvc_instance_idx, NA, wanted_idx, result, fetch_is_accepted, msg, alert_level, "base_procedure", scope, parent_msg_id_panel);
  end procedure;

  procedure fetch_result(
    signal   vvc_target          : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant wanted_idx          : in integer;
    variable result              : out t_vvc_result;
    constant msg                 : in string         := "";
    constant alert_level         : in t_alert_level  := TB_ERROR;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
  ) is
  begin
    fetch_result(vvc_target, vvc_instance_idx, NA, wanted_idx, result, msg, alert_level, scope, parent_msg_id_panel);
  end procedure;

  procedure insert_delay(
    signal   vvc_target          : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant vvc_channel         : in t_channel;
    constant delay               : in natural; -- in clock cycles
    constant msg                 : in string         := "";
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
  ) is
    constant proc_name : string := "insert_delay";
    constant proc_call : string := proc_name & "(" & to_string(vvc_target, vvc_instance_idx, vvc_channel) -- First part common for all
                                   & ", " & to_string(delay) & ")";
    variable v_msg_id_panel  : t_msg_id_panel := shared_msg_id_panel.get(VOID);
    variable v_local_vvc_cmd : t_vvc_cmd_record;
  begin
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(vvc_target, vvc_instance_idx, vvc_channel, proc_call, msg, QUEUED, INSERT_DELAY);

    -- v3
    v_local_vvc_cmd                      := shared_vvc_cmd.get(vvc_instance_idx, vvc_channel);
    v_local_vvc_cmd.gen_integer_array(0) := delay;
    v_local_vvc_cmd.parent_msg_id_panel  := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx, vvc_channel);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(vvc_target, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure;

  procedure insert_delay(
    signal   vvc_target          : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant delay               : in natural; -- in clock cycles
    constant msg                 : in string         := "";
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
  ) is
  begin
    insert_delay(vvc_target, vvc_instance_idx, NA, delay, msg, scope, parent_msg_id_panel);
  end procedure;

  procedure insert_delay(
    signal   vvc_target          : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant vvc_channel         : in t_channel;
    constant delay               : in time;
    constant msg                 : in string         := "";
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
  ) is
    constant proc_name : string := "insert_delay";
    constant proc_call : string := proc_name & "(" & to_string(vvc_target, vvc_instance_idx, vvc_channel) -- First part common for all
                                   & ", " & to_string(delay) & ")";
    variable v_msg_id_panel  : t_msg_id_panel := shared_msg_id_panel.get(VOID);
    variable v_local_vvc_cmd : t_vvc_cmd_record;
  begin
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(vvc_target, vvc_instance_idx, vvc_channel, proc_call, msg, QUEUED, INSERT_DELAY);

    -- v3
    v_local_vvc_cmd                     := shared_vvc_cmd.get(vvc_instance_idx, vvc_channel);
    v_local_vvc_cmd.delay               := delay;
    v_local_vvc_cmd.parent_msg_id_panel := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx, vvc_channel);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(vvc_target, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure;

  procedure insert_delay(
    signal   vvc_target          : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant delay               : in time;
    constant msg                 : in string         := "";
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
  ) is
  begin
    insert_delay(vvc_target, vvc_instance_idx, NA, delay, msg, scope, parent_msg_id_panel);
  end procedure;

  procedure terminate_current_command(
    signal   vvc_target          : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant vvc_channel         : in t_channel;
    constant msg                 : in string         := "";
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
  ) is
    constant proc_name : string := "terminate_current_command";
    constant proc_call : string := proc_name & "(" & to_string(vvc_target, vvc_instance_idx, vvc_channel) -- First part common for all
                                   & ")";
    variable v_msg_id_panel  : t_msg_id_panel := shared_msg_id_panel.get(VOID);
    variable v_local_vvc_cmd : t_vvc_cmd_record;
  begin
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(vvc_target, vvc_instance_idx, vvc_channel, proc_call, msg, IMMEDIATE, TERMINATE_CURRENT_COMMAND);

    -- v3
    v_local_vvc_cmd                     := shared_vvc_cmd.get(vvc_instance_idx, vvc_channel);
    v_local_vvc_cmd.parent_msg_id_panel := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx, vvc_channel);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(vvc_target, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure;

  -- Overload without VVC channel
  procedure terminate_current_command(
    signal   vvc_target          : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant msg                 : in string         := "";
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
  ) is
    constant vvc_channel : t_channel := NA;
    constant proc_name   : string    := "terminate_current_command";
    constant proc_call   : string    := proc_name & "(" & to_string(vvc_target, vvc_instance_idx) -- First part common for all
                                        & ")";
  begin
    terminate_current_command(vvc_target, vvc_instance_idx, vvc_channel, msg, scope, parent_msg_id_panel);
  end procedure;

  procedure terminate_all_commands(
    signal   vvc_target          : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant vvc_channel         : in t_channel;
    constant msg                 : in string         := "";
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
  ) is
  begin
    flush_command_queue(vvc_target, vvc_instance_idx, vvc_channel, msg, scope, parent_msg_id_panel);
    terminate_current_command(vvc_target, vvc_instance_idx, vvc_channel, msg, scope, parent_msg_id_panel);
  end procedure;

  -- Overload without VVC channel
  procedure terminate_all_commands(
    signal   vvc_target          : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant msg                 : in string         := "";
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL
  ) is
    constant vvc_channel : t_channel := NA;
  begin
    terminate_all_commands(vvc_target, vvc_instance_idx, vvc_channel, msg, scope, parent_msg_id_panel);
  end procedure;

  ---- Returns the index of the last queued command
  impure function get_last_received_cmd_idx(
    signal   vvc_target       : in t_vvc_target_record;
    constant vvc_instance_idx : in integer;
    constant vvc_channel      : in t_channel := NA;
    constant scope            : in string    := C_VVC_CMD_SCOPE_DEFAULT
  ) return natural is
    variable v_cmd_idx : integer := -1;
  begin
    v_cmd_idx := shared_vvc_last_received_cmd_idx.get(vvc_instance_idx, vvc_channel);
    check_value(v_cmd_idx /= -1, tb_error, "Channel " & to_string(vvc_channel) & " not supported on VVC " & vvc_target.vvc_name, scope, ID_NEVER);
    if v_cmd_idx /= -1 then
      return v_cmd_idx;
    else
      -- return 0 in case of failure
      return 0;
    end if;
  end function;

end package body td_vvc_framework_common_methods_pkg;
