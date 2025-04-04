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
--  VVC transaction package
--================================================================================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

use work.axistream_bfm_pkg.all;

package vvc_transaction_pkg is

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
    TRANSMIT, RECEIVE, EXPECT
  );

  -- Constants for the maximum sizes to use in this VVC. Can be modified in adaptations_pkg.
  constant C_VVC_CMD_DATA_MAX_BYTES    : natural := C_AXISTREAM_VVC_CMD_DATA_MAX_BYTES;
  constant C_VVC_CMD_MAX_WORD_LENGTH   : natural := C_AXISTREAM_VVC_CMD_MAX_WORD_LENGTH;
  constant C_VVC_CMD_DATA_MAX_WORDS    : natural := C_VVC_CMD_DATA_MAX_BYTES;
  constant C_VVC_CMD_STRING_MAX_LENGTH : natural := C_AXISTREAM_VVC_CMD_STRING_MAX_LENGTH;
  constant C_VVC_MAX_INSTANCE_NUM      : natural := C_AXISTREAM_VVC_MAX_INSTANCE_NUM;

  --==========================================================================================
  -- Transaction info types, constants and global signal
  --==========================================================================================
  -- VVC Meta
  type t_vvc_meta is record
    msg     : string(1 to C_VVC_CMD_STRING_MAX_LENGTH);
    cmd_idx : integer;
  end record;

  constant C_VVC_META_DEFAULT : t_vvc_meta := (
    msg     => (others => ' '),
    cmd_idx => -1
  );

  -- Base transaction
  type t_base_transaction is record
    operation          : t_operation;
    data_array         : t_slv_array(0 to C_VVC_CMD_DATA_MAX_BYTES - 1)(7 downto 0);
    data_length        : integer range 0 to C_VVC_CMD_DATA_MAX_BYTES;
    user_array         : t_user_array(0 to C_VVC_CMD_DATA_MAX_WORDS - 1);
    strb_array         : t_strb_array(0 to C_VVC_CMD_DATA_MAX_WORDS - 1);
    id_array           : t_id_array(0 to C_VVC_CMD_DATA_MAX_WORDS - 1);
    dest_array         : t_dest_array(0 to C_VVC_CMD_DATA_MAX_WORDS - 1);
    vvc_meta           : t_vvc_meta;
    transaction_status : t_transaction_status;
  end record;

  constant C_BASE_TRANSACTION_SET_DEFAULT : t_base_transaction := (
    operation          => NO_OPERATION,
    data_array         => (others => (others => '0')),
    data_length        => 0,
    user_array         => (others => (others => '0')),
    strb_array         => (others => (others => '0')),
    id_array           => (others => (others => '0')),
    dest_array         => (others => (others => '0')),
    vvc_meta           => C_VVC_META_DEFAULT,
    transaction_status => INACTIVE
  );

  -- Transaction group
  type t_transaction_group is record
    bt : t_base_transaction;
  end record;

  constant C_TRANSACTION_GROUP_DEFAULT : t_transaction_group := (
    bt => C_BASE_TRANSACTION_SET_DEFAULT
  );

  -- Global transaction info trigger signal
  type t_axistream_transaction_trigger_array is array (natural range <>) of std_logic;
  signal global_axistream_vvc_transaction_trigger : t_axistream_transaction_trigger_array(0 to C_VVC_MAX_INSTANCE_NUM - 1) := (others => '0');

end package vvc_transaction_pkg;

--================================================================================================================================
--  Generic package instantiations
--================================================================================================================================
----------------------------------------------------------------------
-- Protected type: t_transaction_group
----------------------------------------------------------------------
library uvvm_util;
use work.vvc_transaction_pkg.all;

package protected_transaction_group_pkg is new uvvm_util.protected_generic_types_pkg
  generic map(
    t_generic_element  => t_transaction_group,
    c_generic_default  => C_TRANSACTION_GROUP_DEFAULT,
    c_max_instance_num => C_VVC_MAX_INSTANCE_NUM
  );

--================================================================================================================================
--  Shared variables package
--================================================================================================================================
use work.protected_transaction_group_pkg.all;

package vvc_transaction_shared_variables_pkg is
  shared variable shared_axistream_vvc_transaction_info : work.protected_transaction_group_pkg.t_generic_array;
end package vvc_transaction_shared_variables_pkg;
