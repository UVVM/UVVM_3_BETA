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
-- Protected type: t_spec_cov_config
----------------------------------------------------------------------
library uvvm_util;
use uvvm_util.types_pkg.all;
use uvvm_util.adaptations_pkg.all;

package protected_spec_cov_config_pkg is new uvvm_util.protected_generic_types_pkg
  generic map(
    t_generic_element => t_spec_cov_config,
    c_generic_default => C_SPEC_COV_CONFIG_DEFAULT
  );

----------------------------------------------------------------------
-- Protected type: testcase_name
----------------------------------------------------------------------
library uvvm_util;
use uvvm_util.adaptations_pkg.all;

package protected_testcase_name_pkg is new uvvm_util.protected_generic_types_pkg
  generic map(
    t_generic_element => string(1 to C_SPEC_COV_CONFIG_DEFAULT.csv_max_line_length),
    c_generic_default => (others => NUL)
  );

----------------------------------------------------------------------
-- Protected type: testcase_passed
----------------------------------------------------------------------
library uvvm_util;

package protected_testcase_passed_pkg is new uvvm_util.protected_generic_types_pkg
  generic map(
    t_generic_element => boolean,
    c_generic_default => false
  );

----------------------------------------------------------------------
-- Protected type: requirement_file_exists
----------------------------------------------------------------------
library uvvm_util;

package protected_requirement_file_exists_pkg is new uvvm_util.protected_generic_types_pkg
  generic map(
    t_generic_element => boolean,
    c_generic_default => false
  );

----------------------------------------------------------------------
-- Protected type: req_cov_initialized
----------------------------------------------------------------------
library uvvm_util;

package protected_req_cov_initialized_pkg is new uvvm_util.protected_generic_types_pkg
  generic map(
    t_generic_element => boolean,
    c_generic_default => false
  );

--================================================================================================================================
-- Specification coverage package
--================================================================================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

use std.textio.all;

use work.csv_file_reader_pkg.all;
use work.protected_spec_cov_config_pkg.all;
use work.protected_testcase_name_pkg.all;
use work.protected_testcase_passed_pkg.all;
use work.protected_requirement_file_exists_pkg.all;
use work.protected_req_cov_initialized_pkg.all;

package spec_cov_pkg is

  file RESULT_FILE : text;

  -- Shared variable for configuring the Spec Cov VIP from the testbench sequencer.
  shared variable shared_spec_cov_config : work.protected_spec_cov_config_pkg.t_generic;

  --==========================================================================================
  -- Public procedures
  --==========================================================================================
  procedure initialize_req_cov(
    constant testcase         : string;
    constant req_list_file    : string;
    constant partial_cov_file : string
  );
  -- Overloading procedure
  procedure initialize_req_cov(
    constant testcase         : string;
    constant partial_cov_file : string
  );

  procedure tick_off_req_cov(
    constant requirement        : string;
    constant requirement_status : t_test_status    := NA;
    constant msg                : string           := "";
    constant tickoff_extent     : t_extent_tickoff := LIST_SINGLE_TICKOFF;
    constant scope              : string           := C_SCOPE
  );

  procedure cond_tick_off_req_cov(
    constant requirement        : string;
    constant requirement_status : t_test_status    := NA;
    constant msg                : string           := "";
    constant tickoff_extent     : t_extent_tickoff := LIST_SINGLE_TICKOFF;
    constant scope              : string           := C_SCOPE
  );

  procedure disable_cond_tick_off_req_cov(
    constant requirement : string
  );

  procedure enable_cond_tick_off_req_cov(
    constant requirement : string
  );

  procedure finalize_req_cov(
    constant VOID : t_void
  );

  --==========================================================================================
  -- Private internal functions and procedures
  --==========================================================================================
  procedure priv_log_entry(
    constant index : natural
  );

  procedure priv_read_and_parse_csv_file(
    constant req_list_file : string
  );

  procedure priv_initialize_result_file(
    constant file_name : string
  );

  impure function priv_get_description(
    requirement : string
  ) return string;

  impure function priv_requirement_exists(
    requirement : string
  ) return boolean;

  impure function priv_get_requirement_status(
    requirement : string
  ) return t_test_status;

  procedure priv_set_requirement_status(
    constant requirement : string;
    constant status      : t_test_status
  );

  impure function priv_get_num_requirement_tick_offs(
    requirement : string
  ) return natural;

  procedure priv_inc_num_requirement_tick_offs(
    constant requirement : string
  );

  function priv_test_status_to_string(
    test_status : t_test_status
  ) return string;

  impure function priv_get_summary_string
  return string;

  procedure priv_set_default_testcase_name(
    constant testcase : string
  );

  impure function priv_get_default_testcase_name
  return string;

  impure function priv_find_string_length(
    search_string : string
  ) return natural;

  impure function priv_get_requirement_name_length(
    requirement : string)
  return natural;

  impure function priv_req_listed_in_disabled_tick_off_array(
    requirement : string
  ) return boolean;

end package spec_cov_pkg;

--=================================================================================================
--=================================================================================================
--=================================================================================================

package body spec_cov_pkg is

  constant C_FAIL_STRING : string := "FAIL";
  constant C_PASS_STRING : string := "PASS";

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

  --type t_line_vector is array(0 to shared_spec_cov_config.max_testcases_per_req-1) of line;
  type t_line_vector is array (0 to get_max_testcases_per_req(VOID) - 1) of line; --v3

  type t_requirement_entry is record
    valid        : boolean;
    requirement  : line;
    description  : line;
    num_tcs      : natural;
    tc_list      : t_line_vector;
    num_tickoffs : natural;
    status       : t_test_status;
  end record;

  type t_requirement_entry_array is array (natural range <>) of t_requirement_entry;

  --==========================================================================================
  -- Protected requirement_array type
  --==========================================================================================
  type t_requirement_array is protected

    procedure deallocate_requirement(
      constant index : in natural
    );

    procedure deallocate_description(
      constant index : in natural
    );

    procedure deallocate_tc_list(
      constant array_index   : in natural;
      constant tc_list_index : in natural
    );

    procedure set_valid(
      constant index : in natural;
      constant value : boolean
    );

    procedure set_requirement(
      constant index : in natural;
      constant value : in string
    );

    procedure set_description(
      constant index : in natural;
      constant value : in string
    );

    procedure set_num_tcs(
      constant index : in natural;
      constant value : in natural
    );

    procedure set_tc_list_element(
      constant array_index   : in natural;
      constant tc_list_index : in natural;
      constant value         : in string
    );

    procedure set_num_tickoffs(
      constant index : in natural;
      constant value : in natural
    );

    procedure set_status(
      constant index  : in natural;
      constant status : in t_test_status
    );

    impure function get_valid(
      index : natural
    ) return boolean;

    impure function get_requirement(
      index : natural
    ) return string;

    impure function get_description(
      index : natural
    ) return string;

    impure function get_num_tcs(
      index : natural
    ) return natural;

    impure function get_tc_list_element(
      array_index   : natural;
      tc_list_index : natural
    ) return string;

    impure function get_num_tickoffs(
      index : natural
    ) return natural;

    impure function get_status(
      index : natural
    ) return t_test_status;

  end protected t_requirement_array;

  --==========================================================================================
  -- Protected requirement_in_array type
  --==========================================================================================
  type t_requirements_in_array is protected

    procedure set(
      constant value : in natural
    );

    impure function get(
      VOID : t_void
    ) return natural;
  end protected t_requirements_in_array;

  --==========================================================================================
  -- Protected disabled_tick_off_array type
  --==========================================================================================
  type t_disabled_tick_off_array is protected
    procedure set(
      constant index : in natural;
      constant value : in string(1 to C_SPEC_COV_CONFIG_DEFAULT.csv_max_line_length)
    );

    impure function get(
      index : natural
    ) return string;

    impure function get_length(
      VOID : t_void
    ) return integer;

  end protected;

  --==========================================================================================
  -- Protected requirement_array type
  --==========================================================================================
  type t_requirement_array is protected body

    variable priv_requirement_array : t_requirement_entry_array(0 to get_max_requirements(VOID));

    --
    -- Deallocation of requirement_array entry elements
    --
    procedure deallocate_requirement(
      constant index : in natural
    ) is
    begin
      deallocate(priv_requirement_array(index).requirement);
    end procedure deallocate_requirement;

    procedure deallocate_description(
      constant index : in natural
    ) is
    begin
      deallocate(priv_requirement_array(index).description);
    end procedure deallocate_description;

    procedure deallocate_tc_list(
      constant array_index   : in natural;
      constant tc_list_index : in natural
    ) is
    begin
      deallocate(priv_requirement_array(array_index).tc_list(tc_list_index));
    end procedure deallocate_tc_list;

    --
    -- Setters for requirement_array entry elements
    --
    procedure set_valid(
      constant index : in natural;
      constant value : boolean
    ) is
    begin
      priv_requirement_array(index).valid := value;
    end procedure set_valid;

    procedure set_requirement(
      constant index : in natural;
      constant value : in string
    ) is
    begin
      priv_requirement_array(index).requirement := new string'(value);
    end procedure set_requirement;

    procedure set_description(
      constant index : in natural;
      constant value : in string
    ) is
    begin
      priv_requirement_array(index).description := new string'(value);
    end procedure set_description;

    procedure set_num_tcs(
      constant index : in natural;
      constant value : in natural
    ) is
    begin
      priv_requirement_array(index).num_tcs := value;
    end procedure set_num_tcs;

    procedure set_tc_list_element(
      constant array_index   : in natural;
      constant tc_list_index : in natural;
      constant value         : in string
    ) is
    begin
      priv_requirement_array(array_index).tc_list(tc_list_index) := new string'(value);
    end procedure set_tc_list_element;

    procedure set_num_tickoffs(
      constant index : in natural;
      constant value : in natural
    ) is
    begin
      priv_requirement_array(index).num_tickoffs := value;
    end procedure set_num_tickoffs;

    procedure set_status(
      constant index  : in natural;
      constant status : in t_test_status
    ) is
    begin
      priv_requirement_array(index).status := status;
    end procedure set_status;

    --
    -- Getters for requirement_array entry elements
    --
    impure function get_valid(
      index : natural
    ) return boolean is
    begin
      return priv_requirement_array(index).valid;
    end function get_valid;

    impure function get_requirement(
      index : natural
    ) return string is
    begin
      return priv_requirement_array(index).requirement.all;
    end function get_requirement;

    impure function get_description(
      index : natural
    ) return string is
    begin
      return priv_requirement_array(index).description.all;
    end function get_description;

    impure function get_num_tcs(
      index : natural
    ) return natural is
    begin
      return priv_requirement_array(index).num_tcs;
    end function get_num_tcs;

    impure function get_tc_list_element(
      array_index   : natural;
      tc_list_index : natural
    ) return string is
    begin
      return priv_requirement_array(array_index).tc_list(tc_list_index).all;
    end function get_tc_list_element;

    impure function get_num_tickoffs(
      index : natural
    ) return natural is
    begin
      return priv_requirement_array(index).num_tickoffs;
    end function get_num_tickoffs;

    impure function get_status(
      index : natural
    ) return t_test_status is
    begin
      return priv_requirement_array(index).status;
    end function get_status;

  end protected body t_requirement_array;

  --==========================================================================================
  -- Protected requirement_in_array type
  --==========================================================================================
  type t_requirements_in_array is protected body

    variable priv_requirements_in_array : natural := 0;

    procedure set(
      constant value : in natural
    ) is
    begin
      priv_requirements_in_array := value;
    end procedure set;

    impure function get(
      VOID : t_void
    ) return natural is
    begin
      return priv_requirements_in_array;
    end function get;

  end protected body t_requirements_in_array;

  --==========================================================================================
  -- Protected disabled_tick_off_array type
  --==========================================================================================
  type t_disabled_tick_off_array is protected body

    type t_priv_disabled_tick_off_array is array (0 to get_max_requirements(VOID)) of string(1 to C_SPEC_COV_CONFIG_DEFAULT.csv_max_line_length);

    variable priv_disabled_tick_off_array : t_priv_disabled_tick_off_array := (others => (others => NUL));

    procedure set(
      constant index : in natural;
      constant value : in string(1 to C_SPEC_COV_CONFIG_DEFAULT.csv_max_line_length)
    ) is
    begin
      priv_disabled_tick_off_array(index) := value;
    end procedure set;

    impure function get(
      index : natural
    ) return string is
    begin
      return priv_disabled_tick_off_array(index);
    end function get;

    impure function get_length(
      VOID : t_void
    ) return integer is
    begin
      return priv_disabled_tick_off_array'length;
    end function get_length;

  end protected body;

  --==========================================================================================
  -- Private internal shared variables
  --==========================================================================================
  -- Shared variables used internally in this context
  shared variable priv_csv_file                : t_csv_file_reader;
  --shared variable priv_requirement_array        : t_requirement_entry_array(0 to get_max_requirements(VOID));
  --shared variable priv_requirements_in_array    : natural := 0;
  shared variable priv_requirement_array       : t_requirement_array;
  shared variable priv_requirements_in_array   : t_requirements_in_array;
  --shared variable priv_testcase_name            : string(1 to C_SPEC_COV_CONFIG_DEFAULT.csv_max_line_length) := (others => NUL);
  shared variable priv_testcase_name           : work.protected_testcase_name_pkg.t_generic;
  --shared variable priv_testcase_passed          : boolean;
  shared variable priv_testcase_passed         : work.protected_testcase_passed_pkg.t_generic;
  --shared variable priv_requirement_file_exists  : boolean;
  shared variable priv_requirement_file_exists : work.protected_requirement_file_exists_pkg.t_generic;
  shared variable priv_disabled_tick_off_array : t_disabled_tick_off_array;
  shared variable priv_req_cov_initialized     : work.protected_req_cov_initialized_pkg.t_generic;

  --==========================================================================================
  -- Public procedures
  --==========================================================================================
  --
  -- Initialize testcase requirement coverage
  --
  procedure initialize_req_cov(
    constant testcase         : string;
    constant req_list_file    : string;
    constant partial_cov_file : string
  ) is
  begin
    log(ID_SPEC_COV_INIT, "Initializing requirement coverage with requirement file: " & req_list_file, C_SCOPE);
    priv_set_default_testcase_name(testcase);
    -- update pkg local variables
    priv_testcase_passed.set(true);
    priv_requirement_file_exists.set(true);

    -- Read requirements from CSV file and save to array. TB_ERROR alert will be raised if file is emtpy.
    priv_read_and_parse_csv_file(req_list_file);

    -- Initialize PC file (open file and write info/settings to top of file)
    priv_initialize_result_file(partial_cov_file);

    -- Flag that initialization has been done
    priv_req_cov_initialized.set(true);
  end procedure initialize_req_cov;

  -- Overloading procedure
  procedure initialize_req_cov(
    constant testcase         : string;
    constant partial_cov_file : string
  ) is
  begin
    log(ID_SPEC_COV_INIT, "Initializing requirement coverage without requirement file.", C_SCOPE);
    priv_set_default_testcase_name(testcase);
    -- update pkg local variables
    priv_testcase_passed.set(true);
    priv_requirement_file_exists.set(false);

    -- Initialize PC file (open file and write info/settings to top of file)
    priv_initialize_result_file(partial_cov_file);

    -- Flag that initialization has been done
    priv_req_cov_initialized.set(true);
  end procedure initialize_req_cov;

  --
  -- Log the requirement and testcase
  --
  procedure tick_off_req_cov(
    constant requirement        : string;
    constant requirement_status : t_test_status    := NA;
    constant msg                : string           := "";
    constant tickoff_extent     : t_extent_tickoff := LIST_SINGLE_TICKOFF;
    constant scope              : string           := C_SCOPE
  ) is
    variable v_requirement_to_file_line : line;
    variable v_requirement_status       : t_test_status;
    variable v_prev_requirement_status  : t_test_status;
    variable v_uvvm_status              : t_uvvm_status := shared_uvvm_status.get(VOID);
  begin
    -- Raise TB_ERROR alert if tick_off_req_cov() is called before initialize_req_cov()
    if not priv_req_cov_initialized.get(VOID) then
        alert(TB_ERROR, "Requirement coverage has not been initialized. Please use initialize_req_cov() before calling tick_off_req_cov().", scope);
      return;
    end if;

    -- Check if requirement exists
    if priv_requirement_file_exists.get(VOID) and not priv_requirement_exists(requirement) then
      alert(shared_spec_cov_config.get(VOID).missing_req_label_severity, "Requirement not found in requirement list: " & to_string(requirement), C_SCOPE);
    end if;


    ---- Check if there were any errors globally or testcase was explicit set to FAIL
    if v_uvvm_status.found_unexpected_simulation_errors_or_worse = 1 then
      v_requirement_status := FAIL;
      -- Set failing testcase for finishing summary line
      priv_testcase_passed.set(false);
    elsif requirement_status = FAIL then
      v_requirement_status := FAIL;
    else
      v_requirement_status := PASS;
    end if;

    -- Get previous requirement status (used for checking for PASS to FAIL transition)
    v_prev_requirement_status := priv_get_requirement_status(requirement);

    -- Save requirement status
    priv_set_requirement_status(requirement, v_requirement_status);

    -- Check if requirement tick-off should be written
    if (tickoff_extent = LIST_EVERY_TICKOFF) or (priv_get_num_requirement_tick_offs(requirement) = 0) or (v_prev_requirement_status = PASS and requirement_status = FAIL) then
      -- Log result to transcript
      log(ID_SPEC_COV, "Logging requirement " & requirement & " [" & priv_test_status_to_string(v_requirement_status) & "]. '" & priv_get_description(requirement) & "'. " & msg, scope);
      -- Log to file
      write(v_requirement_to_file_line, requirement & C_SPEC_COV_CONFIG_DEFAULT.csv_delimiter & priv_get_default_testcase_name & C_SPEC_COV_CONFIG_DEFAULT.csv_delimiter & priv_test_status_to_string(v_requirement_status));
      writeline(RESULT_FILE, v_requirement_to_file_line);
      -- Increment number of tick off for this requirement
      priv_inc_num_requirement_tick_offs(requirement);
    end if;
  end procedure tick_off_req_cov;

  --
  -- Conditional tick_off_req_cov() for selected requirement.
  --   If the requirement has been enabled for conditional tick_off_req_cov()
  --   with enable_cond_tick_off_req_cov() it will not be ticked off.
  procedure cond_tick_off_req_cov(
    constant requirement        : string;
    constant requirement_status : t_test_status    := NA;
    constant msg                : string           := "";
    constant tickoff_extent     : t_extent_tickoff := LIST_SINGLE_TICKOFF;
    constant scope              : string           := C_SCOPE
  ) is
  begin
    -- Check: is requirement listed in the conditional tick off array?
    if priv_req_listed_in_disabled_tick_off_array(requirement) = false then
      -- requirement was not listed, call tick off method.
      tick_off_req_cov(requirement, requirement_status, msg, tickoff_extent, scope);
    end if;
  end procedure cond_tick_off_req_cov;

  --
  -- Disable conditional tick_off_req_cov() setting for
  --   selected requirement.
  --
  procedure disable_cond_tick_off_req_cov(
    constant requirement : string
  ) is
    constant c_requirement_length              : natural := priv_get_requirement_name_length(requirement);
    variable v_disabled_tick_off_array_element : string(1 to C_SPEC_COV_CONFIG_DEFAULT.csv_max_line_length);
  begin
    -- Check: is requirement already tracked?
    --        method will also check if the requirement exist in the requirement file.
    if priv_req_listed_in_disabled_tick_off_array(requirement) = true then
      alert(TB_WARNING, "Requirement " & requirement & " is already listed in the conditional tick off array.", C_SCOPE);
      return;
    end if;

    -- add requirement to conditional tick off array.
    for idx in 0 to priv_disabled_tick_off_array.get_length(VOID) - 1 loop
      -- find a free entry, add requirement and exit loop
      if priv_disabled_tick_off_array.get(idx)(1) = NUL then
        --priv_disabled_tick_off_array.(idx)(1 to c_requirement_length) := to_upper(requirement);
        -- Altering disabled_tick_off_array element via a local variable in order to set only a slice of the array element.
        v_disabled_tick_off_array_element                            := priv_disabled_tick_off_array.get(idx);
        v_disabled_tick_off_array_element(1 to c_requirement_length) := to_upper(requirement);
        priv_disabled_tick_off_array.set(idx, v_disabled_tick_off_array_element);
        exit;
      end if;
    end loop;
  end procedure disable_cond_tick_off_req_cov;

  --
  -- Enable conditional tick_off_req_cov() setting for
  --   selected requirement.
  --
  procedure enable_cond_tick_off_req_cov(
    constant requirement : string
  ) is
    constant c_requirement_length : natural := priv_get_requirement_name_length(requirement);
  begin
    -- Check: is requirement not tracked?
    --        method will also check if the requirement exist in the requirement file.
    if priv_req_listed_in_disabled_tick_off_array(requirement) = false then
      alert(TB_WARNING, "Requirement " & requirement & " is not listed in the conditional tick off array.", C_SCOPE);

    else                                -- requirement is tracked
      -- find the requirement and wipe it out from conditional tick off array
      for idx in 0 to priv_disabled_tick_off_array.get_length(VOID) - 1 loop
        -- found requirement, wipe the entry and exit
        if priv_disabled_tick_off_array.get(idx)(1 to c_requirement_length) = to_upper(requirement) then
          priv_disabled_tick_off_array.set(idx, (others => NUL));
          exit;
        end if;
      end loop;
    end if;
  end procedure enable_cond_tick_off_req_cov;

  --
  -- Deallocate memory usage and write summary line to partial_cov file
  --
  procedure finalize_req_cov(
    constant VOID : t_void
  ) is
    variable v_checksum_string : line;
  begin
    -- Free used memory
    log(ID_SPEC_COV, "Finalizing requirement coverage", C_SCOPE);

    for i in 0 to priv_requirements_in_array.get(VOID) - 1 loop
      priv_requirement_array.deallocate_requirement(i);
      priv_requirement_array.deallocate_description(i);
      for tc in 0 to priv_requirement_array.get_num_tcs(i) - 1 loop
        priv_requirement_array.deallocate_tc_list(i, tc);
      end loop;
      priv_requirement_array.set_num_tcs(i, 0);
      priv_requirement_array.set_valid(i, false);
      priv_requirement_array.set_num_tickoffs(i, 0);
    end loop;
    priv_requirements_in_array.set(0);

    -- Add closing line
    write(v_checksum_string, priv_get_summary_string);

    writeline(RESULT_FILE, v_checksum_string);

    file_close(RESULT_FILE);

    -- Clear initialization flag. initialize_req_cov() must be called again before another tickoff can be done
    priv_req_cov_initialized.set(false);
  end procedure finalize_req_cov;

  --==========================================================================================
  -- Private internal functions and procedures
  --==========================================================================================
  --
  -- Initialize the partial_cov result file
  --
  procedure priv_initialize_result_file(
    constant file_name : string
  ) is
    variable v_file_open_status      : FILE_OPEN_STATUS;
    variable v_settings_to_file_line : line;
  begin
    file_open(v_file_open_status, RESULT_FILE, file_name, write_mode);
    check_file_open_status(v_file_open_status, file_name);

    -- Write info and settings to CSV file for Python post-processing script
    log(ID_SPEC_COV_INIT, "Adding test and configuration information to coverage file: " & file_name, C_SCOPE);
    write(v_settings_to_file_line, "NOTE: This coverage file is only valid when the last line is 'SUMMARY, " & priv_get_default_testcase_name & ", PASS'" & LF);
    write(v_settings_to_file_line, "TESTCASE_NAME: " & priv_get_default_testcase_name & LF);
    write(v_settings_to_file_line, "DELIMITER: " & shared_spec_cov_config.get(VOID).csv_delimiter & LF);
    writeline(RESULT_FILE, v_settings_to_file_line);
  end procedure priv_initialize_result_file;

  --
  -- Read requirement CSV file
  --
  procedure priv_read_and_parse_csv_file(
    constant req_list_file : string
  ) is
    variable v_tc_valid : boolean;
    variable v_file_ok  : boolean;
    variable v_requirement : string(1 to C_SPEC_COV_CONFIG_DEFAULT.csv_max_line_length) := (others => NUL);
  begin
    if priv_requirements_in_array.get(VOID) > 0 then
      alert(TB_ERROR, "Requirements have already been read from file, please call finalize_req_cov before starting a new requirement coverage process.", C_SCOPE);
      return;
    end if;

    -- Open file and check status, return if failing
    v_file_ok := priv_csv_file.initialize(req_list_file, C_SPEC_COV_CONFIG_DEFAULT.csv_delimiter);
    if v_file_ok = false then
      return;
    end if;

    -- File ok, read file
    while not priv_csv_file.end_of_file loop
      priv_csv_file.readline;

      -- Read requirement
      v_requirement := priv_csv_file.read_string;
      if v_requirement(1) /= '#' then -- Ignore if comment line
        priv_requirement_array.set_requirement(priv_requirements_in_array.get(VOID), v_requirement);
        -- Read description
        priv_requirement_array.set_description(priv_requirements_in_array.get(VOID), priv_csv_file.read_string);
        -- Read testcases
        v_tc_valid := true;
        priv_requirement_array.set_num_tcs(priv_requirements_in_array.get(VOID), 0);
        while v_tc_valid loop
            --priv_requirement_array(priv_requirements_in_array).tc_list(priv_requirement_array(priv_requirements_in_array).num_tcs) := new string'(priv_csv_file.read_string); 
            priv_requirement_array.set_tc_list_element(priv_requirements_in_array.get(VOID), priv_requirement_array.get_num_tcs(priv_requirements_in_array.get(VOID)), priv_csv_file.read_string);
            --if (priv_requirement_array(priv_requirements_in_array).tc_list(priv_requirement_array(priv_requirements_in_array).num_tcs).all(1) /= NUL) then
            if priv_requirement_array.get_tc_list_element(priv_requirements_in_array.get(VOID), priv_requirement_array.get_num_tcs(priv_requirements_in_array.get(VOID)))(1) /= NUL then
            priv_requirement_array.set_num_tcs(priv_requirements_in_array.get(VOID), priv_requirement_array.get_num_tcs(priv_requirements_in_array.get(VOID)) + 1);
            else
            v_tc_valid := false;
            end if;
        end loop;
        -- Validate entry
        --priv_requirement_array(priv_requirements_in_array).valid := true;
        priv_requirement_array.set_valid(priv_requirements_in_array.get(VOID), true);

        -- Set number of tickoffs for this requirement to 0
        --priv_requirement_array(priv_requirements_in_array).num_tickoffs := 0;
        priv_requirement_array.set_num_tickoffs(priv_requirements_in_array.get(VOID), 0);

        priv_log_entry(priv_requirements_in_array.get(VOID));
        --priv_requirements_in_array := priv_requirements_in_array + 1;
        priv_requirements_in_array.set(priv_requirements_in_array.get(VOID) + 1);
      end if;
    end loop;

    priv_csv_file.dispose;
  end procedure priv_read_and_parse_csv_file;

  --
  -- Log CSV readout to terminal
  --
  procedure priv_log_entry(
    constant index : natural
  ) is
    variable v_line : line;
  begin
    if priv_requirement_array.get_valid(index) then
      -- log requirement and description to terminal
      log(ID_SPEC_COV_REQS, "Requirement: " & priv_requirement_array.get_requirement(index) & ", " & priv_requirement_array.get_description(index), C_SCOPE);
      -- log testcases to terminal
      if priv_requirement_array.get_num_tcs(index) > 0 then
        write(v_line, string'("  TC: "));
        for i in 0 to priv_requirement_array.get_num_tcs(index) - 1 loop
          if i > 0 then
            write(v_line, string'(", "));
          end if;
          write(v_line, priv_requirement_array.get_tc_list_element(index, i));
        end loop;
        log(ID_SPEC_COV_REQS, v_line.all, C_SCOPE);
      end if;
    else
      log(ID_SPEC_COV_REQS, "Requirement entry was not valid", C_SCOPE);
    end if;
    deallocate(v_line);
  end procedure priv_log_entry;

  --
  -- Check if requirement exists, return boolean
  -- 
  impure function priv_requirement_exists(
    requirement : string
  ) return boolean is
  begin
    for i in 0 to priv_requirements_in_array.get(VOID) - 1 loop
      if priv_get_requirement_name_length(priv_requirement_array.get_requirement(i)) = requirement'length then
        if to_upper(priv_requirement_array.get_requirement(i)(1 to requirement'length)) = to_upper(requirement(1 to requirement'length)) then
          return true;
        end if;
      end if;
    end loop;
    return false;
  end function priv_requirement_exists;

  --
  -- Set tick off status for requirement
  --
  procedure priv_set_requirement_status(
    constant requirement : string;
    constant status      : t_test_status
  ) is
  begin
    for i in 0 to priv_requirements_in_array.get(VOID) - 1 loop
      if priv_get_requirement_name_length(priv_requirement_array.get_requirement(i)) = requirement'length then
        if to_upper(priv_requirement_array.get_requirement(i)(1 to requirement'length)) = to_upper(requirement(1 to requirement'length)) then
          priv_requirement_array.set_status(i, status);
        end if;
      end if;
    end loop;
  end procedure priv_set_requirement_status;

  --
  -- Get the most recent tick off status for requirement
  --
  impure function priv_get_requirement_status(
    requirement : string
  ) return t_test_status is
  begin
    for i in 0 to priv_requirements_in_array.get(VOID) - 1 loop
      if priv_get_requirement_name_length(priv_requirement_array.get_requirement(i)) = requirement'length then
        if to_upper(priv_requirement_array.get_requirement(i)(1 to requirement'length)) = to_upper(requirement(1 to requirement'length)) then
          return priv_requirement_array.get_status(i);
        end if;
      end if;
    end loop;
    return FAIL;
  end function priv_get_requirement_status;

  --
  -- Get number of tick offs for requirement
  --
  impure function priv_get_num_requirement_tick_offs(
    requirement : string
  ) return natural is
  begin
    for i in 0 to priv_requirements_in_array.get(VOID) - 1 loop
      if priv_get_requirement_name_length(priv_requirement_array.get_requirement(i)) = requirement'length then
        if to_upper(priv_requirement_array.get_requirement(i)(1 to requirement'length)) = to_upper(requirement(1 to requirement'length)) then
          return priv_requirement_array.get_num_tickoffs(i);
        end if;
      end if;
    end loop;
    return 0;
  end function priv_get_num_requirement_tick_offs;

  --
  -- Increment number of tick offs for requirement
  --
  procedure priv_inc_num_requirement_tick_offs(
    constant requirement : string
  ) is
  begin
    for i in 0 to priv_requirements_in_array.get(VOID) - 1 loop
      if priv_get_requirement_name_length(priv_requirement_array.get_requirement(i)) = requirement'length then
        if to_upper(priv_requirement_array.get_requirement(i)(1 to requirement'length)) = to_upper(requirement(1 to requirement'length)) then
          priv_requirement_array.set_num_tickoffs(i, priv_requirement_array.get_num_tickoffs(i) + 1);
        end if;
      end if;
    end loop;
  end procedure priv_inc_num_requirement_tick_offs;

  --
  -- Get description of requirement
  --
  impure function priv_get_description(
    requirement : string
  ) return string is
  begin
    for i in 0 to priv_requirements_in_array.get(VOID) - 1 loop
      if priv_requirement_array.get_requirement(i)(1 to requirement'length) = requirement(1 to requirement'length) then
        -- Found requirement
        return priv_requirement_array.get_description(i);
      end if;
    end loop;

    if priv_requirement_file_exists.get(VOID) = false then
      return "";
    else
      return "DESCRIPTION NOT FOUND";
    end if;
  end function priv_get_description;

  --
  -- Get the t_test_status parameter as string
  --
  function priv_test_status_to_string(
    test_status : t_test_status
  ) return string is
  begin
    if test_status = PASS then
      return C_PASS_STRING;
    else                                -- test_status = FAIL
      return C_FAIL_STRING;
    end if;
  end function priv_test_status_to_string;

  --
  -- Get a string for finalize summary in the partial_cov CSV file.
  --
  impure function priv_get_summary_string
  return string is
    variable v_uvvm_status : t_uvvm_status := shared_uvvm_status.get(VOID);
  begin
    -- Create a CSV coverage file summary string
    if (priv_testcase_passed.get(VOID) = true) and (v_uvvm_status.found_unexpected_simulation_errors_or_worse = 0) then
      return "SUMMARY, " & priv_get_default_testcase_name & ", " & C_PASS_STRING;
    else
      return "SUMMARY, " & priv_get_default_testcase_name & ", " & C_FAIL_STRING;
    end if;
  end function priv_get_summary_string;

  --
  -- Set the default testcase name.
  --
  procedure priv_set_default_testcase_name(
    constant testcase : string
  ) is
    variable v_priv_testcase_name : string(1 to C_SPEC_COV_CONFIG_DEFAULT.csv_max_line_length) := (others => NUL);
  begin
    v_priv_testcase_name(1 to testcase'length) := testcase;
    priv_testcase_name.set(v_priv_testcase_name);
  end procedure priv_set_default_testcase_name;

  --
  -- Return the default testcase name set when initialize_req_cov() was called.
  --
  impure function priv_get_default_testcase_name
  return string is
    variable v_testcase_length : natural := priv_find_string_length(priv_testcase_name.get(VOID));
    variable v_testcase_name   : string(1 to C_SPEC_COV_CONFIG_DEFAULT.csv_max_line_length);
  begin
    v_testcase_name := priv_testcase_name.get(VOID);
    return v_testcase_name(1 to v_testcase_length);
  end function priv_get_default_testcase_name;

  --
  -- Find the length of a string which will contain NUL characters.
  --
  impure function priv_find_string_length(
    search_string : string
  ) return natural is
    variable v_return : natural := 0;
  begin
    -- loop string until NUL is found and return idx-1
    for idx in 1 to search_string'length loop
      if search_string(idx) = NUL then
        return idx - 1;
      end if;
    end loop;

    -- NUL was not found, return full length
    return search_string'length;
  end function priv_find_string_length;

  --
  -- Get length of requirement name
  --
  impure function priv_get_requirement_name_length(
    requirement : string)
  return natural is
    variable v_length : natural := 0;
  begin
    for i in 1 to requirement'length loop
      if requirement(i) = NUL then
        exit;
      else
        v_length := v_length + 1;
      end if;
    end loop;
    return v_length;
  end function priv_get_requirement_name_length;

  --
  -- Check if requirement is listed in the priv_disabled_tick_off_array() array.
  --
  impure function priv_req_listed_in_disabled_tick_off_array(
    requirement : string
  ) return boolean is
    constant c_requirement_length : natural := priv_get_requirement_name_length(requirement);
  begin
    -- Check if requirement exists
    if (priv_requirement_exists(requirement) = false) and (priv_requirement_file_exists.get(VOID) = true) then
      alert(shared_spec_cov_config.get(VOID).missing_req_label_severity, "Requirement not found in requirement list: " & to_string(requirement), C_SCOPE);
    end if;

    -- Check if requirement is listed in priv_disabled_tick_off_array() array
    for idx in 0 to priv_disabled_tick_off_array.get_length(VOID) - 1 loop
      -- found
      if priv_disabled_tick_off_array.get(idx)(1 to c_requirement_length) = to_upper(requirement(1 to c_requirement_length)) then
        return true;
      end if;
    end loop;
    -- not found
    return false;
  end function priv_req_listed_in_disabled_tick_off_array;

end package body spec_cov_pkg;
