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
use bitvis_vip_scoreboard.generic_sb_support_pkg.C_SB_CONFIG_DEFAULT;

use work.avalon_mm_bfm_pkg.all;
use work.vvc_methods_pkg.all;
use work.vvc_cmd_pkg.all;
use work.td_target_support_pkg.all;
use work.td_vvc_entity_support_pkg.all;
use work.td_cmd_queue_pkg.all;
use work.td_result_queue_pkg.all;
use work.transaction_pkg.all;

--=================================================================================================
entity avalon_mm_vvc is
    generic(
        GC_ADDR_WIDTH                            : integer range 1 to C_VVC_CMD_ADDR_MAX_LENGTH := 8; -- Avalon MM address bus
        GC_DATA_WIDTH                            : integer range 1 to C_VVC_CMD_DATA_MAX_LENGTH := 32; -- Avalon MM data bus
        GC_INSTANCE_IDX                          : natural                                      := 1; -- Instance index for this AVALON_MM_VVCT instance
        GC_AVALON_MM_CONFIG                      : t_avalon_mm_bfm_config                       := C_AVALON_MM_BFM_CONFIG_DEFAULT; -- Behavior specification for BFM
        GC_CMD_QUEUE_COUNT_MAX                   : natural                                      := 1000;
        GC_CMD_QUEUE_COUNT_THRESHOLD             : natural                                      := 950;
        GC_CMD_QUEUE_COUNT_THRESHOLD_SEVERITY    : t_alert_level                                := WARNING;
        GC_RESULT_QUEUE_COUNT_MAX                : natural                                      := 1000;
        GC_RESULT_QUEUE_COUNT_THRESHOLD          : natural                                      := 950;
        GC_RESULT_QUEUE_COUNT_THRESHOLD_SEVERITY : t_alert_level                                := WARNING
    );
    port(
        clk                     : in    std_logic;
        avalon_mm_vvc_master_if : inout t_avalon_mm_if := init_avalon_mm_if_signals(GC_ADDR_WIDTH, GC_DATA_WIDTH)
    );
begin
    -- Check the interface widths to assure that the interface was correctly set up
    assert (avalon_mm_vvc_master_if.address'length = GC_ADDR_WIDTH) report "avalon_mm_vvc_master_if.address'length /= GC_ADDR_WIDTH" severity failure;
    assert (avalon_mm_vvc_master_if.writedata'length = GC_DATA_WIDTH) report "avalon_mm_vvc_master_if.writedata'length /= GC_DATA_WIDTH" severity failure;
    assert (avalon_mm_vvc_master_if.readdata'length = GC_DATA_WIDTH) report "avalon_mm_vvc_master_if.readdata'length /= GC_DATA_WIDTH" severity failure;
    assert (avalon_mm_vvc_master_if.byte_enable'length = GC_DATA_WIDTH / 8) report "avalon_mm_vvc_master_if.byte_enable'length /= GC_DATA_WIDTH/8" severity failure;
end entity avalon_mm_vvc;

--=================================================================================================
--=================================================================================================

architecture behave of avalon_mm_vvc is

    constant C_SCOPE      : string       := C_VVC_NAME & "," & to_string(GC_INSTANCE_IDX);
    constant C_VVC_LABELS : t_vvc_labels := assign_vvc_labels(C_SCOPE, C_VVC_NAME, GC_INSTANCE_IDX, NA);

    signal vvc_is_active                   : boolean := false;
    signal executor_is_busy                : boolean := false;
    signal queue_is_increasing             : boolean := false;
    signal read_response_is_busy           : boolean := false;
    signal response_queue_is_increasing    : boolean := false;
    signal last_cmd_idx_executed           : natural := 0;
    signal last_read_response_idx_executed : natural := 0;
    signal terminate_current_cmd           : t_flag_record;

    -- Instantiation of element dedicated Queues
    shared variable command_queue          : work.td_cmd_queue_pkg.t_generic_queue;
    shared variable command_response_queue : work.td_cmd_queue_pkg.t_generic_queue;
    shared variable result_queue           : work.td_result_queue_pkg.t_generic_queue;

    -- Transaction info
    alias vvc_transaction_info_trigger        : std_logic is global_avalon_mm_vvc_transaction_trigger(GC_INSTANCE_IDX);
    -- VVC Activity
    signal entry_num_in_vvc_activity_register : integer;

    -- Propagation delayed interface signal used when reading data from the slave in the read_response process.
    signal avalon_mm_vvc_master_if_pd : t_avalon_mm_if(address(GC_ADDR_WIDTH - 1 downto 0),
                                                       byte_enable((GC_DATA_WIDTH / 8) - 1 downto 0),
                                                       writedata(GC_DATA_WIDTH - 1 downto 0),
                                                       readdata(GC_DATA_WIDTH - 1 downto 0)) := avalon_mm_vvc_master_if;

    --UVVM: temporary fix for HVVC, remove function below in v3.0
    impure function get_msg_id_panel(   -- v3
        constant command : in t_vvc_cmd_record
    ) return t_msg_id_panel is
    begin
        -- If the parent_msg_id_panel is set then use it,
        -- otherwise use the VVCs msg_id_panel from its config.
        if command.msg(1 to 5) = "HVVC:" then
            return shared_parent_avalon_mm_vvc_msg_id_panel.get(GC_INSTANCE_IDX); -- v3
        else
            return shared_avalon_mm_vvc_msg_id_panel.get(GC_INSTANCE_IDX); -- v3
        end if;
    end function;

    impure function get_vvc_status(
        constant void : t_void
    ) return t_vvc_status is
    begin
        return shared_avalon_mm_vvc_status.get(GC_INSTANCE_IDX);
    end function get_vvc_status;

    procedure set_vvc_status(
        constant vvc_status : t_vvc_status
    ) is
    begin
        shared_avalon_mm_vvc_status.set(vvc_status, GC_INSTANCE_IDX);
    end procedure set_vvc_status;

begin

    --===============================================================================================
    -- Constructor
    -- - Set up the defaults and show constructor if enabled
    --===============================================================================================
    -- v3
    vvc_constructor(C_SCOPE, GC_INSTANCE_IDX, shared_avalon_mm_vvc_config, shared_avalon_mm_vvc_msg_id_panel.get(GC_INSTANCE_IDX), command_queue, result_queue, GC_AVALON_MM_CONFIG,
                    GC_CMD_QUEUE_COUNT_MAX, GC_CMD_QUEUE_COUNT_THRESHOLD, GC_CMD_QUEUE_COUNT_THRESHOLD_SEVERITY,
                    GC_RESULT_QUEUE_COUNT_MAX, GC_RESULT_QUEUE_COUNT_THRESHOLD, GC_RESULT_QUEUE_COUNT_THRESHOLD_SEVERITY);
    --===============================================================================================

    --===============================================================================================
    -- Command interpreter
    -- - Interpret, decode and acknowledge commands from the central sequencer
    --===============================================================================================
    cmd_interpreter : process
        variable v_cmd_has_been_acked  : boolean; -- Indicates if acknowledge_cmd() has been called for the current shared_vvc_cmd
        variable v_local_vvc_cmd       : t_vvc_cmd_record := C_VVC_CMD_DEFAULT;
        variable v_msg_id_panel        : t_msg_id_panel;
        variable v_parent_msg_id_panel : t_msg_id_panel; -- v3
        variable v_temp_msg_id_panel   : t_msg_id_panel; --UVVM: temporary fix for HVVC, remove in v3.0
        variable v_vvc_status          : t_vvc_status;
    begin
        -- 0. Initialize the process prior to first command
        work.td_vvc_entity_support_pkg.initialize_interpreter(terminate_current_cmd, global_awaiting_completion);

        -- initialise shared_vvc_last_received_cmd_idx for channel and instance
        shared_vvc_last_received_cmd_idx.set(0, GC_INSTANCE_IDX);

        -- Register VVC in vvc activity register
        entry_num_in_vvc_activity_register <= shared_vvc_activity_register.priv_register_vvc(name     => C_VVC_NAME,
                                                                                             instance => GC_INSTANCE_IDX);

        -- Then for every single command from the sequencer
        loop                            -- basically as long as new commands are received

            v_msg_id_panel        := shared_avalon_mm_vvc_msg_id_panel.get(GC_INSTANCE_IDX); -- v3
            v_parent_msg_id_panel := get_msg_id_panel(v_local_vvc_cmd); -- v3

            -- 1. wait until command targeted at this VVC. Must match VVC name, instance and channel (if applicable)
            --    releases global semaphore
            -------------------------------------------------------------------------
            work.td_vvc_entity_support_pkg.await_cmd_from_sequencer(C_VVC_LABELS, v_msg_id_panel, v_parent_msg_id_panel, THIS_VVCT, VVC_BROADCAST, global_vvc_busy, global_vvc_ack, v_local_vvc_cmd); -- v3

            v_cmd_has_been_acked := false; -- Clear flag

            -- update shared_vvc_last_received_cmd_idx with received command index
            shared_vvc_last_received_cmd_idx.set(v_local_vvc_cmd.cmd_idx, GC_INSTANCE_IDX);

            -- Select between a provided msg_id_panel via the vvc_cmd_record from a VVC with a higher hierarchy or the
            -- msg_id_panel in this VVC's config. This is to correctly handle the logging when using Hierarchical-VVCs.
            v_msg_id_panel := get_msg_id_panel(v_local_vvc_cmd);

            -- 2a. Put command on the queue if intended for the executor
            -------------------------------------------------------------------------
            if v_local_vvc_cmd.command_type = QUEUED then
                v_vvc_status := get_vvc_status(VOID);
                work.td_vvc_entity_support_pkg.put_command_on_queue(v_local_vvc_cmd, command_queue, v_vvc_status, queue_is_increasing);
                set_vvc_status(v_vvc_status);

            -- 2b. Otherwise command is intended for immediate response
            -------------------------------------------------------------------------
            elsif v_local_vvc_cmd.command_type = IMMEDIATE then

                --UVVM: temporary fix for HVVC, remove two lines below in v3.0
                if v_local_vvc_cmd.operation /= DISABLE_LOG_MSG and v_local_vvc_cmd.operation /= ENABLE_LOG_MSG then
                    v_temp_msg_id_panel := shared_avalon_mm_vvc_msg_id_panel.get(GC_INSTANCE_IDX); -- v3
                    shared_avalon_mm_vvc_msg_id_panel.set(v_msg_id_panel, GC_INSTANCE_IDX); -- v3         
                end if;

                case v_local_vvc_cmd.operation is

                    when AWAIT_COMPLETION =>
                        -- Await completion of all commands in the cmd_executor queue
                        work.td_vvc_entity_support_pkg.interpreter_await_completion(v_local_vvc_cmd, command_queue, v_msg_id_panel, executor_is_busy, C_VVC_LABELS, last_cmd_idx_executed); -- v3
                        -- Await completion of all commands in the read_response queue
                        work.td_vvc_entity_support_pkg.interpreter_await_completion(v_local_vvc_cmd, command_response_queue, v_msg_id_panel, executor_is_busy, C_VVC_LABELS, last_cmd_idx_executed); -- v3

                    when AWAIT_ANY_COMPLETION =>
                        if not v_local_vvc_cmd.gen_boolean then
                            -- Called with lastness = NOT_LAST: Acknowledge immediately to let the sequencer continue
                            work.td_target_support_pkg.acknowledge_cmd(global_vvc_ack, v_local_vvc_cmd.cmd_idx);
                            v_cmd_has_been_acked := true;
                        end if;
                        work.td_vvc_entity_support_pkg.interpreter_await_any_completion(v_local_vvc_cmd, command_queue, v_msg_id_panel, executor_is_busy, C_VVC_LABELS, last_cmd_idx_executed, global_awaiting_completion); -- v3

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

                --UVVM: temporary fix for HVVC, remove line below in v3.0
                if v_local_vvc_cmd.operation /= DISABLE_LOG_MSG and v_local_vvc_cmd.operation /= ENABLE_LOG_MSG then
                    shared_avalon_mm_vvc_msg_id_panel.set(v_temp_msg_id_panel, GC_INSTANCE_IDX); -- v3
                else
                    shared_avalon_mm_vvc_msg_id_panel.set(v_msg_id_panel, GC_INSTANCE_IDX); -- v3
                end if;

            else
                tb_error("command_type is not IMMEDIATE or QUEUED", C_SCOPE);
            end if;

            -- 3. Acknowledge command after runing or queuing the command
            -------------------------------------------------------------------------
            if not v_cmd_has_been_acked then
                work.td_target_support_pkg.acknowledge_cmd(global_vvc_ack, v_local_vvc_cmd.cmd_idx);
            end if;

        end loop;
    end process;
    --===============================================================================================

    --===============================================================================================
    -- Command executor
    -- - Fetch and execute the commands.
    -- - Note that the read response is handled in the read_response process.
    --===============================================================================================
    cmd_executor : process
        variable v_cmd                                   : t_vvc_cmd_record;
        variable v_read_data                             : t_vvc_result; -- See vvc_cmd_pkg
        variable v_timestamp_start_of_current_bfm_access : time                                               := 0 ns;
        variable v_timestamp_start_of_last_bfm_access    : time                                               := 0 ns;
        variable v_timestamp_end_of_last_bfm_access      : time                                               := 0 ns;
        variable v_command_is_bfm_access                 : boolean                                            := false;
        variable v_prev_command_was_bfm_access           : boolean                                            := false;
        variable v_msg_id_panel                          : t_msg_id_panel;
        variable v_normalised_addr                       : unsigned(GC_ADDR_WIDTH - 1 downto 0)               := (others => '0');
        variable v_normalised_data                       : std_logic_vector(GC_DATA_WIDTH - 1 downto 0)       := (others => '0');
        variable v_normalised_byte_ena                   : std_logic_vector((GC_DATA_WIDTH / 8) - 1 downto 0) := (others => '0');
        variable v_cmd_queues_are_empty                  : boolean;
        variable v_vvc_config                            : t_vvc_config;
        variable v_vvc_status                            : t_vvc_status;

    begin
        -- 0. Initialize the process prior to first command
        -------------------------------------------------------------------------
        initialize_executor(terminate_current_cmd);

        -- Setup Avalon MM scoreboard
        AVALON_MM_VVC_SB.set_scope("AVALON_MM_VVC_SB");
        AVALON_MM_VVC_SB.enable(GC_INSTANCE_IDX, "AVALON_MM VVC SB Enabled");
        AVALON_MM_VVC_SB.config(GC_INSTANCE_IDX, C_SB_CONFIG_DEFAULT);
        AVALON_MM_VVC_SB.enable_log_msg(GC_INSTANCE_IDX, ID_DATA);

        loop

            v_msg_id_panel := shared_avalon_mm_vvc_msg_id_panel.get(GC_INSTANCE_IDX); -- v3

            -- update vvc activity
            v_cmd_queues_are_empty := (command_queue.is_empty(VOID) and command_response_queue.is_empty(VOID));
            if not (read_response_is_busy) and v_cmd_queues_are_empty then
                update_vvc_activity_register(global_trigger_vvc_activity_register,
                                             shared_avalon_mm_vvc_status,
                                             GC_INSTANCE_IDX,
                                             NA,
                                             INACTIVE,
                                             entry_num_in_vvc_activity_register,
                                             last_cmd_idx_executed,
                                             v_cmd_queues_are_empty,
                                             C_SCOPE);
            end if;

            -- 1. Set defaults, fetch command and log
            -------------------------------------------------------------------------
            work.td_vvc_entity_support_pkg.fetch_command_and_prepare_executor(v_cmd, command_queue, v_msg_id_panel, shared_avalon_mm_vvc_status, queue_is_increasing, executor_is_busy, C_VVC_LABELS); -- v3

            -- update vvc activity
            v_cmd_queues_are_empty := (command_queue.is_empty(VOID) and command_response_queue.is_empty(VOID));
            update_vvc_activity_register(global_trigger_vvc_activity_register,
                                         shared_avalon_mm_vvc_status,
                                         GC_INSTANCE_IDX,
                                         NA,
                                         ACTIVE,
                                         entry_num_in_vvc_activity_register,
                                         last_cmd_idx_executed,
                                         v_cmd_queues_are_empty,
                                         C_SCOPE);


            v_vvc_config := shared_avalon_mm_vvc_config.get(GC_INSTANCE_IDX);

            -- Select between a provided msg_id_panel via the vvc_cmd_record from a VVC with a higher hierarchy or the
            -- msg_id_panel in this VVC's config. This is to correctly handle the logging when using Hierarchical-VVCs.
            v_msg_id_panel := get_msg_id_panel(v_cmd);

            -- Check if command is a BFM access
            v_prev_command_was_bfm_access := v_command_is_bfm_access; -- save for insert_bfm_delay
            if v_cmd.operation = WRITE or v_cmd.operation = READ or v_cmd.operation = CHECK or v_cmd.operation = RESET then
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
            case v_cmd.operation is     -- Only operations in the dedicated record are relevant

                -- VVC dedicated operations
                --===================================
                when WRITE =>
                    -- Set vvc transaction info
                    set_global_vvc_transaction_info(vvc_transaction_info_trigger, shared_avalon_mm_vvc_transaction_info, GC_INSTANCE_IDX, NA, v_cmd, v_vvc_config);

                    -- Normalise address and data
                    v_normalised_addr                                              := normalize_and_check(v_cmd.addr, v_normalised_addr, ALLOW_WIDER_NARROWER, "v_cmd.addr", "v_normalised_addr", "avalon_mm_write() called with to wide address. " & v_cmd.msg);
                    v_normalised_data                                              := normalize_and_check(v_cmd.data, v_normalised_data, ALLOW_WIDER_NARROWER, "v_cmd.data", "v_normalised_data", "avalon_mm_write() called with to wide data. " & v_cmd.msg);
                    if (v_cmd.byte_enable = (0 to v_cmd.byte_enable'length - 1 => '1')) then
                        v_normalised_byte_ena := (others => '1');
                    else
                        v_normalised_byte_ena := normalize_and_check(v_cmd.byte_enable, v_normalised_byte_ena, ALLOW_WIDER_NARROWER, "v_cmd.byte_enable", "v_normalised_byte_ena", "avalon_mm_write() called with to wide byte_enable. " & v_cmd.msg);
                    end if;

                    -- Call the corresponding procedure in the BFM package.
                    avalon_mm_write(addr_value   => v_normalised_addr,
                                    data_value   => v_normalised_data,
                                    msg          => format_msg(v_cmd),
                                    clk          => clk,
                                    avalon_mm_if => avalon_mm_vvc_master_if,
                                    byte_enable  => v_cmd.byte_enable((GC_DATA_WIDTH / 8) - 1 downto 0),
                                    scope        => C_SCOPE,
                                    msg_id_panel => v_msg_id_panel,
                                    config       => v_vvc_config.bfm_config);

                when READ =>
                    -- Set vvc transaction info
                    set_global_vvc_transaction_info(vvc_transaction_info_trigger, shared_avalon_mm_vvc_transaction_info, GC_INSTANCE_IDX, NA, v_cmd, v_vvc_config);

                    -- Normalise address
                    v_normalised_addr := normalize_and_check(v_cmd.addr, v_normalised_addr, ALLOW_WIDER_NARROWER, "v_cmd.addr", "v_normalised_addr", "avalon_mm_read() called with to wide address. " & v_cmd.msg);


                    -- Call the corresponding procedure in the BFM package.
                    if v_vvc_config.use_read_pipeline then
                        -- Stall until response command queue is no longer full
                        while command_response_queue.get_count(VOID) > v_vvc_config.num_pipeline_stages loop
                            wait for v_vvc_config.bfm_config.clock_period;
                        end loop;
                        avalon_mm_read_request(addr_value   => v_normalised_addr,
                                               msg          => format_msg(v_cmd),
                                               clk          => clk,
                                               avalon_mm_if => avalon_mm_vvc_master_if,
                                               scope        => C_SCOPE,
                                               msg_id_panel => v_msg_id_panel,
                                               config       => v_vvc_config.bfm_config);
                        v_vvc_status := get_vvc_status(VOID);
                        work.td_vvc_entity_support_pkg.put_command_on_queue(v_cmd, command_response_queue, v_vvc_status, response_queue_is_increasing);
                        set_vvc_status(v_vvc_status);

                    else

                        avalon_mm_read(addr_value   => v_normalised_addr,
                                       data_value   => v_read_data(GC_DATA_WIDTH - 1 downto 0),
                                       msg          => format_msg(v_cmd),
                                       clk          => clk,
                                       avalon_mm_if => avalon_mm_vvc_master_if,
                                       scope        => C_SCOPE,
                                       msg_id_panel => v_msg_id_panel,
                                       config       => v_vvc_config.bfm_config);

                        -- Request SB check result
                        if v_cmd.data_routing = TO_SB then
                            -- call SB check_received
                            AVALON_MM_VVC_SB.check_received(GC_INSTANCE_IDX, pad_avalon_mm_sb(v_read_data(GC_DATA_WIDTH - 1 downto 0)));
                        else
                            -- Store the result
                            work.td_vvc_entity_support_pkg.store_result(result_queue => result_queue,
                                                                        cmd_idx      => v_cmd.cmd_idx,
                                                                        result       => v_read_data);
                        end if;
                    end if;

                when CHECK =>
                    -- Set vvc transaction info
                    set_global_vvc_transaction_info(vvc_transaction_info_trigger, shared_avalon_mm_vvc_transaction_info, GC_INSTANCE_IDX, NA, v_cmd, v_vvc_config);

                    -- Normalise address
                    v_normalised_addr := normalize_and_check(v_cmd.addr, v_normalised_addr, ALLOW_WIDER_NARROWER, "v_cmd.addr", "v_normalised_addr", "avalon_mm_check() called with to wide address. " & v_cmd.msg);
                    v_normalised_data := normalize_and_check(v_cmd.data, v_normalised_data, ALLOW_WIDER_NARROWER, "v_cmd.data", "v_normalised_data", "avalon_mm_check() called with to wide data. " & v_cmd.msg);

                    -- Call the corresponding procedure in the BFM package.
                    if v_vvc_config.use_read_pipeline then
                        -- Wait until response command queue is no longer full
                        while command_response_queue.get_count(VOID) > v_vvc_config.num_pipeline_stages loop
                            wait for v_vvc_config.bfm_config.clock_period;
                        end loop;

                        avalon_mm_read_request(addr_value    => v_normalised_addr,
                                               msg           => format_msg(v_cmd),
                                               clk           => clk,
                                               avalon_mm_if  => avalon_mm_vvc_master_if,
                                               scope         => C_SCOPE,
                                               msg_id_panel  => v_msg_id_panel,
                                               config        => v_vvc_config.bfm_config,
                                               ext_proc_call => "avalon_mm_check(A:" & to_string(v_normalised_addr, HEX, AS_IS, INCL_RADIX) & ", " & to_string(v_normalised_data, HEX, AS_IS, INCL_RADIX) & ")"
                                              );
                        v_vvc_status := get_vvc_status(VOID);
                        work.td_vvc_entity_support_pkg.put_command_on_queue(v_cmd, command_response_queue, v_vvc_status, response_queue_is_increasing);
                        set_vvc_status(v_vvc_status);
                    else
                        avalon_mm_check(addr_value   => v_normalised_addr,
                                        data_exp     => v_normalised_data,
                                        msg          => format_msg(v_cmd),
                                        clk          => clk,
                                        avalon_mm_if => avalon_mm_vvc_master_if,
                                        alert_level  => v_cmd.alert_level,
                                        scope        => C_SCOPE,
                                        msg_id_panel => v_msg_id_panel,
                                        config       => v_vvc_config.bfm_config);
                    end if;

                when RESET =>
                    -- Set vvc transaction info
                    set_global_vvc_transaction_info(vvc_transaction_info_trigger, shared_avalon_mm_vvc_transaction_info, GC_INSTANCE_IDX, NA, v_cmd, v_vvc_config);

                    -- Call the corresponding procedure in the BFM package.
                    avalon_mm_reset(clk            => clk,
                                    avalon_mm_if   => avalon_mm_vvc_master_if,
                                    num_rst_cycles => v_cmd.gen_integer_array(0),
                                    msg            => format_msg(v_cmd),
                                    scope          => C_SCOPE,
                                    msg_id_panel   => v_msg_id_panel,
                                    config         => v_vvc_config.bfm_config);

                when LOCK =>
                    -- Set vvc transaction info
                    set_global_vvc_transaction_info(vvc_transaction_info_trigger, shared_avalon_mm_vvc_transaction_info, GC_INSTANCE_IDX, NA, v_cmd, v_vvc_config);

                    -- Call the corresponding procedure in the BFM package.
                    avalon_mm_lock(avalon_mm_if => avalon_mm_vvc_master_if,
                                   msg          => format_msg(v_cmd),
                                   scope        => C_SCOPE,
                                   msg_id_panel => v_msg_id_panel,
                                   config       => v_vvc_config.bfm_config);

                when UNLOCK =>
                    -- Set vvc transaction info
                    set_global_vvc_transaction_info(vvc_transaction_info_trigger, shared_avalon_mm_vvc_transaction_info, GC_INSTANCE_IDX, NA, v_cmd, v_vvc_config);

                    -- Call the corresponding procedure in the BFM package.
                    avalon_mm_unlock(avalon_mm_if => avalon_mm_vvc_master_if,
                                     msg          => format_msg(v_cmd),
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
            reset_vvc_transaction_info(shared_avalon_mm_vvc_transaction_info, GC_INSTANCE_IDX, NA, v_cmd);
        end loop;
    end process;
    --===============================================================================================

    --===============================================================================================
    -- Add a delta cycle to the read response interface signals to avoid reading wrong data.
    --===============================================================================================
    avalon_mm_vvc_master_if_pd <= transport avalon_mm_vvc_master_if after std.env.resolution_limit;

    --===============================================================================================
    -- Read response command execution.
    -- - READ (and CHECK) data received from the slave after the command executor has issued an
    --   read request (or check).
    -- - Note the use of propagation delayed avalon_mm_vv_master_if signal
    --===============================================================================================
    read_response : process
        variable v_cmd                  : t_vvc_cmd_record;
        variable v_msg_id_panel         : t_msg_id_panel;
        variable v_read_data            : t_vvc_result; -- See vvc_cmd_pkg
        variable v_normalised_addr      : unsigned(GC_ADDR_WIDTH - 1 downto 0)         := (others => '0');
        variable v_normalised_data      : std_logic_vector(GC_DATA_WIDTH - 1 downto 0) := (others => '0');
        -- check if command_queue and command_response_queue is empty
        variable v_cmd_queues_are_empty : boolean;
        variable v_vvc_config           : t_vvc_config;

    begin
        -- Set the command response queue up to the same settings as the command queue
        v_vvc_config := shared_avalon_mm_vvc_config.get(GC_INSTANCE_IDX);
        command_response_queue.set_scope(C_SCOPE & ":RQ");
        command_response_queue.set_queue_count_max(v_vvc_config.cmd_queue_count_max);
        command_response_queue.set_queue_count_threshold(v_vvc_config.cmd_queue_count_threshold);
        command_response_queue.set_queue_count_threshold_severity(v_vvc_config.cmd_queue_count_threshold_severity);

        -- Wait until VVC is registered in vvc activity register in the interpreter
        wait until entry_num_in_vvc_activity_register >= 0;

        loop

            v_msg_id_panel := shared_avalon_mm_vvc_msg_id_panel.get(GC_INSTANCE_IDX); -- v3

            -- update vvc activity
            v_cmd_queues_are_empty := command_queue.is_empty(VOID) and command_response_queue.is_empty(VOID);
            if not (executor_is_busy) and v_cmd_queues_are_empty then
                update_vvc_activity_register(global_trigger_vvc_activity_register,
                                             shared_avalon_mm_vvc_status,
                                             GC_INSTANCE_IDX,
                                             NA,
                                             INACTIVE,
                                             entry_num_in_vvc_activity_register,
                                             last_cmd_idx_executed,
                                             v_cmd_queues_are_empty,
                                             C_SCOPE);
            end if;

            -- Fetch commands
            work.td_vvc_entity_support_pkg.fetch_command_and_prepare_executor(v_cmd, command_response_queue, v_msg_id_panel, shared_avalon_mm_vvc_status, response_queue_is_increasing, read_response_is_busy, C_VVC_LABELS); -- v3

            ---- response executor follows executor, thus VVC activity is already set to ACTIVE
            --v_cmd_queues_are_empty := (command_queue.is_empty(VOID) and command_response_queue.is_empty(VOID));
            --update_vvc_activity_register(global_trigger_vvc_activity_register,
            --                             shared_avalon_mm_vvc_status,
            --                             GC_INSTANCE_IDX,
            --                             NA,
            --                             ACTIVE,
            --                             entry_num_in_vvc_activity_register,
            --                             last_cmd_idx_executed,
            --                             v_cmd_queues_are_empty,
            --                             C_SCOPE);

            v_vvc_config := shared_avalon_mm_vvc_config.get(GC_INSTANCE_IDX);

            -- Select between a provided msg_id_panel via the vvc_cmd_record from a VVC with a higher hierarchy or the
            -- msg_id_panel in this VVC's config. This is to correctly handle the logging when using Hierarchical-VVCs.
            v_msg_id_panel := get_msg_id_panel(v_cmd);

            -- Normalise address and data
            v_normalised_addr := normalize_and_check(v_cmd.addr, v_normalised_addr, ALLOW_WIDER_NARROWER, "addr", "shared_vvc_cmd.addr", "Function called with to wide address. " & v_cmd.msg);
            v_normalised_data := normalize_and_check(v_cmd.data, v_normalised_data, ALLOW_WIDER_NARROWER, "data", "shared_vvc_cmd.data", "Function called with to wide data. " & v_cmd.msg);

            case v_cmd.operation is
                when READ =>
                    -- Set vvc transaction info
                    set_global_vvc_transaction_info(vvc_transaction_info_trigger, shared_avalon_mm_vvc_transaction_info, GC_INSTANCE_IDX, NA, v_cmd, v_vvc_config);

                    -- Initiate read response
                    avalon_mm_read_response(addr_value   => v_normalised_addr,
                                            data_value   => v_read_data(GC_DATA_WIDTH - 1 downto 0),
                                            msg          => format_msg(v_cmd),
                                            clk          => clk,
                                            avalon_mm_if => avalon_mm_vvc_master_if_pd,
                                            scope        => C_SCOPE,
                                            msg_id_panel => v_msg_id_panel,
                                            config       => v_vvc_config.bfm_config);
                    -- Request SB check result
                    if v_cmd.data_routing = TO_SB then
                        -- call SB check_received
                        AVALON_MM_VVC_SB.check_received(GC_INSTANCE_IDX, pad_avalon_mm_sb(v_read_data(GC_DATA_WIDTH - 1 downto 0)));
                    else
                        -- Store the result
                        work.td_vvc_entity_support_pkg.store_result(result_queue => result_queue,
                                                                    cmd_idx      => v_cmd.cmd_idx,
                                                                    result       => v_read_data);
                    end if;

                when CHECK =>
                    -- Set vvc transaction info
                    set_global_vvc_transaction_info(vvc_transaction_info_trigger, shared_avalon_mm_vvc_transaction_info, GC_INSTANCE_IDX, NA, v_cmd, v_vvc_config);

                    -- Initiate check response
                    avalon_mm_check_response(addr_value   => v_normalised_addr,
                                             data_exp     => v_normalised_data,
                                             msg          => format_msg(v_cmd),
                                             clk          => clk,
                                             avalon_mm_if => avalon_mm_vvc_master_if_pd,
                                             alert_level  => v_cmd.alert_level,
                                             scope        => C_SCOPE,
                                             msg_id_panel => v_msg_id_panel,
                                             config       => v_vvc_config.bfm_config);
                when others =>
                    tb_error("Unsupported local command received for execution: '" & to_string(v_cmd.operation) & "'", C_SCOPE);

            end case;

            last_read_response_idx_executed <= v_cmd.cmd_idx;

            -- Set vvc transaction info back to default values
            reset_vvc_transaction_info(shared_avalon_mm_vvc_transaction_info, GC_INSTANCE_IDX, NA, v_cmd);
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

