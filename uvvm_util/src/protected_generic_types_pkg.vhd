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
use std.textio.all;

use work.types_pkg.all;
use work.adaptations_pkg.t_channel;
use work.adaptations_pkg.C_MAX_VVC_INSTANCE_NUM;
use work.adaptations_pkg.ALL_INSTANCES;

package protected_generic_types_pkg is

  generic(type t_generic_element;
          c_generic_default : t_generic_element);

  type t_prot_generic_array is protected

    procedure set(
      constant element : in t_generic_element;
      constant index   : in integer;
      constant channel : in t_channel
    );

    procedure set(
      constant element : in t_generic_element;
      constant channel : in t_channel
    );

    procedure set(
      constant element : in t_generic_element;
      constant index   : in integer
    );

    procedure set(
      constant element : in t_generic_element
    );

    impure function get(
      constant index   : in integer;
      constant channel : in t_channel
    ) return t_generic_element;

    impure function get(
      constant channel : t_channel
    ) return t_generic_element;

    impure function get(
      constant index : integer
    ) return t_generic_element;

    impure function get(
      VOID : t_void
    ) return t_generic_element;

  end protected t_prot_generic_array;

  type t_prot_generic is protected

    procedure set(
      constant element : in t_generic_element
    );

    impure function get(
      VOID : t_void
    ) return t_generic_element;

  end protected t_prot_generic;

end package protected_generic_types_pkg;

package body protected_generic_types_pkg is

  type t_prot_generic_array is protected body

    constant C_SCOPE               : string    := "PROTECTED_GENERIC";
    constant C_DEFAULT_ARRAY_INDEX : integer   := 0;
    constant C_DEFAULT_VVC_CHANNEL : t_channel := NA;

    type t_queue_is_initialized_array is array (C_MAX_VVC_INSTANCE_NUM - 1 downto ALL_INSTANCES) of boolean;
    variable vr_queue_is_initialized    : t_queue_is_initialized_array := (others => false);
    variable vr_rx_queue_is_initialized : t_queue_is_initialized_array := (others => false);
    variable vr_tx_queue_is_initialized : t_queue_is_initialized_array := (others => false);

    type t_generic_element_array is array (integer range <>) of t_generic_element;
    variable vr_element           : t_generic_element_array(C_MAX_VVC_INSTANCE_NUM - 1 downto ALL_INSTANCES);
    variable vr_vvc_rx_ch_element : t_generic_element_array(C_MAX_VVC_INSTANCE_NUM - 1 downto ALL_INSTANCES);
    variable vr_vvc_tx_ch_element : t_generic_element_array(C_MAX_VVC_INSTANCE_NUM - 1 downto ALL_INSTANCES);

    ------------------------------------------------------------
    -- Queue initialization helper methods
    ------------------------------------------------------------
    impure function is_queue_initialized(
      constant index   : integer;
      constant channel : t_channel
    ) return boolean is
    begin
      if (index < C_MAX_VVC_INSTANCE_NUM) and (index >= ALL_INSTANCES) then
        case channel is
          when RX =>
            return vr_rx_queue_is_initialized(index);
          when TX =>
            return vr_tx_queue_is_initialized(index);
          when ALL_CHANNELS =>
            return vr_queue_is_initialized(index);
          when others =>
            return vr_queue_is_initialized(index);
        end case;
      else
        return false;
      end if;
    end function is_queue_initialized;

    procedure initialize_queue(
      constant index   : integer;
      constant channel : t_channel
    ) is
    begin
      if (index < C_MAX_VVC_INSTANCE_NUM) and (index >= ALL_INSTANCES) then

        case channel is
          when RX =>
            vr_rx_queue_is_initialized(index) := true;
          when TX =>
            vr_tx_queue_is_initialized(index) := true;
          when ALL_CHANNELS =>
            vr_queue_is_initialized(index) := true;
          when others =>
            vr_queue_is_initialized(index) := true;
        end case;
      end if;
    end procedure initialize_queue;

    ------------------------------------------------------------
    -- Set()
    ------------------------------------------------------------
    procedure set(
      constant element : in t_generic_element;
      constant index   : in integer;
      constant channel : in t_channel
    ) is
    begin
      if (index < C_MAX_VVC_INSTANCE_NUM) and (index >= ALL_INSTANCES) then
        initialize_queue(index, channel);

        case channel is
          when RX =>
            vr_vvc_rx_ch_element(index) := element;
          when TX =>
            vr_vvc_tx_ch_element(index) := element;
          when ALL_CHANNELS =>          -- Set all channels to the given value
            vr_vvc_tx_ch_element(index) := element;
            vr_vvc_rx_ch_element(index) := element;
            vr_element(index)           := element;
          when others =>
            vr_element(index) := element;
        end case;
      end if;
    end procedure set;

    -- Set() overload without index
    procedure set(
      constant element : in t_generic_element;
      constant channel : in t_channel
    ) is
    begin
      set(element, C_DEFAULT_ARRAY_INDEX, channel);
    end procedure set;

    -- Set() overload without channel
    procedure set(
      constant element : in t_generic_element;
      constant index   : in integer
    ) is
    begin
      set(element, index, C_DEFAULT_VVC_CHANNEL);
    end procedure set;

    -- Set() overload without index and channel
    procedure set(
      constant element : in t_generic_element
    ) is
    begin
      set(element, C_DEFAULT_ARRAY_INDEX, C_DEFAULT_VVC_CHANNEL);
    end procedure set;

    ------------------------------------------------------------
    -- Get()
    ------------------------------------------------------------
    impure function get(
      constant index   : in integer;
      constant channel : in t_channel
    ) return t_generic_element is

      constant queue_is_initialized : boolean := is_queue_initialized(index, channel);
    begin
      if (index < C_MAX_VVC_INSTANCE_NUM) and (index >= ALL_INSTANCES) and (queue_is_initialized = true) then
        case channel is
          when RX =>
            return vr_vvc_rx_ch_element(index);
          when TX =>
            return vr_vvc_tx_ch_element(index);
          -- TODO: Decide how to handle get() being called with ALL_CHANNELS. Treat as invalid input and give error?
          when others =>
            return vr_element(index);
        end case;
      else
        return C_GENERIC_DEFAULT;
      end if;
    end function get;

    -- Get() overload without channel
    impure function get(
      constant index : integer
    ) return t_generic_element is
    begin
      return get(index, C_DEFAULT_VVC_CHANNEL);
    end function get;

    -- Get() overload without index
    impure function get(
      constant channel : t_channel
    ) return t_generic_element is
    begin
      return get(C_DEFAULT_ARRAY_INDEX, channel);
    end function get;

    -- Get() overload without index and channel
    impure function get(
      VOID : t_void
    ) return t_generic_element is
    begin
      return get(C_DEFAULT_ARRAY_INDEX, C_DEFAULT_VVC_CHANNEL);
    end function get;

  end protected body t_prot_generic_array;

  -- Protected type that holds a single, non-array element. v3
  type t_prot_generic is protected body

    variable vr_element : t_generic_element := c_generic_default;

    procedure set(
      constant element : in t_generic_element
    ) is
    begin
      vr_element := element;
    end procedure set;

    impure function get(
      VOID : t_void
    ) return t_generic_element is
    begin
      return vr_element;
    end function get;

  end protected body t_prot_generic;

end package body protected_generic_types_pkg;
