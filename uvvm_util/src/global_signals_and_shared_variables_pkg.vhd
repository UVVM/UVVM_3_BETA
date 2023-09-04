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

use work.types_pkg.all;
use work.adaptations_pkg.all;
use work.protected_types_pkg.all;

package global_signals_and_shared_variables_pkg is

  -------------------------------------------------------------------------
  -- Generic package instantiations
  -------------------------------------------------------------------------

  -- Protected type: boolean
  package protected_boolean_pkg is new work.protected_generic_types_pkg
    generic map(t_generic_element => boolean,
                c_generic_default => false);
  use protected_boolean_pkg.all;

  -- Protected type: postive
  package protected_positive_pkg is new work.protected_generic_types_pkg
    generic map(t_generic_element => positive,
                c_generic_default => 1);
  use protected_positive_pkg.all;

  -- Protected type: t_sync_flag_record_array
  subtype t_sync_flag_record_array_constrained is t_sync_flag_record_array(1 to C_NUM_SYNC_FLAGS);
  constant C_DEFAULT_SYNC_FLAG_RECORD_ARRAY : t_sync_flag_record_array(1 to C_NUM_SYNC_FLAGS) := (others => C_SYNC_FLAG_DEFAULT);
  package protected_sync_flag_record_array is new work.protected_generic_types_pkg
    generic map(t_generic_element => t_sync_flag_record_array_constrained,
                c_generic_default => C_DEFAULT_SYNC_FLAG_RECORD_ARRAY);
  use protected_sync_flag_record_array.all;

  package protected_msg_id_panel_pkg is new work.protected_generic_types_pkg
    generic map(t_generic_element => t_msg_id_panel,
                c_generic_default => C_MSG_ID_PANEL_DEFAULT);
  use protected_msg_id_panel_pkg.all;

  -- Protected type: t_alert_attention
  package protected_alert_attention is new work.protected_generic_types_pkg
    generic map(t_generic_element => t_alert_attention,
                c_generic_default => C_DEFAULT_ALERT_ATTENTION);
  use protected_alert_attention.all;

  -- Protected type: t_alert_countert
  package protected_alert_counters is new work.protected_generic_types_pkg
    generic map(t_generic_element => t_alert_counters,
                c_generic_default => C_DEFAULT_STOP_LIMIT);
  use protected_alert_counters.all;

  -- Protected type: t_waveview_log_hdr
  package protected_waveview_log_hdr is new work.protected_generic_types_pkg
    generic map(t_generic_element => t_waveview_log_hdr,
                c_generic_default => C_WAVEVIEW_LOG_HDR_DEFAULT);
  use protected_waveview_log_hdr.all;

  -- Protected type: t_current_log_hdr
  package protected_current_log_hdr is new work.protected_generic_types_pkg
    generic map(t_generic_element => t_current_log_hdr,
                c_generic_default => C_CURRENT_LOG_HDR_DEFAULT);
  use protected_current_log_hdr.all;

  -- Protected type: t_uvvm_status
  package protected_uvvm_status is new work.protected_generic_types_pkg
    generic map(t_generic_element => t_uvvm_status,
                c_generic_default => C_UVVM_STATUS_DEFAULT);
  use protected_uvvm_status.all;

  -- Protected type: t_log_destination
  package protected_log_destination_pkg is new work.protected_generic_types_pkg
    generic map(t_generic_element => t_log_destination,
                c_generic_default => CONSOLE_AND_LOG);
  use protected_log_destination_pkg.all;

  -- Protected type: t_log_deprecate_list
  constant C_DEPRECATE_LIST_DEFAULT : t_deprecate_list := (others => (others => ' '));
  package protected_deprecate_list_pkg is new work.protected_generic_types_pkg
    generic map(t_generic_element => t_deprecate_list,
                c_generic_default => C_DEPRECATE_LIST_DEFAULT);
  use protected_deprecate_list_pkg.all;

  -------------------------------------------------------------------------
  -- Shared variables
  -------------------------------------------------------------------------
  shared variable shared_initialised_util           : protected_boolean_pkg.t_prot_generic_array;
  shared variable shared_msg_id_panel               : protected_msg_id_panel_pkg.t_prot_generic_array;
  shared variable shared_log_file_name_is_set       : protected_boolean_pkg.t_prot_generic_array;
  shared variable shared_alert_file_name_is_set     : protected_boolean_pkg.t_prot_generic_array;
  shared variable shared_warned_time_stamp_trunc    : protected_boolean_pkg.t_prot_generic_array;
  shared variable shared_warned_rand_time_res       : protected_boolean_pkg.t_prot_generic_array;
  shared variable shared_alert_attention            : protected_alert_attention.t_prot_generic_array;
  shared variable shared_stop_limit                 : protected_alert_counters.t_prot_generic_array;
  --shared variable shared_log_hdr_for_waveview      	: string(1 to C_LOG_HDR_FOR_WAVEVIEW_WIDTH);   -- skip, will be a signal
  shared variable shared_log_hdr_for_waveview       : protected_waveview_log_hdr.t_prot_generic;
  shared variable shared_current_log_hdr            : protected_current_log_hdr.t_prot_generic_array;
  shared variable shared_seed1                      : protected_positive_pkg.t_prot_generic_array;
  shared variable shared_seed2                      : protected_positive_pkg.t_prot_generic_array;
  shared variable shared_flag_array                 : protected_sync_flag_record_array.t_prot_generic_array;
  shared variable shared_semaphore                  : t_prot_semaphore;
  shared variable shared_broadcast_semaphore        : t_prot_semaphore;
  shared variable shared_response_semaphore         : t_prot_semaphore;
  shared variable shared_uvvm_status                : protected_uvvm_status.t_prot_generic_array;
  shared variable shared_covergroup_status          : t_prot_covergroup_status;
  shared variable shared_default_log_destination    : protected_log_destination_pkg.t_prot_generic_array;
  shared variable shared_deprecated_subprogram_list : protected_deprecate_list_pkg.t_prot_generic_array;

  -------------------------------------------------------------------------
  -- Global signals
  -------------------------------------------------------------------------
  signal global_trigger : std_logic := 'L';
  signal global_barrier : std_logic := 'X';

end package global_signals_and_shared_variables_pkg;
