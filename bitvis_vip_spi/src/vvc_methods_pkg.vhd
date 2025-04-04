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

--================================================================================================================================
--  Support package
--================================================================================================================================
library uvvm_util;
use uvvm_util.adaptations_pkg.all;
use uvvm_util.types_pkg.all;
use work.spi_bfm_pkg.all;
use work.td_target_support_pkg.all;

package vvc_methods_support_pkg is

  --==========================================================================================
  -- Types and constants for the SPI VVC
  --==========================================================================================
  constant C_VVC_NAME : string := "SPI_VVC";

  signal SPI_VVCT : t_vvc_target_record := set_vvc_target_defaults(C_VVC_NAME);
  alias THIS_VVCT : t_vvc_target_record is SPI_VVCT;
  alias t_bfm_config is t_spi_bfm_config;

  constant C_SPI_INTER_BFM_DELAY_DEFAULT : t_inter_bfm_delay := (
    delay_type                         => NO_DELAY,
    delay_in_time                      => 0 ns,
    inter_bfm_delay_violation_severity => warning
  );

  type t_vvc_config is record
    inter_bfm_delay            : t_inter_bfm_delay; -- Minimum delay between BFM accesses from the VVC. If parameter delay_type is set to NO_DELAY, BFM accesses will be back to back, i.e. no delay.
    bfm_config                 : t_bfm_config;      -- Configuration for the BFM. See BFM quick reference.
    unwanted_activity_severity : t_alert_level;     -- Severity of alert to be initiated if unwanted activity on the DUT outputs is detected.
  end record;

  constant C_SPI_VVC_CONFIG_DEFAULT : t_vvc_config := (
    inter_bfm_delay            => C_SPI_INTER_BFM_DELAY_DEFAULT,
    bfm_config                 => C_SPI_BFM_CONFIG_DEFAULT,
    unwanted_activity_severity => C_UNWANTED_ACTIVITY_SEVERITY
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
use work.vvc_transaction_pkg.all;

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
use work.vvc_transaction_pkg.all;

package protected_vvc_config_pkg is new uvvm_util.protected_generic_types_pkg
  generic map(
    t_generic_element  => t_vvc_config,
    c_generic_default  => C_SPI_VVC_CONFIG_DEFAULT,
    c_max_instance_num => C_VVC_MAX_INSTANCE_NUM
  );

----------------------------------------------------------------------
-- Protected type: t_msg_id_panel
----------------------------------------------------------------------
library uvvm_util;
use uvvm_util.types_pkg.all;
use uvvm_util.adaptations_pkg.all;
use work.vvc_transaction_pkg.all;

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

use work.spi_bfm_pkg.all;
use work.vvc_transaction_pkg.all;
use work.protected_transaction_group_pkg.all;
use work.vvc_cmd_pkg.all;
use work.vvc_cmd_shared_variables_pkg.all;
use work.td_target_support_pkg.all;
use work.vvc_methods_support_pkg.all;
use work.protected_vvc_status_pkg.all;
use work.protected_vvc_config_pkg.all;
use work.protected_msg_id_panel_pkg.all;
use work.vvc_sb_pkg.all;

package vvc_methods_pkg is

  shared variable shared_spi_vvc_status       : work.protected_vvc_status_pkg.t_generic_array;
  shared variable shared_spi_vvc_config       : work.protected_vvc_config_pkg.t_generic_array;
  shared variable shared_spi_vvc_msg_id_panel : work.protected_msg_id_panel_pkg.t_generic_array;
  shared variable SPI_VVC_SB                  : t_generic_sb;

  alias shared_vvc_status       is shared_spi_vvc_status;       -- This alias is for internal use in the VVC
  alias shared_vvc_config       is shared_spi_vvc_config;       -- This alias is for internal use in the VVC
  alias shared_vvc_msg_id_panel is shared_spi_vvc_msg_id_panel; -- This alias is for internal use in the VVC

  --==========================================================================================
  -- Methods dedicated to this VVC 
  -- - These procedures are called from the testbench in order for the VVC to execute
  --   BFM calls towards the given interface. The VVC interpreter will queue these calls
  --   and then the VVC executor will fetch the commands from the queue and handle the
  --   actual BFM execution.
  --   For details on how the BFM procedures work, see the QuickRef.
  --==========================================================================================

  ----------------------------------------------------------
  -- SPI_MASTER
  ----------------------------------------------------------
  -- Single-word
  procedure spi_master_transmit_and_receive(
    signal   VVCT                         : inout t_vvc_target_record;
    constant vvc_instance_idx             : in integer;
    constant data                         : in std_logic_vector;
    constant data_routing                 : in t_data_routing;
    constant msg                          : in string;
    constant action_when_transfer_is_done : in t_action_when_transfer_is_done := RELEASE_LINE_AFTER_TRANSFER;
    constant scope                        : in string                         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel          : in t_msg_id_panel                 := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );
  procedure spi_master_transmit_and_receive(
    signal   VVCT                         : inout t_vvc_target_record;
    constant vvc_instance_idx             : in integer;
    constant data                         : in std_logic_vector;
    constant msg                          : in string;
    constant action_when_transfer_is_done : in t_action_when_transfer_is_done := RELEASE_LINE_AFTER_TRANSFER;
    constant scope                        : in string                         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel          : in t_msg_id_panel                 := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );
  -- Multi-word
  procedure spi_master_transmit_and_receive(
    signal   VVCT                         : inout t_vvc_target_record;
    constant vvc_instance_idx             : in integer;
    constant data                         : in t_slv_array;
    constant data_routing                 : in t_data_routing;
    constant msg                          : in string;
    constant action_when_transfer_is_done : in t_action_when_transfer_is_done := RELEASE_LINE_AFTER_TRANSFER;
    constant action_between_words         : in t_action_between_words         := HOLD_LINE_BETWEEN_WORDS;
    constant scope                        : in string                         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel          : in t_msg_id_panel                 := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );
  procedure spi_master_transmit_and_receive(
    signal   VVCT                         : inout t_vvc_target_record;
    constant vvc_instance_idx             : in integer;
    constant data                         : in t_slv_array;
    constant msg                          : in string;
    constant action_when_transfer_is_done : in t_action_when_transfer_is_done := RELEASE_LINE_AFTER_TRANSFER;
    constant action_between_words         : in t_action_between_words         := HOLD_LINE_BETWEEN_WORDS;
    constant scope                        : in string                         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel          : in t_msg_id_panel                 := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  -- Single-word
  procedure spi_master_transmit_and_check(
    signal   VVCT                         : inout t_vvc_target_record;
    constant vvc_instance_idx             : in integer;
    constant data                         : in std_logic_vector;
    constant data_exp                     : in std_logic_vector;
    constant msg                          : in string;
    constant alert_level                  : in t_alert_level                  := error;
    constant action_when_transfer_is_done : in t_action_when_transfer_is_done := RELEASE_LINE_AFTER_TRANSFER;
    constant scope                        : in string                         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel          : in t_msg_id_panel                 := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );
  -- Multi-word
  procedure spi_master_transmit_and_check(
    signal   VVCT                         : inout t_vvc_target_record;
    constant vvc_instance_idx             : in integer;
    constant data                         : in t_slv_array;
    constant data_exp                     : in t_slv_array;
    constant msg                          : in string;
    constant alert_level                  : in t_alert_level                  := error;
    constant action_when_transfer_is_done : in t_action_when_transfer_is_done := RELEASE_LINE_AFTER_TRANSFER;
    constant action_between_words         : in t_action_between_words         := HOLD_LINE_BETWEEN_WORDS;
    constant scope                        : in string                         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel          : in t_msg_id_panel                 := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  -- Single-word
  procedure spi_master_transmit_only(
    signal   VVCT                         : inout t_vvc_target_record;
    constant vvc_instance_idx             : in integer;
    constant data                         : in std_logic_vector;
    constant msg                          : in string;
    constant action_when_transfer_is_done : in t_action_when_transfer_is_done := RELEASE_LINE_AFTER_TRANSFER;
    constant scope                        : in string                         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel          : in t_msg_id_panel                 := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );
  -- Multi-word
  procedure spi_master_transmit_only(
    signal   VVCT                         : inout t_vvc_target_record;
    constant vvc_instance_idx             : in integer;
    constant data                         : in t_slv_array;
    constant msg                          : in string;
    constant action_when_transfer_is_done : in t_action_when_transfer_is_done := RELEASE_LINE_AFTER_TRANSFER;
    constant action_between_words         : in t_action_between_words         := HOLD_LINE_BETWEEN_WORDS;
    constant scope                        : in string                         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel          : in t_msg_id_panel                 := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  procedure spi_master_receive_only(
    signal   VVCT                         : inout t_vvc_target_record;
    constant vvc_instance_idx             : in integer;
    constant data_routing                 : in t_data_routing;
    constant msg                          : in string;
    constant num_words                    : in positive                       := 1;
    constant action_when_transfer_is_done : in t_action_when_transfer_is_done := RELEASE_LINE_AFTER_TRANSFER;
    constant action_between_words         : in t_action_between_words         := HOLD_LINE_BETWEEN_WORDS;
    constant scope                        : in string                         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel          : in t_msg_id_panel                 := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  procedure spi_master_receive_only(
    signal   VVCT                         : inout t_vvc_target_record;
    constant vvc_instance_idx             : in integer;
    constant msg                          : in string;
    constant num_words                    : in positive                       := 1;
    constant action_when_transfer_is_done : in t_action_when_transfer_is_done := RELEASE_LINE_AFTER_TRANSFER;
    constant action_between_words         : in t_action_between_words         := HOLD_LINE_BETWEEN_WORDS;
    constant scope                        : in string                         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel          : in t_msg_id_panel                 := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  -- Single-word
  procedure spi_master_check_only(
    signal   VVCT                         : inout t_vvc_target_record;
    constant vvc_instance_idx             : in integer;
    constant data_exp                     : in std_logic_vector;
    constant msg                          : in string;
    constant alert_level                  : in t_alert_level                  := error;
    constant action_when_transfer_is_done : in t_action_when_transfer_is_done := RELEASE_LINE_AFTER_TRANSFER;
    constant scope                        : in string                         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel          : in t_msg_id_panel                 := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );
  -- Multi-word
  procedure spi_master_check_only(
    signal   VVCT                         : inout t_vvc_target_record;
    constant vvc_instance_idx             : in integer;
    constant data_exp                     : in t_slv_array;
    constant msg                          : in string;
    constant alert_level                  : in t_alert_level                  := error;
    constant action_when_transfer_is_done : in t_action_when_transfer_is_done := RELEASE_LINE_AFTER_TRANSFER;
    constant action_between_words         : in t_action_between_words         := HOLD_LINE_BETWEEN_WORDS;
    constant scope                        : in string                         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel          : in t_msg_id_panel                 := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  ----------------------------------------------------------
  -- SPI_SLAVE
  ----------------------------------------------------------
  -- Single-word
  procedure spi_slave_transmit_and_receive(
    signal   VVCT                   : inout t_vvc_target_record;
    constant vvc_instance_idx       : in integer;
    constant data                   : in std_logic_vector;
    constant data_routing           : in t_data_routing;
    constant msg                    : in string;
    constant when_to_start_transfer : in t_when_to_start_transfer := START_TRANSFER_ON_NEXT_SS;
    constant scope                  : in string                   := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel    : in t_msg_id_panel           := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );
  procedure spi_slave_transmit_and_receive(
    signal   VVCT                   : inout t_vvc_target_record;
    constant vvc_instance_idx       : in integer;
    constant data                   : in std_logic_vector;
    constant msg                    : in string;
    constant when_to_start_transfer : in t_when_to_start_transfer := START_TRANSFER_ON_NEXT_SS;
    constant scope                  : in string                   := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel    : in t_msg_id_panel           := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );
  -- Multi-word
  procedure spi_slave_transmit_and_receive(
    signal   VVCT                   : inout t_vvc_target_record;
    constant vvc_instance_idx       : in integer;
    constant data                   : in t_slv_array;
    constant data_routing           : in t_data_routing;
    constant msg                    : in string;
    constant when_to_start_transfer : in t_when_to_start_transfer := START_TRANSFER_ON_NEXT_SS;
    constant scope                  : in string                   := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel    : in t_msg_id_panel           := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );
  procedure spi_slave_transmit_and_receive(
    signal   VVCT                   : inout t_vvc_target_record;
    constant vvc_instance_idx       : in integer;
    constant data                   : in t_slv_array;
    constant msg                    : in string;
    constant when_to_start_transfer : in t_when_to_start_transfer := START_TRANSFER_ON_NEXT_SS;
    constant scope                  : in string                   := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel    : in t_msg_id_panel           := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  -- Single-word
  procedure spi_slave_transmit_and_check(
    signal   VVCT                   : inout t_vvc_target_record;
    constant vvc_instance_idx       : in integer;
    constant data                   : in std_logic_vector;
    constant data_exp               : in std_logic_vector;
    constant msg                    : in string;
    constant alert_level            : in t_alert_level            := error;
    constant when_to_start_transfer : in t_when_to_start_transfer := START_TRANSFER_ON_NEXT_SS;
    constant scope                  : in string                   := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel    : in t_msg_id_panel           := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );
  -- Multi-word
  procedure spi_slave_transmit_and_check(
    signal   VVCT                   : inout t_vvc_target_record;
    constant vvc_instance_idx       : in integer;
    constant data                   : in t_slv_array;
    constant data_exp               : in t_slv_array;
    constant msg                    : in string;
    constant alert_level            : in t_alert_level            := error;
    constant when_to_start_transfer : in t_when_to_start_transfer := START_TRANSFER_ON_NEXT_SS;
    constant scope                  : in string                   := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel    : in t_msg_id_panel           := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  -- Single-word
  procedure spi_slave_transmit_only(
    signal   VVCT                   : inout t_vvc_target_record;
    constant vvc_instance_idx       : in integer;
    constant data                   : in std_logic_vector;
    constant msg                    : in string;
    constant when_to_start_transfer : in t_when_to_start_transfer := START_TRANSFER_ON_NEXT_SS;
    constant scope                  : in string                   := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel    : in t_msg_id_panel           := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );
  -- Multi-word
  procedure spi_slave_transmit_only(
    signal   VVCT                   : inout t_vvc_target_record;
    constant vvc_instance_idx       : in integer;
    constant data                   : in t_slv_array;
    constant msg                    : in string;
    constant when_to_start_transfer : in t_when_to_start_transfer := START_TRANSFER_ON_NEXT_SS;
    constant scope                  : in string                   := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel    : in t_msg_id_panel           := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  procedure spi_slave_receive_only(
    signal   VVCT                   : inout t_vvc_target_record;
    constant vvc_instance_idx       : in integer;
    constant data_routing           : in t_data_routing;
    constant msg                    : in string;
    constant num_words              : in positive                 := 1;
    constant when_to_start_transfer : in t_when_to_start_transfer := START_TRANSFER_ON_NEXT_SS;
    constant scope                  : in string                   := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel    : in t_msg_id_panel           := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );
  procedure spi_slave_receive_only(
    signal   VVCT                   : inout t_vvc_target_record;
    constant vvc_instance_idx       : in integer;
    constant msg                    : in string;
    constant num_words              : in positive                 := 1;
    constant when_to_start_transfer : in t_when_to_start_transfer := START_TRANSFER_ON_NEXT_SS;
    constant scope                  : in string                   := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel    : in t_msg_id_panel           := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  -- Single-word
  procedure spi_slave_check_only(
    signal   VVCT                   : inout t_vvc_target_record;
    constant vvc_instance_idx       : in integer;
    constant data_exp               : in std_logic_vector;
    constant msg                    : in string;
    constant alert_level            : in t_alert_level            := error;
    constant when_to_start_transfer : in t_when_to_start_transfer := START_TRANSFER_ON_NEXT_SS;
    constant scope                  : in string                   := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel    : in t_msg_id_panel           := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );
  -- Multi-word
  procedure spi_slave_check_only(
    signal   VVCT                   : inout t_vvc_target_record;
    constant vvc_instance_idx       : in integer;
    constant data_exp               : in t_slv_array;
    constant msg                    : in string;
    constant alert_level            : in t_alert_level            := error;
    constant when_to_start_transfer : in t_when_to_start_transfer := START_TRANSFER_ON_NEXT_SS;
    constant scope                  : in string                   := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel    : in t_msg_id_panel           := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  --==========================================================================================
  -- Transaction info methods
  --==========================================================================================
  procedure set_global_vvc_transaction_info(
    signal   vvc_transaction_info_trigger : inout std_logic;
    variable vvc_transaction_info_group   : inout work.protected_transaction_group_pkg.t_generic_array; -- v3 t_transaction_group;
    constant instance_idx                 : in natural;
    constant channel                      : in t_channel;
    constant vvc_cmd                      : in t_vvc_cmd_record;
    constant vvc_config                   : in t_vvc_config;
    constant transaction_status           : in t_transaction_status;
    constant scope                        : in string := C_VVC_CMD_SCOPE_DEFAULT);

  procedure set_global_vvc_transaction_info(
    signal   vvc_transaction_info_trigger : inout std_logic;
    variable vvc_transaction_info_group   : inout work.protected_transaction_group_pkg.t_generic_array; -- v3 t_transaction_group;
    constant instance_idx                 : in natural;
    constant channel                      : in t_channel;
    constant vvc_cmd                      : in t_vvc_cmd_record;
    constant vvc_result                   : in t_slv_array;
    constant transaction_status           : in t_transaction_status;
    constant scope                        : in string := C_VVC_CMD_SCOPE_DEFAULT);

  procedure reset_vvc_transaction_info(
    variable vvc_transaction_info_group : inout work.protected_transaction_group_pkg.t_generic_array; -- v3 t_transaction_group;
    constant instance_idx               : in natural;
    constant channel                    : in t_channel;
    constant vvc_cmd                    : in t_vvc_cmd_record);

end package vvc_methods_pkg;

package body vvc_methods_pkg is

  --==========================================================================================
  -- Methods dedicated to this VVC
  -- Notes:
  --   - shared_vvc_cmd is initialised to C_VVC_CMD_DEFAULT, and also reset to this after every command
  --==========================================================================================

  ----------------------------------------------------------
  -- SPI_MASTER
  ----------------------------------------------------------
  -- Single-word
  procedure spi_master_transmit_and_receive(
    signal   VVCT                         : inout t_vvc_target_record;
    constant vvc_instance_idx             : in integer;
    constant data                         : in std_logic_vector;
    constant data_routing                 : in t_data_routing;
    constant msg                          : in string;
    constant action_when_transfer_is_done : in t_action_when_transfer_is_done := RELEASE_LINE_AFTER_TRANSFER;
    constant scope                        : in string                         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel          : in t_msg_id_panel                 := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant proc_name         : string                                                                                := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant proc_call         : string                                                                                := proc_name & "(" & to_string(VVCT, vvc_instance_idx) & ")";
    -- Helper variable
    variable v_local_vvc_cmd   : t_vvc_cmd_record                                                                      := shared_vvc_cmd.get(vvc_instance_idx);
    variable v_word_length     : natural                                                                               := data'length;
    variable v_num_words       : natural                                                                               := 1;
    variable v_normalized_data : t_slv_array(C_VVC_CMD_MAX_WORDS - 1 downto 0)(C_VVC_CMD_DATA_MAX_LENGTH - 1 downto 0) := (others => (others => '0'));
    variable v_msg_id_panel    : t_msg_id_panel                                                                        := shared_msg_id_panel.get(VOID);
  begin
    -- normalize
    v_normalized_data(0) := normalize_and_check(data, v_local_vvc_cmd.data(0), ALLOW_WIDER_NARROWER, "data", "shared_vvc_cmd.data", proc_call & " called with too wide data. " & add_msg_delimiter(msg));
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- Locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, proc_call, msg, QUEUED, MASTER_TRANSMIT_AND_RECEIVE);

    -- v3
    v_local_vvc_cmd                                     := shared_vvc_cmd.get(vvc_instance_idx);
    v_local_vvc_cmd.data(0)(v_word_length - 1 downto 0) := v_normalized_data(0)(v_word_length - 1 downto 0);
    v_local_vvc_cmd.num_words                           := v_num_words;
    v_local_vvc_cmd.word_length                         := v_word_length;
    v_local_vvc_cmd.data_routing                        := data_routing;
    v_local_vvc_cmd.action_when_transfer_is_done        := action_when_transfer_is_done;
    v_local_vvc_cmd.action_between_words                := RELEASE_LINE_BETWEEN_WORDS;
    v_local_vvc_cmd.parent_msg_id_panel                 := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(VVCT, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure;

  procedure spi_master_transmit_and_receive(
    signal   VVCT                         : inout t_vvc_target_record;
    constant vvc_instance_idx             : in integer;
    constant data                         : in std_logic_vector;
    constant msg                          : in string;
    constant action_when_transfer_is_done : in t_action_when_transfer_is_done := RELEASE_LINE_AFTER_TRANSFER;
    constant scope                        : in string                         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel          : in t_msg_id_panel                 := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
  begin
    spi_master_transmit_and_receive(VVCT, vvc_instance_idx, data, NA, msg, action_when_transfer_is_done, scope, parent_msg_id_panel);
  end procedure;

  -- Multi-word
  procedure spi_master_transmit_and_receive(
    signal   VVCT                         : inout t_vvc_target_record;
    constant vvc_instance_idx             : in integer;
    constant data                         : in t_slv_array;
    constant data_routing                 : in t_data_routing;
    constant msg                          : in string;
    constant action_when_transfer_is_done : in t_action_when_transfer_is_done := RELEASE_LINE_AFTER_TRANSFER;
    constant action_between_words         : in t_action_between_words         := HOLD_LINE_BETWEEN_WORDS;
    constant scope                        : in string                         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel          : in t_msg_id_panel                 := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant proc_name         : string                                                                                := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant proc_call         : string                                                                                := proc_name & "(" & to_string(VVCT, vvc_instance_idx) & ")";
    -- Helper variable
    variable v_local_vvc_cmd   : t_vvc_cmd_record                                                                      := shared_vvc_cmd.get(vvc_instance_idx);
    variable v_word_length     : natural                                                                               := data(0)'length;
    variable v_num_words       : natural                                                                               := data'length;
    variable v_normalized_data : t_slv_array(C_VVC_CMD_MAX_WORDS - 1 downto 0)(C_VVC_CMD_DATA_MAX_LENGTH - 1 downto 0) := (others => (others => '0'));
    variable v_msg_id_panel    : t_msg_id_panel                                                                        := shared_msg_id_panel.get(VOID);
  begin
    -- normalize
    v_normalized_data := normalize_and_check(data, v_local_vvc_cmd.data, ALLOW_WIDER_NARROWER, "data", "shared_vvc_cmd.data", proc_call & " called with too wide data. " & add_msg_delimiter(msg));
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- Locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, proc_call, msg, QUEUED, MASTER_TRANSMIT_AND_RECEIVE);

    -- v3
    v_local_vvc_cmd                              := shared_vvc_cmd.get(vvc_instance_idx);
    v_local_vvc_cmd.data                         := v_normalized_data;
    v_local_vvc_cmd.num_words                    := v_num_words;
    v_local_vvc_cmd.word_length                  := v_word_length;
    v_local_vvc_cmd.data_routing                 := data_routing;
    v_local_vvc_cmd.action_when_transfer_is_done := action_when_transfer_is_done;
    v_local_vvc_cmd.action_between_words         := action_between_words;
    v_local_vvc_cmd.parent_msg_id_panel          := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(VVCT, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure;

  procedure spi_master_transmit_and_receive(
    signal   VVCT                         : inout t_vvc_target_record;
    constant vvc_instance_idx             : in integer;
    constant data                         : in t_slv_array;
    constant msg                          : in string;
    constant action_when_transfer_is_done : in t_action_when_transfer_is_done := RELEASE_LINE_AFTER_TRANSFER;
    constant action_between_words         : in t_action_between_words         := HOLD_LINE_BETWEEN_WORDS;
    constant scope                        : in string                         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel          : in t_msg_id_panel                 := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
  begin
    spi_master_transmit_and_receive(VVCT, vvc_instance_idx, data, NA, msg, action_when_transfer_is_done, action_between_words, scope, parent_msg_id_panel);
  end procedure;

  -- Single-word
  procedure spi_master_transmit_and_check(
    signal   VVCT                         : inout t_vvc_target_record;
    constant vvc_instance_idx             : in integer;
    constant data                         : in std_logic_vector;
    constant data_exp                     : in std_logic_vector;
    constant msg                          : in string;
    constant alert_level                  : in t_alert_level                  := error;
    constant action_when_transfer_is_done : in t_action_when_transfer_is_done := RELEASE_LINE_AFTER_TRANSFER;
    constant scope                        : in string                         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel          : in t_msg_id_panel                 := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant proc_name             : string                                                                                := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant proc_call             : string                                                                                := proc_name & "(" & to_string(VVCT, vvc_instance_idx) & ")";
    -- Helper variable
    variable v_local_vvc_cmd       : t_vvc_cmd_record                                                                      := shared_vvc_cmd.get(vvc_instance_idx);
    variable v_word_length         : natural                                                                               := data'length;
    variable v_num_words           : natural                                                                               := 1;
    variable v_normalized_data     : t_slv_array(C_VVC_CMD_MAX_WORDS - 1 downto 0)(C_VVC_CMD_DATA_MAX_LENGTH - 1 downto 0) := (others => (others => '0'));
    variable v_normalized_data_exp : t_slv_array(C_VVC_CMD_MAX_WORDS - 1 downto 0)(C_VVC_CMD_DATA_MAX_LENGTH - 1 downto 0) := (others => (others => '0'));
    variable v_msg_id_panel        : t_msg_id_panel                                                                        := shared_msg_id_panel.get(VOID);
  begin
    -- normalize to t_slv_array
    v_normalized_data(0)     := normalize_and_check(data, v_local_vvc_cmd.data(0), ALLOW_WIDER_NARROWER, "data", "shared_vvc_cmd.data", proc_call & " called with too wide data. " & add_msg_delimiter(msg));
    v_normalized_data_exp(0) := normalize_and_check(data_exp, v_local_vvc_cmd.data_exp(0), ALLOW_WIDER_NARROWER, "data_exp", "shared_vvc_cmd.data_exp", proc_call & " called with too wide data. " & add_msg_delimiter(msg));

    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- Locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, proc_call, msg, QUEUED, MASTER_TRANSMIT_AND_CHECK);

    -- v3
    v_local_vvc_cmd                                         := shared_vvc_cmd.get(vvc_instance_idx);
    v_local_vvc_cmd.data(0)(v_word_length - 1 downto 0)     := v_normalized_data(0)(v_word_length - 1 downto 0);
    v_local_vvc_cmd.data_exp(0)(v_word_length - 1 downto 0) := v_normalized_data_exp(0)(v_word_length - 1 downto 0);
    v_local_vvc_cmd.num_words                               := v_num_words;
    v_local_vvc_cmd.word_length                             := v_word_length;
    v_local_vvc_cmd.action_when_transfer_is_done            := action_when_transfer_is_done;
    v_local_vvc_cmd.alert_level                             := alert_level;
    v_local_vvc_cmd.parent_msg_id_panel                     := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(VVCT, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure;

  -- Multi-word
  procedure spi_master_transmit_and_check(
    signal   VVCT                         : inout t_vvc_target_record;
    constant vvc_instance_idx             : in integer;
    constant data                         : in t_slv_array;
    constant data_exp                     : in t_slv_array;
    constant msg                          : in string;
    constant alert_level                  : in t_alert_level                  := error;
    constant action_when_transfer_is_done : in t_action_when_transfer_is_done := RELEASE_LINE_AFTER_TRANSFER;
    constant action_between_words         : in t_action_between_words         := HOLD_LINE_BETWEEN_WORDS;
    constant scope                        : in string                         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel          : in t_msg_id_panel                 := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant proc_name             : string                                                                                := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant proc_call             : string                                                                                := proc_name & "(" & to_string(VVCT, vvc_instance_idx) & ")";
    -- Helper variable
    variable v_local_vvc_cmd       : t_vvc_cmd_record                                                                      := shared_vvc_cmd.get(vvc_instance_idx);
    variable v_word_length         : natural                                                                               := data(0)'length;
    variable v_num_words           : natural                                                                               := data'length;
    variable v_normalized_data     : t_slv_array(C_VVC_CMD_MAX_WORDS - 1 downto 0)(C_VVC_CMD_DATA_MAX_LENGTH - 1 downto 0) := (others => (others => '0'));
    variable v_normalized_data_exp : t_slv_array(C_VVC_CMD_MAX_WORDS - 1 downto 0)(C_VVC_CMD_DATA_MAX_LENGTH - 1 downto 0) := (others => (others => '0'));
    variable v_msg_id_panel        : t_msg_id_panel                                                                        := shared_msg_id_panel.get(VOID);
  begin
    -- normalize
    v_normalized_data     := normalize_and_check(data, v_local_vvc_cmd.data, ALLOW_WIDER_NARROWER, "data", "shared_vvc_cmd.data", proc_call & " called with too wide data. " & add_msg_delimiter(msg));
    v_normalized_data_exp := normalize_and_check(data_exp, v_local_vvc_cmd.data_exp, ALLOW_WIDER_NARROWER, "data_exp", "shared_vvc_cmd.data_exp", proc_call & " called with too wide data. " & add_msg_delimiter(msg));
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- Locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, proc_call, msg, QUEUED, MASTER_TRANSMIT_AND_CHECK);

    -- v3
    v_local_vvc_cmd                              := shared_vvc_cmd.get(vvc_instance_idx);
    v_local_vvc_cmd.data                         := v_normalized_data;
    v_local_vvc_cmd.data_exp                     := v_normalized_data_exp;
    v_local_vvc_cmd.num_words                    := v_num_words;
    v_local_vvc_cmd.word_length                  := v_word_length;
    v_local_vvc_cmd.action_when_transfer_is_done := action_when_transfer_is_done;
    v_local_vvc_cmd.action_between_words         := action_between_words;
    v_local_vvc_cmd.alert_level                  := alert_level;
    v_local_vvc_cmd.parent_msg_id_panel          := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(VVCT, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure;

  -- Single-word
  procedure spi_master_transmit_only(
    signal   VVCT                         : inout t_vvc_target_record;
    constant vvc_instance_idx             : in integer;
    constant data                         : in std_logic_vector;
    constant msg                          : in string;
    constant action_when_transfer_is_done : in t_action_when_transfer_is_done := RELEASE_LINE_AFTER_TRANSFER;
    constant scope                        : in string                         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel          : in t_msg_id_panel                 := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant proc_name         : string                                                                                := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant proc_call         : string                                                                                := proc_name & "(" & to_string(VVCT, vvc_instance_idx) & ")";
    -- Helper variable
    variable v_local_vvc_cmd   : t_vvc_cmd_record                                                                      := shared_vvc_cmd.get(vvc_instance_idx);
    variable v_word_length     : natural                                                                               := data'length;
    variable v_num_words       : natural                                                                               := 1;
    variable v_normalized_data : t_slv_array(C_VVC_CMD_MAX_WORDS - 1 downto 0)(C_VVC_CMD_DATA_MAX_LENGTH - 1 downto 0) := (others => (others => '0'));
    variable v_msg_id_panel    : t_msg_id_panel                                                                        := shared_msg_id_panel.get(VOID);
  begin
    -- normalize to t_slv_array
    v_normalized_data(0) := normalize_and_check(data, v_local_vvc_cmd.data(0), ALLOW_WIDER_NARROWER, "data", "shared_vvc_cmd.data", proc_call & " called with too wide data. " & add_msg_delimiter(msg));

    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- Locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, proc_call, msg, QUEUED, MASTER_TRANSMIT_ONLY);

    -- v3
    v_local_vvc_cmd                                     := shared_vvc_cmd.get(vvc_instance_idx);
    v_local_vvc_cmd.data(0)(v_word_length - 1 downto 0) := v_normalized_data(0)(v_word_length - 1 downto 0);
    v_local_vvc_cmd.num_words                           := v_num_words;
    v_local_vvc_cmd.word_length                         := v_word_length;
    v_local_vvc_cmd.action_when_transfer_is_done        := action_when_transfer_is_done;
    v_local_vvc_cmd.parent_msg_id_panel                 := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(VVCT, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure;

  -- Multi-word
  procedure spi_master_transmit_only(
    signal   VVCT                         : inout t_vvc_target_record;
    constant vvc_instance_idx             : in integer;
    constant data                         : in t_slv_array;
    constant msg                          : in string;
    constant action_when_transfer_is_done : in t_action_when_transfer_is_done := RELEASE_LINE_AFTER_TRANSFER;
    constant action_between_words         : in t_action_between_words         := HOLD_LINE_BETWEEN_WORDS;
    constant scope                        : in string                         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel          : in t_msg_id_panel                 := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant proc_name         : string                                                                                := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant proc_call         : string                                                                                := proc_name & "(" & to_string(VVCT, vvc_instance_idx) & ")";
    -- Helper variable
    variable v_local_vvc_cmd   : t_vvc_cmd_record                                                                      := shared_vvc_cmd.get(vvc_instance_idx);
    variable v_word_length     : natural                                                                               := data(0)'length;
    variable v_num_words       : natural                                                                               := data'length;
    variable v_normalized_data : t_slv_array(C_VVC_CMD_MAX_WORDS - 1 downto 0)(C_VVC_CMD_DATA_MAX_LENGTH - 1 downto 0) := (others => (others => '0'));
    variable v_msg_id_panel    : t_msg_id_panel                                                                        := shared_msg_id_panel.get(VOID);
  begin
    -- normalize
    v_normalized_data := normalize_and_check(data, v_local_vvc_cmd.data, ALLOW_WIDER_NARROWER, "data", "shared_vvc_cmd.data", proc_call & " called with too wide data. " & add_msg_delimiter(msg));
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- Locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, proc_call, msg, QUEUED, MASTER_TRANSMIT_ONLY);

    -- v3
    v_local_vvc_cmd                              := shared_vvc_cmd.get(vvc_instance_idx);
    v_local_vvc_cmd.data                         := v_normalized_data;
    v_local_vvc_cmd.num_words                    := v_num_words;
    v_local_vvc_cmd.word_length                  := v_word_length;
    v_local_vvc_cmd.action_when_transfer_is_done := action_when_transfer_is_done;
    v_local_vvc_cmd.action_between_words         := action_between_words;
    v_local_vvc_cmd.parent_msg_id_panel          := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(VVCT, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure;

  -- Single-word
  procedure spi_master_receive_only(
    signal   VVCT                         : inout t_vvc_target_record;
    constant vvc_instance_idx             : in integer;
    constant data_routing                 : in t_data_routing;
    constant msg                          : in string;
    constant num_words                    : in positive                       := 1;
    constant action_when_transfer_is_done : in t_action_when_transfer_is_done := RELEASE_LINE_AFTER_TRANSFER;
    constant action_between_words         : in t_action_between_words         := HOLD_LINE_BETWEEN_WORDS;
    constant scope                        : in string                         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel          : in t_msg_id_panel                 := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant proc_name       : string           := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant proc_call       : string           := proc_name & "(" & to_string(VVCT, vvc_instance_idx) & ")";
    variable v_local_vvc_cmd : t_vvc_cmd_record := shared_vvc_cmd.get(vvc_instance_idx);
    variable v_msg_id_panel  : t_msg_id_panel   := shared_msg_id_panel.get(VOID);
  begin
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- Locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, proc_call, msg, QUEUED, MASTER_RECEIVE_ONLY);

    -- v3
    v_local_vvc_cmd                              := shared_vvc_cmd.get(vvc_instance_idx);
    v_local_vvc_cmd.data_routing                 := data_routing;
    v_local_vvc_cmd.num_words                    := num_words;
    v_local_vvc_cmd.action_when_transfer_is_done := action_when_transfer_is_done;
    v_local_vvc_cmd.action_between_words         := action_between_words;
    v_local_vvc_cmd.parent_msg_id_panel          := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(VVCT, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure;

  procedure spi_master_receive_only(
    signal   VVCT                         : inout t_vvc_target_record;
    constant vvc_instance_idx             : in integer;
    constant msg                          : in string;
    constant num_words                    : in positive                       := 1;
    constant action_when_transfer_is_done : in t_action_when_transfer_is_done := RELEASE_LINE_AFTER_TRANSFER;
    constant action_between_words         : in t_action_between_words         := HOLD_LINE_BETWEEN_WORDS;
    constant scope                        : in string                         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel          : in t_msg_id_panel                 := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
  begin
    spi_master_receive_only(VVCT, vvc_instance_idx, NA, msg, num_words, action_when_transfer_is_done, action_between_words, scope, parent_msg_id_panel);
  end procedure;

  -- Single-word
  procedure spi_master_check_only(
    signal   VVCT                         : inout t_vvc_target_record;
    constant vvc_instance_idx             : in integer;
    constant data_exp                     : in std_logic_vector;
    constant msg                          : in string;
    constant alert_level                  : in t_alert_level                  := error;
    constant action_when_transfer_is_done : in t_action_when_transfer_is_done := RELEASE_LINE_AFTER_TRANSFER;
    constant scope                        : in string                         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel          : in t_msg_id_panel                 := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant proc_name             : string                                                                                := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant proc_call             : string                                                                                := proc_name & "(" & to_string(VVCT, vvc_instance_idx) & ")";
    -- Helper variable
    variable v_local_vvc_cmd       : t_vvc_cmd_record                                                                      := shared_vvc_cmd.get(vvc_instance_idx);
    variable v_word_length         : natural                                                                               := data_exp'length;
    variable v_num_words           : natural                                                                               := 1;
    variable v_normalized_data_exp : t_slv_array(C_VVC_CMD_MAX_WORDS - 1 downto 0)(C_VVC_CMD_DATA_MAX_LENGTH - 1 downto 0) := (others => (others => '0'));
    variable v_msg_id_panel        : t_msg_id_panel                                                                        := shared_msg_id_panel.get(VOID);
  begin
    -- normalize to t_slv_array
    v_normalized_data_exp(0) := normalize_and_check(data_exp, v_local_vvc_cmd.data_exp(0), ALLOW_WIDER_NARROWER, "data_exp", "shared_vvc_cmd.data_exp", proc_call & " called with too wide data. " & add_msg_delimiter(msg));

    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, proc_call, msg, QUEUED, MASTER_CHECK_ONLY);

    -- v3
    v_local_vvc_cmd                                         := shared_vvc_cmd.get(vvc_instance_idx);
    v_local_vvc_cmd.data_exp(0)(v_word_length - 1 downto 0) := v_normalized_data_exp(0)(v_word_length - 1 downto 0);
    v_local_vvc_cmd.num_words                               := v_num_words;
    v_local_vvc_cmd.word_length                             := v_word_length;
    v_local_vvc_cmd.action_when_transfer_is_done            := action_when_transfer_is_done;
    v_local_vvc_cmd.alert_level                             := alert_level;
    v_local_vvc_cmd.parent_msg_id_panel                     := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(VVCT, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure;

  -- Multi-word
  procedure spi_master_check_only(
    signal   VVCT                         : inout t_vvc_target_record;
    constant vvc_instance_idx             : in integer;
    constant data_exp                     : in t_slv_array;
    constant msg                          : in string;
    constant alert_level                  : in t_alert_level                  := error;
    constant action_when_transfer_is_done : in t_action_when_transfer_is_done := RELEASE_LINE_AFTER_TRANSFER;
    constant action_between_words         : in t_action_between_words         := HOLD_LINE_BETWEEN_WORDS;
    constant scope                        : in string                         := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel          : in t_msg_id_panel                 := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant proc_name             : string                                                                                := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant proc_call             : string                                                                                := proc_name & "(" & to_string(VVCT, vvc_instance_idx) & ")";
    -- Helper variable
    variable v_local_vvc_cmd       : t_vvc_cmd_record                                                                      := shared_vvc_cmd.get(vvc_instance_idx);
    variable v_word_length         : natural                                                                               := data_exp(0)'length;
    variable v_num_words           : natural                                                                               := data_exp'length;
    variable v_normalized_data_exp : t_slv_array(C_VVC_CMD_MAX_WORDS - 1 downto 0)(C_VVC_CMD_DATA_MAX_LENGTH - 1 downto 0) := (others => (others => '0'));
    variable v_msg_id_panel        : t_msg_id_panel                                                                        := shared_msg_id_panel.get(VOID);
  begin
    -- normalize
    v_normalized_data_exp := normalize_and_check(data_exp, v_local_vvc_cmd.data_exp, ALLOW_WIDER_NARROWER, "data_exp", "shared_vvc_cmd.data_exp", proc_call & " called with too wide data. " & add_msg_delimiter(msg));
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, proc_call, msg, QUEUED, MASTER_CHECK_ONLY);

    -- v3
    v_local_vvc_cmd                              := shared_vvc_cmd.get(vvc_instance_idx);
    v_local_vvc_cmd.data_exp                     := v_normalized_data_exp;
    v_local_vvc_cmd.num_words                    := v_num_words;
    v_local_vvc_cmd.word_length                  := v_word_length;
    v_local_vvc_cmd.action_when_transfer_is_done := action_when_transfer_is_done;
    v_local_vvc_cmd.action_between_words         := action_between_words;
    v_local_vvc_cmd.alert_level                  := alert_level;
    v_local_vvc_cmd.parent_msg_id_panel          := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(VVCT, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure;

  ----------------------------------------------------------
  -- SPI_SLAVE
  ----------------------------------------------------------
  -- Single-word
  procedure spi_slave_transmit_and_receive(
    signal   VVCT                   : inout t_vvc_target_record;
    constant vvc_instance_idx       : in integer;
    constant data                   : in std_logic_vector;
    constant data_routing           : in t_data_routing;
    constant msg                    : in string;
    constant when_to_start_transfer : in t_when_to_start_transfer := START_TRANSFER_ON_NEXT_SS;
    constant scope                  : in string                   := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel    : in t_msg_id_panel           := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant proc_name         : string                                                                                := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant proc_call         : string                                                                                := proc_name & "(" & to_string(VVCT, vvc_instance_idx) & ")";
    -- Helper variable
    variable v_local_vvc_cmd   : t_vvc_cmd_record                                                                      := shared_vvc_cmd.get(vvc_instance_idx);
    variable v_word_length     : natural                                                                               := data'length;
    variable v_num_words       : natural                                                                               := 1;
    variable v_normalized_data : t_slv_array(C_VVC_CMD_MAX_WORDS - 1 downto 0)(C_VVC_CMD_DATA_MAX_LENGTH - 1 downto 0) := (others => (others => '0'));
    variable v_msg_id_panel    : t_msg_id_panel                                                                        := shared_msg_id_panel.get(VOID);
  begin
    -- normalize to t_slv_array
    v_normalized_data(0) := normalize_and_check(data, v_local_vvc_cmd.data(0), ALLOW_WIDER_NARROWER, "data", "shared_vvc_cmd.data", proc_call & " called with too wide data. " & add_msg_delimiter(msg));
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, proc_call, msg, QUEUED, SLAVE_TRANSMIT_AND_RECEIVE);

    -- v3
    v_local_vvc_cmd                                     := shared_vvc_cmd.get(vvc_instance_idx);
    v_local_vvc_cmd.data(0)(v_word_length - 1 downto 0) := v_normalized_data(0)(v_word_length - 1 downto 0);
    v_local_vvc_cmd.num_words                           := v_num_words;
    v_local_vvc_cmd.word_length                         := v_word_length;
    v_local_vvc_cmd.data_routing                        := data_routing;
    v_local_vvc_cmd.when_to_start_transfer              := when_to_start_transfer;
    v_local_vvc_cmd.parent_msg_id_panel                 := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(VVCT, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure;

  procedure spi_slave_transmit_and_receive(
    signal   VVCT                   : inout t_vvc_target_record;
    constant vvc_instance_idx       : in integer;
    constant data                   : in std_logic_vector;
    constant msg                    : in string;
    constant when_to_start_transfer : in t_when_to_start_transfer := START_TRANSFER_ON_NEXT_SS;
    constant scope                  : in string                   := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel    : in t_msg_id_panel           := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
  begin
    spi_slave_transmit_and_receive(VVCT, vvc_instance_idx, data, NA, msg, when_to_start_transfer, scope, parent_msg_id_panel);
  end procedure;

  -- Multi-word
  procedure spi_slave_transmit_and_receive(
    signal   VVCT                   : inout t_vvc_target_record;
    constant vvc_instance_idx       : in integer;
    constant data                   : in t_slv_array;
    constant data_routing           : in t_data_routing;
    constant msg                    : in string;
    constant when_to_start_transfer : in t_when_to_start_transfer := START_TRANSFER_ON_NEXT_SS;
    constant scope                  : in string                   := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel    : in t_msg_id_panel           := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant proc_name         : string                                                                                := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant proc_call         : string                                                                                := proc_name & "(" & to_string(VVCT, vvc_instance_idx) & ")";
    -- Helper variable
    variable v_local_vvc_cmd   : t_vvc_cmd_record                                                                      := shared_vvc_cmd.get(vvc_instance_idx);
    variable v_word_length     : natural                                                                               := data(0)'length;
    variable v_num_words       : natural                                                                               := data'length;
    variable v_normalized_data : t_slv_array(C_VVC_CMD_MAX_WORDS - 1 downto 0)(C_VVC_CMD_DATA_MAX_LENGTH - 1 downto 0) := (others => (others => '0'));
    variable v_msg_id_panel    : t_msg_id_panel                                                                        := shared_msg_id_panel.get(VOID);
  begin
    -- normalize
    v_normalized_data := normalize_and_check(data, v_local_vvc_cmd.data, ALLOW_WIDER_NARROWER, "data", "shared_vvc_cmd.data", proc_call & " called with too wide data. " & add_msg_delimiter(msg));
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, proc_call, msg, QUEUED, SLAVE_TRANSMIT_AND_RECEIVE);

    -- v3
    v_local_vvc_cmd                        := shared_vvc_cmd.get(vvc_instance_idx);
    v_local_vvc_cmd.data                   := v_normalized_data;
    v_local_vvc_cmd.num_words              := v_num_words;
    v_local_vvc_cmd.word_length            := v_word_length;
    v_local_vvc_cmd.data_routing           := data_routing;
    v_local_vvc_cmd.when_to_start_transfer := when_to_start_transfer;
    v_local_vvc_cmd.parent_msg_id_panel    := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(VVCT, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure;

  procedure spi_slave_transmit_and_receive(
    signal   VVCT                   : inout t_vvc_target_record;
    constant vvc_instance_idx       : in integer;
    constant data                   : in t_slv_array;
    constant msg                    : in string;
    constant when_to_start_transfer : in t_when_to_start_transfer := START_TRANSFER_ON_NEXT_SS;
    constant scope                  : in string                   := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel    : in t_msg_id_panel           := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
  begin
    spi_slave_transmit_and_receive(VVCT, vvc_instance_idx, data, NA, msg, when_to_start_transfer, scope, parent_msg_id_panel);
  end procedure;

  -- Single-word
  procedure spi_slave_transmit_and_check(
    signal   VVCT                   : inout t_vvc_target_record;
    constant vvc_instance_idx       : in integer;
    constant data                   : in std_logic_vector;
    constant data_exp               : in std_logic_vector;
    constant msg                    : in string;
    constant alert_level            : in t_alert_level            := error;
    constant when_to_start_transfer : in t_when_to_start_transfer := START_TRANSFER_ON_NEXT_SS;
    constant scope                  : in string                   := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel    : in t_msg_id_panel           := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant proc_name             : string                                                                                := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant proc_call             : string                                                                                := proc_name & "(" & to_string(VVCT, vvc_instance_idx) & ")";
    -- Helper variable
    variable v_local_vvc_cmd       : t_vvc_cmd_record                                                                      := shared_vvc_cmd.get(vvc_instance_idx);
    variable v_word_length         : natural                                                                               := data'length;
    variable v_num_words           : natural                                                                               := 1;
    variable v_normalized_data     : t_slv_array(C_VVC_CMD_MAX_WORDS - 1 downto 0)(C_VVC_CMD_DATA_MAX_LENGTH - 1 downto 0) := (others => (others => '0'));
    variable v_normalized_data_exp : t_slv_array(C_VVC_CMD_MAX_WORDS - 1 downto 0)(C_VVC_CMD_DATA_MAX_LENGTH - 1 downto 0) := (others => (others => '0'));
    variable v_msg_id_panel        : t_msg_id_panel                                                                        := shared_msg_id_panel.get(VOID);
  begin
    -- normalize to t_slv_array
    v_normalized_data(0)     := normalize_and_check(data, v_local_vvc_cmd.data(0), ALLOW_WIDER_NARROWER, "data", "shared_vvc_cmd.data", proc_call & " called with too wide data. " & add_msg_delimiter(msg));
    v_normalized_data_exp(0) := normalize_and_check(data_exp, v_local_vvc_cmd.data_exp(0), ALLOW_WIDER_NARROWER, "data_exp", "shared_vvc_cmd.data_exp", proc_call & " called with too wide data. " & add_msg_delimiter(msg));

    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, proc_call, msg, QUEUED, SLAVE_TRANSMIT_AND_CHECK);

    -- v3
    v_local_vvc_cmd                                         := shared_vvc_cmd.get(vvc_instance_idx);
    v_local_vvc_cmd.data(0)(v_word_length - 1 downto 0)     := v_normalized_data(0)(v_word_length - 1 downto 0);
    v_local_vvc_cmd.data_exp(0)(v_word_length - 1 downto 0) := v_normalized_data_exp(0)(v_word_length - 1 downto 0);
    v_local_vvc_cmd.num_words                               := v_num_words;
    v_local_vvc_cmd.word_length                             := v_word_length;
    v_local_vvc_cmd.when_to_start_transfer                  := when_to_start_transfer;
    v_local_vvc_cmd.alert_level                             := alert_level;
    v_local_vvc_cmd.parent_msg_id_panel                     := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(VVCT, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure;

  -- Multi-word
  procedure spi_slave_transmit_and_check(
    signal   VVCT                   : inout t_vvc_target_record;
    constant vvc_instance_idx       : in integer;
    constant data                   : in t_slv_array;
    constant data_exp               : in t_slv_array;
    constant msg                    : in string;
    constant alert_level            : in t_alert_level            := error;
    constant when_to_start_transfer : in t_when_to_start_transfer := START_TRANSFER_ON_NEXT_SS;
    constant scope                  : in string                   := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel    : in t_msg_id_panel           := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant proc_name             : string                                                                                := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant proc_call             : string                                                                                := proc_name & "(" & to_string(VVCT, vvc_instance_idx) & ")";
    -- Helper variable
    variable v_local_vvc_cmd       : t_vvc_cmd_record                                                                      := shared_vvc_cmd.get(vvc_instance_idx);
    variable v_word_length         : natural                                                                               := data(0)'length;
    variable v_num_words           : natural                                                                               := data'length;
    variable v_normalized_data     : t_slv_array(C_VVC_CMD_MAX_WORDS - 1 downto 0)(C_VVC_CMD_DATA_MAX_LENGTH - 1 downto 0) := (others => (others => '0'));
    variable v_normalized_data_exp : t_slv_array(C_VVC_CMD_MAX_WORDS - 1 downto 0)(C_VVC_CMD_DATA_MAX_LENGTH - 1 downto 0) := (others => (others => '0'));
    variable v_msg_id_panel        : t_msg_id_panel                                                                        := shared_msg_id_panel.get(VOID);
  begin
    -- normalize
    v_normalized_data     := normalize_and_check(data, v_local_vvc_cmd.data, ALLOW_WIDER_NARROWER, "data", "shared_vvc_cmd.data", proc_call & " called with too wide data. " & add_msg_delimiter(msg));
    v_normalized_data_exp := normalize_and_check(data_exp, v_local_vvc_cmd.data_exp, ALLOW_WIDER_NARROWER, "data_exp", "shared_vvc_cmd.data_exp", proc_call & " called with too wide data. " & add_msg_delimiter(msg));
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, proc_call, msg, QUEUED, SLAVE_TRANSMIT_AND_CHECK);

    -- v3
    v_local_vvc_cmd                        := shared_vvc_cmd.get(vvc_instance_idx);
    v_local_vvc_cmd.data                   := v_normalized_data;
    v_local_vvc_cmd.data_exp               := v_normalized_data_exp;
    v_local_vvc_cmd.num_words              := v_num_words;
    v_local_vvc_cmd.word_length            := v_word_length;
    v_local_vvc_cmd.when_to_start_transfer := when_to_start_transfer;
    v_local_vvc_cmd.alert_level            := alert_level;
    v_local_vvc_cmd.parent_msg_id_panel    := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(VVCT, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure;

  -- Single-word
  procedure spi_slave_transmit_only(
    signal   VVCT                   : inout t_vvc_target_record;
    constant vvc_instance_idx       : in integer;
    constant data                   : in std_logic_vector;
    constant msg                    : in string;
    constant when_to_start_transfer : in t_when_to_start_transfer := START_TRANSFER_ON_NEXT_SS;
    constant scope                  : in string                   := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel    : in t_msg_id_panel           := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant proc_name         : string                                                                                := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant proc_call         : string                                                                                := proc_name & "(" & to_string(VVCT, vvc_instance_idx) & ")";
    -- Helper variable
    variable v_local_vvc_cmd   : t_vvc_cmd_record                                                                      := shared_vvc_cmd.get(vvc_instance_idx);
    variable v_word_length     : natural                                                                               := data'length;
    variable v_num_words       : natural                                                                               := 1;
    variable v_normalized_data : t_slv_array(C_VVC_CMD_MAX_WORDS - 1 downto 0)(C_VVC_CMD_DATA_MAX_LENGTH - 1 downto 0) := (others => (others => '0'));
    variable v_msg_id_panel    : t_msg_id_panel                                                                        := shared_msg_id_panel.get(VOID);
  begin
    -- normalize to t_slv_array
    v_normalized_data(0) := normalize_and_check(data, v_local_vvc_cmd.data(0), ALLOW_WIDER_NARROWER, "data", "shared_vvc_cmd.data", proc_call & " called with too wide data. " & add_msg_delimiter(msg));
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, proc_call, msg, QUEUED, SLAVE_TRANSMIT_ONLY);

    -- v3
    v_local_vvc_cmd                                     := shared_vvc_cmd.get(vvc_instance_idx);
    v_local_vvc_cmd.data(0)(v_word_length - 1 downto 0) := v_normalized_data(0)(v_word_length - 1 downto 0);
    v_local_vvc_cmd.num_words                           := v_num_words;
    v_local_vvc_cmd.word_length                         := v_word_length;
    v_local_vvc_cmd.when_to_start_transfer              := when_to_start_transfer;
    v_local_vvc_cmd.parent_msg_id_panel                 := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(VVCT, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure;

  -- Multi-word
  procedure spi_slave_transmit_only(
    signal   VVCT                   : inout t_vvc_target_record;
    constant vvc_instance_idx       : in integer;
    constant data                   : in t_slv_array;
    constant msg                    : in string;
    constant when_to_start_transfer : in t_when_to_start_transfer := START_TRANSFER_ON_NEXT_SS;
    constant scope                  : in string                   := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel    : in t_msg_id_panel           := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant proc_name         : string                                                                                := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant proc_call         : string                                                                                := proc_name & "(" & to_string(VVCT, vvc_instance_idx) & ")";
    -- Helper variable
    variable v_local_vvc_cmd   : t_vvc_cmd_record                                                                      := shared_vvc_cmd.get(vvc_instance_idx);
    variable v_word_length     : natural                                                                               := data(0)'length;
    variable v_num_words       : natural                                                                               := data'length;
    variable v_normalized_data : t_slv_array(C_VVC_CMD_MAX_WORDS - 1 downto 0)(C_VVC_CMD_DATA_MAX_LENGTH - 1 downto 0) := (others => (others => '0'));
    variable v_msg_id_panel    : t_msg_id_panel                                                                        := shared_msg_id_panel.get(VOID);
  begin
    -- normalize
    v_normalized_data := normalize_and_check(data, v_local_vvc_cmd.data, ALLOW_WIDER_NARROWER, "data", "shared_vvc_cmd.data", proc_call & " called with too wide data. " & add_msg_delimiter(msg));

    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, proc_call, msg, QUEUED, SLAVE_TRANSMIT_ONLY);

    -- v3
    v_local_vvc_cmd                        := shared_vvc_cmd.get(vvc_instance_idx);
    v_local_vvc_cmd.data                   := v_normalized_data;
    v_local_vvc_cmd.num_words              := v_num_words;
    v_local_vvc_cmd.word_length            := v_word_length;
    v_local_vvc_cmd.when_to_start_transfer := when_to_start_transfer;
    v_local_vvc_cmd.parent_msg_id_panel    := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(VVCT, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure;

  -- Single-word
  procedure spi_slave_receive_only(
    signal   VVCT                   : inout t_vvc_target_record;
    constant vvc_instance_idx       : in integer;
    constant data_routing           : in t_data_routing;
    constant msg                    : in string;
    constant num_words              : in positive                 := 1;
    constant when_to_start_transfer : in t_when_to_start_transfer := START_TRANSFER_ON_NEXT_SS;
    constant scope                  : in string                   := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel    : in t_msg_id_panel           := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant proc_name       : string           := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant proc_call       : string           := proc_name & "(" & to_string(VVCT, vvc_instance_idx) & ")";
    variable v_local_vvc_cmd : t_vvc_cmd_record := shared_vvc_cmd.get(vvc_instance_idx);
    variable v_msg_id_panel  : t_msg_id_panel   := shared_msg_id_panel.get(VOID);
  begin
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, proc_call, msg, QUEUED, SLAVE_RECEIVE_ONLY);

    -- v3
    v_local_vvc_cmd                        := shared_vvc_cmd.get(vvc_instance_idx);
    v_local_vvc_cmd.data_routing           := data_routing;
    v_local_vvc_cmd.num_words              := num_words;
    v_local_vvc_cmd.when_to_start_transfer := when_to_start_transfer;
    v_local_vvc_cmd.parent_msg_id_panel    := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(VVCT, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure;

  procedure spi_slave_receive_only(
    signal   VVCT                   : inout t_vvc_target_record;
    constant vvc_instance_idx       : in integer;
    constant msg                    : in string;
    constant num_words              : in positive                 := 1;
    constant when_to_start_transfer : in t_when_to_start_transfer := START_TRANSFER_ON_NEXT_SS;
    constant scope                  : in string                   := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel    : in t_msg_id_panel           := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
  begin
    spi_slave_receive_only(VVCT, vvc_instance_idx, NA, msg, num_words, when_to_start_transfer, scope, parent_msg_id_panel);
  end procedure;

  -- Single-word
  procedure spi_slave_check_only(
    signal   VVCT                   : inout t_vvc_target_record;
    constant vvc_instance_idx       : in integer;
    constant data_exp               : in std_logic_vector;
    constant msg                    : in string;
    constant alert_level            : in t_alert_level            := error;
    constant when_to_start_transfer : in t_when_to_start_transfer := START_TRANSFER_ON_NEXT_SS;
    constant scope                  : in string                   := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel    : in t_msg_id_panel           := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant proc_name             : string                                                                                := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant proc_call             : string                                                                                := proc_name & "(" & to_string(VVCT, vvc_instance_idx) & ")";
    -- Helper variable
    variable v_local_vvc_cmd       : t_vvc_cmd_record                                                                      := shared_vvc_cmd.get(vvc_instance_idx);
    variable v_word_length         : natural                                                                               := data_exp'length;
    variable v_num_words           : natural                                                                               := 1;
    variable v_normalized_data_exp : t_slv_array(C_VVC_CMD_MAX_WORDS - 1 downto 0)(C_VVC_CMD_DATA_MAX_LENGTH - 1 downto 0) := (others => (others => '0'));
    variable v_msg_id_panel        : t_msg_id_panel                                                                        := shared_msg_id_panel.get(VOID);
  begin
    -- normalize to t_slv_array
    v_normalized_data_exp(0) := normalize_and_check(data_exp, v_local_vvc_cmd.data_exp(0), ALLOW_WIDER_NARROWER, "data_exp", "shared_vvc_cmd.data_exp", proc_call & " called with too wide data. " & add_msg_delimiter(msg));
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, proc_call, msg, QUEUED, SLAVE_CHECK_ONLY);

    -- v3
    v_local_vvc_cmd                                         := shared_vvc_cmd.get(vvc_instance_idx);
    v_local_vvc_cmd.data_exp(0)(v_word_length - 1 downto 0) := v_normalized_data_exp(0)(v_word_length - 1 downto 0);
    v_local_vvc_cmd.num_words                               := v_num_words;
    v_local_vvc_cmd.word_length                             := v_word_length;
    v_local_vvc_cmd.when_to_start_transfer                  := when_to_start_transfer;
    v_local_vvc_cmd.alert_level                             := alert_level;
    v_local_vvc_cmd.parent_msg_id_panel                     := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(VVCT, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure;

  -- Multi-word
  procedure spi_slave_check_only(
    signal   VVCT                   : inout t_vvc_target_record;
    constant vvc_instance_idx       : in integer;
    constant data_exp               : in t_slv_array;
    constant msg                    : in string;
    constant alert_level            : in t_alert_level            := error;
    constant when_to_start_transfer : in t_when_to_start_transfer := START_TRANSFER_ON_NEXT_SS;
    constant scope                  : in string                   := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel    : in t_msg_id_panel           := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant proc_name             : string                                                                                := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant proc_call             : string                                                                                := proc_name & "(" & to_string(VVCT, vvc_instance_idx) & ")";
    -- Helper variable
    variable v_local_vvc_cmd       : t_vvc_cmd_record                                                                      := shared_vvc_cmd.get(vvc_instance_idx);
    variable v_word_length         : natural                                                                               := data_exp(0)'length;
    variable v_num_words           : natural                                                                               := data_exp'length;
    variable v_normalized_data_exp : t_slv_array(C_VVC_CMD_MAX_WORDS - 1 downto 0)(C_VVC_CMD_DATA_MAX_LENGTH - 1 downto 0) := (others => (others => '0'));
    variable v_msg_id_panel        : t_msg_id_panel                                                                        := shared_msg_id_panel.get(VOID);
  begin
    -- normalize
    v_normalized_data_exp := normalize_and_check(data_exp, v_local_vvc_cmd.data_exp, ALLOW_WIDER_NARROWER, "data_exp", "shared_vvc_cmd.data_exp", proc_call & " called with too wide data. " & add_msg_delimiter(msg));
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, proc_call, msg, QUEUED, SLAVE_CHECK_ONLY);

    -- v3
    v_local_vvc_cmd                        := shared_vvc_cmd.get(vvc_instance_idx);
    v_local_vvc_cmd.data_exp               := v_normalized_data_exp;
    v_local_vvc_cmd.num_words              := v_num_words;
    v_local_vvc_cmd.word_length            := v_word_length;
    v_local_vvc_cmd.when_to_start_transfer := when_to_start_transfer;
    v_local_vvc_cmd.alert_level            := alert_level;
    v_local_vvc_cmd.parent_msg_id_panel    := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(VVCT, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure;

  --==========================================================================================
  -- Transaction info methods
  --==========================================================================================
  procedure set_global_vvc_transaction_info(
    signal   vvc_transaction_info_trigger : inout std_logic;
    variable vvc_transaction_info_group   : inout work.protected_transaction_group_pkg.t_generic_array; -- v3 t_transaction_group;
    constant instance_idx                 : in natural;
    constant channel                      : in t_channel;
    constant vvc_cmd                      : in t_vvc_cmd_record;
    constant vvc_config                   : in t_vvc_config;
    constant transaction_status           : in t_transaction_status;
    constant scope                        : in string := C_VVC_CMD_SCOPE_DEFAULT) is
    variable v_transaction_info_group : t_transaction_group := vvc_transaction_info_group.get(instance_idx, channel);
  begin
    case vvc_cmd.operation is
      when MASTER_TRANSMIT_AND_RECEIVE | MASTER_TRANSMIT_AND_CHECK | MASTER_TRANSMIT_ONLY |
           MASTER_RECEIVE_ONLY | MASTER_CHECK_ONLY | SLAVE_TRANSMIT_AND_RECEIVE |
           SLAVE_TRANSMIT_AND_CHECK | SLAVE_TRANSMIT_ONLY | SLAVE_RECEIVE_ONLY | SLAVE_CHECK_ONLY =>
        v_transaction_info_group.bt.operation                    := vvc_cmd.operation;
        v_transaction_info_group.bt.data                         := vvc_cmd.data;
        v_transaction_info_group.bt.data_exp                     := vvc_cmd.data_exp;
        v_transaction_info_group.bt.num_words                    := vvc_cmd.num_words;
        v_transaction_info_group.bt.word_length                  := vvc_cmd.word_length;
        v_transaction_info_group.bt.when_to_start_transfer       := vvc_cmd.when_to_start_transfer;
        v_transaction_info_group.bt.action_when_transfer_is_done := vvc_cmd.action_when_transfer_is_done;
        v_transaction_info_group.bt.action_between_words         := vvc_cmd.action_between_words;
        v_transaction_info_group.bt.vvc_meta.msg                 := vvc_cmd.msg;
        v_transaction_info_group.bt.vvc_meta.cmd_idx             := vvc_cmd.cmd_idx;
        v_transaction_info_group.bt.transaction_status           := transaction_status;

        vvc_transaction_info_group.set(v_transaction_info_group, instance_idx, channel);
        gen_pulse(vvc_transaction_info_trigger, 0 ns, "pulsing global vvc transaction info trigger", scope, ID_NEVER);

      when others =>
        alert(TB_ERROR, "VVC operation not recognized", scope);
    end case;

    wait for 0 ns;
  end procedure set_global_vvc_transaction_info;

  procedure set_global_vvc_transaction_info(
    signal   vvc_transaction_info_trigger : inout std_logic;
    variable vvc_transaction_info_group   : inout work.protected_transaction_group_pkg.t_generic_array; -- v3 t_transaction_group;
    constant instance_idx                 : in natural;
    constant channel                      : in t_channel;
    constant vvc_cmd                      : in t_vvc_cmd_record;
    constant vvc_result                   : in t_slv_array;
    constant transaction_status           : in t_transaction_status;
    constant scope                        : in string := C_VVC_CMD_SCOPE_DEFAULT) is
    variable v_transaction_info_group : t_transaction_group := vvc_transaction_info_group.get(instance_idx, channel);
  begin
    case vvc_cmd.operation is
      when MASTER_TRANSMIT_AND_RECEIVE | MASTER_RECEIVE_ONLY | SLAVE_TRANSMIT_AND_RECEIVE | SLAVE_RECEIVE_ONLY =>
        v_transaction_info_group.bt.data               := vvc_result;
        v_transaction_info_group.bt.transaction_status := transaction_status;

        vvc_transaction_info_group.set(v_transaction_info_group, instance_idx, channel);
        gen_pulse(vvc_transaction_info_trigger, 0 ns, "pulsing global vvc transaction info trigger", scope, ID_NEVER);

      when others =>
        alert(TB_ERROR, "VVC operation does not update vvc_result", scope);
    end case;

    wait for 0 ns;
  end procedure set_global_vvc_transaction_info;

  procedure reset_vvc_transaction_info(
    variable vvc_transaction_info_group : inout work.protected_transaction_group_pkg.t_generic_array; -- v3 t_transaction_group;
    constant instance_idx               : in natural;
    constant channel                    : in t_channel;
    constant vvc_cmd                    : in t_vvc_cmd_record) is
    variable v_transaction_info_group : t_transaction_group := vvc_transaction_info_group.get(instance_idx, channel);
  begin
    case vvc_cmd.operation is
      when MASTER_TRANSMIT_AND_RECEIVE | MASTER_TRANSMIT_AND_CHECK | MASTER_TRANSMIT_ONLY |
           MASTER_RECEIVE_ONLY | MASTER_CHECK_ONLY | SLAVE_TRANSMIT_AND_RECEIVE |
           SLAVE_TRANSMIT_AND_CHECK | SLAVE_TRANSMIT_ONLY | SLAVE_RECEIVE_ONLY | SLAVE_CHECK_ONLY =>
        v_transaction_info_group.bt := C_BASE_TRANSACTION_SET_DEFAULT;

      when others =>
        null;
    end case;
    vvc_transaction_info_group.set(v_transaction_info_group, instance_idx, channel);

    wait for 0 ns;
  end procedure reset_vvc_transaction_info;

end package body vvc_methods_pkg;
