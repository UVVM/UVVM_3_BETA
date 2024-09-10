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

use work.axi_bfm_pkg.all;

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
    WRITE, READ, CHECK
  );

  -- Constants for the maximum sizes to use in this VVC. Can be modified in adaptations_pkg.
  constant C_VVC_CMD_MAX_BURST_WORDS        : natural := C_AXI_VVC_CMD_MAX_BURST_WORDS;
  constant C_VVC_CMD_DATA_MAX_LENGTH        : natural := C_AXI_VVC_CMD_DATA_MAX_LENGTH;
  constant C_VVC_CMD_ADDR_MAX_LENGTH        : natural := C_AXI_VVC_CMD_ADDR_MAX_LENGTH;
  constant C_VVC_CMD_ID_MAX_LENGTH          : natural := C_AXI_VVC_CMD_ID_MAX_LENGTH;
  constant C_VVC_CMD_USER_MAX_LENGTH        : natural := C_AXI_VVC_CMD_USER_MAX_LENGTH;
  constant C_VVC_CMD_BYTE_ENABLE_MAX_LENGTH : natural := C_VVC_CMD_DATA_MAX_LENGTH / 8;
  constant C_VVC_CMD_STRING_MAX_LENGTH      : natural := C_AXI_VVC_CMD_STRING_MAX_LENGTH;
  constant C_VVC_MAX_INSTANCE_NUM           : natural := C_AXI_VVC_MAX_INSTANCE_NUM;

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
    vvc_meta           : t_vvc_meta;
    transaction_status : t_transaction_status;
  end record;

  constant C_BASE_TRANSACTION_SET_DEFAULT : t_base_transaction := (
    operation          => NO_OPERATION,
    vvc_meta           => C_VVC_META_DEFAULT,
    transaction_status => INACTIVE
  );

  type t_arw_transaction is record
    operation          : t_operation;
    arwid              : std_logic_vector(C_VVC_CMD_ID_MAX_LENGTH - 1 downto 0);
    arwaddr            : unsigned(C_VVC_CMD_ADDR_MAX_LENGTH - 1 downto 0);
    arwlen             : unsigned(7 downto 0);
    arwsize            : integer range 1 to 128;
    arwburst           : t_axburst;
    arwlock            : t_axlock;
    arwcache           : std_logic_vector(3 downto 0);
    arwprot            : t_axprot;
    arwqos             : std_logic_vector(3 downto 0);
    arwregion          : std_logic_vector(3 downto 0);
    arwuser            : std_logic_vector(C_VVC_CMD_USER_MAX_LENGTH - 1 downto 0);
    vvc_meta           : t_vvc_meta;
    transaction_status : t_transaction_status;
  end record t_arw_transaction;

  constant C_ARW_TRANSACTION_DEFAULT : t_arw_transaction := (
    operation          => NO_OPERATION,
    arwid              => (others => '0'),
    arwaddr            => (others => '0'),
    arwlen             => (others => '0'),
    arwsize            => 4,
    arwburst           => INCR,
    arwlock            => NORMAL,
    arwcache           => (others => '0'),
    arwprot            => UNPRIVILEGED_NONSECURE_DATA,
    arwqos             => (others => '0'),
    arwregion          => (others => '0'),
    arwuser            => (others => '0'),
    vvc_meta           => C_VVC_META_DEFAULT,
    transaction_status => INACTIVE
  );

  type t_w_transaction is record
    operation          : t_operation;
    wdata              : t_slv_array(0 to C_VVC_CMD_MAX_BURST_WORDS - 1)(C_VVC_CMD_DATA_MAX_LENGTH - 1 downto 0);
    wstrb              : t_slv_array(0 to C_VVC_CMD_MAX_BURST_WORDS - 1)(C_VVC_CMD_BYTE_ENABLE_MAX_LENGTH - 1 downto 0);
    wuser              : t_slv_array(0 to C_VVC_CMD_MAX_BURST_WORDS - 1)(C_VVC_CMD_USER_MAX_LENGTH - 1 downto 0);
    vvc_meta           : t_vvc_meta;
    transaction_status : t_transaction_status;
  end record t_w_transaction;

  constant C_W_TRANSACTION_DEFAULT : t_w_transaction := (
    operation          => NO_OPERATION,
    wdata              => (others => (others => '0')),
    wstrb              => (others => (others => '0')),
    wuser              => (others => (others => '0')),
    vvc_meta           => C_VVC_META_DEFAULT,
    transaction_status => INACTIVE
  );

  type t_b_transaction is record
    operation          : t_operation;
    bid                : std_logic_vector(C_VVC_CMD_ID_MAX_LENGTH - 1 downto 0);
    bresp              : t_xresp;
    buser              : std_logic_vector(C_VVC_CMD_USER_MAX_LENGTH - 1 downto 0);
    vvc_meta           : t_vvc_meta;
    transaction_status : t_transaction_status;
  end record t_b_transaction;

  constant C_B_TRANSACTION_DEFAULT : t_b_transaction := (
    operation          => NO_OPERATION,
    bid                => (others => '0'),
    bresp              => OKAY,
    buser              => (others => '0'),
    vvc_meta           => C_VVC_META_DEFAULT,
    transaction_status => INACTIVE
  );

  type t_r_transaction is record
    operation          : t_operation;
    rid                : std_logic_vector(C_VVC_CMD_ID_MAX_LENGTH - 1 downto 0);
    rdata              : t_slv_array(0 to C_VVC_CMD_MAX_BURST_WORDS - 1)(C_VVC_CMD_DATA_MAX_LENGTH - 1 downto 0);
    rresp              : t_xresp_array(0 to C_VVC_CMD_MAX_BURST_WORDS - 1);
    ruser              : t_slv_array(0 to C_VVC_CMD_MAX_BURST_WORDS - 1)(C_VVC_CMD_USER_MAX_LENGTH - 1 downto 0);
    vvc_meta           : t_vvc_meta;
    transaction_status : t_transaction_status;
  end record t_r_transaction;

  constant C_R_TRANSACTION_DEFAULT : t_r_transaction := (
    operation          => NO_OPERATION,
    rid                => (others => '0'),
    rdata              => (others => (others => '0')),
    rresp              => (others => OKAY),
    ruser              => (others => (others => '0')),
    vvc_meta           => C_VVC_META_DEFAULT,
    transaction_status => INACTIVE
  );

  -- Transaction group
  type t_transaction_group is record
    bt_wr : t_base_transaction;
    bt_rd : t_base_transaction;
    st_aw : t_arw_transaction;
    st_w  : t_w_transaction;
    st_b  : t_b_transaction;
    st_ar : t_arw_transaction;
    st_r  : t_r_transaction;
  end record;

  constant C_TRANSACTION_GROUP_DEFAULT : t_transaction_group := (
    bt_wr => C_BASE_TRANSACTION_SET_DEFAULT,
    bt_rd => C_BASE_TRANSACTION_SET_DEFAULT,
    st_aw => C_ARW_TRANSACTION_DEFAULT,
    st_w  => C_W_TRANSACTION_DEFAULT,
    st_b  => C_B_TRANSACTION_DEFAULT,
    st_ar => C_ARW_TRANSACTION_DEFAULT,
    st_r  => C_R_TRANSACTION_DEFAULT
  );

  -- Global transaction info trigger signal
  type t_axi_transaction_trigger_array is array (natural range <>) of std_logic;
  signal global_axi_vvc_transaction_trigger : t_axi_transaction_trigger_array(0 to C_VVC_MAX_INSTANCE_NUM - 1) := (others => '0');

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
  shared variable shared_axi_vvc_transaction_info : work.protected_transaction_group_pkg.t_generic_array;
end package vvc_transaction_shared_variables_pkg;
