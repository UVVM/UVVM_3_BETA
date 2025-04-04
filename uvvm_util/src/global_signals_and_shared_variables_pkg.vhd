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
--  Generic package instantiations
--================================================================================================================================
----------------------------------------------------------------------
-- Protected type: boolean
----------------------------------------------------------------------
package protected_boolean_pkg is new work.protected_generic_types_pkg
  generic map(
    t_generic_element => boolean,
    c_generic_default => false
  );

----------------------------------------------------------------------
-- Protected type: positive
----------------------------------------------------------------------
package protected_positive_pkg is new work.protected_generic_types_pkg
  generic map(
    t_generic_element => positive,
    c_generic_default => 1
  );

----------------------------------------------------------------------
-- Protected type: t_sync_flag_record_array_constrained
----------------------------------------------------------------------
use work.types_pkg.all;
use work.adaptations_pkg.all;

package protected_sync_flag_record_array_pkg is new work.protected_generic_types_pkg
  generic map(
    t_generic_element => t_sync_flag_record_array_constrained,
    c_generic_default => C_DEFAULT_SYNC_FLAG_RECORD_ARRAY
  );

----------------------------------------------------------------------
-- Protected type: t_msg_id_panel
----------------------------------------------------------------------
use work.adaptations_pkg.all;

package protected_msg_id_panel_pkg is new work.protected_generic_types_pkg
  generic map(
    t_generic_element => t_msg_id_panel,
    c_generic_default => C_MSG_ID_PANEL_DEFAULT
  );

----------------------------------------------------------------------
-- Protected type: t_alert_attention
----------------------------------------------------------------------
use work.types_pkg.all;
use work.adaptations_pkg.all;

package protected_alert_attention_pkg is new work.protected_generic_types_pkg
  generic map(
    t_generic_element => t_alert_attention,
    c_generic_default => C_DEFAULT_ALERT_ATTENTION
  );

----------------------------------------------------------------------
-- Protected type: t_alert_counters
----------------------------------------------------------------------
use work.types_pkg.all;
use work.adaptations_pkg.all;

package protected_alert_counters_pkg is new work.protected_generic_types_pkg
  generic map(
    t_generic_element => t_alert_counters,
    c_generic_default => C_DEFAULT_STOP_LIMIT
  );

----------------------------------------------------------------------
-- Protected type: t_waveview_log_hdr
----------------------------------------------------------------------
use work.types_pkg.all;

package protected_waveview_log_hdr_pkg is new work.protected_generic_types_pkg
  generic map(
    t_generic_element => t_waveview_log_hdr,
    c_generic_default => C_WAVEVIEW_LOG_HDR_DEFAULT
  );

----------------------------------------------------------------------
-- Protected type: t_current_log_hdr
----------------------------------------------------------------------
use work.types_pkg.all;

package protected_current_log_hdr_pkg is new work.protected_generic_types_pkg
  generic map(
    t_generic_element => t_current_log_hdr,
    c_generic_default => C_CURRENT_LOG_HDR_DEFAULT
  );

----------------------------------------------------------------------
-- Protected type: t_uvvm_status
----------------------------------------------------------------------
use work.types_pkg.all;

package protected_uvvm_status_pkg is new work.protected_generic_types_pkg
  generic map(
    t_generic_element => t_uvvm_status,
    c_generic_default => C_UVVM_STATUS_DEFAULT
  );

----------------------------------------------------------------------
-- Protected type: t_log_destination
----------------------------------------------------------------------
use work.types_pkg.all;

package protected_log_destination_pkg is new work.protected_generic_types_pkg
  generic map(
    t_generic_element => t_log_destination,
    c_generic_default => CONSOLE_AND_LOG
  );

-----------------------------------------------------------------------
-- Protected type: t_deprecate_list
---------------------------------------------------------------------
use work.types_pkg.all;

package protected_deprecate_list_pkg is new work.protected_generic_types_pkg
  generic map(
    t_generic_element => t_deprecate_list,
    c_generic_default => C_DEPRECATE_LIST_DEFAULT
  );


--================================================================================================================================
--  Global signals and shared variables package
--================================================================================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.types_pkg.all;
use work.adaptations_pkg.all;
use work.protected_types_pkg.all;
use work.protected_boolean_pkg.all;
use work.protected_positive_pkg.all;
use work.protected_sync_flag_record_array_pkg.all;
use work.protected_msg_id_panel_pkg.all;
use work.protected_alert_attention_pkg.all;
use work.protected_alert_counters_pkg.all;
use work.protected_waveview_log_hdr_pkg.all;
use work.protected_current_log_hdr_pkg.all;
use work.protected_uvvm_status_pkg.all;
use work.protected_log_destination_pkg.all;
use work.protected_deprecate_list_pkg.all;

package global_signals_and_shared_variables_pkg is

  -- Global signals
  signal global_trigger : std_logic := 'L';
  signal global_barrier : std_logic := 'X';

  -- Shared variables
  shared variable shared_uvvm_status  : work.protected_uvvm_status_pkg.t_generic;
  shared variable shared_msg_id_panel : work.protected_msg_id_panel_pkg.t_generic;

  -- Randomization seeds
  shared variable shared_rand_seeds_register : t_seeds;

  -- UVVM internal shared variables
  shared variable shared_initialised_util           : work.protected_boolean_pkg.t_generic;
  shared variable shared_log_file_name_is_set       : work.protected_boolean_pkg.t_generic;
  shared variable shared_alert_file_name_is_set     : work.protected_boolean_pkg.t_generic;
  shared variable shared_warned_time_stamp_trunc    : work.protected_boolean_pkg.t_generic;
  shared variable shared_warned_rand_time_res       : work.protected_boolean_pkg.t_generic;
  shared variable shared_alert_attention            : work.protected_alert_attention_pkg.t_generic;
  shared variable shared_stop_limit                 : work.protected_alert_counters_pkg.t_generic;
  shared variable shared_log_hdr_for_waveview       : work.protected_waveview_log_hdr_pkg.t_generic;
  shared variable shared_current_log_hdr            : work.protected_current_log_hdr_pkg.t_generic;
  shared variable shared_seed1                      : work.protected_positive_pkg.t_generic;
  shared variable shared_seed2                      : work.protected_positive_pkg.t_generic;
  shared variable shared_flag_array                 : work.protected_sync_flag_record_array_pkg.t_generic;
  shared variable shared_semaphore                  : t_semaphore;
  shared variable shared_broadcast_semaphore        : t_semaphore;
  shared variable shared_response_semaphore         : t_semaphore;
  shared variable shared_covergroup_status          : t_covergroup_status;
  shared variable shared_sb_activity_register       : t_sb_activity;
  shared variable shared_default_log_destination    : work.protected_log_destination_pkg.t_generic;
  shared variable shared_deprecated_subprogram_list : work.protected_deprecate_list_pkg.t_generic;

end package global_signals_and_shared_variables_pkg;
