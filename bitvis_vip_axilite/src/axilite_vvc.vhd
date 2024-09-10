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

library bitvis_vip_scoreboard;
use bitvis_vip_scoreboard.generic_sb_support_pkg.C_SB_CONFIG_DEFAULT;

use work.axilite_bfm_pkg.all;
use work.axilite_channel_handler_pkg.all;
use work.vvc_transaction_pkg.all;
use work.vvc_transaction_shared_variables_pkg.all;
use work.vvc_cmd_pkg.all;
use work.vvc_cmd_shared_variables_pkg.all;
use work.td_target_support_pkg.all;
use work.vvc_sb_support_pkg.all;
use work.vvc_methods_pkg.all;
use work.vvc_methods_support_pkg.all;
use work.td_vvc_entity_support_pkg.all;
use work.td_cmd_queue_pkg.all;
use work.td_result_queue_pkg.all;

--=================================================================================================
entity axilite_vvc is
  generic(
    GC_ADDR_WIDTH                            : integer range 1 to C_VVC_CMD_ADDR_MAX_LENGTH := 8;
    GC_DATA_WIDTH                            : integer range 1 to C_VVC_CMD_DATA_MAX_LENGTH := 32;
    GC_INSTANCE_IDX                          : natural                                      := 1; -- Instance index for this AXILITE_VVCT instance
    GC_AXILITE_CONFIG                        : t_axilite_bfm_config                         := C_AXILITE_BFM_CONFIG_DEFAULT; -- Behavior specification for BFM
    GC_CMD_QUEUE_COUNT_MAX                   : natural                                      := C_CMD_QUEUE_COUNT_MAX;
    GC_CMD_QUEUE_COUNT_THRESHOLD             : natural                                      := C_CMD_QUEUE_COUNT_THRESHOLD;
    GC_CMD_QUEUE_COUNT_THRESHOLD_SEVERITY    : t_alert_level                                := C_CMD_QUEUE_COUNT_THRESHOLD_SEVERITY;
    GC_RESULT_QUEUE_COUNT_MAX                : natural                                      := C_RESULT_QUEUE_COUNT_MAX;
    GC_RESULT_QUEUE_COUNT_THRESHOLD          : natural                                      := C_RESULT_QUEUE_COUNT_THRESHOLD;
    GC_RESULT_QUEUE_COUNT_THRESHOLD_SEVERITY : t_alert_level                                := C_RESULT_QUEUE_COUNT_THRESHOLD_SEVERITY
  );
  port(
    clk                   : in    std_logic;
    axilite_vvc_master_if : inout t_axilite_if := init_axilite_if_signals(GC_ADDR_WIDTH, GC_DATA_WIDTH)
  );
begin
  -- Check the interface widths to assure that the interface was correctly set up
  assert (axilite_vvc_master_if.write_address_channel.awaddr'length = GC_ADDR_WIDTH) report "axilite_vvc_master_if.write_address_channel.awaddr'length =/ GC_ADDR_WIDTH" severity failure;
  assert (axilite_vvc_master_if.read_address_channel.araddr'length = GC_ADDR_WIDTH) report "axilite_vvc_master_if.read_address_channel.araddr'length =/ GC_ADDR_WIDTH" severity failure;
  assert (axilite_vvc_master_if.write_data_channel.wdata'length = GC_DATA_WIDTH) report "axilite_vvc_master_if.write_data_channel.wdata'length =/ GC_DATA_WIDTH" severity failure;
  assert (axilite_vvc_master_if.write_data_channel.wstrb'length = GC_DATA_WIDTH / 8) report "axilite_vvc_master_if.write_data_channel.wstrb'length =/ GC_DATA_WIDTH/8" severity failure;
  assert (axilite_vvc_master_if.read_data_channel.rdata'length = GC_DATA_WIDTH) report "axilite_vvc_master_if.read_data_channel.rdata'length =/ GC_DATA_WIDTH" severity failure;
end entity axilite_vvc;

--=================================================================================================
--=================================================================================================

architecture behave of axilite_vvc is

  constant C_SCOPE      : string       := get_scope_for_log(C_VVC_NAME, GC_INSTANCE_IDX);
  constant C_VVC_LABELS : t_vvc_labels := assign_vvc_labels(C_VVC_NAME, GC_INSTANCE_IDX, NA);

  signal executor_is_busy                           : boolean := false;
  signal write_address_channel_executor_is_busy     : boolean := false;
  signal write_data_channel_executor_is_busy        : boolean := false;
  signal write_response_channel_executor_is_busy    : boolean := false;
  signal read_address_channel_executor_is_busy      : boolean := false;
  signal read_data_channel_executor_is_busy         : boolean := false;
  signal any_executors_busy                         : boolean := false;
  signal queue_is_increasing                        : boolean := false;
  signal write_address_channel_queue_is_increasing  : boolean := false;
  signal write_data_channel_queue_is_increasing     : boolean := false;
  signal write_response_channel_queue_is_increasing : boolean := false;
  signal read_address_channel_queue_is_increasing   : boolean := false;
  signal read_data_channel_queue_is_increasing      : boolean := false;
  signal last_write_response_channel_idx_executed   : natural := 0;
  signal last_read_data_channel_idx_executed        : natural := 0;
  signal terminate_current_cmd                      : t_flag_record;
  signal clock_period                               : time;

  -- Instantiation of the element dedicated Queue
  shared variable command_queue                : work.td_cmd_queue_pkg.t_generic_queue;
  shared variable write_address_channel_queue  : work.td_cmd_queue_pkg.t_generic_queue;
  shared variable write_data_channel_queue     : work.td_cmd_queue_pkg.t_generic_queue;
  shared variable write_response_channel_queue : work.td_cmd_queue_pkg.t_generic_queue;
  shared variable read_address_channel_queue   : work.td_cmd_queue_pkg.t_generic_queue;
  shared variable read_data_channel_queue      : work.td_cmd_queue_pkg.t_generic_queue;
  shared variable result_queue                 : work.td_result_queue_pkg.t_generic_queue;

  -- Transaction info
  alias vvc_transaction_info_trigger        : std_logic is global_axilite_vvc_transaction_trigger(GC_INSTANCE_IDX);
  -- VVC Activity
  signal entry_num_in_vvc_activity_register : integer;

  impure function get_vvc_config(
    constant void : t_void
  ) return t_vvc_config is
  begin
    return shared_vvc_config.get(GC_INSTANCE_IDX);
  end function get_vvc_config;

  impure function get_vvc_status(
    constant void : t_void
  ) return t_vvc_status is
  begin
    return shared_vvc_status.get(GC_INSTANCE_IDX);
  end function get_vvc_status;

  impure function get_msg_id_panel(
    constant void : t_void
  ) return t_msg_id_panel is
  begin
    return shared_vvc_msg_id_panel.get(GC_INSTANCE_IDX);
  end function get_msg_id_panel;

  procedure set_vvc_status(
    constant vvc_status : t_vvc_status
  ) is
  begin
    shared_vvc_status.set(vvc_status, GC_INSTANCE_IDX);
  end procedure set_vvc_status;

  procedure set_msg_id_panel(
    constant msg_id_panel : t_msg_id_panel
  ) is
  begin
    shared_vvc_msg_id_panel.set(msg_id_panel, GC_INSTANCE_IDX);
  end procedure set_msg_id_panel;

begin

  -- Remove vsim-8684 warning
  p_initial_drivers : process begin
    axilite_vvc_master_if.write_address_channel.awready <= 'Z';
    axilite_vvc_master_if.write_data_channel.wready     <= 'Z';
    axilite_vvc_master_if.write_response_channel.bvalid <= 'Z';
    axilite_vvc_master_if.write_response_channel.bresp  <= (others => 'Z');
    axilite_vvc_master_if.read_address_channel.arready  <= 'Z';
    axilite_vvc_master_if.read_data_channel.rvalid      <= 'Z';
    axilite_vvc_master_if.read_data_channel.rdata       <= (axilite_vvc_master_if.read_data_channel.rdata'range => 'Z');
    axilite_vvc_master_if.read_data_channel.rresp       <= (others => 'Z');
    wait;
  end process p_initial_drivers;

  --===============================================================================================
  -- Constructor
  -- - Set up the defaults and show constructor if enabled
  --===============================================================================================
  -- v3
  vvc_constructor(C_SCOPE, GC_INSTANCE_IDX, shared_vvc_config, get_msg_id_panel(VOID), command_queue, result_queue, GC_AXILITE_CONFIG,
                  GC_CMD_QUEUE_COUNT_MAX, GC_CMD_QUEUE_COUNT_THRESHOLD, GC_CMD_QUEUE_COUNT_THRESHOLD_SEVERITY,
                  GC_RESULT_QUEUE_COUNT_MAX, GC_RESULT_QUEUE_COUNT_THRESHOLD, GC_RESULT_QUEUE_COUNT_THRESHOLD_SEVERITY,
                  C_VVC_MAX_INSTANCE_NUM);
  --===============================================================================================

  --===============================================================================================
  -- Set if any of the executors are busy
  --===============================================================================================
  any_executors_busy <= executor_is_busy or write_address_channel_executor_is_busy or write_data_channel_executor_is_busy or write_response_channel_executor_is_busy or read_address_channel_executor_is_busy or read_data_channel_executor_is_busy;
  --===============================================================================================

  --===============================================================================================
  -- Command interpreter
  -- - Interpret, decode and acknowledge commands from the central sequencer
  --===============================================================================================
  cmd_interpreter : process
    variable v_local_vvc_cmd : t_vvc_cmd_record := C_VVC_CMD_DEFAULT;
    variable v_msg_id_panel  : t_msg_id_panel;
    variable v_vvc_status    : t_vvc_status;
  begin
    -- 0. Initialize the process prior to first command
    work.td_vvc_entity_support_pkg.initialize_interpreter(terminate_current_cmd);

    -- initialise shared_vvc_last_received_cmd_idx for channel and instance
    shared_vvc_last_received_cmd_idx.set(0, GC_INSTANCE_IDX);

    -- Register VVC in vvc activity register
    entry_num_in_vvc_activity_register <= shared_vvc_activity_register.priv_register_vvc(name          => C_VVC_NAME,
                                                                                         instance      => GC_INSTANCE_IDX,
                                                                                         num_executors => 6);

    -- Then for every single command from the sequencer
    loop                                -- basically as long as new commands are received

      v_msg_id_panel := get_msg_id_panel(VOID); -- v3

      -- 1. wait until command targeted at this VVC. Must match VVC name, instance and channel (if applicable)
      --    releases global semaphore
      -------------------------------------------------------------------------
      work.td_vvc_entity_support_pkg.await_cmd_from_sequencer(C_VVC_LABELS, C_SCOPE, v_msg_id_panel, THIS_VVCT, VVC_BROADCAST, global_vvc_busy, global_vvc_ack, v_local_vvc_cmd); -- v3

      -- update shared_vvc_last_received_cmd_idx with received command index
      shared_vvc_last_received_cmd_idx.set(v_local_vvc_cmd.cmd_idx, GC_INSTANCE_IDX);

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
            work.td_vvc_entity_support_pkg.interpreter_flush_command_queue(v_local_vvc_cmd, write_address_channel_queue, v_msg_id_panel, v_vvc_status, C_VVC_LABELS, C_SCOPE); -- v3
            work.td_vvc_entity_support_pkg.interpreter_flush_command_queue(v_local_vvc_cmd, write_data_channel_queue, v_msg_id_panel, v_vvc_status, C_VVC_LABELS, C_SCOPE); -- v3
            work.td_vvc_entity_support_pkg.interpreter_flush_command_queue(v_local_vvc_cmd, write_response_channel_queue, v_msg_id_panel, v_vvc_status, C_VVC_LABELS, C_SCOPE); -- v3
            work.td_vvc_entity_support_pkg.interpreter_flush_command_queue(v_local_vvc_cmd, read_address_channel_queue, v_msg_id_panel, v_vvc_status, C_VVC_LABELS, C_SCOPE); -- v3
            work.td_vvc_entity_support_pkg.interpreter_flush_command_queue(v_local_vvc_cmd, read_data_channel_queue, v_msg_id_panel, v_vvc_status, C_VVC_LABELS, C_SCOPE); -- v3
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
    constant C_EXECUTOR_ID                           : natural                                      := 0;
    variable v_cmd                                   : t_vvc_cmd_record;
    variable v_read_data                             : t_vvc_result; -- See vvc_cmd_pkg
    variable v_timestamp_start_of_current_bfm_access : time                                         := 0 ns;
    variable v_timestamp_start_of_last_bfm_access    : time                                         := 0 ns;
    variable v_timestamp_end_of_last_bfm_access      : time                                         := 0 ns;
    variable v_command_is_bfm_access                 : boolean                                      := false;
    variable v_prev_command_was_bfm_access           : boolean                                      := false;
    variable v_msg_id_panel                          : t_msg_id_panel;
    variable v_normalised_addr                       : unsigned(GC_ADDR_WIDTH - 1 downto 0)         := (others => '0');
    variable v_normalised_data                       : std_logic_vector(GC_DATA_WIDTH - 1 downto 0) := (others => '0');
    variable v_vvc_config                            : t_vvc_config                                 := get_vvc_config(VOID);
    variable v_vvc_status                            : t_vvc_status;

  begin
    -- 0. Initialize the process prior to first command
    -------------------------------------------------------------------------
    work.td_vvc_entity_support_pkg.initialize_executor(terminate_current_cmd);

    -- Setup AXILite scoreboard
    AXILITE_VVC_SB.set_scope("AXILITE_VVC_SB");
    AXILITE_VVC_SB.enable(GC_INSTANCE_IDX, "AXILITE VVC SB Enabled");
    AXILITE_VVC_SB.config(GC_INSTANCE_IDX, C_SB_CONFIG_DEFAULT);
    AXILITE_VVC_SB.enable_log_msg(GC_INSTANCE_IDX, ID_DATA);

    loop

      v_msg_id_panel := get_msg_id_panel(VOID); -- v3

      -- update vvc activity
      update_vvc_activity_register(global_trigger_vvc_activity_register, shared_vvc_status, GC_INSTANCE_IDX, NA, INACTIVE, entry_num_in_vvc_activity_register, C_EXECUTOR_ID, 0, command_queue.is_empty(VOID), C_SCOPE);

      -- 1. Set defaults, fetch command and log
      -------------------------------------------------------------------------
      work.td_vvc_entity_support_pkg.fetch_command_and_prepare_executor(v_cmd, command_queue, shared_vvc_status, queue_is_increasing, executor_is_busy, C_VVC_LABELS, C_SCOPE); -- v3

      -- update vvc activity
      update_vvc_activity_register(global_trigger_vvc_activity_register, shared_vvc_status, GC_INSTANCE_IDX, NA, ACTIVE, entry_num_in_vvc_activity_register, C_EXECUTOR_ID, 0, command_queue.is_empty(VOID), C_SCOPE);

      v_vvc_config := get_vvc_config(VOID);

      -- Select between a provided msg_id_panel via the vvc_cmd_record from a VVC with a higher hierarchy or the
      -- msg_id_panel in this VVC's config. This is to correctly handle the logging when using Hierarchical-VVCs.
      v_msg_id_panel := get_msg_id_panel(v_cmd, get_msg_id_panel(VOID));

      -- Check if command is a BFM access
      v_prev_command_was_bfm_access := v_command_is_bfm_access; -- save for inter_bfm_delay
      if v_cmd.operation = WRITE or v_cmd.operation = READ or v_cmd.operation = CHECK then
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

        -- VVC dedicated operations
        --===================================
        when WRITE =>
          -- Set vvc transaction info
          set_global_vvc_transaction_info(vvc_transaction_info_trigger, shared_axilite_vvc_transaction_info, GC_INSTANCE_IDX, NA, v_cmd, v_vvc_config, IN_PROGRESS, C_SCOPE);

          -- Normalise address and data
          v_normalised_addr := normalize_and_check(v_cmd.addr, v_normalised_addr, ALLOW_WIDER_NARROWER, "v_cmd.addr", "v_normalised_addr", "axilite_write() called with too wide address. " & v_cmd.msg);
          v_normalised_data := normalize_and_check(v_cmd.data, v_normalised_data, ALLOW_WIDER_NARROWER, "v_cmd.data", "v_normalised_data", "axilite_write() called with too wide data. " & v_cmd.msg);

          -- Adding the write command to the write address channel queue , write data channel queue and write response channel queue
          v_vvc_status := get_vvc_status(VOID);
          work.td_vvc_entity_support_pkg.put_command_on_queue(v_cmd, write_address_channel_queue, v_vvc_status, write_address_channel_queue_is_increasing);
          work.td_vvc_entity_support_pkg.put_command_on_queue(v_cmd, write_data_channel_queue, v_vvc_status, write_data_channel_queue_is_increasing);
          work.td_vvc_entity_support_pkg.put_command_on_queue(v_cmd, write_response_channel_queue, v_vvc_status, write_response_channel_queue_is_increasing);
          set_vvc_status(v_vvc_status);

        when READ =>
          -- Set vvc transaction info
          set_global_vvc_transaction_info(vvc_transaction_info_trigger, shared_axilite_vvc_transaction_info, GC_INSTANCE_IDX, NA, v_cmd, v_vvc_config, IN_PROGRESS, C_SCOPE);

          -- Normalise address and data
          v_normalised_addr := normalize_and_check(v_cmd.addr, v_normalised_addr, ALLOW_WIDER_NARROWER, "v_cmd.addr", "v_normalised_addr", "axilite_read() called with too wide address. " & v_cmd.msg);

          -- Adding the read command to the read address channel queue and the read address data queue
          v_vvc_status := get_vvc_status(VOID);
          work.td_vvc_entity_support_pkg.put_command_on_queue(v_cmd, read_address_channel_queue, v_vvc_status, read_address_channel_queue_is_increasing);
          work.td_vvc_entity_support_pkg.put_command_on_queue(v_cmd, read_data_channel_queue, v_vvc_status, read_data_channel_queue_is_increasing);
          set_vvc_status(v_vvc_status);

        when CHECK =>
          -- Set vvc transaction info
          set_global_vvc_transaction_info(vvc_transaction_info_trigger, shared_axilite_vvc_transaction_info, GC_INSTANCE_IDX, NA, v_cmd, v_vvc_config, IN_PROGRESS, C_SCOPE);

          -- Normalise address and data
          v_normalised_addr := normalize_and_check(v_cmd.addr, v_normalised_addr, ALLOW_WIDER_NARROWER, "v_cmd.addr", "v_normalised_addr", "axilite_check() called with too wide address. " & v_cmd.msg);
          v_normalised_data := normalize_and_check(v_cmd.data, v_normalised_data, ALLOW_WIDER_NARROWER, "v_cmd.data", "v_normalised_data", "axilite_check() called with too wide data. " & v_cmd.msg);

          -- Adding the check command to the read address channel queue and the read address data queue
          v_vvc_status := get_vvc_status(VOID);
          work.td_vvc_entity_support_pkg.put_command_on_queue(v_cmd, read_address_channel_queue, v_vvc_status, read_address_channel_queue_is_increasing);
          work.td_vvc_entity_support_pkg.put_command_on_queue(v_cmd, read_data_channel_queue, v_vvc_status, read_data_channel_queue_is_increasing);
          set_vvc_status(v_vvc_status);

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

      -- These commands are sent to other executors where they are executed.
      -- Since the commands can finish in any order, to detect when this specific command has finished, we store the cmd_idx
      -- in a list with pending commands which will be cleared in the corresponding executor when it has finished.
      if v_cmd.operation = WRITE or v_cmd.operation = READ or v_cmd.operation = CHECK then
        shared_vvc_activity_register.priv_add_pending_cmd_idx(entry_num_in_vvc_activity_register, v_cmd.cmd_idx);
      end if;

      -- In case we only allow a single pending transaction, wait here until every channel is finished. 
      -- Even though this wait doesn't have a timeout, each of the executors have timeouts.
      if v_vvc_config.force_single_pending_transaction and v_command_is_bfm_access then
        wait until not write_address_channel_executor_is_busy and not write_data_channel_executor_is_busy and not write_response_channel_executor_is_busy and not read_address_channel_executor_is_busy and not read_data_channel_executor_is_busy;
      end if;

    end loop;
  end process;
  --===============================================================================================

  --===============================================================================================
  -- Read address channel executor
  -- - Fetch and execute the read address channel transactions
  --===============================================================================================
  read_address_channel_executor : process
    constant C_EXECUTOR_ID          : natural                              := 1;
    variable v_cmd                  : t_vvc_cmd_record;
    variable v_msg_id_panel         : t_msg_id_panel;
    variable v_normalised_addr      : unsigned(GC_ADDR_WIDTH - 1 downto 0) := (others => '0');
    variable v_vvc_config           : t_vvc_config                         := get_vvc_config(VOID);
    constant C_CHANNEL_SCOPE        : string                               := get_scope_for_log(C_VVC_NAME & "_AR", GC_INSTANCE_IDX);
    constant C_CHANNEL_VVC_LABELS   : t_vvc_labels                         := assign_vvc_labels(C_VVC_NAME, GC_INSTANCE_IDX, NA);

  begin
    -- Set the command response queue up to the same settings as the command queue
    read_address_channel_queue.set_scope(C_CHANNEL_SCOPE & ":Q");
    read_address_channel_queue.set_queue_count_max(GC_CMD_QUEUE_COUNT_MAX);
    read_address_channel_queue.set_queue_count_threshold(GC_CMD_QUEUE_COUNT_THRESHOLD);
    read_address_channel_queue.set_queue_count_threshold_severity(GC_CMD_QUEUE_COUNT_THRESHOLD_SEVERITY);

    -- Wait until VVC is registered in vvc activity register in the interpreter
    wait until entry_num_in_vvc_activity_register >= 0;

    loop

      v_msg_id_panel := get_msg_id_panel(VOID); -- v3

      -- update vvc activity
      update_vvc_activity_register(global_trigger_vvc_activity_register, shared_vvc_status, GC_INSTANCE_IDX, NA, INACTIVE, entry_num_in_vvc_activity_register, C_EXECUTOR_ID, 0, read_address_channel_queue.is_empty(VOID), C_SCOPE);
      -- Fetch commands
      work.td_vvc_entity_support_pkg.fetch_command_and_prepare_executor(v_cmd, read_address_channel_queue, shared_vvc_status, read_address_channel_queue_is_increasing, read_address_channel_executor_is_busy, C_VVC_LABELS, C_CHANNEL_SCOPE, ID_CHANNEL_EXECUTOR, ID_CHANNEL_EXECUTOR_WAIT); -- v3
      -- update vvc activity
      update_vvc_activity_register(global_trigger_vvc_activity_register, shared_vvc_status, GC_INSTANCE_IDX, NA, ACTIVE, entry_num_in_vvc_activity_register, C_EXECUTOR_ID, 0, read_address_channel_queue.is_empty(VOID), C_SCOPE);

      v_vvc_config := get_vvc_config(VOID);

      -- Select between a provided msg_id_panel via the vvc_cmd_record from a VVC with a higher hierarchy or the
      -- msg_id_panel in this VVC's config. This is to correctly handle the logging when using Hierarchical-VVCs.
      v_msg_id_panel := get_msg_id_panel(v_cmd, get_msg_id_panel(VOID));

      -- Normalise address
      v_normalised_addr := normalize_and_check(v_cmd.addr, v_normalised_addr, ALLOW_WIDER_NARROWER, "addr", "shared_vvc_cmd.addr", "Function called with too wide address. " & v_cmd.msg);

      -- Handling commands
      case v_cmd.operation is
        when READ | CHECK =>
          -- Set vvc transaction info
          set_arw_vvc_transaction_info(vvc_transaction_info_trigger, shared_axilite_vvc_transaction_info, GC_INSTANCE_IDX, NA, v_cmd, v_vvc_config, IN_PROGRESS, C_CHANNEL_SCOPE);
          -- Start transaction
          read_address_channel_write(araddr_value => std_logic_vector(v_normalised_addr),
                                     msg          => format_msg(v_cmd),
                                     clk          => clk,
                                     araddr       => axilite_vvc_master_if.read_address_channel.araddr,
                                     arvalid      => axilite_vvc_master_if.read_address_channel.arvalid,
                                     arprot       => axilite_vvc_master_if.read_address_channel.arprot,
                                     arready      => axilite_vvc_master_if.read_address_channel.arready,
                                     scope        => C_CHANNEL_SCOPE,
                                     msg_id_panel => v_msg_id_panel,
                                     config       => v_vvc_config.bfm_config);
          -- Update vvc transaction info
          set_arw_vvc_transaction_info(vvc_transaction_info_trigger, shared_axilite_vvc_transaction_info, GC_INSTANCE_IDX, NA, v_cmd, v_vvc_config, COMPLETED, C_CHANNEL_SCOPE);
        when others =>
          tb_error("Unsupported local command received for execution: '" & to_string(v_cmd.operation) & "'", C_CHANNEL_SCOPE);
      end case;
      -- Set vvc transaction info back to default values
      reset_arw_vvc_transaction_info(shared_axilite_vvc_transaction_info, GC_INSTANCE_IDX, NA, v_cmd);
    end loop;
  end process;
  --===============================================================================================

  --===============================================================================================
  -- Read data channel executor
  -- - Fetch and execute the read data channel transactions
  --===============================================================================================
  read_data_channel_executor : process
    constant C_EXECUTOR_ID          : natural                                      := 2;
    variable v_cmd                  : t_vvc_cmd_record;
    variable v_msg_id_panel         : t_msg_id_panel;
    variable v_read_data            : t_vvc_result; -- See vvc_cmd_pkg
    variable v_normalised_data      : std_logic_vector(GC_DATA_WIDTH - 1 downto 0) := (others => '0');
    variable v_vvc_config           : t_vvc_config                                 := get_vvc_config(VOID);
    constant C_CHANNEL_SCOPE        : string                                       := get_scope_for_log(C_VVC_NAME & "_R", GC_INSTANCE_IDX);
    constant C_CHANNEL_VVC_LABELS   : t_vvc_labels                                 := assign_vvc_labels(C_VVC_NAME, GC_INSTANCE_IDX, NA);
  begin
    -- Set the command response queue up to the same settings as the command queue
    read_data_channel_queue.set_scope(C_CHANNEL_SCOPE & ":Q");
    read_data_channel_queue.set_queue_count_max(GC_CMD_QUEUE_COUNT_MAX);
    read_data_channel_queue.set_queue_count_threshold(GC_CMD_QUEUE_COUNT_THRESHOLD);
    read_data_channel_queue.set_queue_count_threshold_severity(GC_CMD_QUEUE_COUNT_THRESHOLD_SEVERITY);

    -- Wait until VVC is registered in vvc activity register in the interpreter
    wait until entry_num_in_vvc_activity_register >= 0;

    loop

      v_msg_id_panel := get_msg_id_panel(VOID); -- v3

      -- update vvc activity
      update_vvc_activity_register(global_trigger_vvc_activity_register, shared_vvc_status, GC_INSTANCE_IDX, NA, INACTIVE, entry_num_in_vvc_activity_register, C_EXECUTOR_ID, last_read_data_channel_idx_executed, read_data_channel_queue.is_empty(VOID), C_SCOPE);
      -- Fetch commands
      work.td_vvc_entity_support_pkg.fetch_command_and_prepare_executor(v_cmd, read_data_channel_queue, shared_vvc_status, read_data_channel_queue_is_increasing, read_data_channel_executor_is_busy, C_VVC_LABELS, C_CHANNEL_SCOPE, ID_CHANNEL_EXECUTOR, ID_CHANNEL_EXECUTOR_WAIT); -- v3
      -- update vvc activity
      update_vvc_activity_register(global_trigger_vvc_activity_register, shared_vvc_status, GC_INSTANCE_IDX, NA, ACTIVE, entry_num_in_vvc_activity_register, C_EXECUTOR_ID, last_read_data_channel_idx_executed, read_data_channel_queue.is_empty(VOID), C_SCOPE);

      v_vvc_config := get_vvc_config(VOID);

      -- Select between a provided msg_id_panel via the vvc_cmd_record from a VVC with a higher hierarchy or the
      -- msg_id_panel in this VVC's config. This is to correctly handle the logging when using Hierarchical-VVCs.

      v_msg_id_panel := get_msg_id_panel(v_cmd, get_msg_id_panel(VOID));

      -- Normalise data
      v_normalised_data := normalize_and_check(v_cmd.data, v_normalised_data, ALLOW_WIDER_NARROWER, "data", "shared_vvc_cmd.data", "Function called with too wide data. " & v_cmd.msg);

      -- Handling commands
      case v_cmd.operation is
        when READ =>
          -- Set vvc transaction info
          set_r_vvc_transaction_info(vvc_transaction_info_trigger, shared_axilite_vvc_transaction_info, GC_INSTANCE_IDX, NA, v_cmd, v_vvc_config, IN_PROGRESS, C_CHANNEL_SCOPE);
          -- Start transaction
          read_data_channel_receive(rdata_value  => v_read_data(GC_DATA_WIDTH - 1 downto 0),
                                    msg          => format_msg(v_cmd),
                                    clk          => clk,
                                    rready       => axilite_vvc_master_if.read_data_channel.rready,
                                    rdata        => axilite_vvc_master_if.read_data_channel.rdata,
                                    rresp        => axilite_vvc_master_if.read_data_channel.rresp,
                                    rvalid       => axilite_vvc_master_if.read_data_channel.rvalid,
                                    scope        => C_CHANNEL_SCOPE,
                                    msg_id_panel => v_msg_id_panel,
                                    config       => v_vvc_config.bfm_config);
          -- Request SB check result
          if v_cmd.data_routing = TO_SB then
            -- call SB check_received
            AXILITE_VVC_SB.check_received(GC_INSTANCE_IDX, pad_axilite_sb(v_read_data(GC_DATA_WIDTH - 1 downto 0)));
          else
            -- Store the result
            work.td_vvc_entity_support_pkg.store_result(result_queue => result_queue,
                                                        cmd_idx      => v_cmd.cmd_idx,
                                                        result       => v_read_data);
          end if;
          -- Update vvc transaction info
          set_r_vvc_transaction_info(vvc_transaction_info_trigger, shared_axilite_vvc_transaction_info, GC_INSTANCE_IDX, NA, v_cmd, v_read_data, COMPLETED, C_CHANNEL_SCOPE);

        when CHECK =>
          -- Set vvc transaction info
          set_r_vvc_transaction_info(vvc_transaction_info_trigger, shared_axilite_vvc_transaction_info, GC_INSTANCE_IDX, NA, v_cmd, v_vvc_config, IN_PROGRESS, C_CHANNEL_SCOPE);
          -- Start transaction
          read_data_channel_check(rdata_exp    => v_normalised_data,
                                  msg          => format_msg(v_cmd),
                                  clk          => clk,
                                  rready       => axilite_vvc_master_if.read_data_channel.rready,
                                  rdata        => axilite_vvc_master_if.read_data_channel.rdata,
                                  rresp        => axilite_vvc_master_if.read_data_channel.rresp,
                                  rvalid       => axilite_vvc_master_if.read_data_channel.rvalid,
                                  alert_level  => v_cmd.alert_level,
                                  scope        => C_CHANNEL_SCOPE,
                                  msg_id_panel => v_msg_id_panel,
                                  config       => v_vvc_config.bfm_config);
          -- Update vvc transaction info
          set_r_vvc_transaction_info(vvc_transaction_info_trigger, shared_axilite_vvc_transaction_info, GC_INSTANCE_IDX, NA, v_cmd, v_vvc_config, COMPLETED, C_CHANNEL_SCOPE);
        when others =>
          tb_error("Unsupported local command received for execution: '" & to_string(v_cmd.operation) & "'", C_CHANNEL_SCOPE);
      end case;
      last_read_data_channel_idx_executed <= v_cmd.cmd_idx;

      -- Update vvc transaction info
      set_global_vvc_transaction_info(vvc_transaction_info_trigger, shared_axilite_vvc_transaction_info, GC_INSTANCE_IDX, NA, v_cmd, v_vvc_config, COMPLETED, C_CHANNEL_SCOPE);
      -- Set vvc transaction info back to default values
      reset_r_vvc_transaction_info(shared_axilite_vvc_transaction_info, GC_INSTANCE_IDX, NA);
      reset_vvc_transaction_info(shared_axilite_vvc_transaction_info, GC_INSTANCE_IDX, NA, v_cmd);
    end loop;
  end process;
  --===============================================================================================

  --===============================================================================================
  -- write address channel executor
  -- - Fetch and execute the write address channel transactions
  --===============================================================================================
  write_address_channel_executor : process
    constant C_EXECUTOR_ID          : natural                              := 3;
    variable v_cmd                  : t_vvc_cmd_record;
    variable v_msg_id_panel         : t_msg_id_panel;
    variable v_normalised_addr      : unsigned(GC_ADDR_WIDTH - 1 downto 0) := (others => '0');
    variable v_vvc_config           : t_vvc_config                         := get_vvc_config(VOID);
    constant C_CHANNEL_SCOPE        : string                               := get_scope_for_log(C_VVC_NAME & "_AW", GC_INSTANCE_IDX);
    constant C_CHANNEL_VVC_LABELS   : t_vvc_labels                         := assign_vvc_labels(C_VVC_NAME, GC_INSTANCE_IDX, NA);
  begin
    -- Set the command response queue up to the same settings as the command queue
    write_address_channel_queue.set_scope(C_CHANNEL_SCOPE & ":Q");
    write_address_channel_queue.set_queue_count_max(GC_CMD_QUEUE_COUNT_MAX);
    write_address_channel_queue.set_queue_count_threshold(GC_CMD_QUEUE_COUNT_THRESHOLD);
    write_address_channel_queue.set_queue_count_threshold_severity(GC_CMD_QUEUE_COUNT_THRESHOLD_SEVERITY);

    -- Wait until VVC is registered in vvc activity register in the interpreter
    wait until entry_num_in_vvc_activity_register >= 0;

    loop

      v_msg_id_panel := get_msg_id_panel(VOID); -- v3

      -- update vvc activity
      update_vvc_activity_register(global_trigger_vvc_activity_register, shared_vvc_status, GC_INSTANCE_IDX, NA, INACTIVE, entry_num_in_vvc_activity_register, C_EXECUTOR_ID, 0, write_address_channel_queue.is_empty(VOID), C_SCOPE);
      -- Fetch commands
      work.td_vvc_entity_support_pkg.fetch_command_and_prepare_executor(v_cmd, write_address_channel_queue, shared_vvc_status, write_address_channel_queue_is_increasing, write_address_channel_executor_is_busy, C_VVC_LABELS, C_CHANNEL_SCOPE, ID_CHANNEL_EXECUTOR, ID_CHANNEL_EXECUTOR_WAIT); -- v3
      -- update vvc activity
      update_vvc_activity_register(global_trigger_vvc_activity_register, shared_vvc_status, GC_INSTANCE_IDX, NA, ACTIVE, entry_num_in_vvc_activity_register, C_EXECUTOR_ID, 0, write_address_channel_queue.is_empty(VOID), C_SCOPE);

      v_vvc_config := get_vvc_config(VOID);

      -- Select between a provided msg_id_panel via the vvc_cmd_record from a VVC with a higher hierarchy or the
      -- msg_id_panel in this VVC's config. This is to correctly handle the logging when using Hierarchical-VVCs.
      v_msg_id_panel := get_msg_id_panel(v_cmd, get_msg_id_panel(VOID));

      -- Normalise address
      v_normalised_addr := normalize_and_check(v_cmd.addr, v_normalised_addr, ALLOW_WIDER_NARROWER, "addr", "shared_vvc_cmd.addr", "Function called with too wide address. " & v_cmd.msg);

      -- Set vvc transaction info
      set_arw_vvc_transaction_info(vvc_transaction_info_trigger, shared_axilite_vvc_transaction_info, GC_INSTANCE_IDX, NA, v_cmd, v_vvc_config, IN_PROGRESS, C_CHANNEL_SCOPE);

      -- Start transaction
      write_address_channel_write(awaddr_value => std_logic_vector(v_normalised_addr),
                                  msg          => format_msg(v_cmd),
                                  clk          => clk,
                                  awaddr       => axilite_vvc_master_if.write_address_channel.awaddr,
                                  awvalid      => axilite_vvc_master_if.write_address_channel.awvalid,
                                  awprot       => axilite_vvc_master_if.write_address_channel.awprot,
                                  awready      => axilite_vvc_master_if.write_address_channel.awready,
                                  scope        => C_CHANNEL_SCOPE,
                                  msg_id_panel => v_msg_id_panel,
                                  config       => v_vvc_config.bfm_config);

      -- Update vvc transaction info
      set_arw_vvc_transaction_info(vvc_transaction_info_trigger, shared_axilite_vvc_transaction_info, GC_INSTANCE_IDX, NA, v_cmd, v_vvc_config, COMPLETED, C_CHANNEL_SCOPE);
      -- Set vvc transaction info back to default values
      reset_arw_vvc_transaction_info(shared_axilite_vvc_transaction_info, GC_INSTANCE_IDX, NA, v_cmd);
    end loop;
  end process;
  --===============================================================================================

  --===============================================================================================
  -- write data channel executor
  -- - Fetch and execute the write data channel transactions
  --===============================================================================================
  write_data_channel_executor : process
    constant C_EXECUTOR_ID          : natural                                      := 4;
    variable v_cmd                  : t_vvc_cmd_record;
    variable v_msg_id_panel         : t_msg_id_panel;
    variable v_normalised_data      : std_logic_vector(GC_DATA_WIDTH - 1 downto 0) := (others => '0');
    variable v_vvc_config           : t_vvc_config                                 := get_vvc_config(VOID);
    constant C_CHANNEL_SCOPE        : string                                       := get_scope_for_log(C_VVC_NAME & "_W", GC_INSTANCE_IDX);
    constant C_CHANNEL_VVC_LABELS   : t_vvc_labels                                 := assign_vvc_labels(C_VVC_NAME, GC_INSTANCE_IDX, NA);
  begin
    -- Set the command response queue up to the same settings as the command queue
    write_data_channel_queue.set_scope(C_CHANNEL_SCOPE & ":Q");
    write_data_channel_queue.set_queue_count_max(GC_CMD_QUEUE_COUNT_MAX);
    write_data_channel_queue.set_queue_count_threshold(GC_CMD_QUEUE_COUNT_THRESHOLD);
    write_data_channel_queue.set_queue_count_threshold_severity(GC_CMD_QUEUE_COUNT_THRESHOLD_SEVERITY);

    -- Wait until VVC is registered in vvc activity register in the interpreter
    wait until entry_num_in_vvc_activity_register >= 0;

    loop

      v_msg_id_panel := get_msg_id_panel(VOID); -- v3

      -- update vvc activity
      update_vvc_activity_register(global_trigger_vvc_activity_register, shared_vvc_status, GC_INSTANCE_IDX, NA, INACTIVE, entry_num_in_vvc_activity_register, C_EXECUTOR_ID, 0, write_data_channel_queue.is_empty(VOID), C_SCOPE);
      -- Fetch commands
      work.td_vvc_entity_support_pkg.fetch_command_and_prepare_executor(v_cmd, write_data_channel_queue, shared_vvc_status, write_data_channel_queue_is_increasing, write_data_channel_executor_is_busy, C_VVC_LABELS, C_CHANNEL_SCOPE, ID_CHANNEL_EXECUTOR, ID_CHANNEL_EXECUTOR_WAIT); -- v3
      -- update vvc activity
      update_vvc_activity_register(global_trigger_vvc_activity_register, shared_vvc_status, GC_INSTANCE_IDX, NA, ACTIVE, entry_num_in_vvc_activity_register, C_EXECUTOR_ID, 0, write_data_channel_queue.is_empty(VOID), C_SCOPE);

      v_vvc_config := get_vvc_config(VOID);

      -- Select between a provided msg_id_panel via the vvc_cmd_record from a VVC with a higher hierarchy or the
      -- msg_id_panel in this VVC's config. This is to correctly handle the logging when using Hierarchical-VVCs.
      v_msg_id_panel := get_msg_id_panel(v_cmd, get_msg_id_panel(VOID));

      -- Normalise data
      v_normalised_data := normalize_and_check(v_cmd.data, v_normalised_data, ALLOW_WIDER_NARROWER, "data", "shared_vvc_cmd.data", "Function called with too wide data. " & v_cmd.msg);

      -- Set vvc transaction info
      set_w_vvc_transaction_info(vvc_transaction_info_trigger, shared_axilite_vvc_transaction_info, GC_INSTANCE_IDX, NA, v_cmd, v_vvc_config, IN_PROGRESS, C_CHANNEL_SCOPE);

      -- Start transaction
      write_data_channel_write(wdata_value  => v_normalised_data,
                               wstrb_value  => v_cmd.byte_enable((GC_DATA_WIDTH / 8 - 1) downto 0),
                               msg          => format_msg(v_cmd),
                               clk          => clk,
                               wdata        => axilite_vvc_master_if.write_data_channel.wdata,
                               wstrb        => axilite_vvc_master_if.write_data_channel.wstrb,
                               wvalid       => axilite_vvc_master_if.write_data_channel.wvalid,
                               wready       => axilite_vvc_master_if.write_data_channel.wready,
                               scope        => C_CHANNEL_SCOPE,
                               msg_id_panel => v_msg_id_panel,
                               config       => v_vvc_config.bfm_config);

      -- Update vvc transaction info
      set_w_vvc_transaction_info(vvc_transaction_info_trigger, shared_axilite_vvc_transaction_info, GC_INSTANCE_IDX, NA, v_cmd, v_vvc_config, COMPLETED, C_CHANNEL_SCOPE);
      -- Set vvc transaction info back to default values
      reset_w_vvc_transaction_info(shared_axilite_vvc_transaction_info, GC_INSTANCE_IDX, NA);
    end loop;
  end process;
  --===============================================================================================

  --===============================================================================================
  -- write response channel executor
  -- - Fetch and execute the write response channel transactions
  --===============================================================================================
  write_response_channel_executor : process
    constant C_EXECUTOR_ID          : natural                                      := 5;
    variable v_cmd                  : t_vvc_cmd_record;
    variable v_msg_id_panel         : t_msg_id_panel;
    variable v_normalised_data      : std_logic_vector(GC_DATA_WIDTH - 1 downto 0) := (others => '0');
    variable v_vvc_config           : t_vvc_config                                 := get_vvc_config(VOID);
    constant C_CHANNEL_SCOPE        : string                                       := get_scope_for_log(C_VVC_NAME & "_B", GC_INSTANCE_IDX);
    constant C_CHANNEL_VVC_LABELS   : t_vvc_labels                                 := assign_vvc_labels(C_VVC_NAME, GC_INSTANCE_IDX, NA);
  begin
    -- Set the command response queue up to the same settings as the command queue
    write_response_channel_queue.set_scope(C_CHANNEL_SCOPE & ":Q");
    write_response_channel_queue.set_queue_count_max(GC_CMD_QUEUE_COUNT_MAX);
    write_response_channel_queue.set_queue_count_threshold(GC_CMD_QUEUE_COUNT_THRESHOLD);
    write_response_channel_queue.set_queue_count_threshold_severity(GC_CMD_QUEUE_COUNT_THRESHOLD_SEVERITY);

    -- Wait until VVC is registered in vvc activity register in the interpreter
    wait until entry_num_in_vvc_activity_register >= 0;

    loop

      v_msg_id_panel := get_msg_id_panel(VOID); -- v3

      -- update vvc activity
      update_vvc_activity_register(global_trigger_vvc_activity_register, shared_vvc_status, GC_INSTANCE_IDX, NA, INACTIVE, entry_num_in_vvc_activity_register, C_EXECUTOR_ID, last_write_response_channel_idx_executed, write_response_channel_queue.is_empty(VOID), C_SCOPE);
      -- Fetch commands
      work.td_vvc_entity_support_pkg.fetch_command_and_prepare_executor(v_cmd, write_response_channel_queue, shared_vvc_status, write_response_channel_queue_is_increasing, write_response_channel_executor_is_busy, C_VVC_LABELS, C_CHANNEL_SCOPE, ID_CHANNEL_EXECUTOR, ID_CHANNEL_EXECUTOR_WAIT); -- v3
      -- update vvc activity
      update_vvc_activity_register(global_trigger_vvc_activity_register, shared_vvc_status, GC_INSTANCE_IDX, NA, ACTIVE, entry_num_in_vvc_activity_register, C_EXECUTOR_ID, last_write_response_channel_idx_executed, write_response_channel_queue.is_empty(VOID), C_SCOPE);

      v_vvc_config := get_vvc_config(VOID);

      -- Select between a provided msg_id_panel via the vvc_cmd_record from a VVC with a higher hierarchy or the
      -- msg_id_panel in this VVC's config. This is to correctly handle the logging when using Hierarchical-VVCs.
      v_msg_id_panel := get_msg_id_panel(v_cmd, get_msg_id_panel(VOID));

      -- Set vvc transaction info
      set_b_vvc_transaction_info(vvc_transaction_info_trigger, shared_axilite_vvc_transaction_info, GC_INSTANCE_IDX, NA, v_cmd, v_vvc_config, IN_PROGRESS, C_CHANNEL_SCOPE);

      -- Receiving a write response
      write_response_channel_check(msg          => format_msg(v_cmd),
                                   clk          => clk,
                                   bready       => axilite_vvc_master_if.write_response_channel.bready,
                                   bresp        => axilite_vvc_master_if.write_response_channel.bresp,
                                   bvalid       => axilite_vvc_master_if.write_response_channel.bvalid,
                                   alert_level  => error,
                                   scope        => C_CHANNEL_SCOPE,
                                   msg_id_panel => v_msg_id_panel,
                                   config       => v_vvc_config.bfm_config);

      last_write_response_channel_idx_executed <= v_cmd.cmd_idx;

      -- Update vvc transaction info
      set_b_vvc_transaction_info(vvc_transaction_info_trigger, shared_axilite_vvc_transaction_info, GC_INSTANCE_IDX, NA, v_cmd, v_vvc_config, COMPLETED, C_CHANNEL_SCOPE);
      set_global_vvc_transaction_info(vvc_transaction_info_trigger, shared_axilite_vvc_transaction_info, GC_INSTANCE_IDX, NA, v_cmd, v_vvc_config, COMPLETED, C_CHANNEL_SCOPE);
      -- Set vvc transaction info back to default values
      reset_b_vvc_transaction_info(shared_axilite_vvc_transaction_info, GC_INSTANCE_IDX, NA);
      reset_vvc_transaction_info(shared_axilite_vvc_transaction_info, GC_INSTANCE_IDX, NA, v_cmd);
    end loop;
  end process;
  --===============================================================================================

  --===============================================================================================
  -- Command termination handler
  -- - Handles the termination request record (sets and resets terminate flag on request)
  --===============================================================================================
  cmd_terminator : uvvm_vvc_framework.ti_vvc_framework_support_pkg.flag_handler(terminate_current_cmd); -- flag: is_active, set, reset
  --===============================================================================================

  --===============================================================================================
  -- Clock period
  -- - Finds the clock period
  --===============================================================================================
  p_clock_period : process
  begin
    wait until rising_edge(clk);
    clock_period <= now;
    wait until rising_edge(clk);
    clock_period <= now - clock_period;
    wait;
  end process;
  --===============================================================================================

  --===============================================================================================
  -- Unwanted activity detection
  -- - Monitors unwanted activity from the DUT
  --===============================================================================================
  p_unwanted_activity : process
    variable v_vvc_config : t_vvc_config;
  begin
    -- Add a delay to avoid detecting the first transition from the undefined value to initial value
    wait for std.env.resolution_limit;

    loop
      -- Skip if the vvc is inactive to avoid waiting for an inactive activity register
      if shared_vvc_activity_register.priv_get_vvc_activity(entry_num_in_vvc_activity_register) = ACTIVE then
        -- Wait until the vvc is inactive
        loop
          wait on global_trigger_vvc_activity_register;
          if shared_vvc_activity_register.priv_get_vvc_activity(entry_num_in_vvc_activity_register) = INACTIVE then
            exit;
          end if;
        end loop;
      end if;

      -- All ready signals are not monitored. See AXI-Lite VVC QuickRef.
      wait on axilite_vvc_master_if.write_response_channel.bresp, axilite_vvc_master_if.write_response_channel.bvalid, axilite_vvc_master_if.read_data_channel.rdata,
              axilite_vvc_master_if.read_data_channel.rresp, axilite_vvc_master_if.read_data_channel.rvalid, global_trigger_vvc_activity_register;

      -- Check the changes on the DUT outputs only when the vvc is inactive
      if shared_vvc_activity_register.priv_get_vvc_activity(entry_num_in_vvc_activity_register) = INACTIVE then
        v_vvc_config := get_vvc_config(VOID);
        -- Skip checking the changes if the bvalid signal goes low within one clock period after the VVC becomes inactive
        if not (falling_edge(axilite_vvc_master_if.write_response_channel.bvalid) and global_trigger_vvc_activity_register'last_event < clock_period) then
          check_value(not axilite_vvc_master_if.write_response_channel.bvalid'event, v_vvc_config.unwanted_activity_severity, "Unwanted activity detected on bvalid", C_SCOPE, ID_NEVER, get_msg_id_panel(VOID));
          check_value(not axilite_vvc_master_if.write_response_channel.bresp'event, v_vvc_config.unwanted_activity_severity, "Unwanted activity detected on bresp", C_SCOPE, ID_NEVER, get_msg_id_panel(VOID));
        end if;

        -- Skip checking the changes if the rvalid signal goes low within one clock period after the VVC becomes inactive
        if not (falling_edge(axilite_vvc_master_if.read_data_channel.rvalid) and global_trigger_vvc_activity_register'last_event < clock_period) then
          check_value(not axilite_vvc_master_if.read_data_channel.rvalid'event, v_vvc_config.unwanted_activity_severity, "Unwanted activity detected on rvalid", C_SCOPE, ID_NEVER, get_msg_id_panel(VOID));
          check_value(not axilite_vvc_master_if.read_data_channel.rdata'event, v_vvc_config.unwanted_activity_severity, "Unwanted activity detected on rdata", C_SCOPE, ID_NEVER, get_msg_id_panel(VOID));
          check_value(not axilite_vvc_master_if.read_data_channel.rresp'event, v_vvc_config.unwanted_activity_severity, "Unwanted activity detected on rresp", C_SCOPE, ID_NEVER, get_msg_id_panel(VOID));
        end if;
      end if;
    end loop;
  end process p_unwanted_activity;
  --===============================================================================================

end behave;
