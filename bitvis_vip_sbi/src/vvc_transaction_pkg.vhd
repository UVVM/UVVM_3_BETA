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
    WRITE, READ, CHECK, POLL_UNTIL
  );

  -- Constants for the maximum sizes to use in this VVC. Can be modified in adaptations_pkg.
  constant C_VVC_CMD_DATA_MAX_LENGTH   : natural := C_SBI_VVC_CMD_DATA_MAX_LENGTH;
  constant C_VVC_CMD_ADDR_MAX_LENGTH   : natural := C_SBI_VVC_CMD_ADDR_MAX_LENGTH;
  constant C_VVC_CMD_STRING_MAX_LENGTH : natural := C_SBI_VVC_CMD_STRING_MAX_LENGTH;
  constant C_VVC_MAX_INSTANCE_NUM      : natural := C_SBI_VVC_MAX_INSTANCE_NUM;

  --==========================================================================================
  -- Transaction Info types, constants and global signal
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

  -- Base transaction type
  type t_base_transaction is record
    operation          : t_operation;
    address            : unsigned(C_VVC_CMD_ADDR_MAX_LENGTH - 1 downto 0); -- Max width may be increased if required
    data               : std_logic_vector(C_VVC_CMD_DATA_MAX_LENGTH - 1 downto 0);
    vvc_meta           : t_vvc_meta;
    transaction_status : t_transaction_status;
  end record;

  constant C_BASE_TRANSACTION_SET_DEFAULT : t_base_transaction := (
    operation          => NO_OPERATION,
    address            => (others => '0'),
    data               => (others => '0'),
    vvc_meta           => C_VVC_META_DEFAULT,
    transaction_status => INACTIVE
  );

  -- Compound transaction  type
  type t_compound_transaction is record
    operation          : t_operation;
    address            : unsigned(C_VVC_CMD_ADDR_MAX_LENGTH - 1 downto 0); -- Max width may be increased if required
    data               : std_logic_vector(C_VVC_CMD_DATA_MAX_LENGTH - 1 downto 0);
    randomisation      : t_randomisation;
    num_words          : natural;
    max_polls          : integer;
    vvc_meta           : t_vvc_meta;
    transaction_status : t_transaction_status;
  end record;

  constant C_COMPOUND_TRANSACTION_SET_DEFAULT : t_compound_transaction := (
    operation          => NO_OPERATION,
    address            => (others => '0'),
    data               => (others => '0'),
    randomisation      => NA,
    num_words          => 1,
    max_polls          => 1,
    vvc_meta           => C_VVC_META_DEFAULT,
    transaction_status => INACTIVE
  );

  -- Transaction group
  type t_transaction_group is record
    bt : t_base_transaction;
    ct : t_compound_transaction;
  end record;

  constant C_TRANSACTION_GROUP_DEFAULT : t_transaction_group := (
    bt => C_BASE_TRANSACTION_SET_DEFAULT,
    ct => C_COMPOUND_TRANSACTION_SET_DEFAULT
  );

  -- Global transaction info trigger signal
  type t_sbi_transaction_trigger_array is array (natural range <>) of std_logic;
  signal global_sbi_vvc_transaction_trigger : t_sbi_transaction_trigger_array(0 to C_VVC_MAX_INSTANCE_NUM - 1) := (others => '0');

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
  shared variable shared_sbi_vvc_transaction_info : work.protected_transaction_group_pkg.t_generic_array;
end package vvc_transaction_shared_variables_pkg;
