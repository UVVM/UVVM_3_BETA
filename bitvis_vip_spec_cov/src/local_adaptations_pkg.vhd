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

package local_adaptations_pkg is

  -- Max length of line read from CSV file, used in csv_file_reader_pkg.vhd
  constant C_CSV_FILE_MAX_LINE_LENGTH : positive  := 256;
  -- Delimiter when reading and writing CSV files.
  constant C_CSV_DELIMITER            : character := ',';

  -------------------------------------------------------------------------------
  -- VIP configuration record
  -------------------------------------------------------------------------------
  type t_spec_cov_config is record
    missing_req_label_severity : t_alert_level; -- Alert level used when the tick_off_req_cov() procedure does not find the specified
                                                -- requirement label in the requirement list.
    csv_delimiter              : character; -- Character used as delimiter in the CSV files. Default is ",".
    max_requirements           : natural; -- Maximum number of requirements in the req_map file used in initialize_req_cov().
    max_testcases_per_req      : natural; -- Max number of testcases allowed per requirement. 
    csv_max_line_length        : positive; -- Max length of each line in any CSV file.
  end record;

  constant C_SPEC_COV_CONFIG_DEFAULT : t_spec_cov_config := (
    missing_req_label_severity => TB_WARNING,
    csv_delimiter              => C_CSV_DELIMITER,
    max_requirements           => 1000,
    max_testcases_per_req      => 20,
    csv_max_line_length        => C_CSV_FILE_MAX_LINE_LENGTH
  );

  -- Shared variable for configuring the Spec Cov VIP from the testbench sequencer.
  package protected_spec_cov_config_pkg is new uvvm_util.protected_generic_types_pkg --v3
    generic map(
      t_generic_element => t_spec_cov_config,
      c_generic_default => C_SPEC_COV_CONFIG_DEFAULT);
  use protected_spec_cov_config_pkg.all;

  --shared variable shared_spec_cov_config  : t_spec_cov_config := C_SPEC_COV_CONFIG_DEFAULT;
  shared variable shared_spec_cov_config : protected_spec_cov_config_pkg.t_prot_generic; --v3

  --v3 edit
  impure function get_max_testcases_per_req(
    VOID : t_void
  ) return natural;

  -- v3 edit
  impure function get_max_requirements(
    VOID : t_void
  ) return natural;

end package local_adaptations_pkg;

package body local_adaptations_pkg is

  --v3 edit
  -- Function for extracting the max_testcases_per_req element from the shared_spec_cov_config PT variable.
  impure function get_max_testcases_per_req(
    VOID : t_void
  ) return natural is
    variable v_shared_spec_cov_config : t_spec_cov_config;
    variable v_max_testcases_per_req  : natural;
  begin
    v_shared_spec_cov_config := shared_spec_cov_config.get(VOID);
    v_max_testcases_per_req  := v_shared_spec_cov_config.max_testcases_per_req;
    return v_max_testcases_per_req;
  end function get_max_testcases_per_req;

  -- Function for extracting the max_requirements element from the shared_spec_cov_config PT variable.
  impure function get_max_requirements(
    VOID : t_void
  ) return natural is
    variable v_shared_spec_cov_config : t_spec_cov_config;
    variable v_max_requirements       : natural;
  begin
    v_shared_spec_cov_config := shared_spec_cov_config.get(VOID);
    v_max_requirements       := v_shared_spec_cov_config.max_requirements;
    return v_max_requirements;
  end function get_max_requirements;

end package body local_adaptations_pkg;
