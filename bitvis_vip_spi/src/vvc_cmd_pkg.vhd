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
--  VVC command package
--================================================================================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library uvvm_vvc_framework;
use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

use work.vvc_transaction_pkg.all;

package vvc_cmd_pkg is

  alias t_operation is work.vvc_transaction_pkg.t_operation;

  --==========================================================================================
  -- t_vvc_cmd_record
  -- - Record type used for communication with the VVC
  --==========================================================================================
  type t_vvc_cmd_record is record
    -- VVC dedicated fields
    data                         : t_slv_array(0 to C_VVC_CMD_MAX_WORDS - 1)(C_VVC_CMD_DATA_MAX_LENGTH - 1 downto 0);
    data_exp                     : t_slv_array(0 to C_VVC_CMD_MAX_WORDS - 1)(C_VVC_CMD_DATA_MAX_LENGTH - 1 downto 0);
    num_words                    : natural;
    word_length                  : natural;
    when_to_start_transfer       : t_when_to_start_transfer;
    action_when_transfer_is_done : t_action_when_transfer_is_done;
    action_between_words         : t_action_between_words;
    -- Common VVC fields  (Used by td_vvc_framework_common_methods_pkg procedures, and thus mandatory)
    operation                    : t_operation;
    proc_call                    : string(1 to C_VVC_CMD_STRING_MAX_LENGTH);
    msg                          : string(1 to C_VVC_CMD_STRING_MAX_LENGTH);
    data_routing                 : t_data_routing;
    cmd_idx                      : natural;
    command_type                 : t_immediate_or_queued; -- QUEUED/IMMEDIATE
    msg_id                       : t_msg_id;
    gen_integer_array            : t_integer_array(0 to 1); -- Increase array length if needed
    gen_boolean                  : boolean; -- Generic boolean
    timeout                      : time;
    alert_level                  : t_alert_level;
    delay                        : time;
    quietness                    : t_quietness;
    parent_msg_id_panel          : t_msg_id_panel;
  end record;

  constant C_VVC_CMD_DEFAULT : t_vvc_cmd_record := (
    data                         => (others => (others => '0')),
    data_exp                     => (others => (others => '0')),
    num_words                    => 0,
    word_length                  => 0,
    when_to_start_transfer       => START_TRANSFER_IMMEDIATE,
    action_when_transfer_is_done => RELEASE_LINE_AFTER_TRANSFER,
    action_between_words         => HOLD_LINE_BETWEEN_WORDS,
    -- Common VVC fields
    operation                    => NO_OPERATION,
    proc_call                    => (others => NUL),
    msg                          => (others => NUL),
    data_routing                 => NA,
    cmd_idx                      => 0,
    command_type                 => NO_COMMAND_TYPE,
    msg_id                       => NO_ID,
    gen_integer_array            => (others => -1),
    gen_boolean                  => false,
    timeout                      => 0 ns,
    alert_level                  => failure,
    delay                        => 0 ns,
    quietness                    => NON_QUIET,
    parent_msg_id_panel          => C_UNUSED_MSG_ID_PANEL
  );

  --==========================================================================================
  -- t_vvc_result, t_vvc_result_queue_element, t_vvc_response and shared_vvc_response :
  --
  -- - Used for storing the result of a BFM procedure called by the VVC,
  --   so that the result can be transported from the VVC to for example a sequencer via
  --   fetch_result() as described in VVC_Framework_common_methods_QuickRef
  --
  -- - t_vvc_result includes the return value of the procedure in the BFM.
  --   It can also be defined as a record if multiple values shall be transported from the BFM
  --==========================================================================================
  subtype t_vvc_result is std_logic_vector(C_VVC_CMD_DATA_MAX_LENGTH - 1 downto 0);

  type t_vvc_result_queue_element is record
    cmd_idx : natural;                  -- from UVVM handshake mechanism
    result  : t_vvc_result;
  end record;

  type t_vvc_response is record
    fetch_is_accepted  : boolean;
    transaction_result : t_transaction_result;
    result             : t_vvc_result;
  end record;

  constant C_VVC_RESPONSE_DEFAULT : t_vvc_response := (
    fetch_is_accepted  => false,
    transaction_result => ACK,
    result             => (others => '0')
  );

end package vvc_cmd_pkg;

package body vvc_cmd_pkg is

end package body vvc_cmd_pkg;

--================================================================================================================================
--  Generic package instantiations
--================================================================================================================================
----------------------------------------------------------------------
-- Protected type: t_vvc_cmd_record
----------------------------------------------------------------------
library uvvm_util;
use work.vvc_cmd_pkg.all;
use work.vvc_transaction_pkg.all;

package protected_vvc_cmd_pkg is new uvvm_util.protected_generic_types_pkg
  generic map(
    t_generic_element  => t_vvc_cmd_record,
    c_generic_default  => C_VVC_CMD_DEFAULT,
    c_max_instance_num => C_VVC_MAX_INSTANCE_NUM
  );

----------------------------------------------------------------------
-- Protected type: t_vvc_response
----------------------------------------------------------------------
library uvvm_util;
use work.vvc_cmd_pkg.all;
use work.vvc_transaction_pkg.all;

package protected_vvc_response_pkg is new uvvm_util.protected_generic_types_pkg
  generic map(
    t_generic_element  => t_vvc_response,
    c_generic_default  => C_VVC_RESPONSE_DEFAULT,
    c_max_instance_num => C_VVC_MAX_INSTANCE_NUM
  );

----------------------------------------------------------------------
-- Protected type: vvc_last_received_cmd_idx
----------------------------------------------------------------------
library uvvm_util;
use work.vvc_cmd_pkg.all;
use work.vvc_transaction_pkg.all;

package protected_vvc_last_received_cmd_idx_pkg is new uvvm_util.protected_generic_types_pkg
  generic map(
    t_generic_element  => integer,
    c_generic_default  => -1,
    c_max_instance_num => C_VVC_MAX_INSTANCE_NUM
  );

--================================================================================================================================
--  Shared variables package
--================================================================================================================================
use work.protected_vvc_cmd_pkg.all;
use work.protected_vvc_response_pkg.all;
use work.protected_vvc_last_received_cmd_idx_pkg.all;

package vvc_cmd_shared_variables_pkg is
  shared variable shared_vvc_cmd                   : work.protected_vvc_cmd_pkg.t_generic_array;
  shared variable shared_vvc_response              : work.protected_vvc_response_pkg.t_generic_array;
  shared variable shared_vvc_last_received_cmd_idx : work.protected_vvc_last_received_cmd_idx_pkg.t_generic_array;
end package vvc_cmd_shared_variables_pkg;
