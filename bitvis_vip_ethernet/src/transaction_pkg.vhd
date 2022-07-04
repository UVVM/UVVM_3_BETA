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

use work.support_pkg.all;

--=================================================================================================
--=================================================================================================
package transaction_pkg is

    --==========================================================================================
    -- t_operation
    -- - VVC and BFM operations
    --==========================================================================================
    type t_operation is (
        NO_OPERATION,
        AWAIT_COMPLETION,
        AWAIT_ANY_COMPLETION,
        ENABLE_LOG_MSG,
        DISABLE_LOG_MSG,
        FLUSH_COMMAND_QUEUE,
        FETCH_RESULT,
        INSERT_DELAY,
        TERMINATE_CURRENT_COMMAND,
        -- VVC local
        TRANSMIT,
        RECEIVE,
        EXPECT
    );

    -- Constants for the maximum sizes to use in this VVC.
    -- You can create VVCs with smaller sizes than these constants, but not larger.
    constant C_VVC_CMD_STRING_MAX_LENGTH : natural := 300;

    --==========================================================================================
    --
    -- Transaction info types, constants and global signal
    --
    --==========================================================================================

    -- Transaction status
    type t_transaction_status is (INACTIVE, IN_PROGRESS, FAILED, SUCCEEDED);

    constant C_TRANSACTION_STATUS_DEFAULT : t_transaction_status := INACTIVE;

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
        ethernet_frame     : t_ethernet_frame;
        vvc_meta           : t_vvc_meta;
        transaction_status : t_transaction_status;
    end record;

    constant C_BASE_TRANSACTION_SET_DEFAULT : t_base_transaction := (
        operation          => NO_OPERATION,
        ethernet_frame     => C_ETHERNET_FRAME_DEFAULT,
        vvc_meta           => C_VVC_META_DEFAULT,
        transaction_status => C_TRANSACTION_STATUS_DEFAULT
    );

    -- Transaction group
    type t_transaction_group is record
        bt : t_base_transaction;
    end record;

    constant C_TRANSACTION_GROUP_DEFAULT : t_transaction_group := (
        bt => C_BASE_TRANSACTION_SET_DEFAULT
    );

    subtype t_sub_channel is t_channel range RX to TX;

    -- Global transaction info trigger signal
    type t_ethernet_transaction_trigger_array is array (t_sub_channel range <>, natural range <>) of std_logic;
    signal global_ethernet_vvc_transaction_trigger : t_ethernet_transaction_trigger_array(t_sub_channel'left to t_sub_channel'right, 0 to C_MAX_VVC_INSTANCE_NUM - 1) := (others => (others => '0'));

    -- Shared transaction info variable
    package protected_vvc_transaction_info_pkg is new uvvm_util.protected_generic_types_pkg
        generic map(
            t_generic_element => t_transaction_group,
            c_generic_default           => C_TRANSACTION_GROUP_DEFAULT);
    use protected_vvc_transaction_info_pkg.all;
    shared variable shared_ethernet_vvc_transaction_info : protected_vvc_transaction_info_pkg.t_protected_generic_array;

end package transaction_pkg;