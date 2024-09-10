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

package vvc_cmd_pkg is

  --==========================================================================================
  -- t_operation
  -- - VVC and BFM operations
  --==========================================================================================
  type t_operation is (
    -- UVVM common
    NO_OPERATION,
    ENABLE_LOG_MSG,
    DISABLE_LOG_MSG,
    FLUSH_COMMAND_QUEUE,
    FETCH_RESULT,
    INSERT_DELAY,
    TERMINATE_CURRENT_COMMAND,
    -- VVC local
    WRITE, READ, CHECK
  );

  -- Constants for the maximum sizes to use in this VVC. Can be modified in adaptations_pkg.
  constant C_VVC_CMD_DATA_MAX_LENGTH   : natural := C_WISHBONE_VVC_CMD_DATA_MAX_LENGTH;
  constant C_VVC_CMD_ADDR_MAX_LENGTH   : natural := C_WISHBONE_VVC_CMD_ADDR_MAX_LENGTH;
  constant C_VVC_CMD_STRING_MAX_LENGTH : natural := C_WISHBONE_VVC_CMD_STRING_MAX_LENGTH;
  constant C_VVC_MAX_INSTANCE_NUM      : natural := C_WISHBONE_VVC_MAX_INSTANCE_NUM;

  --==========================================================================================
  -- t_vvc_cmd_record
  -- - Record type used for communication with the VVC
  --==========================================================================================
  type t_vvc_cmd_record is record
    -- VVC dedicated fields
    addr                : unsigned(C_VVC_CMD_ADDR_MAX_LENGTH - 1 downto 0);
    data                : std_logic_vector(C_VVC_CMD_DATA_MAX_LENGTH - 1 downto 0);
    max_receptions      : integer;
    -- Common VVC fields
    operation           : t_operation;
    proc_call           : string(1 to C_VVC_CMD_STRING_MAX_LENGTH);
    msg                 : string(1 to C_VVC_CMD_STRING_MAX_LENGTH);
    data_routing        : t_data_routing;
    cmd_idx             : natural;
    command_type        : t_immediate_or_queued;
    msg_id              : t_msg_id;
    gen_integer_array   : t_integer_array(0 to 1); -- Increase array length if needed
    gen_boolean         : boolean;      -- Generic boolean
    timeout             : time;
    alert_level         : t_alert_level;
    delay               : time;
    quietness           : t_quietness;
    parent_msg_id_panel : t_msg_id_panel;
  end record;

  constant C_VVC_CMD_DEFAULT : t_vvc_cmd_record := (
    addr                => (others => '0'),
    data                => (others => '0'),
    max_receptions      => 1,
    -- Common VVC fields
    operation           => NO_OPERATION,
    proc_call           => (others => NUL),
    msg                 => (others => NUL),
    data_routing        => NA,
    cmd_idx             => 0,
    command_type        => NO_COMMAND_TYPE,
    msg_id              => NO_ID,
    gen_integer_array   => (others => -1),
    gen_boolean         => false,
    timeout             => 0 ns,
    alert_level         => FAILURE,
    delay               => 0 ns,
    quietness           => NON_QUIET,
    parent_msg_id_panel => C_UNUSED_MSG_ID_PANEL
  );

  --==========================================================================================
  -- t_vvc_result, t_vvc_result_queue_element, t_vvc_response and shared_vvc_response :
  --
  -- - These are used for storing the result of the read/receive BFM commands issued by the VVC,
  -- - so that the result can be transported from the VVC to the sequencer via a
  --   a fetch_result() call as described in VVC_Framework_common_methods_QuickRef
  --
  -- - t_vvc_result matches the return value of read/receive procedure in the BFM.
  --   It can also be defined as a record if multiple return values shall be transported from the BFM
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
