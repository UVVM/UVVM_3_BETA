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
--  Error injection package
--================================================================================================================================
library ieee;
use ieee.std_logic_1164.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

package error_injection_pkg is

  type t_error_injection_types is (
    BYPASS,
    PULSE,
    DELAY,
    JITTER,
    INVERT,
    STUCK_AT_OLD,
    STUCK_AT_NEW
  );

  type t_error_injection_config is record
    error_type          : t_error_injection_types;
    initial_delay_min   : time;
    initial_delay_max   : time;
    return_delay_min    : time;
    return_delay_max    : time;
    width_min           : time;
    width_max           : time;
    interval            : positive;
    base_value          : std_logic;    -- SL only
  end record;

  constant C_EI_CONFIG_DEFAULT : t_error_injection_config := (
    error_type          => BYPASS,
    initial_delay_min   => 0 ns,
    initial_delay_max   => 0 ns,
    return_delay_min    => 0 ns,
    return_delay_max    => 0 ns,
    width_min           => 0 ns,
    width_max           => 0 ns,
    interval            => 1,
    base_value          => '0'
  );

  constant C_MAX_EI_INSTANCE_NUM : natural := C_EI_VVC_MAX_INSTANCE_NUM;

  type t_error_injection_config_array is array (natural range <>) of t_error_injection_config;

end package error_injection_pkg;

--================================================================================================================================
--  Generic package instantiations
--================================================================================================================================
----------------------------------------------------------------------
-- Protected type: t_error_injection_config_array
----------------------------------------------------------------------
library uvvm_util;
use work.error_injection_pkg.all;

package protected_ei_config_pkg is new uvvm_util.protected_generic_types_pkg
  generic map(
    t_generic_element => t_error_injection_config_array(0 to C_MAX_EI_INSTANCE_NUM),
    c_generic_default => (others => C_EI_CONFIG_DEFAULT)
  );

--================================================================================================================================
--  Shared variables package
--================================================================================================================================
use work.protected_ei_config_pkg.all;

package error_injection_shared_variables_pkg is
  shared variable shared_ei_config : work.protected_ei_config_pkg.t_generic;
end package error_injection_shared_variables_pkg;
