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

use work.uart_bfm_pkg.all;
use work.vvc_transaction_pkg.all;
use work.vvc_transaction_shared_variables_pkg.all;
use work.vvc_cmd_pkg.all;
use work.vvc_cmd_shared_variables_pkg.all;
use work.td_target_support_pkg.all;
use work.vvc_methods_pkg.all;
use work.vvc_methods_support_pkg.all;
use work.td_vvc_entity_support_pkg.all;
use work.td_cmd_queue_pkg.all;
use work.td_result_queue_pkg.all;

entity uart_tx_vvc is
  generic(
    GC_DATA_WIDTH                            : natural           := 8;
    GC_INSTANCE_IDX                          : natural           := 1;
    GC_UART_CONFIG                           : t_uart_bfm_config := C_UART_BFM_CONFIG_DEFAULT;
    GC_CMD_QUEUE_COUNT_MAX                   : natural           := C_CMD_QUEUE_COUNT_MAX;
    GC_CMD_QUEUE_COUNT_THRESHOLD             : natural           := C_CMD_QUEUE_COUNT_THRESHOLD;
    GC_CMD_QUEUE_COUNT_THRESHOLD_SEVERITY    : t_alert_level     := C_CMD_QUEUE_COUNT_THRESHOLD_SEVERITY;
    GC_RESULT_QUEUE_COUNT_MAX                : natural           := C_RESULT_QUEUE_COUNT_MAX;
    GC_RESULT_QUEUE_COUNT_THRESHOLD          : natural           := C_RESULT_QUEUE_COUNT_THRESHOLD;
    GC_RESULT_QUEUE_COUNT_THRESHOLD_SEVERITY : t_alert_level     := C_RESULT_QUEUE_COUNT_THRESHOLD_SEVERITY
  );
  port(
    uart_vvc_tx : inout std_logic := GC_UART_CONFIG.idle_state
  );
end entity uart_tx_vvc;

architecture behave of uart_tx_vvc is

  constant C_CHANNEL    : t_channel    := TX;
  constant C_SCOPE      : string       := get_scope_for_log(C_VVC_NAME, GC_INSTANCE_IDX, C_CHANNEL);
  constant C_VVC_LABELS : t_vvc_labels := assign_vvc_labels(C_VVC_NAME, GC_INSTANCE_IDX, C_CHANNEL);

  signal executor_is_busy      : boolean := false;
  signal queue_is_increasing   : boolean := false;
  signal last_cmd_idx_executed : natural := 0;
  signal terminate_current_cmd : t_flag_record;

  -- Instantiation of the element dedicated Queue
  shared variable command_queue : work.td_cmd_queue_pkg.t_generic_queue;
  shared variable result_queue  : work.td_result_queue_pkg.t_generic_queue;

  -- Transaction info
  alias vvc_transaction_info_trigger        : std_logic is global_uart_vvc_transaction_trigger(C_CHANNEL, GC_INSTANCE_IDX);
  -- Activity Watchdog
  signal entry_num_in_vvc_activity_register : integer;

  impure function get_vvc_config(
    constant void : t_void
  ) return t_vvc_config is
  begin
    return shared_vvc_config.get(GC_INSTANCE_IDX, C_CHANNEL);
  end function get_vvc_config;

  impure function get_vvc_status(
    constant void : t_void
  ) return t_vvc_status is
  begin
    return shared_vvc_status.get(GC_INSTANCE_IDX, C_CHANNEL);
  end function get_vvc_status;

  impure function get_msg_id_panel(
    constant void : t_void
  ) return t_msg_id_panel is
  begin
    return shared_vvc_msg_id_panel.get(GC_INSTANCE_IDX, C_CHANNEL);
  end function get_msg_id_panel;

  procedure set_vvc_status(
    constant vvc_status : t_vvc_status
  ) is
  begin
    shared_vvc_status.set(vvc_status, GC_INSTANCE_IDX, C_CHANNEL);
  end procedure set_vvc_status;

  procedure set_msg_id_panel(
    constant msg_id_panel : t_msg_id_panel
  ) is
  begin
    shared_vvc_msg_id_panel.set(msg_id_panel, GC_INSTANCE_IDX, C_CHANNEL);
  end procedure set_msg_id_panel;

begin

  --===============================================================================================
  -- Constructor
  -- - Set up the defaults and show constructor if enabled
  --===============================================================================================
  -- v3
  vvc_constructor(C_SCOPE, GC_INSTANCE_IDX, C_CHANNEL, shared_vvc_config, get_msg_id_panel(VOID), command_queue, result_queue,
                  GC_UART_CONFIG, GC_CMD_QUEUE_COUNT_MAX, GC_CMD_QUEUE_COUNT_THRESHOLD, GC_CMD_QUEUE_COUNT_THRESHOLD_SEVERITY,
                  GC_RESULT_QUEUE_COUNT_MAX, GC_RESULT_QUEUE_COUNT_THRESHOLD, GC_RESULT_QUEUE_COUNT_THRESHOLD_SEVERITY,
                  C_VVC_MAX_INSTANCE_NUM);
  --===============================================================================================

  --===============================================================================================
  -- Command interpreter
  -- - Interpret, decode and acknowledge commands from the central sequencer
  --===============================================================================================
  cmd_interpreter : process
    variable v_local_vvc_cmd : t_vvc_cmd_record := C_VVC_CMD_DEFAULT;
    variable v_msg_id_panel  : t_msg_id_panel;
    variable v_vvc_config    : t_vvc_config;
    variable v_vvc_status    : t_vvc_status;
  begin
    -- 0. Initialize the process prior to first command
    work.td_vvc_entity_support_pkg.initialize_interpreter(terminate_current_cmd);
    -- initialise shared_vvc_last_received_cmd_idx for channel and instance
    shared_vvc_last_received_cmd_idx.set(0, GC_INSTANCE_IDX, C_CHANNEL);
    -- Register VVC in vvc activity register
    entry_num_in_vvc_activity_register <= shared_vvc_activity_register.priv_register_vvc(name     => C_VVC_NAME,
                                                                                         instance => GC_INSTANCE_IDX,
                                                                                         channel  => C_CHANNEL);

    -- Update BFM config num_data_bits with GC_DATA_WIDTH
    v_vvc_config                          := get_vvc_config(VOID);
    v_vvc_config.bfm_config.num_data_bits := GC_DATA_WIDTH;
    shared_vvc_config.set(v_vvc_config, GC_INSTANCE_IDX, C_CHANNEL);

    -- Then for every single command from the sequencer
    loop                                -- basically as long as new commands are received

      v_msg_id_panel := get_msg_id_panel(VOID); -- v3

      -- 1. wait until command targeted at this VVC. Must match VVC name, instance and channel (if applicable)
      --    releases global semaphore
      -------------------------------------------------------------------------
      work.td_vvc_entity_support_pkg.await_cmd_from_sequencer(C_VVC_LABELS, C_SCOPE, v_msg_id_panel, THIS_VVCT, VVC_BROADCAST, global_vvc_busy, global_vvc_ack, v_local_vvc_cmd); -- v3

      -- update shared_vvc_last_received_cmd_idx with received command index
      shared_vvc_last_received_cmd_idx.set(v_local_vvc_cmd.cmd_idx, GC_INSTANCE_IDX, C_CHANNEL);

      -- Select between a provided msg_id_panel via the vvc_cmd_record from a VVC with a higher hierarchy or the
      -- msg_id_panel in this VVC's config. This is to correctly handle the logging when using Hierarchical-VVCs.
      v_msg_id_panel := get_msg_id_panel(v_local_vvc_cmd, v_msg_id_panel);

      -- 2a. Put command on the queue if intended for the executor
      -------------------------------------------------------------------------
      if v_local_vvc_cmd.command_type = QUEUED then
        v_vvc_status := get_vvc_status(VOID);
        work.td_vvc_entity_support_pkg.put_command_on_queue(v_local_vvc_cmd, command_queue, v_vvc_status, queue_is_increasing);
        set_vvc_status(v_vvc_status);

      -- 2b. Otherwise command is intended for immediate response
      -------------------------------------------------------------------------
      elsif v_local_vvc_cmd.command_type = IMMEDIATE then

        case v_local_vvc_cmd.operation is

          when DISABLE_LOG_MSG =>
            uvvm_util.methods_pkg.disable_log_msg(v_local_vvc_cmd.msg_id, v_msg_id_panel, to_string(v_local_vvc_cmd.msg) & format_command_idx(v_local_vvc_cmd), C_SCOPE, v_local_vvc_cmd.quietness); -- v3

          when ENABLE_LOG_MSG =>
            uvvm_util.methods_pkg.enable_log_msg(v_local_vvc_cmd.msg_id, v_msg_id_panel, to_string(v_local_vvc_cmd.msg) & format_command_idx(v_local_vvc_cmd), C_SCOPE, v_local_vvc_cmd.quietness); -- v3

          when FLUSH_COMMAND_QUEUE =>
            v_vvc_status := get_vvc_status(VOID);
            work.td_vvc_entity_support_pkg.interpreter_flush_command_queue(v_local_vvc_cmd, command_queue, v_msg_id_panel, v_vvc_status, C_VVC_LABELS, C_SCOPE); -- v3
            set_vvc_status(v_vvc_status);

          when TERMINATE_CURRENT_COMMAND =>
            work.td_vvc_entity_support_pkg.interpreter_terminate_current_command(v_local_vvc_cmd, v_msg_id_panel, C_VVC_LABELS, C_SCOPE, terminate_current_cmd, executor_is_busy); -- v3

          when FETCH_RESULT =>
            work.td_vvc_entity_support_pkg.interpreter_fetch_result(result_queue, entry_num_in_vvc_activity_register, v_local_vvc_cmd, v_msg_id_panel, C_VVC_LABELS, C_SCOPE, shared_vvc_response); -- v3

          when others =>
            tb_error("Unsupported command received for IMMEDIATE execution: '" & to_string(v_local_vvc_cmd.operation) & "'", C_SCOPE);

        end case;

        set_msg_id_panel(v_msg_id_panel); -- v3

      else
        tb_error("command_type is not IMMEDIATE or QUEUED", C_SCOPE);
      end if;

      -- 3. Acknowledge command after runing or queuing the command
      -------------------------------------------------------------------------
      work.td_target_support_pkg.acknowledge_cmd(global_vvc_ack, v_local_vvc_cmd.cmd_idx);

    end loop;
    wait;
  end process;
  --===============================================================================================

  --===============================================================================================
  -- Command executor
  -- - Fetch and execute the commands
  --===============================================================================================
  cmd_executor : process
    constant C_EXECUTOR_ID                            : natural                                     := 0;
    variable v_cmd                                    : t_vvc_cmd_record;
    variable v_read_data                              : t_vvc_result; -- See vvc_cmd_pkg
    variable v_timestamp_start_of_current_bfm_access  : time                                        := 0 ns;
    variable v_timestamp_start_of_last_bfm_access     : time                                        := 0 ns;
    variable v_timestamp_end_of_last_bfm_access       : time                                        := 0 ns;
    variable v_command_is_bfm_access                  : boolean                                     := false;
    variable v_prev_command_was_bfm_access            : boolean                                     := false;
    variable v_msg_id_panel                           : t_msg_id_panel;
    variable v_normalised_data                        : std_logic_vector(GC_DATA_WIDTH - 1 downto 0) := (others => '0');
    variable v_num_data_bits                          : natural;
    variable v_has_raised_warning_if_vvc_bfm_conflict : boolean                                     := false;
    variable v_vvc_config                             : t_vvc_config; -- v3
    variable v_vvc_config_copy                        : t_vvc_config; --v3
    variable v_seeds                                  : t_positive_vector(0 to 1)                   := (1, 2);

  begin
    -- 0. Initialize the process prior to first command
    -------------------------------------------------------------------------
    work.td_vvc_entity_support_pkg.initialize_executor(terminate_current_cmd);

    -- Set the randomization seeds
    set_rand_seeds(C_SCOPE, v_seeds(0), v_seeds(1));

    loop

      v_msg_id_panel := get_msg_id_panel(VOID); -- v3

      -- update vvc activity
      update_vvc_activity_register(global_trigger_vvc_activity_register, shared_vvc_status, GC_INSTANCE_IDX, C_CHANNEL, INACTIVE, entry_num_in_vvc_activity_register, C_EXECUTOR_ID, last_cmd_idx_executed, command_queue.is_empty(VOID), C_SCOPE);

      -- 1. Set defaults, fetch command and log
      -------------------------------------------------------------------------
      work.td_vvc_entity_support_pkg.fetch_command_and_prepare_executor(v_cmd, command_queue, shared_vvc_status, queue_is_increasing, executor_is_busy, C_VVC_LABELS, C_SCOPE); -- v3

      -- update vvc activity
      update_vvc_activity_register(global_trigger_vvc_activity_register, shared_vvc_status, GC_INSTANCE_IDX, C_CHANNEL, ACTIVE, entry_num_in_vvc_activity_register, C_EXECUTOR_ID, last_cmd_idx_executed, command_queue.is_empty(VOID), C_SCOPE);

      v_vvc_config := get_vvc_config(VOID);

      v_num_data_bits := v_vvc_config.bfm_config.num_data_bits; -- v3            

      -- Select between a provided msg_id_panel via the vvc_cmd_record from a VVC with a higher hierarchy or the
      -- msg_id_panel in this VVC's config. This is to correctly handle the logging when using Hierarchical-VVCs.
      v_msg_id_panel := get_msg_id_panel(v_cmd, get_msg_id_panel(VOID));

      -- Check if command is a BFM access
      v_prev_command_was_bfm_access := v_command_is_bfm_access; -- save for inter_bfm_delay
      if v_cmd.operation = TRANSMIT then
        v_command_is_bfm_access := true;
      else
        v_command_is_bfm_access := false;
      end if;

      -- Insert delay if needed
      work.td_vvc_entity_support_pkg.insert_inter_bfm_delay_if_requested(vvc_config                         => v_vvc_config,
                                                                         command_is_bfm_access              => v_prev_command_was_bfm_access,
                                                                         timestamp_start_of_last_bfm_access => v_timestamp_start_of_last_bfm_access,
                                                                         timestamp_end_of_last_bfm_access   => v_timestamp_end_of_last_bfm_access,
                                                                         msg_id_panel                       => v_msg_id_panel,
                                                                         scope                              => C_SCOPE);

      if v_command_is_bfm_access then
        v_timestamp_start_of_current_bfm_access := now;
      end if;

      -- 2. Execute the fetched command
      -------------------------------------------------------------------------
      case v_cmd.operation is           -- Only operations in the dedicated record are relevant
        when TRANSMIT =>
          -- Loop the number of words to transmit
          for idx in 1 to v_cmd.num_words loop

            -- Get VVC config as starting point
            v_vvc_config_copy := v_vvc_config; -- v3
            -- Determine setting for BFM error injection
            determine_error_injection(v_vvc_config.error_injection.parity_bit_error_prob,
                                      v_vvc_config_copy.bfm_config.error_injection.parity_bit_error,
                                      v_has_raised_warning_if_vvc_bfm_conflict,
                                      C_SCOPE);
            determine_error_injection(v_vvc_config.error_injection.stop_bit_error_prob,
                                      v_vvc_config_copy.bfm_config.error_injection.stop_bit_error,
                                      v_has_raised_warning_if_vvc_bfm_conflict,
                                      C_SCOPE);

            -- Randomise data if applicable
            case v_cmd.randomisation is
              when RANDOM =>
                random(v_seeds(0), v_seeds(1), v_cmd.data(v_num_data_bits - 1 downto 0));
              when RANDOM_FAVOUR_EDGES =>
                null;                   -- Not implemented yet
              when others =>            -- NA
                null;
            end case;

            -- Set vvc transaction info
            set_global_vvc_transaction_info(vvc_transaction_info_trigger, shared_uart_vvc_transaction_info, GC_INSTANCE_IDX, C_CHANNEL, v_cmd, v_vvc_config_copy, IN_PROGRESS, C_SCOPE);

            -- Normalise address and data
            v_normalised_data := normalize_and_check(v_cmd.data, v_normalised_data, ALLOW_WIDER_NARROWER, "data", "shared_vvc_cmd.data", "uart_transmit() called with too wide data. " & add_msg_delimiter(v_cmd.msg));

            -- Call the corresponding procedure in the BFM package.
            uart_transmit(data_value   => v_normalised_data(v_num_data_bits - 1 downto 0),
                          msg          => format_msg(v_cmd),
                          tx           => uart_vvc_tx,
                          config       => v_vvc_config_copy.bfm_config,
                          scope        => C_SCOPE,
                          msg_id_panel => v_msg_id_panel);

            -- Update vvc transaction info
            set_global_vvc_transaction_info(vvc_transaction_info_trigger, shared_uart_vvc_transaction_info, GC_INSTANCE_IDX, C_CHANNEL, v_cmd, v_vvc_config_copy, COMPLETED, C_SCOPE);

            -- Set vvc transaction info back to default values
            reset_vvc_transaction_info(shared_uart_vvc_transaction_info, GC_INSTANCE_IDX, C_CHANNEL, v_cmd);

            -- exit loop if terminate_current_cmd is requested
            if terminate_current_cmd.is_active = '1' then
              exit;
            end if;
          end loop;

        when INSERT_DELAY =>
          log(ID_INSERTED_DELAY, "Running: " & to_string(v_cmd.proc_call) & " " & format_command_idx(v_cmd), C_SCOPE, v_msg_id_panel);
          if v_cmd.gen_integer_array(0) = -1 then
            -- Delay specified using time
            wait until terminate_current_cmd.is_active = '1' for v_cmd.delay;
          else
            -- Delay specified using integer
            wait until terminate_current_cmd.is_active = '1' for (v_cmd.gen_integer_array(0) * v_vvc_config.bfm_config.bit_time);
          end if;

        when others =>
          tb_error("Unsupported local command received for execution: '" & to_string(v_cmd.operation) & "'", C_SCOPE);
      end case;

      if v_command_is_bfm_access then
        v_timestamp_end_of_last_bfm_access   := now;
        v_timestamp_start_of_last_bfm_access := v_timestamp_start_of_current_bfm_access;
        if ((v_vvc_config.inter_bfm_delay.delay_type = TIME_START2START) and ((now - v_timestamp_start_of_current_bfm_access) > v_vvc_config.inter_bfm_delay.delay_in_time)) then
          alert(v_vvc_config.inter_bfm_delay.inter_bfm_delay_violation_severity, "BFM access exceeded specified start-to-start inter-bfm delay, " & to_string(v_vvc_config.inter_bfm_delay.delay_in_time) & ".", C_SCOPE);
        end if;
      end if;

      -- Reset terminate flag if any occurred
      if (terminate_current_cmd.is_active = '1') then
        log(ID_CMD_EXECUTOR, "Termination request received", C_SCOPE, v_msg_id_panel);
        uvvm_vvc_framework.ti_vvc_framework_support_pkg.reset_flag(terminate_current_cmd);
      end if;

      last_cmd_idx_executed <= v_cmd.cmd_idx;
      -- Set VVC Transaction Info back to default values
      reset_vvc_transaction_info(shared_uart_vvc_transaction_info, GC_INSTANCE_IDX, C_CHANNEL, v_cmd);
    end loop;
  end process;
  --===============================================================================================

  --===============================================================================================
  -- Command termination handler
  -- - Handles the termination request record (sets and resets terminate flag on request)
  --===============================================================================================
  cmd_terminator : uvvm_vvc_framework.ti_vvc_framework_support_pkg.flag_handler(terminate_current_cmd); -- flag: is_active, set, reset
  --===============================================================================================

end behave;

