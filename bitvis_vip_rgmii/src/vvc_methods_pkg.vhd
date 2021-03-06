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
use bitvis_vip_scoreboard.generic_sb_support_pkg.all;

use work.rgmii_bfm_pkg.all;
use work.vvc_cmd_pkg.all;
use work.td_target_support_pkg.all;
use work.transaction_pkg.all;

--==========================================================================================
--==========================================================================================
package vvc_methods_pkg is

    --==========================================================================================
    -- Types and constants for the RGMII VVC 
    --==========================================================================================
    constant C_VVC_NAME : string := "RGMII_VVC";

    signal RGMII_VVCT : t_vvc_target_record := set_vvc_target_defaults(C_VVC_NAME);
    alias THIS_VVCT   : t_vvc_target_record is RGMII_VVCT;
    alias t_bfm_config is t_rgmii_bfm_config;

    -- Type found in UVVM-Util types_pkg
    constant C_RGMII_INTER_BFM_DELAY_DEFAULT : t_inter_bfm_delay := (
        delay_type                         => NO_DELAY,
        delay_in_time                      => 0 ns,
        inter_bfm_delay_violation_severity => WARNING
    );

    type t_vvc_config is record
        inter_bfm_delay                       : t_inter_bfm_delay; -- Minimum delay between BFM accesses from the VVC. If parameter delay_type is set to NO_DELAY, BFM accesses will be back to back, i.e. no delay.
        cmd_queue_count_max                   : natural; -- Maximum pending number in command executor before executor is full. Adding additional commands will result in an ERROR.
        cmd_queue_count_threshold             : natural; -- An alert with severity 'cmd_queue_count_threshold_severity' will be issued if command executor exceeds this count. Used for early warning if command executor is almost full. Will be ignored if set to 0.
        cmd_queue_count_threshold_severity    : t_alert_level; -- Severity of alert to be initiated if exceeding cmd_queue_count_threshold.
        result_queue_count_max                : natural;
        result_queue_count_threshold          : natural;
        result_queue_count_threshold_severity : t_alert_level;
        bfm_config                            : t_rgmii_bfm_config; -- Configuration for the BFM. See BFM quick reference.
    end record;

    constant C_RGMII_VVC_CONFIG_DEFAULT : t_vvc_config := (
        inter_bfm_delay                       => C_RGMII_INTER_BFM_DELAY_DEFAULT,
        cmd_queue_count_max                   => C_CMD_QUEUE_COUNT_MAX, --  from adaptation package
        cmd_queue_count_threshold             => C_CMD_QUEUE_COUNT_THRESHOLD,
        cmd_queue_count_threshold_severity    => C_CMD_QUEUE_COUNT_THRESHOLD_SEVERITY,
        result_queue_count_max                => C_RESULT_QUEUE_COUNT_MAX,
        result_queue_count_threshold          => C_RESULT_QUEUE_COUNT_THRESHOLD,
        result_queue_count_threshold_severity => C_RESULT_QUEUE_COUNT_THRESHOLD_SEVERITY,
        bfm_config                            => C_RGMII_BFM_CONFIG_DEFAULT
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

    -- v3
    package protected_vvc_status_pkg is new uvvm_util.protected_generic_types_pkg
        generic map(t_generic_element => t_vvc_status,
                    c_generic_default           => C_VVC_STATUS_DEFAULT);
    use protected_vvc_status_pkg.all;
    shared variable shared_rgmii_vvc_status : protected_vvc_status_pkg.t_protected_generic_array;

    package protected_vvc_config_pkg is new uvvm_util.protected_generic_types_pkg
        generic map(t_generic_element => t_vvc_config,
                    c_generic_default           => C_RGMII_VVC_CONFIG_DEFAULT);
    use protected_vvc_config_pkg.all;
    shared variable shared_rgmii_vvc_config : protected_vvc_config_pkg.t_protected_generic_array;

    package protected_msg_id_panel_pkg is new uvvm_util.protected_generic_types_pkg
        generic map(t_generic_element => t_msg_id_panel,
                    c_generic_default           => C_VVC_MSG_ID_PANEL_DEFAULT);
    use protected_msg_id_panel_pkg.all;
    shared variable shared_rgmii_vvc_msg_id_panel        : protected_msg_id_panel_pkg.t_protected_generic_array;
    shared variable shared_parent_rgmii_vvc_msg_id_panel : protected_msg_id_panel_pkg.t_protected_generic_array;

    -- Scoreboard
    package rgmii_sb_pkg is new bitvis_vip_scoreboard.generic_sb_pkg
        generic map(t_element         => std_logic_vector(7 downto 0),
                    element_match     => std_match,
                    to_string_element => to_string);
    use rgmii_sb_pkg.all;
    shared variable RGMII_VVC_SB : rgmii_sb_pkg.t_generic_sb;

    --==========================================================================================
    -- Methods dedicated to this VVC 
    -- - These procedures are called from the testbench in order for the VVC to execute
    --   BFM calls towards the given interface. The VVC interpreter will queue these calls
    --   and then the VVC executor will fetch the commands from the queue and handle the
    --   actual BFM execution.
    --==========================================================================================
    procedure rgmii_write(
        signal   VVCT                : inout t_vvc_target_record;
        constant vvc_instance_idx    : in integer;
        constant channel             : in t_channel;
        constant data_array          : in t_byte_array;
        constant msg                 : in string;
        constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
        constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
    );

    procedure rgmii_read(
        signal   VVCT                : inout t_vvc_target_record;
        constant vvc_instance_idx    : in integer;
        constant channel             : in t_channel;
        constant data_routing        : in t_data_routing;
        constant msg                 : in string;
        constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
        constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
    );

    procedure rgmii_read(
        signal   VVCT                : inout t_vvc_target_record;
        constant vvc_instance_idx    : in integer;
        constant channel             : in t_channel;
        constant msg                 : in string;
        constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
        constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
    );

    procedure rgmii_expect(
        signal   VVCT                : inout t_vvc_target_record;
        constant vvc_instance_idx    : in integer;
        constant channel             : in t_channel;
        constant data_exp            : in t_byte_array;
        constant msg                 : in string;
        constant alert_level         : in t_alert_level  := ERROR;
        constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
        constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
    );

    --==============================================================================
    -- Transaction info methods
    --==============================================================================
    procedure set_global_vvc_transaction_info(
        signal   vvc_transaction_info_trigger : inout std_logic;
        variable vvc_transaction_info_group   : inout protected_vvc_transaction_info_pkg.t_protected_generic_array; -- v3 t_transaction_group;
        constant instance_idx                 : in natural;
        constant channel                      : in t_channel;
        constant vvc_cmd                      : in t_vvc_cmd_record;
        constant vvc_config                   : in t_vvc_config;
        constant scope                        : in string := C_VVC_CMD_SCOPE_DEFAULT);

    procedure reset_vvc_transaction_info(
        variable vvc_transaction_info_group : inout protected_vvc_transaction_info_pkg.t_protected_generic_array; -- v3 t_transaction_group;
        constant instance_idx               : in natural;
        constant channel                    : in t_channel;
        constant vvc_cmd                    : in t_vvc_cmd_record);

    --==============================================================================
    -- VVC Activity
    --==============================================================================
    procedure update_vvc_activity_register(signal   global_trigger_vvc_activity_register : inout std_logic;
                                           variable vvc_status                           : inout protected_vvc_status_pkg.t_protected_generic_array;
                                           constant instance_idx                         : in natural;
                                           constant channel                              : in t_channel;
                                           constant activity                             : in t_activity;
                                           constant entry_num_in_vvc_activity_register   : in integer;
                                           constant last_cmd_idx_executed                : in natural;
                                           constant command_queue_is_empty               : in boolean;
                                           constant scope                                : in string := C_VVC_NAME);

end package vvc_methods_pkg;

package body vvc_methods_pkg is

    --==========================================================================================
    -- Methods dedicated to this VVC
    --==========================================================================================
    procedure rgmii_write(
        signal   VVCT                : inout t_vvc_target_record;
        constant vvc_instance_idx    : in integer;
        constant channel             : in t_channel;
        constant data_array          : in t_byte_array;
        constant msg                 : in string;
        constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
        constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
    ) is
        constant proc_name       : string           := "rgmii_write";
        constant proc_call       : string           := proc_name & "(" & to_string(VVCT, vvc_instance_idx, channel) & ", " & to_string(data_array'length) & " bytes)";
        variable v_local_vvc_cmd : t_vvc_cmd_record := shared_vvc_cmd.get(vvc_instance_idx, channel);
        variable v_msg_id_panel  : t_msg_id_panel   := shared_msg_id_panel.get(VOID);
    begin
        -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
        -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
        -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
        set_general_target_and_command_fields(VVCT, vvc_instance_idx, channel, proc_call, msg, QUEUED, WRITE);

        -- v3
        v_local_vvc_cmd                                        := shared_vvc_cmd.get(vvc_instance_idx, channel);
        v_local_vvc_cmd.data_array(0 to data_array'length - 1) := data_array;
        v_local_vvc_cmd.data_array_length                      := data_array'length;
        v_local_vvc_cmd.parent_msg_id_panel                    := parent_msg_id_panel;
        shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx, channel);

        if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
            v_msg_id_panel := parent_msg_id_panel;
        end if;
        send_command_to_vvc(VVCT, std.env.resolution_limit, scope, v_msg_id_panel);
    end procedure;

    procedure rgmii_read(
        signal   VVCT                : inout t_vvc_target_record;
        constant vvc_instance_idx    : in integer;
        constant channel             : in t_channel;
        constant data_routing        : in t_data_routing;
        constant msg                 : in string;
        constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
        constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
    ) is
        constant proc_name       : string           := "rgmii_read";
        constant proc_call       : string           := proc_name & "(" & to_string(VVCT, vvc_instance_idx, channel) & ")";
        variable v_local_vvc_cmd : t_vvc_cmd_record := shared_vvc_cmd.get(vvc_instance_idx, channel);
        variable v_msg_id_panel  : t_msg_id_panel   := shared_msg_id_panel.get(VOID);
    begin
        -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
        -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
        -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
        set_general_target_and_command_fields(VVCT, vvc_instance_idx, channel, proc_call, msg, QUEUED, READ);

        -- v3
        v_local_vvc_cmd                     := shared_vvc_cmd.get(vvc_instance_idx, channel);
        v_local_vvc_cmd.data_routing        := data_routing;
        v_local_vvc_cmd.parent_msg_id_panel := parent_msg_id_panel;
        shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx, channel);

        if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
            v_msg_id_panel := parent_msg_id_panel;
        end if;
        send_command_to_vvc(VVCT, std.env.resolution_limit, scope, v_msg_id_panel);
    end procedure;

    procedure rgmii_read(
        signal   VVCT                : inout t_vvc_target_record;
        constant vvc_instance_idx    : in integer;
        constant channel             : in t_channel;
        constant msg                 : in string;
        constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
        constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
    ) is
    begin
        rgmii_read(VVCT, vvc_instance_idx, channel, NA, msg, scope, parent_msg_id_panel);
    end procedure;

    procedure rgmii_expect(
        signal   VVCT                : inout t_vvc_target_record;
        constant vvc_instance_idx    : in integer;
        constant channel             : in t_channel;
        constant data_exp            : in t_byte_array;
        constant msg                 : in string;
        constant alert_level         : in t_alert_level  := ERROR;
        constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
        constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
    ) is
        constant proc_name       : string           := "rgmii_expect";
        constant proc_call       : string           := proc_name & "(" & to_string(VVCT, vvc_instance_idx, channel) & ", " & to_string(data_exp'length) & " bytes)";
        variable v_local_vvc_cmd : t_vvc_cmd_record := shared_vvc_cmd.get(vvc_instance_idx, channel);
        variable v_msg_id_panel  : t_msg_id_panel   := shared_msg_id_panel.get(VOID);
    begin
        -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
        -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
        -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
        set_general_target_and_command_fields(VVCT, vvc_instance_idx, channel, proc_call, msg, QUEUED, EXPECT);

        -- v3
        v_local_vvc_cmd                                      := shared_vvc_cmd.get(vvc_instance_idx, channel);
        v_local_vvc_cmd.data_array(0 to data_exp'length - 1) := data_exp;
        v_local_vvc_cmd.data_array_length                    := data_exp'length;
        v_local_vvc_cmd.alert_level                          := alert_level;
        v_local_vvc_cmd.parent_msg_id_panel                  := parent_msg_id_panel;
        shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx, channel);

        if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
            v_msg_id_panel := parent_msg_id_panel;
        end if;
        send_command_to_vvc(VVCT, std.env.resolution_limit, scope, v_msg_id_panel);
    end procedure;

    --==============================================================================
    -- Transaction info methods
    --==============================================================================
    procedure set_global_vvc_transaction_info(
        signal   vvc_transaction_info_trigger : inout std_logic;
        variable vvc_transaction_info_group   : inout protected_vvc_transaction_info_pkg.t_protected_generic_array; -- v3 t_transaction_group;
        constant instance_idx                 : in natural;
        constant channel                      : in t_channel;
        constant vvc_cmd                      : in t_vvc_cmd_record;
        constant vvc_config                   : in t_vvc_config;
        constant scope                        : in string := C_VVC_CMD_SCOPE_DEFAULT) is
        variable v_transaction_info_group : t_transaction_group := vvc_transaction_info_group.get(instance_idx, channel);
    begin
        case vvc_cmd.operation is
            when WRITE | READ | EXPECT =>
                v_transaction_info_group.bt.operation                             := vvc_cmd.operation;
                v_transaction_info_group.bt.data_array                            := vvc_cmd.data_array;
                v_transaction_info_group.bt.vvc_meta.msg(1 to vvc_cmd.msg'length) := vvc_cmd.msg;
                v_transaction_info_group.bt.vvc_meta.cmd_idx                      := vvc_cmd.cmd_idx;
                v_transaction_info_group.bt.transaction_status                    := IN_PROGRESS;
                vvc_transaction_info_group.set(v_transaction_info_group, instance_idx, channel);
                gen_pulse(vvc_transaction_info_trigger, 0 ns, "pulsing global vvc transaction info trigger", scope, ID_NEVER);
            when others =>
                alert(TB_ERROR, "VVC operation not recognized");
        end case;

        wait for 0 ns;
    end procedure set_global_vvc_transaction_info;

    procedure reset_vvc_transaction_info(
        variable vvc_transaction_info_group : inout protected_vvc_transaction_info_pkg.t_protected_generic_array; -- v3 t_transaction_group;
        constant instance_idx               : in natural;
        constant channel                    : in t_channel;
        constant vvc_cmd                    : in t_vvc_cmd_record) is
        variable v_transaction_info_group : t_transaction_group := vvc_transaction_info_group.get(instance_idx, channel);
    begin
        case vvc_cmd.operation is
            when WRITE | READ | EXPECT =>
                v_transaction_info_group.bt := C_BASE_TRANSACTION_SET_DEFAULT;
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
                                           variable vvc_status                           : inout protected_vvc_status_pkg.t_protected_generic_array;
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
