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

use work.td_cmd_queue_pkg.all;
use work.td_result_queue_pkg.all;
use work.vvc_cmd_pkg.all;
use work.vvc_methods_pkg.all;
use work.td_vvc_framework_common_methods_pkg.all;
use work.td_target_support_pkg.all;
use work.vvc_methods_pkg.all;

--=================================================================================================
--=================================================================================================
--=================================================================================================
package td_vvc_entity_support_pkg is

  type t_vvc_labels is record
    scope        : string(1 to C_LOG_SCOPE_WIDTH);
    vvc_name     : string(1 to C_LOG_SCOPE_WIDTH - 2);
    instance_idx : natural;
    channel      : t_channel;
  end record;

  -------------------------------------------
  -- assign_vvc_labels
  -------------------------------------------
  -- This function puts common VVC labels into a record - to reduce the number of procedure parameters
  function assign_vvc_labels(
    scope        : string;
    vvc_name     : string;
    instance_idx : integer;
    channel      : t_channel
  ) return t_vvc_labels;

  -------------------------------------------
  -- format_msg
  -------------------------------------------
  -- Generates a sting containing the command message and index
  -- - Format: Message [index]
  impure function format_msg(
    command : t_vvc_cmd_record
  ) return string;

  -------------------------------------------
  -- vvc_constructor
  -------------------------------------------
  -- Procedure used as concurrent process in the VVCs
  -- - Sets up the vvc_config, command queue and result_queue
  -- - Verifies that UVVM has been initialized
  procedure vvc_constructor(
    constant scope                                 : in string;
    constant instance_idx                          : in natural;
    constant channel                               : in t_channel;
    --variable vvc_config                            : inout t_vvc_config;
    variable vvc_config                            : inout work.vvc_methods_pkg.protected_vvc_config_pkg.t_prot_generic_array; -- v3
    constant msg_id_panel                          : in t_msg_id_panel; -- v3
    variable command_queue                         : inout work.td_cmd_queue_pkg.t_prot_generic_queue;
    variable result_queue                          : inout work.td_result_queue_pkg.t_prot_generic_queue;
    constant bfm_config                            : in t_bfm_config;
    constant cmd_queue_count_max                   : in natural;
    constant cmd_queue_count_threshold             : in natural;
    constant cmd_queue_count_threshold_severity    : in t_alert_level;
    constant result_queue_count_max                : in natural;
    constant result_queue_count_threshold          : in natural;
    constant result_queue_count_threshold_severity : in t_alert_level
  );

  -- overload without t_channel
  procedure vvc_constructor(
    constant scope                                 : in string;
    constant instance_idx                          : in natural;
    --variable vvc_config                            : inout t_vvc_config;
    variable vvc_config                            : inout work.vvc_methods_pkg.protected_vvc_config_pkg.t_prot_generic_array; -- v3
    constant msg_id_panel                          : in t_msg_id_panel; -- v3
    variable command_queue                         : inout work.td_cmd_queue_pkg.t_prot_generic_queue;
    variable result_queue                          : inout work.td_result_queue_pkg.t_prot_generic_queue;
    constant bfm_config                            : in t_bfm_config;
    constant cmd_queue_count_max                   : in natural;
    constant cmd_queue_count_threshold             : in natural;
    constant cmd_queue_count_threshold_severity    : in t_alert_level;
    constant result_queue_count_max                : in natural;
    constant result_queue_count_threshold          : in natural;
    constant result_queue_count_threshold_severity : in t_alert_level
  );

  -------------------------------------------
  -- initialize_interpreter
  -------------------------------------------
  -- Initialises the VVC interpreter
  -- - Clears terminate_current_cmd.set to '0'
  procedure initialize_interpreter(
    signal terminate_current_cmd      : out t_flag_record
  );

  -------------------------------------------
  -- await_cmd_from_sequencer
  -------------------------------------------
  -- Waits for a command from the central sequencer. Continues on matching VVC, Instance, Name and Channel (unless channel = NA)
  -- - Log at start using ID_CMD_INTERPRETER_WAIT and at the end using ID_CMD_INTERPRETER
  procedure await_cmd_from_sequencer(
    constant vvc_labels      : in t_vvc_labels;
    constant msg_id_panel    : in t_msg_id_panel; -- v3
    signal   VVCT            : in t_vvc_target_record;
    signal   VVC_BROADCAST   : inout std_logic;
    signal   global_vvc_busy : inout std_logic;
    signal   vvc_ack         : out std_logic;
    variable output_vvc_cmd  : out t_vvc_cmd_record
  );

  --    -- DEPRECATED
  --    procedure await_cmd_from_sequencer(
  --        constant vvc_labels          : in t_vvc_labels;
  --        constant msg_id_panel        : in t_msg_id_panel; -- v3
  --        constant parent_msg_id_panel : in t_msg_id_panel; -- v3
  --        signal   VVCT                : in t_vvc_target_record;
  --        signal   VVC_BROADCAST       : inout std_logic;
  --        signal   global_vvc_busy     : inout std_logic;
  --        signal   vvc_ack             : out std_logic;
  --        constant shared_vvc_cmd      : in t_vvc_cmd_record;
  --        variable output_vvc_cmd      : out t_vvc_cmd_record
  --    );

  -------------------------------------------
  -- put_command_on_queue
  -------------------------------------------
  -- Puts the received command (by Interpreter) on the VVC queue (for later retrieval by Executor)
  procedure put_command_on_queue(
    constant command             : in t_vvc_cmd_record;
    variable command_queue       : inout work.td_cmd_queue_pkg.t_prot_generic_queue;
    variable vvc_status          : inout t_vvc_status;
    signal   queue_is_increasing : out boolean
  );

  -------------------------------------------
  -- interpreter_flush_command_queue
  -------------------------------------------
  -- Immediate command: flush_command_queue (in interpreter)
  -- - Command description in Quick reference for UVVM common methods
  -- - Log using ID_IMMEDIATE_CMD
  procedure interpreter_flush_command_queue(
    constant command       : in t_vvc_cmd_record;
    variable command_queue : inout work.td_cmd_queue_pkg.t_prot_generic_queue;
    constant msg_id_panel  : in t_msg_id_panel; -- v3
    variable vvc_status    : inout t_vvc_status;
    constant vvc_labels    : in t_vvc_labels
  );

  -------------------------------------------
  -- interpreter_terminate_current_command
  -------------------------------------------
  -- Immediate command: terminate_current_command (in interpreter)
  -- - Command description in Quick reference for UVVM common methods
  -- - Log using ID_IMMEDIATE_CMD
  procedure interpreter_terminate_current_command(
    constant command               : in t_vvc_cmd_record;
    constant msg_id_panel          : in t_msg_id_panel; -- v3
    constant vvc_labels            : in t_vvc_labels;
    signal   terminate_current_cmd : inout t_flag_record;
    constant executor_is_busy      : in boolean := true
  );

  -------------------------------------------
  -- interpreter_fetch_result
  -------------------------------------------
  -- Immediate command: interpreter_fetch_result (in interpreter)
  -- - Command description in Quick reference for UVVM common methods
  -- - Log using ID_IMMEDIATE_CMD
  -- t_vvc_response is specific to each VVC,
  -- so the BFM can return any type which is then transported from the VVC to the sequencer via a fetch_result() call
  procedure interpreter_fetch_result(
    variable result_queue          : inout work.td_result_queue_pkg.t_prot_generic_queue;
    constant command               : in t_vvc_cmd_record;
    constant msg_id_panel          : in t_msg_id_panel; -- v3
    constant vvc_labels            : in t_vvc_labels;
    constant last_cmd_idx_executed : in natural;
    variable vvc_response          : inout protected_vvc_response_pkg.t_prot_generic_array
  );

  -------------------------------------------
  -- initialize_executor
  -------------------------------------------
  -- Initialises the VVC executor
  -- - Resets terminate_current_cmd.reset flag
  procedure initialize_executor(
    signal terminate_current_cmd : inout t_flag_record
  );

  -------------------------------------------
  -- fetch_command_and_prepare_executor
  -------------------------------------------
  -- Fetches a command from the queue (waits until available if needed)
  -- - Log command using ID_CMD_EXECUTOR
  -- - Log using ID_CMD_EXECUTOR_WAIT if queue is empty
  -- - Sets relevant flags
  procedure fetch_command_and_prepare_executor(
    variable command             : inout t_vvc_cmd_record;
    variable command_queue       : inout work.td_cmd_queue_pkg.t_prot_generic_queue;
    variable vvc_status          : inout protected_vvc_status_pkg.t_prot_generic_array; -- v3
    signal   queue_is_increasing : in boolean;
    signal   executor_is_busy    : inout boolean;
    constant vvc_labels          : in t_vvc_labels;
    constant executor_id         : in t_msg_id := ID_CMD_EXECUTOR;
    constant executor_wait_id    : in t_msg_id := ID_CMD_EXECUTOR_WAIT
  );

  -------------------------------------------
  -- store_result
  -------------------------------------------
  -- Store result from BFM in the VVC's result_queue
  -- The result_queue is used to store a generic type that is returned from
  -- a read/expect BFM procedure.
  -- It can be fetched later using fetch_result() to return it from the VVC to sequencer
  procedure store_result(
    variable result_queue : inout work.td_result_queue_pkg.t_prot_generic_queue;
    constant cmd_idx      : in natural;
    constant result       : in t_vvc_result
  );

  -------------------------------------------
  -- insert_inter_bfm_delay_if_requested
  -------------------------------------------
  -- Inserts delay of either START2START or FINISH2START in time, given that
  -- - vvc_config inter-bfm delay type is not set to NO_DELAY
  -- - command_is_bfm_access is set to true
  -- - Both timestamps are not set to 0 ns.
  -- A log message with ID ID_CMD_EXECUTOR is issued when the delay begins and
  -- when it has finished delaying.
  procedure insert_inter_bfm_delay_if_requested(
    constant vvc_config                         : in t_vvc_config;
    constant command_is_bfm_access              : in boolean;
    constant timestamp_start_of_last_bfm_access : in time;
    constant timestamp_end_of_last_bfm_access   : in time;
    constant msg_id_panel                       : in t_msg_id_panel;
    constant scope                              : in string := C_SCOPE
  );

  function broadcast_cmd_to_shared_cmd(
    constant broadcast_cmd : t_broadcastable_cmd
  ) return t_operation;

  function get_command_type_from_operation(
    constant broadcast_cmd : t_broadcastable_cmd
  ) return t_immediate_or_queued;

  procedure populate_shared_vvc_cmd_with_broadcast(
    variable output_vvc_cmd : out t_vvc_cmd_record;
    constant scope          : in string := C_SCOPE
  );

  function get_msg_id_panel(
    constant command          : t_vvc_cmd_record;
    constant vvc_msg_id_panel : t_msg_id_panel
  ) return t_msg_id_panel;

end package td_vvc_entity_support_pkg;

package body td_vvc_entity_support_pkg is

  function assign_vvc_labels(
    scope        : string;
    vvc_name     : string;
    instance_idx : integer;
    channel      : t_channel
  ) return t_vvc_labels is
    variable vvc_labels : t_vvc_labels;
  begin
    vvc_labels.scope        := pad_string(scope, NUL, vvc_labels.scope'length);
    vvc_labels.vvc_name     := pad_string(vvc_name, NUL, vvc_labels.vvc_name'length);
    vvc_labels.instance_idx := instance_idx;
    vvc_labels.channel      := channel;
    return vvc_labels;
  end;

  impure function format_msg(
    command : t_vvc_cmd_record
  ) return string is
  begin
    return add_msg_delimiter(to_string(command.msg)) & " " & format_command_idx(command);
  end;

  procedure vvc_constructor(
    constant scope                                 : in string;
    constant instance_idx                          : in natural;
    constant channel                               : in t_channel;
    --variable vvc_config                            : inout t_vvc_config;
    variable vvc_config                            : inout work.vvc_methods_pkg.protected_vvc_config_pkg.t_prot_generic_array; -- v3
    constant msg_id_panel                          : in t_msg_id_panel; -- v3
    variable command_queue                         : inout work.td_cmd_queue_pkg.t_prot_generic_queue;
    variable result_queue                          : inout work.td_result_queue_pkg.t_prot_generic_queue;
    constant bfm_config                            : in t_bfm_config;
    constant cmd_queue_count_max                   : in natural;
    constant cmd_queue_count_threshold             : in natural;
    constant cmd_queue_count_threshold_severity    : in t_alert_level;
    constant result_queue_count_max                : in natural;
    constant result_queue_count_threshold          : in natural;
    constant result_queue_count_threshold_severity : in t_alert_level
  ) is
    variable v_delta_cycle_counter : natural := 0;
    variable v_comma_number        : natural := 0;
    variable v_vvc_config          : t_vvc_config;
  begin
    check_value(instance_idx <= C_MAX_VVC_INSTANCE_NUM - 1, TB_FAILURE, "Generic VVC Instance index =" & to_string(instance_idx) & " cannot exceed C_MAX_VVC_INSTANCE_NUM-1 in UVVM adaptations = " & to_string(C_MAX_VVC_INSTANCE_NUM - 1), C_SCOPE, ID_NEVER);

    v_vvc_config            := vvc_config.get(instance_idx, channel);
    v_vvc_config.bfm_config := bfm_config;
    vvc_config.set(v_vvc_config, instance_idx, channel);

    -- compose log message based on the number of channels in scope string
    if pos_of_leftmost(',', scope, 1) = pos_of_rightmost(',', scope, 1) then
      log(ID_CONSTRUCTOR, "VVC instantiated.", scope, msg_id_panel);
    else
      for idx in scope'range loop
        if (scope(idx) = ',') and (v_comma_number < 2) then -- locate 2nd comma in string
          v_comma_number := v_comma_number + 1;
        end if;
        if v_comma_number = 2 then      -- rest of string is channel name
          log(ID_CONSTRUCTOR, "VVC instantiated for channel " & scope((idx + 1) to scope'length), scope, msg_id_panel);
          exit;
        end if;
      end loop;
    end if;
    command_queue.set_scope(scope);
    command_queue.set_name("cmd_queue");
    command_queue.set_queue_count_max(cmd_queue_count_max);
    command_queue.set_queue_count_threshold(cmd_queue_count_threshold);
    command_queue.set_queue_count_threshold_severity(cmd_queue_count_threshold_severity);
    log(ID_CONSTRUCTOR_SUB, "Command queue instantiated and will give a warning when reaching " & to_string(command_queue.get_queue_count_max(VOID)) & " elements in queue.", scope, msg_id_panel);

    result_queue.set_scope(scope);
    result_queue.set_name("result_queue");
    result_queue.set_queue_count_max(result_queue_count_max);
    result_queue.set_queue_count_threshold(result_queue_count_threshold);
    result_queue.set_queue_count_threshold_severity(result_queue_count_threshold_severity);
    log(ID_CONSTRUCTOR_SUB, "Result queue instantiated and will give a warning when reaching " & to_string(result_queue.get_queue_count_max(VOID)) & " elements in queue.", scope, msg_id_panel);

    if shared_uvvm_state.get(VOID) /= PHASE_A then
      loop
        wait for 0 ns;
        v_delta_cycle_counter := v_delta_cycle_counter + 1;
        exit when shared_uvvm_state.get(VOID) = PHASE_A;
        if shared_uvvm_state.get(VOID) /= IDLE then
          alert(TB_FAILURE, "UVVM will not work without entity ti_uvvm_engine instantiated in the testbench or test harness.");
        end if;
      end loop;
    end if;

    wait;                               -- show message only once per VVC instance
  end procedure;

  -- overload without t_channel
  procedure vvc_constructor(
    constant scope                                 : in string;
    constant instance_idx                          : in natural;
    --variable vvc_config                            : inout t_vvc_config;
    variable vvc_config                            : inout work.vvc_methods_pkg.protected_vvc_config_pkg.t_prot_generic_array; -- v3
    constant msg_id_panel                          : in t_msg_id_panel; -- v3
    variable command_queue                         : inout work.td_cmd_queue_pkg.t_prot_generic_queue;
    variable result_queue                          : inout work.td_result_queue_pkg.t_prot_generic_queue;
    constant bfm_config                            : in t_bfm_config;
    constant cmd_queue_count_max                   : in natural;
    constant cmd_queue_count_threshold             : in natural;
    constant cmd_queue_count_threshold_severity    : in t_alert_level;
    constant result_queue_count_max                : in natural;
    constant result_queue_count_threshold          : in natural;
    constant result_queue_count_threshold_severity : in t_alert_level
  ) is
  begin
    vvc_constructor(scope, instance_idx, NA, vvc_config, msg_id_panel, command_queue, result_queue, bfm_config,
                    cmd_queue_count_max, cmd_queue_count_threshold, cmd_queue_count_threshold_severity,
                    result_queue_count_max, result_queue_count_threshold, result_queue_count_threshold_severity);
  end procedure vvc_constructor;

  procedure initialize_interpreter(
    signal terminate_current_cmd      : out t_flag_record
  ) is
  begin
    terminate_current_cmd <= (set => '0', reset => 'Z', is_active => 'Z'); -- Initialise to avoid undefineds. This process is driving param 1 only.
    wait for 0 ns;                      -- delay by 1 delta cycle to allow constructor to finish first
  end procedure;

  function broadcast_cmd_to_shared_cmd(
    constant broadcast_cmd : t_broadcastable_cmd
  ) return t_operation is
  begin
    case broadcast_cmd is
      when ENABLE_LOG_MSG            => return ENABLE_LOG_MSG;
      when DISABLE_LOG_MSG           => return DISABLE_LOG_MSG;
      when FLUSH_COMMAND_QUEUE       => return FLUSH_COMMAND_QUEUE;
      when INSERT_DELAY              => return INSERT_DELAY;
      when TERMINATE_CURRENT_COMMAND => return TERMINATE_CURRENT_COMMAND;
      when others                    => return NO_OPERATION;
    end case;
  end function;

  function get_command_type_from_operation(
    constant broadcast_cmd : t_broadcastable_cmd
  ) return t_immediate_or_queued is
  begin
    case broadcast_cmd is
      when ENABLE_LOG_MSG            => return IMMEDIATE;
      when DISABLE_LOG_MSG           => return IMMEDIATE;
      when FLUSH_COMMAND_QUEUE       => return IMMEDIATE;
      when TERMINATE_CURRENT_COMMAND => return IMMEDIATE;
      when INSERT_DELAY              => return QUEUED;
      when others                    => return NO_command_type;
    end case;
  end function;

  procedure populate_shared_vvc_cmd_with_broadcast(
    variable output_vvc_cmd : out t_vvc_cmd_record;
    constant scope          : in string := C_SCOPE
  ) is
    variable v_broadcast_cmd : t_vvc_broadcast_cmd_record; -- v3
  begin

    -- Increment the shared command index. This is normally done in the CDM, but for broadcast commands it is done by the VVC itself.
    check_value((shared_uvvm_state.get(VOID) /= IDLE), TB_FAILURE, "UVVM will not work without uvvm_vvc_framework.ti_uvvm_engine instantiated in the test harness", C_SCOPE, ID_NEVER);
    await_semaphore_in_delta_cycles(shared_broadcast_semaphore);

    -- v3
    -- Populate the shared VVC command record
    v_broadcast_cmd                     := shared_vvc_broadcast_cmd.get(ALL_INSTANCES);
    output_vvc_cmd.operation            := broadcast_cmd_to_shared_cmd(v_broadcast_cmd.operation);
    output_vvc_cmd.msg_id               := v_broadcast_cmd.msg_id;
    output_vvc_cmd.msg                  := v_broadcast_cmd.msg;
    output_vvc_cmd.quietness            := v_broadcast_cmd.quietness;
    output_vvc_cmd.delay                := v_broadcast_cmd.delay;
    output_vvc_cmd.timeout              := v_broadcast_cmd.timeout;
    output_vvc_cmd.gen_integer_array(0) := v_broadcast_cmd.gen_integer;
    output_vvc_cmd.proc_call            := v_broadcast_cmd.proc_call;
    output_vvc_cmd.cmd_idx              := shared_cmd_idx.get(VOID);
    output_vvc_cmd.command_type         := get_command_type_from_operation(v_broadcast_cmd.operation);

    if global_show_msg_for_uvvm_cmd then
      log(ID_UVVM_SEND_CMD, to_string(v_broadcast_cmd.proc_call) & ": " & add_msg_delimiter(to_string(v_broadcast_cmd.msg)) & format_command_idx(shared_cmd_idx.get(VOID)), scope);
    else
      log(ID_UVVM_SEND_CMD, to_string(v_broadcast_cmd.proc_call) & format_command_idx(shared_cmd_idx.get(VOID)), scope);
    end if;
    release_semaphore(shared_broadcast_semaphore);

  end procedure;

  procedure await_cmd_from_sequencer(
    constant vvc_labels      : in t_vvc_labels;
    constant msg_id_panel    : in t_msg_id_panel; -- v3
    signal   VVCT            : in t_vvc_target_record;
    signal   VVC_BROADCAST   : inout std_logic;
    signal   global_vvc_busy : inout std_logic;
    signal   vvc_ack         : out std_logic;
    variable output_vvc_cmd  : out t_vvc_cmd_record
  ) is
    variable v_was_broadcast                : boolean                                := false;
    variable v_vvc_idx_in_activity_register : t_integer_array(0 to C_MAX_TB_VVC_NUM) := (others => -1);
    variable v_num_vvc_instances            : natural range 0 to C_MAX_TB_VVC_NUM    := 0;
    variable v_vvc_instance_idx             : integer                                := vvc_labels.instance_idx;
    variable v_vvc_channel                  : t_channel                              := vvc_labels.channel;
    variable v_msg_id_panel                 : t_msg_id_panel;

  begin
    vvc_ack <= 'Z';                     -- Do not contribute to the acknowledge unless selected
    -- Wait for a new command
    log(ID_CMD_INTERPRETER_WAIT, "Interpreter: Waiting for command", to_string(vvc_labels.scope), msg_id_panel);

    loop
      VVC_BROADCAST   <= 'Z';
      global_vvc_busy <= 'L';
      wait until (VVCT.trigger = '1' or VVC_BROADCAST = '1');
      if VVC_BROADCAST'event and VVC_BROADCAST = '1' then
        v_was_broadcast := true;
        VVC_BROADCAST   <= '1';
        populate_shared_vvc_cmd_with_broadcast(output_vvc_cmd, vvc_labels.scope);
      else
        -- set VVC_BROADCAST to 0 to force a broadcast to wait for that VVC
        VVC_BROADCAST   <= '0';
        global_vvc_busy <= '1';

        -- Copy shared_vvc_cmd to release the semaphore.
        -- VVC specific broadcast is sent with VVCT, i.e. need to check which shared_vvc_cmd
        -- to use:populated for ALL_INSTANCES, and VVC instance for ALL_CHANNELS and other.
        if VVCT.vvc_instance_idx = ALL_INSTANCES then -- ALL_INSTANCES
          output_vvc_cmd := shared_vvc_cmd.get(ALL_INSTANCES, vvc_labels.channel); -- v3        
        elsif VVCT.vvc_channel /= NA then -- VVC dedicated with ALL_CHANNELS
          output_vvc_cmd := shared_vvc_cmd.get(vvc_labels.instance_idx, VVCT.vvc_channel); -- v3
        else                            -- VVC dedicated
          output_vvc_cmd := shared_vvc_cmd.get(vvc_labels.instance_idx, vvc_labels.channel); -- v3
        end if;
      end if;

      -- Check that the channel is valid
      if (not v_was_broadcast) then
        if (VVCT.vvc_instance_idx = vvc_labels.instance_idx and VVCT.vvc_name(1 to valid_length(vvc_labels.vvc_name)) = vvc_labels.vvc_name(1 to valid_length(vvc_labels.vvc_name))) then
          if ((VVCT.vvc_channel = NA and vvc_labels.channel /= NA) or (vvc_labels.channel = NA and (VVCT.vvc_channel /= NA and VVCT.vvc_channel /= ALL_CHANNELS))) then
            tb_warning(to_string(output_vvc_cmd.proc_call) & " Channel " & to_string(VVCT.vvc_channel) & " not supported on this VVC " & format_command_idx(output_vvc_cmd), to_string(vvc_labels.scope));
            -- only release semaphore and stay in loop forcing a timeout too
            release_semaphore(shared_semaphore);
          end if;
        end if;
      end if;

      exit when (v_was_broadcast or     -- Broadcast, or
                 (((VVCT.vvc_instance_idx = vvc_labels.instance_idx) or (VVCT.vvc_instance_idx = ALL_INSTANCES)) and -- Index is correct or broadcast index
                  ((VVCT.vvc_channel = ALL_CHANNELS) or (VVCT.vvc_channel = vvc_labels.channel)) and -- Channel is correct or broadcast channel
                  VVCT.vvc_name(1 to valid_length(vvc_labels.vvc_name)) = vvc_labels.vvc_name(1 to valid_length(vvc_labels.vvc_name)))); -- Name is correct
    end loop;
    if ((VVCT.vvc_instance_idx = ALL_INSTANCES) or (VVCT.vvc_channel = ALL_CHANNELS)) then
      -- in case of a multicast block the global acknowledge until all vvc receiving the message processed it
      vvc_ack <= '0';
    end if;

    wait for 0 ns;

    if v_vvc_instance_idx = -1 then
      v_vvc_instance_idx := ALL_INSTANCES;
    end if;
    if v_vvc_channel = NA then
      v_vvc_channel := ALL_CHANNELS;
    end if;
    -- Get the corresponding index from the vvc activity register
    get_vvc_index_in_activity_register(VVCT,
                                       v_vvc_instance_idx,
                                       v_vvc_channel,
                                       v_vvc_idx_in_activity_register,
                                       v_num_vvc_instances);

    if not v_was_broadcast then
      -- VVCs registered in the VVC activity register have released the
      -- semaphore in send_command_to_vvc().
      if v_num_vvc_instances = 0 then
        -- release the semaphore if it was not a broadcast
        release_semaphore(shared_semaphore);
      end if;
    end if;

    v_msg_id_panel := get_msg_id_panel(output_vvc_cmd, msg_id_panel); -- v3
    log(ID_CMD_INTERPRETER, to_string(output_vvc_cmd.proc_call) & ". Command received " & format_command_idx(output_vvc_cmd), vvc_labels.scope, v_msg_id_panel); -- Get and ack the new command
  end procedure await_cmd_from_sequencer;

  --    -- Overloading procedure - DEPRECATED
  --    procedure await_cmd_from_sequencer(
  --        constant vvc_labels          : in t_vvc_labels;
  --        constant msg_id_panel        : in t_msg_id_panel; -- v3
  --        constant parent_msg_id_panel : in t_msg_id_panel; -- v3
  --        signal   VVCT                : in t_vvc_target_record;
  --        signal   VVC_BROADCAST       : inout std_logic;
  --        signal   global_vvc_busy     : inout std_logic;
  --        signal   vvc_ack             : out std_logic;
  --        constant shared_vvc_cmd      : in t_vvc_cmd_record;
  --        variable output_vvc_cmd      : out t_vvc_cmd_record
  --    ) is
  --    begin
  --        deprecate(get_procedure_name_from_instance_name(vvc_labels'instance_name), "shared_vvc_cmd parameter is no longer in use. Please call this procedure without the shared_vvc_cmd parameter.");
  --
  --        -- v3
  --        await_cmd_from_sequencer(vvc_labels, msg_id_panel, parent_msg_id_panel, VVCT, VVC_BROADCAST,
  --                                 global_vvc_busy, vvc_ack, output_vvc_cmd);
  --    end procedure;

  procedure put_command_on_queue(
    constant command             : in t_vvc_cmd_record;
    variable command_queue       : inout work.td_cmd_queue_pkg.t_prot_generic_queue;
    variable vvc_status          : inout t_vvc_status;
    signal   queue_is_increasing : out boolean
  ) is
  begin
    command_queue.put(command);
    vvc_status.pending_cmd_cnt := command_queue.get_count(VOID);
    queue_is_increasing        <= true;
    wait for 0 ns;
    queue_is_increasing        <= false;
  end procedure;

  procedure interpreter_flush_command_queue(
    constant command       : in t_vvc_cmd_record;
    variable command_queue : inout work.td_cmd_queue_pkg.t_prot_generic_queue;
    constant msg_id_panel  : in t_msg_id_panel; -- v3
    variable vvc_status    : inout t_vvc_status;
    constant vvc_labels    : in t_vvc_labels
  ) is
    variable v_local_vvc_cmd : t_vvc_cmd_record := shared_vvc_cmd.get(vvc_labels.instance_idx, vvc_labels.channel); -- v3
  begin
    log(ID_IMMEDIATE_CMD, "Flushing command queue (" & to_string(v_local_vvc_cmd.gen_integer_array(0)) & ") " & format_command_idx(v_local_vvc_cmd), to_string(vvc_labels.scope), msg_id_panel);
    command_queue.flush(VOID);
    vvc_status.pending_cmd_cnt := command_queue.get_count(VOID);
  end;

  procedure interpreter_terminate_current_command(
    constant command               : in t_vvc_cmd_record;
    --constant vvc_config           : in t_vvc_config; -- v3
    constant msg_id_panel          : in t_msg_id_panel; -- v3
    constant vvc_labels            : in t_vvc_labels;
    signal   terminate_current_cmd : inout t_flag_record;
    constant executor_is_busy      : in boolean := true
  ) is
  begin
    if executor_is_busy then
      log(ID_IMMEDIATE_CMD, "Terminating command in executor", to_string(vvc_labels.scope), msg_id_panel);
      set_flag(terminate_current_cmd);
    end if;
  end procedure;

  procedure interpreter_fetch_result(
    variable result_queue          : inout work.td_result_queue_pkg.t_prot_generic_queue;
    constant command               : in t_vvc_cmd_record;
    constant msg_id_panel          : in t_msg_id_panel; -- v3
    constant vvc_labels            : in t_vvc_labels;
    constant last_cmd_idx_executed : in natural;
    variable vvc_response          : inout protected_vvc_response_pkg.t_prot_generic_array
  ) is
    variable v_current_element    : work.vvc_cmd_pkg.t_vvc_result_queue_element;
    variable v_local_result_queue : work.td_result_queue_pkg.t_prot_generic_queue;
    variable v_vvc_response       : t_vvc_response := vvc_response.get(vvc_labels.instance_idx, vvc_labels.channel);
  begin
    v_local_result_queue.set_scope(to_string(vvc_labels.scope));

    v_vvc_response.fetch_is_accepted := false; -- default
    if last_cmd_idx_executed < command.gen_integer_array(0) then
      tb_warning(to_string(command.proc_call) & ". Requested result is not yet available. " & format_command_idx(command), to_string(vvc_labels.scope));
    else
      -- Search for the command idx among the elements of the queue.
      -- Easiest method of doing this is to pop elements, and pushing them again
      -- if the cmd idx does not match. Not very efficient, but an OK initial implementation.

      -- Pop the element. Compare cmd idx. If it does not match, push to local result queue.
      -- If an index matches, set vvc_response.result. (Don't push element back to result queue)
      while result_queue.get_count(VOID) > 0 loop
        v_current_element := result_queue.get(VOID);
        if v_current_element.cmd_idx = command.gen_integer_array(0) then
          v_vvc_response.fetch_is_accepted := true;
          v_vvc_response.result            := v_current_element.result;
          log(ID_IMMEDIATE_CMD, to_string(command.proc_call) & " Requested result is found" & ". " & to_string(command.msg) & " " & format_command_idx(command), to_string(vvc_labels.scope), msg_id_panel); -- Get and ack the new command -- v3
          exit;
        else
          -- No match for element: put in local result queue
          v_local_result_queue.put(v_current_element);
        end if;
      end loop;

      -- Pop each element of local result queue and push to result queue.
      -- This is to clear the local result queue and restore the result
      -- queue to its original state (except that the matched element is not put back).
      while v_local_result_queue.get_count(VOID) > 0 loop
        result_queue.put(v_local_result_queue.get(VOID));
      end loop;

      if not v_vvc_response.fetch_is_accepted then
        tb_warning(to_string(command.proc_call) & ". Requested result was not found. Given command index is not available in this VVC. " & format_command_idx(command), to_string(vvc_labels.scope));
      end if;

      vvc_response.set(v_vvc_response, vvc_labels.instance_idx, vvc_labels.channel);
    end if;
  end procedure;

  procedure initialize_executor(
    signal terminate_current_cmd : inout t_flag_record
  ) is
  begin
    reset_flag(terminate_current_cmd);
    wait for 0 ns;                      -- delay by 1 delta cycle to allow constructor to finish first
  end procedure;

  procedure fetch_command_and_prepare_executor(
    variable command             : inout t_vvc_cmd_record;
    variable command_queue       : inout work.td_cmd_queue_pkg.t_prot_generic_queue;
    variable vvc_status          : inout protected_vvc_status_pkg.t_prot_generic_array; -- v3
    signal   queue_is_increasing : in boolean;
    signal   executor_is_busy    : inout boolean;
    constant vvc_labels          : in t_vvc_labels;
    constant executor_id         : in t_msg_id := ID_CMD_EXECUTOR;
    constant executor_wait_id    : in t_msg_id := ID_CMD_EXECUTOR_WAIT
  ) is
    variable v_vvc_status   : t_vvc_status := vvc_status.get(vvc_labels.instance_idx, vvc_labels.channel);
    variable v_msg_id_panel : t_msg_id_panel;
  begin
    executor_is_busy              <= false;
    v_vvc_status.previous_cmd_idx := command.cmd_idx;
    v_vvc_status.current_cmd_idx  := 0;
    vvc_status.set(v_vvc_status, vvc_labels.instance_idx, vvc_labels.channel);

    wait for 0 ns;                      -- to allow delta updates in other processes.
    if command_queue.is_empty(VOID) then
      log(executor_wait_id, "Executor: Waiting for command", to_string(vvc_labels.scope), shared_vvc_msg_id_panel.get(vvc_labels.instance_idx, vvc_labels.channel));
      wait until queue_is_increasing;
    end if;

    -- Queue is now not empty
    executor_is_busy <= true;
    wait until executor_is_busy;
    command          := command_queue.get(VOID);

    v_msg_id_panel               := get_msg_id_panel(command, shared_vvc_msg_id_panel.get(vvc_labels.instance_idx, vvc_labels.channel)); -- v3
    log(executor_id, to_string(command.proc_call) & " - Will be executed " & format_command_idx(command), to_string(vvc_labels.scope), v_msg_id_panel); -- Get and ack the new command -- v3
    v_vvc_status                 := vvc_status.get(vvc_labels.instance_idx, vvc_labels.channel);
    v_vvc_status.pending_cmd_cnt := command_queue.get_count(VOID);
    v_vvc_status.current_cmd_idx := command.cmd_idx;
    vvc_status.set(v_vvc_status, vvc_labels.instance_idx, vvc_labels.channel);
  end procedure;

  -- The result_queue is used so that whatever type defined in the VVC can be stored,
  -- and later fetched with fetch_result()
  procedure store_result(
    variable result_queue : inout work.td_result_queue_pkg.t_prot_generic_queue;
    constant cmd_idx      : in natural;
    constant result       : in t_vvc_result
  ) is
    variable v_result_queue_element : t_vvc_result_queue_element;
  begin
    v_result_queue_element.cmd_idx := cmd_idx;
    v_result_queue_element.result  := result;
    result_queue.put(v_result_queue_element);
  end procedure;

  procedure insert_inter_bfm_delay_if_requested(
    constant vvc_config                         : in t_vvc_config;
    constant command_is_bfm_access              : in boolean;
    constant timestamp_start_of_last_bfm_access : in time;
    constant timestamp_end_of_last_bfm_access   : in time;
    constant msg_id_panel                       : in t_msg_id_panel;
    constant scope                              : in string := C_SCOPE
  ) is
  begin
    -- If both timestamps are at 0 ns we interpret this as the first BFM access, hence no delay shall be applied.
    if ((vvc_config.inter_bfm_delay.delay_type /= NO_DELAY) and command_is_bfm_access and not ((timestamp_start_of_last_bfm_access = 0 ns) and (timestamp_end_of_last_bfm_access = 0 ns))) then
      case vvc_config.inter_bfm_delay.delay_type is
        when TIME_FINISH2START =>
          if now < (timestamp_end_of_last_bfm_access + vvc_config.inter_bfm_delay.delay_in_time) then
            log(ID_INSERTED_DELAY, "Delaying BFM access until time " & to_string(timestamp_end_of_last_bfm_access + vvc_config.inter_bfm_delay.delay_in_time) & ".", scope, msg_id_panel);
            wait for (timestamp_end_of_last_bfm_access + vvc_config.inter_bfm_delay.delay_in_time - now);
          end if;
        when TIME_START2START =>
          if now < (timestamp_start_of_last_bfm_access + vvc_config.inter_bfm_delay.delay_in_time) then
            log(ID_INSERTED_DELAY, "Delaying BFM access until time " & to_string(timestamp_start_of_last_bfm_access + vvc_config.inter_bfm_delay.delay_in_time) & ".", scope, msg_id_panel);
            wait for (timestamp_start_of_last_bfm_access + vvc_config.inter_bfm_delay.delay_in_time - now);
          end if;
        when others =>
          tb_error("Delay type " & to_upper(to_string(vvc_config.inter_bfm_delay.delay_type)) & " not supported for this VVC.", scope);
      end case;
      log(ID_INSERTED_DELAY, "Finished delaying BFM access", scope, msg_id_panel);
    end if;
  end procedure;

  function get_msg_id_panel(
    constant command          : t_vvc_cmd_record;
    constant vvc_msg_id_panel : t_msg_id_panel
  ) return t_msg_id_panel is
  begin
    -- If the parent_msg_id_panel is set then use it,
    -- otherwise use the configured VVC's msg_id_panel.
    if command.parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      return command.parent_msg_id_panel;
    else
      return vvc_msg_id_panel;
    end if;
  end function;

end package body td_vvc_entity_support_pkg;
