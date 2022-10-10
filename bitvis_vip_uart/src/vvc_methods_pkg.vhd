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
use bitvis_vip_scoreboard.generic_sb_support_pkg.all;

use work.uart_bfm_pkg.all;
use work.vvc_cmd_pkg.all;
use work.monitor_cmd_pkg.all;
use work.td_target_support_pkg.all;
use work.transaction_pkg.all;

--=================================================================================================
--=================================================================================================
--=================================================================================================
package vvc_methods_pkg is

  constant C_VVC_NAME                    : string  := "UART_VVC";
  constant C_EXECUTOR_RESULT_ARRAY_DEPTH : natural := 3;

  signal UART_VVCT : t_vvc_target_record := set_vvc_target_defaults(C_VVC_NAME);
  alias THIS_VVCT  : t_vvc_target_record is UART_VVCT;

  alias t_bfm_config is t_uart_bfm_config;

  -- Type found in UVVM-Util types_pkg
  constant C_UART_INTER_BFM_DELAY_DEFAULT : t_inter_bfm_delay := (
    delay_type                         => NO_DELAY,
    delay_in_time                      => 0 ns,
    inter_bfm_delay_violation_severity => WARNING
  );

  type t_vvc_error_injection is record
    parity_bit_error_prob : real;
    stop_bit_error_prob   : real;
  end record t_vvc_error_injection;

  constant C_VVC_ERROR_INJECTION_INACTIVE : t_vvc_error_injection := (
    parity_bit_error_prob => -1.0,
    stop_bit_error_prob   => -1.0
  );

  type t_bit_rate_checker is record
    enable      : boolean;
    min_period  : time;
    alert_level : t_alert_level;
  end record;

  constant C_BIT_RATE_CHECKER_DEFAULT : t_bit_rate_checker := (
    enable      => FALSE,
    min_period  => -1 ns,
    alert_level => WARNING
  );

  type t_vvc_config is record
    inter_bfm_delay                       : t_inter_bfm_delay; -- Minimum delay between BFM accesses from the VVC. If parameter delay_type is set to NO_DELAY, BFM accesses will be back to back, i.e. no delay.
    cmd_queue_count_max                   : natural; -- Maximum pending number in command queue before queue is full. Adding additional commands will result in an ERROR.
    cmd_queue_count_threshold             : natural; -- An alert with severity 'cmd_queue_count_threshold_severity' will be issued if command queue exceeds this count. Used for early warning if command queue is almost full. Will be ignored if set to 0.
    cmd_queue_count_threshold_severity    : t_alert_level; -- Severity of alert to be initiated if exceeding cmd_queue_count_threshold
    result_queue_count_max                : natural; -- Maximum number of unfetched results before result_queue is full.
    result_queue_count_threshold_severity : t_alert_level; -- An alert with severity 'result_queue_count_threshold_severity' will be issued if command queue exceeds this count. Used for early warning if result queue is almost full. Will be ignored if set to 0.
    result_queue_count_threshold          : natural; -- Severity of alert to be initiated if exceeding result_queue_count_threshold
    bfm_config                            : t_uart_bfm_config; -- Configuration for the BFM. See BFM quick reference
    error_injection                       : t_vvc_error_injection;
    bit_rate_checker                      : t_bit_rate_checker;
  end record;

  --type t_vvc_config_array is array (t_channel range <>, natural range <>) of t_vvc_config;

  constant C_UART_VVC_CONFIG_DEFAULT : t_vvc_config := (
    inter_bfm_delay                       => C_UART_INTER_BFM_DELAY_DEFAULT,
    cmd_queue_count_max                   => C_CMD_QUEUE_COUNT_MAX, --  from adaptation package
    cmd_queue_count_threshold             => C_CMD_QUEUE_COUNT_THRESHOLD,
    cmd_queue_count_threshold_severity    => C_CMD_QUEUE_COUNT_THRESHOLD_SEVERITY,
    result_queue_count_max                => C_RESULT_QUEUE_COUNT_MAX,
    result_queue_count_threshold_severity => C_RESULT_QUEUE_COUNT_THRESHOLD_SEVERITY,
    result_queue_count_threshold          => C_RESULT_QUEUE_COUNT_THRESHOLD,
    bfm_config                            => C_UART_BFM_CONFIG_DEFAULT,
    error_injection                       => C_VVC_ERROR_INJECTION_INACTIVE,
    bit_rate_checker                      => C_BIT_RATE_CHECKER_DEFAULT
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
    data      : std_logic_vector(C_VVC_CMD_DATA_MAX_LENGTH - 1 downto 0);
    msg       : string(1 to C_VVC_CMD_STRING_MAX_LENGTH);
  end record;

  type t_transaction_info_array is array (t_channel range <>, natural range <>) of t_transaction_info;

  constant C_TRANSACTION_INFO_DEFAULT : t_transaction_info := (
    operation => NO_OPERATION,
    data      => (others => '0'),
    msg       => (others => ' ')
  );

  -- v3
  package protected_vvc_status_pkg is new uvvm_util.protected_generic_types_pkg
    generic map(t_generic_element => t_vvc_status,
                c_generic_default => C_VVC_STATUS_DEFAULT);
  use protected_vvc_status_pkg.all;
  shared variable shared_uart_vvc_status : protected_vvc_status_pkg.t_prot_generic_array;

  package protected_vvc_config_pkg is new uvvm_util.protected_generic_types_pkg
    generic map(t_generic_element => t_vvc_config,
                c_generic_default => C_UART_VVC_CONFIG_DEFAULT);
  use protected_vvc_config_pkg.all;
  shared variable shared_uart_vvc_config : protected_vvc_config_pkg.t_prot_generic_array;

  package protected_msg_id_panel_pkg is new uvvm_util.protected_generic_types_pkg
    generic map(t_generic_element => t_msg_id_panel,
                c_generic_default => C_VVC_MSG_ID_PANEL_DEFAULT);
  use protected_msg_id_panel_pkg.all;
  shared variable shared_uart_vvc_msg_id_panel : protected_msg_id_panel_pkg.t_prot_generic_array;

  -- Scoreboard
  package uart_sb_pkg is new bitvis_vip_scoreboard.generic_sb_pkg
    generic map(t_element         => std_logic_vector(C_VVC_CMD_DATA_MAX_LENGTH - 1 downto 0),
                element_match     => std_match,
                to_string_element => to_string);
  use uart_sb_pkg.all;
  shared variable UART_VVC_SB : uart_sb_pkg.t_prot_generic_sb;

  --==========================================================================================
  -- Methods dedicated to this VVC
  -- - These procedures are called from the testbench in order for the VVC to execute
  --   BFM calls towards the given interface. The VVC interpreter will queue these calls
  --   and then the VVC executor will fetch the commands from the queue and handle the
  --   actual BFM execution.
  --   For details on how the BFM procedures work, see the QuickRef.
  --==========================================================================================

  procedure uart_transmit(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant channel             : in t_channel;
    constant data                : in std_logic_vector;
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  procedure uart_transmit(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant channel             : in t_channel;
    constant num_words           : in natural;
    constant randomisation       : in t_randomisation;
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  procedure uart_receive(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant channel             : in t_channel;
    constant data_routing        : in t_data_routing;
    constant msg                 : in string;
    constant alert_level         : in t_alert_level  := error;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  procedure uart_receive(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant channel             : in t_channel;
    constant msg                 : in string;
    constant alert_level         : in t_alert_level  := error;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  procedure uart_expect(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant channel             : in t_channel;
    constant data                : in std_logic_vector;
    constant msg                 : in string;
    constant max_receptions      : in natural        := 1;
    constant timeout             : in time           := -1 ns;
    constant alert_level         : in t_alert_level  := error;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  --==============================================================================
  -- Transaction info methods
  --==============================================================================
  procedure set_global_vvc_transaction_info(
    signal   vvc_transaction_info_trigger : inout std_logic;
    variable vvc_transaction_info_group   : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx                 : in natural;
    constant channel                      : in t_channel;
    constant vvc_cmd                      : in t_vvc_cmd_record;
    constant vvc_config                   : in t_vvc_config;
    constant scope                        : in string := C_VVC_CMD_SCOPE_DEFAULT);

  procedure reset_vvc_transaction_info(
    variable vvc_transaction_info_group : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx               : in natural;
    constant channel                    : in t_channel;
    constant vvc_cmd                    : in t_vvc_cmd_record);

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

  --==============================================================================
  -- Error Injection methods
  --==============================================================================
  procedure determine_error_injection(
    constant probability                            : in real;
    variable bfm_configured_error_injection_setting : inout boolean;
    variable has_raised_warning_if_vvc_bfm_conflict : inout boolean;
    constant scope                                  : in string
  );

end package vvc_methods_pkg;

package body vvc_methods_pkg is

  procedure uart_transmit(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant channel             : in t_channel;
    constant data                : in std_logic_vector;
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant proc_name : string := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant proc_call : string := proc_name & "(" & to_string(VVCT, vvc_instance_idx, channel) -- First part common for all
                                   & ", " & to_string(data, HEX, AS_IS, INCL_RADIX) & ")";
    variable v_local_vvc_cmd   : t_vvc_cmd_record                                         := shared_vvc_cmd.get(vvc_instance_idx, channel); -- v3
    variable v_normalised_data : std_logic_vector(C_VVC_CMD_DATA_MAX_LENGTH - 1 downto 0) := normalize_and_check(data, v_local_vvc_cmd.data, ALLOW_WIDER_NARROWER, "data", "shared_vvc_cmd.data", proc_call & " called with to wide data. " & add_msg_delimiter(msg));
    variable v_msg_id_panel    : t_msg_id_panel                                           := shared_msg_id_panel.get(VOID);
  begin
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, channel, proc_call, msg, QUEUED, TRANSMIT);

    -- v3
    v_local_vvc_cmd                     := shared_vvc_cmd.get(vvc_instance_idx, channel);
    v_local_vvc_cmd.data                := v_normalised_data;
    v_local_vvc_cmd.parent_msg_id_panel := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx, channel);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(VVCT, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure;

  procedure uart_transmit(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant channel             : in t_channel;
    constant num_words           : in natural;
    constant randomisation       : in t_randomisation;
    constant msg                 : in string;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant proc_name : string := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant proc_call : string := proc_name & "(" & to_string(VVCT, vvc_instance_idx, channel) -- First part common for all
                                   & ", RANDOM)";
    variable v_msg_id_panel  : t_msg_id_panel   := shared_msg_id_panel.get(VOID);
    variable v_local_vvc_cmd : t_vvc_cmd_record := shared_vvc_cmd.get(vvc_instance_idx, channel); -- v3
  begin
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, channel, proc_call, msg, QUEUED, TRANSMIT);
    -- Randomisation specific
    -- v3
    v_local_vvc_cmd                     := shared_vvc_cmd.get(vvc_instance_idx, channel);
    v_local_vvc_cmd.randomisation       := randomisation;
    v_local_vvc_cmd.num_words           := num_words;
    v_local_vvc_cmd.parent_msg_id_panel := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx, channel);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(VVCT, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure;

  procedure uart_receive(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant channel             : in t_channel;
    constant data_routing        : in t_data_routing;
    constant msg                 : in string;
    constant alert_level         : in t_alert_level  := error;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant proc_name : string := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant proc_call : string := proc_name & "(" & to_string(VVCT, vvc_instance_idx, channel) -- First part common for all
                                   & ")";
    variable v_msg_id_panel  : t_msg_id_panel   := shared_msg_id_panel.get(VOID);
    variable v_local_vvc_cmd : t_vvc_cmd_record := shared_vvc_cmd.get(vvc_instance_idx, channel); -- v3
  begin
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, channel, proc_call, msg, QUEUED, RECEIVE);

    -- v3
    v_local_vvc_cmd                     := shared_vvc_cmd.get(vvc_instance_idx, channel);
    v_local_vvc_cmd.alert_level         := alert_level;
    v_local_vvc_cmd.data_routing        := data_routing;
    v_local_vvc_cmd.parent_msg_id_panel := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx, channel);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(VVCT, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure;

  procedure uart_receive(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant channel             : in t_channel;
    constant msg                 : in string;
    constant alert_level         : in t_alert_level  := error;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
  begin
    uart_receive(VVCT, vvc_instance_idx, channel, NA, msg, alert_level, scope, parent_msg_id_panel);
  end procedure;

  procedure uart_expect(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant channel             : in t_channel;
    constant data                : in std_logic_vector;
    constant msg                 : in string;
    constant max_receptions      : in natural        := 1;
    constant timeout             : in time           := -1 ns;
    constant alert_level         : in t_alert_level  := error;
    constant scope               : in string         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant proc_name : string := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant proc_call : string := proc_name & "(" & to_string(VVCT, vvc_instance_idx, channel) -- First part common for all
                                   & ", " & to_string(data, HEX, AS_IS, INCL_RADIX) & ")";
    variable v_local_vvc_cmd   : t_vvc_cmd_record                                         := shared_vvc_cmd.get(vvc_instance_idx, channel); -- v3
    variable v_normalised_data : std_logic_vector(C_VVC_CMD_DATA_MAX_LENGTH - 1 downto 0) := normalize_and_check(data, v_local_vvc_cmd.data, ALLOW_WIDER_NARROWER, "data", "shared_vvc_cmd.data", proc_call & " called with to wide data. " & add_msg_delimiter(msg));
    variable v_msg_id_panel    : t_msg_id_panel                                           := shared_msg_id_panel.get(VOID);
    variable v_vvc_config      : t_vvc_config;
  begin
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, channel, proc_call, msg, QUEUED, EXPECT);

    -- v3
    v_local_vvc_cmd                := shared_vvc_cmd.get(vvc_instance_idx, channel);
    v_local_vvc_cmd.data           := v_normalised_data;
    v_local_vvc_cmd.alert_level    := alert_level;
    v_local_vvc_cmd.max_receptions := max_receptions;

    v_vvc_config := shared_uart_vvc_config.get(vvc_instance_idx, channel);
    if timeout = -1 ns then
      v_local_vvc_cmd.timeout := v_vvc_config.bfm_config.timeout;
    else
      v_local_vvc_cmd.timeout := timeout;
    end if;

    v_local_vvc_cmd.parent_msg_id_panel := parent_msg_id_panel;
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
    variable vvc_transaction_info_group   : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx                 : in natural;
    constant channel                      : in t_channel;
    constant vvc_cmd                      : in t_vvc_cmd_record;
    constant vvc_config                   : in t_vvc_config;
    constant scope                        : in string := C_VVC_CMD_SCOPE_DEFAULT) is
    variable v_transaction_info_group : t_transaction_group := vvc_transaction_info_group.get(instance_idx, channel);
  begin
    case vvc_cmd.operation is
      when TRANSMIT | RECEIVE | EXPECT =>
        v_transaction_info_group.bt.operation                              := vvc_cmd.operation;
        v_transaction_info_group.bt.data(vvc_cmd.data'length - 1 downto 0) := vvc_cmd.data;
        v_transaction_info_group.bt.vvc_meta.msg(1 to vvc_cmd.msg'length)  := vvc_cmd.msg;
        v_transaction_info_group.bt.vvc_meta.cmd_idx                       := vvc_cmd.cmd_idx;
        v_transaction_info_group.bt.transaction_status                     := IN_PROGRESS;
        v_transaction_info_group.bt.error_info.parity_bit_error            := false;
        v_transaction_info_group.bt.error_info.stop_bit_error              := false;

        if vvc_cmd.operation = TRANSMIT then
          v_transaction_info_group.bt.error_info.parity_bit_error := vvc_config.bfm_config.error_injection.parity_bit_error;
          v_transaction_info_group.bt.error_info.stop_bit_error   := vvc_config.bfm_config.error_injection.stop_bit_error;
        end if;

        vvc_transaction_info_group.set(v_transaction_info_group, instance_idx, channel);
        gen_pulse(vvc_transaction_info_trigger, 0 ns, "pulsing global vvc transaction info trigger", scope, ID_NEVER);

      when others =>
        alert(TB_ERROR, "VVC operation not recognized");
    end case;

    wait for 0 ns;
  end procedure set_global_vvc_transaction_info;

  procedure reset_vvc_transaction_info(
    variable vvc_transaction_info_group : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx               : in natural;
    constant channel                    : in t_channel;
    constant vvc_cmd                    : in t_vvc_cmd_record) is
    variable v_transaction_info_group : t_transaction_group := vvc_transaction_info_group.get(instance_idx, channel);
  begin
    case vvc_cmd.operation is
      when TRANSMIT | RECEIVE | EXPECT =>
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

  --==============================================================================
  -- Error Injection methods
  --==============================================================================

  procedure determine_error_injection(
    constant probability                            : in real;
    variable bfm_configured_error_injection_setting : inout boolean;
    variable has_raised_warning_if_vvc_bfm_conflict : inout boolean;
    constant scope                                  : in string
  ) is
  begin
    if probability /= -1.0 then
      check_value_in_range(probability, 0.0, 1.0, tb_error, "Verify probability value within range 0.0 - 1.0.", scope, ID_NEVER);

      -- Raise a TB_WARNING only once if there is a conflict between VVC and BFM setting
      if not (has_raised_warning_if_vvc_bfm_conflict) and bfm_configured_error_injection_setting and probability < 1.0 then
        alert(TB_WARNING, "VVC error injection probability will override BFM configuration.", scope);
        has_raised_warning_if_vvc_bfm_conflict := true;
      end if;

      bfm_configured_error_injection_setting := (random(0.0, 1.0) <= probability);
    end if;
  end procedure determine_error_injection;

end package body vvc_methods_pkg;

