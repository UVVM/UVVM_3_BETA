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

---------------------------------------------------------------------------------------------
-- Description : See library quick reference (under 'doc') and README-file(s)
---------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library uvvm_vvc_framework;
use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library bitvis_vip_scoreboard;
use bitvis_vip_scoreboard.generic_sb_support_pkg.C_SB_CONFIG_DEFAULT;

use work.gmii_bfm_pkg.all;
use work.vvc_methods_pkg.all;
use work.vvc_cmd_pkg.all;
use work.td_target_support_pkg.all;
use work.td_vvc_entity_support_pkg.all;
use work.td_cmd_queue_pkg.all;
use work.td_result_queue_pkg.all;
use work.transaction_pkg.all;

--==========================================================================================
entity gmii_rx_vvc is
  generic(
    GC_INSTANCE_IDX                          : natural;
    GC_CHANNEL                               : t_channel;
    GC_GMII_BFM_CONFIG                       : t_gmii_bfm_config := C_GMII_BFM_CONFIG_DEFAULT;
    GC_CMD_QUEUE_COUNT_MAX                   : natural           := C_CMD_QUEUE_COUNT_MAX;
    GC_CMD_QUEUE_COUNT_THRESHOLD             : natural           := C_CMD_QUEUE_COUNT_THRESHOLD;
    GC_CMD_QUEUE_COUNT_THRESHOLD_SEVERITY    : t_alert_level     := C_CMD_QUEUE_COUNT_THRESHOLD_SEVERITY;
    GC_RESULT_QUEUE_COUNT_MAX                : natural           := C_RESULT_QUEUE_COUNT_MAX;
    GC_RESULT_QUEUE_COUNT_THRESHOLD          : natural           := C_RESULT_QUEUE_COUNT_THRESHOLD;
    GC_RESULT_QUEUE_COUNT_THRESHOLD_SEVERITY : t_alert_level     := C_RESULT_QUEUE_COUNT_THRESHOLD_SEVERITY
  );
  port(
    gmii_vvc_rx_if : inout t_gmii_rx_if := init_gmii_if_signals
  );
end entity gmii_rx_vvc;

--==========================================================================================
--==========================================================================================
architecture behave of gmii_rx_vvc is

  constant C_SCOPE      : string       := C_VVC_NAME & "," & to_string(GC_INSTANCE_IDX);
  constant C_VVC_LABELS : t_vvc_labels := assign_vvc_labels(C_SCOPE, C_VVC_NAME, GC_INSTANCE_IDX, GC_CHANNEL);

  signal executor_is_busy      : boolean := false;
  signal queue_is_increasing   : boolean := false;
  signal last_cmd_idx_executed : natural := 0;
  signal terminate_current_cmd : t_flag_record;

  -- Instantiation of the element dedicated executor
  shared variable command_queue : work.td_cmd_queue_pkg.t_prot_generic_queue;
  shared variable result_queue  : work.td_result_queue_pkg.t_prot_generic_queue;

  -- Transaction info
  alias vvc_transaction_info_trigger        : std_logic is global_gmii_vvc_transaction_trigger(GC_CHANNEL, GC_INSTANCE_IDX);
  -- VVC Activity 
  signal entry_num_in_vvc_activity_register : integer;

  impure function get_vvc_config(
    constant void : t_void
  ) return t_vvc_config is
  begin
    return shared_vvc_config.get(GC_INSTANCE_IDX, GC_CHANNEL);
  end function get_vvc_config;

  impure function get_vvc_status(
    constant void : t_void
  ) return t_vvc_status is
  begin
    return shared_vvc_status.get(GC_INSTANCE_IDX, GC_CHANNEL);
  end function get_vvc_status;

  procedure set_vvc_status(
    constant vvc_status : t_vvc_status
  ) is
  begin
    shared_vvc_status.set(vvc_status, GC_INSTANCE_IDX, GC_CHANNEL);
  end procedure set_vvc_status;

begin

  --==========================================================================================
  -- Constructor
  -- - Set up the defaults and show constructor if enabled
  --==========================================================================================
  -- v3
  vvc_constructor(C_SCOPE, GC_INSTANCE_IDX, shared_vvc_config, shared_vvc_msg_id_panel.get(GC_INSTANCE_IDX, GC_CHANNEL), command_queue, result_queue, GC_GMII_BFM_CONFIG,
                  GC_CMD_QUEUE_COUNT_MAX, GC_CMD_QUEUE_COUNT_THRESHOLD, GC_CMD_QUEUE_COUNT_THRESHOLD_SEVERITY,
                  GC_RESULT_QUEUE_COUNT_MAX, GC_RESULT_QUEUE_COUNT_THRESHOLD, GC_RESULT_QUEUE_COUNT_THRESHOLD_SEVERITY);
  --==========================================================================================

  --==========================================================================================
  -- Command interpreter
  -- - Interpret, decode and acknowledge commands from the central sequencer
  --==========================================================================================
  cmd_interpreter : process
    variable v_local_vvc_cmd : t_vvc_cmd_record := C_VVC_CMD_DEFAULT;
    variable v_msg_id_panel  : t_msg_id_panel;
    variable v_vvc_status    : t_vvc_status;
  begin
    -- 0. Initialize the process prior to first command
    work.td_vvc_entity_support_pkg.initialize_interpreter(terminate_current_cmd);
    -- initialise shared_vvc_last_received_cmd_idx for channel and instance
    shared_vvc_last_received_cmd_idx.set(0, GC_INSTANCE_IDX, GC_CHANNEL);

    -- Register VVC in vvc activity register
    entry_num_in_vvc_activity_register <= shared_vvc_activity_register.priv_register_vvc(name     => C_VVC_NAME,
                                                                                         channel  => GC_CHANNEL,
                                                                                         instance => GC_INSTANCE_IDX);

    -- Then for every single command from the sequencer
    loop                                -- basically as long as new commands are received

      v_msg_id_panel := shared_vvc_msg_id_panel.get(GC_INSTANCE_IDX, GC_CHANNEL); -- v3

      -- 1. wait until command targeted at this VVC. Must match VVC name, instance and channel (if applicable)
      --    releases global semaphore
      -------------------------------------------------------------------------
      work.td_vvc_entity_support_pkg.await_cmd_from_sequencer(C_VVC_LABELS, v_msg_id_panel, THIS_VVCT, VVC_BROADCAST, global_vvc_busy, global_vvc_ack, v_local_vvc_cmd); -- v3

      -- Update shared_vvc_last_received_cmd_idx with received command index
      shared_vvc_last_received_cmd_idx.set(v_local_vvc_cmd.cmd_idx, GC_INSTANCE_IDX, GC_CHANNEL);

      -- Select between a provided msg_id_panel via the vvc_cmd_record from a VVC with a higher hierarchy or the
      -- msg_id_panel in this VVC's config. This is to correctly handle the logging when using Hierarchical-VVCs.
      v_msg_id_panel := get_msg_id_panel(v_local_vvc_cmd, v_msg_id_panel);

      -- 2a. Put command on the executor if intended for the executor
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
            work.td_vvc_entity_support_pkg.interpreter_flush_command_queue(v_local_vvc_cmd, command_queue, v_msg_id_panel, v_vvc_status, C_VVC_LABELS); -- v3
            set_vvc_status(v_vvc_status);

          when TERMINATE_CURRENT_COMMAND =>
            work.td_vvc_entity_support_pkg.interpreter_terminate_current_command(v_local_vvc_cmd, v_msg_id_panel, C_VVC_LABELS, terminate_current_cmd); -- v3

          when FETCH_RESULT =>
            work.td_vvc_entity_support_pkg.interpreter_fetch_result(result_queue, v_local_vvc_cmd, v_msg_id_panel, C_VVC_LABELS, last_cmd_idx_executed, shared_vvc_response); -- v3

          when others =>
            tb_error("Unsupported command received for IMMEDIATE execution: '" & to_string(v_local_vvc_cmd.operation) & "'", C_SCOPE);

        end case;

        shared_vvc_msg_id_panel.set(v_msg_id_panel, GC_INSTANCE_IDX, GC_CHANNEL); -- v3

      else
        tb_error("command_type is not IMMEDIATE or QUEUED", C_SCOPE);
      end if;

      -- 3. Acknowledge command after runing or queuing the command
      -------------------------------------------------------------------------
      work.td_target_support_pkg.acknowledge_cmd(global_vvc_ack, v_local_vvc_cmd.cmd_idx);

    end loop;
  end process;
  --==========================================================================================

  --==========================================================================================
  -- Command executor
  -- - Fetch and execute the commands
  --==========================================================================================
  cmd_executor : process
    variable v_cmd                                   : t_vvc_cmd_record;
    variable v_result                                : t_vvc_result; -- See vvc_cmd_pkg
    variable v_timestamp_start_of_current_bfm_access : time    := 0 ns;
    variable v_timestamp_start_of_last_bfm_access    : time    := 0 ns;
    variable v_timestamp_end_of_last_bfm_access      : time    := 0 ns;
    variable v_command_is_bfm_access                 : boolean := false;
    variable v_prev_command_was_bfm_access           : boolean := false;
    variable v_msg_id_panel                          : t_msg_id_panel;
    variable v_vvc_config                            : t_vvc_config;

  begin
    -- 0. Initialize the process prior to first command
    -------------------------------------------------------------------------
    work.td_vvc_entity_support_pkg.initialize_executor(terminate_current_cmd);

    -- Setup GMII scoreboard
    GMII_VVC_SB.set_scope("GMII_VVC_SB");
    GMII_VVC_SB.enable(GC_INSTANCE_IDX, "GMII VVC SB Enabled");
    GMII_VVC_SB.config(GC_INSTANCE_IDX, C_SB_CONFIG_DEFAULT);
    GMII_VVC_SB.enable_log_msg(GC_INSTANCE_IDX, ID_DATA);

    loop

      v_msg_id_panel := shared_vvc_msg_id_panel.get(GC_INSTANCE_IDX, GC_CHANNEL); -- v3

      -- update vvc activity
      update_vvc_activity_register(global_trigger_vvc_activity_register,
                                   shared_vvc_status,
                                   GC_INSTANCE_IDX,
                                   GC_CHANNEL,
                                   INACTIVE,
                                   entry_num_in_vvc_activity_register,
                                   last_cmd_idx_executed,
                                   command_queue.is_empty(VOID),
                                   C_SCOPE);

      -- 1. Set defaults, fetch command and log
      -------------------------------------------------------------------------
      work.td_vvc_entity_support_pkg.fetch_command_and_prepare_executor(v_cmd, command_queue, shared_vvc_status, queue_is_increasing, executor_is_busy, C_VVC_LABELS); -- v3

      -- update vvc activity
      update_vvc_activity_register(global_trigger_vvc_activity_register,
                                   shared_vvc_status,
                                   GC_INSTANCE_IDX,
                                   GC_CHANNEL,
                                   ACTIVE,
                                   entry_num_in_vvc_activity_register,
                                   last_cmd_idx_executed,
                                   command_queue.is_empty(VOID),
                                   C_SCOPE);

      v_vvc_config := get_vvc_config(VOID);

      -- Select between a provided msg_id_panel via the vvc_cmd_record from a VVC with a higher hierarchy or the
      -- msg_id_panel in this VVC's config. This is to correctly handle the logging when using Hierarchical-VVCs.
      v_msg_id_panel := get_msg_id_panel(v_cmd, shared_vvc_msg_id_panel.get(GC_INSTANCE_IDX, GC_CHANNEL));

      -- Check if command is a BFM access
      v_prev_command_was_bfm_access := v_command_is_bfm_access; -- save for inter_bfm_delay 
      if v_cmd.operation = READ or v_cmd.operation = EXPECT then
        v_command_is_bfm_access := true;
      else
        v_command_is_bfm_access := false;
      end if;

      -- Insert delay if needed
      work.td_vvc_entity_support_pkg.insert_inter_bfm_delay_if_requested(vvc_config                         => v_vvc_config,
                                                                         command_is_bfm_access              => v_prev_command_was_bfm_access,
                                                                         timestamp_start_of_last_bfm_access => v_timestamp_start_of_last_bfm_access,
                                                                         timestamp_end_of_last_bfm_access   => v_timestamp_end_of_last_bfm_access,
                                                                         scope                              => C_SCOPE,
                                                                         msg_id_panel                       => v_msg_id_panel);

      if v_command_is_bfm_access then
        v_timestamp_start_of_current_bfm_access := now;
      end if;

      -- 2. Execute the fetched command
      -------------------------------------------------------------------------
      case v_cmd.operation is           -- Only operations in the dedicated record are relevant

        -- VVC dedicated operations
        --===================================
        when READ =>
          -- Set transaction info
          set_global_vvc_transaction_info(vvc_transaction_info_trigger, shared_gmii_vvc_transaction_info, GC_INSTANCE_IDX, GC_CHANNEL, v_cmd, v_vvc_config);

          -- Call the corresponding procedure in the BFM package.
          gmii_read(data_array   => v_result.data_array(0 to v_cmd.num_bytes_read - 1),
                    data_len     => v_result.data_array_length,
                    msg          => format_msg(v_cmd),
                    gmii_rx_if   => gmii_vvc_rx_if,
                    scope        => C_SCOPE,
                    msg_id_panel => v_msg_id_panel,
                    config       => v_vvc_config.bfm_config);

          -- Request SB check result
          if v_cmd.data_routing = TO_SB then
            -- call SB check_received
            for i in 0 to v_result.data_array_length - 1 loop
              GMII_VVC_SB.check_received(GC_INSTANCE_IDX, v_result.data_array(i));
            end loop;
          else
            -- Store the result
            work.td_vvc_entity_support_pkg.store_result(result_queue => result_queue,
                                                        cmd_idx      => v_cmd.cmd_idx,
                                                        result       => v_result);
          end if;

        when EXPECT =>
          -- Set transaction info
          set_global_vvc_transaction_info(vvc_transaction_info_trigger, shared_gmii_vvc_transaction_info, GC_INSTANCE_IDX, GC_CHANNEL, v_cmd, v_vvc_config);

          -- Call the corresponding procedure in the BFM package.
          gmii_expect(data_exp     => v_cmd.data_array(0 to v_cmd.data_array_length - 1),
                      msg          => format_msg(v_cmd),
                      gmii_rx_if   => gmii_vvc_rx_if,
                      alert_level  => v_cmd.alert_level,
                      scope        => C_SCOPE,
                      msg_id_panel => v_msg_id_panel,
                      config       => v_vvc_config.bfm_config);

        -- UVVM common operations
        --===================================
        when INSERT_DELAY =>
          log(ID_INSERTED_DELAY, "Running: " & to_string(v_cmd.proc_call) & " " & format_command_idx(v_cmd), C_SCOPE, v_msg_id_panel);
          if v_cmd.gen_integer_array(0) = -1 then
            -- Delay specified using time
            wait until terminate_current_cmd.is_active = '1' for v_cmd.delay;
          else
            -- Delay specified using integer
            check_value(v_vvc_config.bfm_config.clock_period > -1 ns, TB_ERROR, "Check that clock_period is configured when using insert_delay().",
                        C_SCOPE, ID_NEVER, v_msg_id_panel);
            wait until terminate_current_cmd.is_active = '1' for v_cmd.gen_integer_array(0) * v_vvc_config.bfm_config.clock_period;
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
      reset_vvc_transaction_info(shared_gmii_vvc_transaction_info, GC_INSTANCE_IDX, GC_CHANNEL, v_cmd);
    end loop;
  end process;
  --==========================================================================================

  --==========================================================================================
  -- Command termination handler
  -- - Handles the termination request record (sets and resets terminate flag on request)
  --==========================================================================================
  cmd_terminator : uvvm_vvc_framework.ti_vvc_framework_support_pkg.flag_handler(terminate_current_cmd); -- flag: is_active, set, reset
  --==========================================================================================

end behave;
