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

library uvvm_util;
context uvvm_util.uvvm_util_context;

library uvvm_vvc_framework;
use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library bitvis_vip_scoreboard;
use bitvis_vip_scoreboard.generic_sb_support_pkg.all;

library work;
use work.axi_sb_pkg.all;
use work.axi_bfm_pkg.all;
use work.vvc_cmd_pkg.all;
use work.td_target_support_pkg.all;
use work.transaction_pkg.all;

--=================================================================================================
--=================================================================================================
--=================================================================================================
package vvc_methods_pkg is

  --===============================================================================================
  -- Types and constants for the AXI VVC 
  --===============================================================================================
  constant C_VVC_NAME : string := "AXI_VVC";

  signal AXI_VVCT : t_vvc_target_record := set_vvc_target_defaults(C_VVC_NAME);
  alias THIS_VVCT : t_vvc_target_record is AXI_VVCT;
  alias t_bfm_config is t_axi_bfm_config;

  type t_executor_result is record
    cmd_idx           : natural;        -- from UVVM handshake mechanism
    data              : std_logic_vector(127 downto 0);
    value_is_new      : boolean;        -- turn true/false for put/fetch
    fetch_is_accepted : boolean;
  end record;

  type t_executor_result_array is array (natural range <>) of t_executor_result;

  -- Type found in UVVM-Util types_pkg
  constant C_AXI_INTER_BFM_DELAY_DEFAULT : t_inter_bfm_delay := (
    delay_type                         => NO_DELAY,
    delay_in_time                      => 0 ns,
    inter_bfm_delay_violation_severity => WARNING
  );

  type t_vvc_config is record
    inter_bfm_delay                  : t_inter_bfm_delay; -- Minimum delay between BFM accesses from the VVC. If parameter delay_type is set to NO_DELAY, BFM accesses will be back to back, i.e. no delay.
    bfm_config                       : t_bfm_config;      -- Configuration for the BFM. See BFM quick reference.
    force_single_pending_transaction : boolean;           -- Waits until the previous transaction is completed before starting the next one
  end record;

  constant C_AXI_VVC_CONFIG_DEFAULT : t_vvc_config := (
    inter_bfm_delay                  => C_AXI_INTER_BFM_DELAY_DEFAULT,
    bfm_config                       => C_AXI_BFM_CONFIG_DEFAULT,
    force_single_pending_transaction => false
  );

  type t_vvc_status is record
    current_cmd_idx  : natural;
    previous_cmd_idx : natural;
    pending_cmd_cnt  : natural;
  end record;

  constant C_VVC_STATUS_DEFAULT : t_vvc_status := (
    current_cmd_idx  => 0,
    previous_cmd_idx => 0,
    pending_cmd_cnt  => 0
  );

  -- Transaction information for the wave view during simulation
  type t_transaction_info is record
    operation   : t_operation;
    addr        : unsigned(C_VVC_CMD_ADDR_MAX_LENGTH - 1 downto 0);
    data        : std_logic_vector(C_VVC_CMD_DATA_MAX_LENGTH - 1 downto 0);
    byte_enable : std_logic_vector(C_VVC_CMD_BYTE_ENABLE_MAX_LENGTH - 1 downto 0);
    msg         : string(1 to C_VVC_CMD_STRING_MAX_LENGTH);
  end record;

  -- v3
  package protected_vvc_status_pkg is new uvvm_util.protected_generic_types_pkg
    generic map(t_generic_element => t_vvc_status,
                c_generic_default => C_VVC_STATUS_DEFAULT);
  use protected_vvc_status_pkg.all;
  shared variable shared_axi_vvc_status : protected_vvc_status_pkg.t_prot_generic_array;
  alias shared_vvc_status is shared_axi_vvc_status; -- This alias is for internal use in the VVC

  package protected_vvc_config_pkg is new uvvm_util.protected_generic_types_pkg
    generic map(t_generic_element => t_vvc_config,
                c_generic_default => C_AXI_VVC_CONFIG_DEFAULT);
  use protected_vvc_config_pkg.all;
  shared variable shared_axi_vvc_config : protected_vvc_config_pkg.t_prot_generic_array;
  alias shared_vvc_config is shared_axi_vvc_config; -- This alias is for internal use in the VVC

  package protected_msg_id_panel_pkg is new uvvm_util.protected_generic_types_pkg
    generic map(t_generic_element => t_msg_id_panel,
                c_generic_default => C_VVC_MSG_ID_PANEL_DEFAULT);
  use protected_msg_id_panel_pkg.all;
  shared variable shared_axi_vvc_msg_id_panel : protected_msg_id_panel_pkg.t_prot_generic_array;
  alias shared_vvc_msg_id_panel is shared_axi_vvc_msg_id_panel; -- This alias is for internal use in the VVC

  -- Scoreboard
  shared variable AXI_VVC_SB : t_prot_generic_sb;

  --==========================================================================================
  -- Methods dedicated to this VVC 
  -- - These procedures are called from the testbench in order for the VVC to execute
  --   BFM calls towards the given interface. The VVC interpreter will queue these calls
  --   and then the VVC executor will fetch the commands from the queue and handle the
  --   actual BFM execution.
  --   For details on how the BFM procedures work, see the QuickRef.
  --==========================================================================================

  procedure axi_write(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant awid                : in std_logic_vector             := "";
    constant awaddr              : in unsigned;
    constant awlen               : in unsigned(7 downto 0)         := (others => '0');
    constant awsize              : in integer range 1 to 128       := 4;
    constant awburst             : in t_axburst                    := INCR;
    constant awlock              : in t_axlock                     := NORMAL;
    constant awcache             : in std_logic_vector(3 downto 0) := (others => '0');
    constant awprot              : in t_axprot                     := UNPRIVILEGED_NONSECURE_DATA;
    constant awqos               : in std_logic_vector(3 downto 0) := (others => '0');
    constant awregion            : in std_logic_vector(3 downto 0) := (others => '0');
    constant awuser              : in std_logic_vector             := "";
    constant wdata               : in t_slv_array;
    constant wstrb               : in t_slv_array                  := C_EMPTY_SLV_ARRAY;
    constant wuser               : in t_slv_array                  := C_EMPTY_SLV_ARRAY;
    constant bresp_exp           : in t_xresp                      := OKAY;
    constant buser_exp           : in std_logic_vector             := "";
    constant msg                 : in string;
    constant scope               : in string                       := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel               := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  procedure axi_read(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant arid                : in std_logic_vector             := "";
    constant araddr              : in unsigned;
    constant arlen               : in unsigned(7 downto 0)         := (others => '0');
    constant arsize              : in integer range 1 to 128       := 4;
    constant arburst             : in t_axburst                    := INCR;
    constant arlock              : in t_axlock                     := NORMAL;
    constant arcache             : in std_logic_vector(3 downto 0) := (others => '0');
    constant arprot              : in t_axprot                     := UNPRIVILEGED_NONSECURE_DATA;
    constant arqos               : in std_logic_vector(3 downto 0) := (others => '0');
    constant arregion            : in std_logic_vector(3 downto 0) := (others => '0');
    constant aruser              : in std_logic_vector             := "";
    constant data_routing        : in t_data_routing;
    constant msg                 : in string;
    constant scope               : in string                       := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel               := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  procedure axi_check(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant arid                : in std_logic_vector             := "";
    constant araddr              : in unsigned;
    constant arlen               : in unsigned(7 downto 0)         := (others => '0');
    constant arsize              : in integer range 1 to 128       := 4;
    constant arburst             : in t_axburst                    := INCR;
    constant arlock              : in t_axlock                     := NORMAL;
    constant arcache             : in std_logic_vector(3 downto 0) := (others => '0');
    constant arprot              : in t_axprot                     := UNPRIVILEGED_NONSECURE_DATA;
    constant arqos               : in std_logic_vector(3 downto 0) := (others => '0');
    constant arregion            : in std_logic_vector(3 downto 0) := (others => '0');
    constant aruser              : in std_logic_vector             := "";
    constant rdata_exp           : in t_slv_array;
    constant rresp_exp           : in t_xresp_array                := C_EMPTY_XRESP_ARRAY;
    constant ruser_exp           : in t_slv_array                  := C_EMPTY_SLV_ARRAY;
    constant msg                 : in string;
    constant alert_level         : in t_alert_level                := ERROR;
    constant scope               : in string                       := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel               := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  );

  --==============================================================================
  -- Transaction info methods
  --==============================================================================
  procedure set_global_vvc_transaction_info(
    signal   vvc_transaction_info_trigger : inout std_logic;
    variable vvc_transaction_info_group   : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx                 : in natural;
    constant channel                      : in t_channel;
    constant vvc_cmd                      : in t_vvc_cmd_record;
    constant vvc_config                   : in t_vvc_config;
    constant scope                        : in string := C_VVC_CMD_SCOPE_DEFAULT
  );

  procedure set_arw_vvc_transaction_info(
    signal   vvc_transaction_info_trigger : inout std_logic;
    variable vvc_transaction_info_group   : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx                 : in natural;
    constant channel                      : in t_channel;
    constant vvc_cmd                      : in t_vvc_cmd_record;
    constant vvc_config                   : in t_vvc_config;
    constant scope                        : in string := C_VVC_CMD_SCOPE_DEFAULT
  );

  procedure set_w_vvc_transaction_info(
    signal   vvc_transaction_info_trigger : inout std_logic;
    variable vvc_transaction_info_group   : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx                 : in natural;
    constant channel                      : in t_channel;
    constant vvc_cmd                      : in t_vvc_cmd_record;
    constant vvc_config                   : in t_vvc_config;
    constant scope                        : in string := C_VVC_CMD_SCOPE_DEFAULT
  );

  procedure set_b_vvc_transaction_info(
    signal   vvc_transaction_info_trigger : inout std_logic;
    variable vvc_transaction_info_group   : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx                 : in natural;
    constant channel                      : in t_channel;
    constant vvc_cmd                      : in t_vvc_cmd_record;
    constant vvc_config                   : in t_vvc_config;
    constant scope                        : in string := C_VVC_CMD_SCOPE_DEFAULT
  );

  procedure set_r_vvc_transaction_info(
    signal   vvc_transaction_info_trigger : inout std_logic;
    variable vvc_transaction_info_group   : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx                 : in natural;
    constant channel                      : in t_channel;
    constant vvc_cmd                      : in t_vvc_cmd_record;
    constant vvc_config                   : in t_vvc_config;
    constant scope                        : in string := C_VVC_CMD_SCOPE_DEFAULT
  );

  procedure reset_vvc_transaction_info(
    variable vvc_transaction_info_group : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx               : in natural;
    constant channel                    : in t_channel;
    constant vvc_cmd                    : in t_vvc_cmd_record
  );

  procedure reset_arw_vvc_transaction_info(
    variable vvc_transaction_info_group : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx               : in natural;
    constant channel                    : in t_channel;
    constant vvc_cmd                    : in t_vvc_cmd_record
  );

  procedure reset_w_vvc_transaction_info(
    variable vvc_transaction_info_group : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx               : in natural;
    constant channel                    : in t_channel
  );

  procedure reset_b_vvc_transaction_info(
    variable vvc_transaction_info_group : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx               : in natural;
    constant channel                    : in t_channel
  );

  procedure reset_r_vvc_transaction_info(
    variable vvc_transaction_info_group : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx               : in natural;
    constant channel                    : in t_channel
  );

  --==============================================================================
  -- VVC Activity
  --==============================================================================
  procedure update_vvc_activity_register(signal   global_trigger_vvc_activity_register : inout std_logic;
                                         variable vvc_status                           : inout protected_vvc_status_pkg.t_prot_generic_array;
                                         constant instance_idx                         : in natural;
                                         constant channel                              : in t_channel;
                                         constant activity                             : in t_activity;
                                         constant entry_num_in_vvc_activity_register   : in integer;
                                         constant last_cmd_idx_executed                : in natural;
                                         constant command_queue_is_empty               : in boolean;
                                         constant scope                                : in string := C_VVC_NAME);

end package vvc_methods_pkg;

package body vvc_methods_pkg is

  --==============================================================================
  -- Methods dedicated to this VVC
  -- Notes:
  --   - shared_vvc_cmd is initialised to C_VVC_CMD_DEFAULT, and also reset to this after every command
  --==============================================================================

  procedure axi_write(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant awid                : in std_logic_vector             := "";
    constant awaddr              : in unsigned;
    constant awlen               : in unsigned(7 downto 0)         := (others => '0');
    constant awsize              : in integer range 1 to 128       := 4;
    constant awburst             : in t_axburst                    := INCR;
    constant awlock              : in t_axlock                     := NORMAL;
    constant awcache             : in std_logic_vector(3 downto 0) := (others => '0');
    constant awprot              : in t_axprot                     := UNPRIVILEGED_NONSECURE_DATA;
    constant awqos               : in std_logic_vector(3 downto 0) := (others => '0');
    constant awregion            : in std_logic_vector(3 downto 0) := (others => '0');
    constant awuser              : in std_logic_vector             := "";
    constant wdata               : in t_slv_array;
    constant wstrb               : in t_slv_array                  := C_EMPTY_SLV_ARRAY;
    constant wuser               : in t_slv_array                  := C_EMPTY_SLV_ARRAY;
    constant bresp_exp           : in t_xresp                      := OKAY;
    constant buser_exp           : in std_logic_vector             := "";
    constant msg                 : in string;
    constant scope               : in string                       := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel               := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant proc_name : string := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant proc_call : string := proc_name & "(" & to_string(VVCT, vvc_instance_idx) -- First part common for all
                                   & ", " & to_string(awaddr, HEX, AS_IS, INCL_RADIX) & ")";
    variable v_local_vvc_cmd        : t_vvc_cmd_record := shared_vvc_cmd.get(vvc_instance_idx);
    variable v_normalised_awid      : std_logic_vector(v_local_vvc_cmd.id'length - 1 downto 0);
    variable v_normalised_awaddr    : unsigned(v_local_vvc_cmd.addr'length - 1 downto 0);
    variable v_normalised_awuser    : std_logic_vector(v_local_vvc_cmd.auser'length - 1 downto 0);
    variable v_normalised_wdata     : t_slv_array(0 to v_local_vvc_cmd.data_array'length - 1)(v_local_vvc_cmd.data_array(0)'length - 1 downto 0);
    variable v_normalised_wstrb     : t_slv_array(0 to v_local_vvc_cmd.strb_array'length - 1)(v_local_vvc_cmd.strb_array(0)'length - 1 downto 0);
    variable v_normalised_wuser     : t_slv_array(0 to v_local_vvc_cmd.user_array'length - 1)(v_local_vvc_cmd.user_array(0)'length - 1 downto 0);
    variable v_normalised_buser_exp : std_logic_vector(v_local_vvc_cmd.user'length - 1 downto 0);
    variable v_msg_id_panel         : t_msg_id_panel   := shared_msg_id_panel.get(VOID);
  begin
    -- Normalizing inputs to the command record
    if awid'length = 0 then
      v_normalised_awid := C_VVC_CMD_DEFAULT.id;
    else
      v_normalised_awid := normalize_and_check(awid, v_local_vvc_cmd.id, ALLOW_WIDER_NARROWER, "awid", "shared_vvc_cmd.id", "Normalizing awid. " & add_msg_delimiter(msg));
    end if;
    v_normalised_awaddr := normalize_and_check(awaddr, v_local_vvc_cmd.addr, ALLOW_WIDER_NARROWER, "awaddr", "shared_vvc_cmd.addr", "Normalizing awaddr. " & add_msg_delimiter(msg));
    if awuser'length = 0 then
      v_normalised_awuser := C_VVC_CMD_DEFAULT.auser;
    else
      v_normalised_awuser := normalize_and_check(awuser, v_local_vvc_cmd.auser, ALLOW_WIDER_NARROWER, "awuser", "shared_vvc_cmd.auser", "Normalizing awuser. " & add_msg_delimiter(msg));
    end if;
    v_normalised_wdata  := normalize_and_check(wdata, v_local_vvc_cmd.data_array, ALLOW_WIDER_NARROWER, "wdata", "shared_vvc_cmd.data_array", "Normalizing wdata. " & add_msg_delimiter(msg));
    if wstrb'length = 1 and wstrb(0)'length = 1 and wstrb(0) = "U" then
      v_normalised_wstrb := C_VVC_CMD_DEFAULT.strb_array;
    else
      v_normalised_wstrb := normalize_and_check(wstrb, v_local_vvc_cmd.strb_array, ALLOW_WIDER_NARROWER, "wstrb", "shared_vvc_cmd.strb_array", "Normalizing wstrb. " & add_msg_delimiter(msg));
    end if;
    if wuser'length = 1 and wuser(0)'length = 1 and wuser(0) = "U" then
      v_normalised_wuser := C_VVC_CMD_DEFAULT.user_array;
    else
      v_normalised_wuser := normalize_and_check(wuser, v_local_vvc_cmd.user_array, ALLOW_WIDER_NARROWER, "wuser", "shared_vvc_cmd.user_array", "Normalizing wuser. " & add_msg_delimiter(msg));
    end if;
    if buser_exp'length = 0 then
      v_normalised_buser_exp := C_VVC_CMD_DEFAULT.user;
    else
      v_normalised_buser_exp := normalize_and_check(buser_exp, v_local_vvc_cmd.user, ALLOW_WIDER_NARROWER, "buser_exp", "shared_vvc_cmd.user", "Normalizing buser. " & add_msg_delimiter(msg));
    end if;
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, proc_call, msg, QUEUED, WRITE);

    -- v3
    v_local_vvc_cmd                     := shared_vvc_cmd.get(vvc_instance_idx);
    v_local_vvc_cmd.id                  := v_normalised_awid;
    v_local_vvc_cmd.addr                := v_normalised_awaddr;
    v_local_vvc_cmd.len                 := awlen;
    v_local_vvc_cmd.size                := awsize;
    v_local_vvc_cmd.burst               := awburst;
    v_local_vvc_cmd.lock                := awlock;
    v_local_vvc_cmd.cache               := awcache;
    v_local_vvc_cmd.prot                := awprot;
    v_local_vvc_cmd.qos                 := awqos;
    v_local_vvc_cmd.region              := awregion;
    v_local_vvc_cmd.resp                := bresp_exp;
    v_local_vvc_cmd.auser               := v_normalised_awuser;
    v_local_vvc_cmd.user                := v_normalised_buser_exp;
    v_local_vvc_cmd.data_array          := v_normalised_wdata;
    v_local_vvc_cmd.strb_array          := v_normalised_wstrb;
    v_local_vvc_cmd.user_array          := v_normalised_wuser;
    v_local_vvc_cmd.parent_msg_id_panel := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(VVCT, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure;

  procedure axi_read(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant arid                : in std_logic_vector             := "";
    constant araddr              : in unsigned;
    constant arlen               : in unsigned(7 downto 0)         := (others => '0');
    constant arsize              : in integer range 1 to 128       := 4;
    constant arburst             : in t_axburst                    := INCR;
    constant arlock              : in t_axlock                     := NORMAL;
    constant arcache             : in std_logic_vector(3 downto 0) := (others => '0');
    constant arprot              : in t_axprot                     := UNPRIVILEGED_NONSECURE_DATA;
    constant arqos               : in std_logic_vector(3 downto 0) := (others => '0');
    constant arregion            : in std_logic_vector(3 downto 0) := (others => '0');
    constant aruser              : in std_logic_vector             := "";
    constant data_routing        : in t_data_routing;
    constant msg                 : in string;
    constant scope               : in string                       := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel               := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant proc_name : string := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant proc_call : string := proc_name & "(" & to_string(VVCT, vvc_instance_idx) -- First part common for all
                                   & ", " & to_string(araddr, HEX, AS_IS, INCL_RADIX) & ")";
    variable v_local_vvc_cmd     : t_vvc_cmd_record := shared_vvc_cmd.get(vvc_instance_idx);
    variable v_normalised_arid   : std_logic_vector(v_local_vvc_cmd.id'length - 1 downto 0);
    variable v_normalised_araddr : unsigned(v_local_vvc_cmd.addr'length - 1 downto 0);
    variable v_normalised_aruser : std_logic_vector(v_local_vvc_cmd.user'length - 1 downto 0);
    variable v_msg_id_panel      : t_msg_id_panel   := shared_msg_id_panel.get(VOID);
  begin
    -- Normalizing inputs to the command record
    if arid'length = 0 then
      v_normalised_arid := C_VVC_CMD_DEFAULT.id;
    else
      v_normalised_arid := normalize_and_check(arid, v_local_vvc_cmd.id, ALLOW_WIDER_NARROWER, "arid", "shared_vvc_cmd.id", "Normalizing arid. " & add_msg_delimiter(msg));
    end if;
    v_normalised_araddr := normalize_and_check(araddr, v_local_vvc_cmd.addr, ALLOW_WIDER_NARROWER, "araddr", "shared_vvc_cmd.addr", msg);
    if aruser'length = 0 then
      v_normalised_aruser := C_VVC_CMD_DEFAULT.auser;
    else
      v_normalised_aruser := normalize_and_check(aruser, v_local_vvc_cmd.user, ALLOW_WIDER_NARROWER, "aruser", "shared_vvc_cmd.auser", "Normalizing aruser. " & add_msg_delimiter(msg));
    end if;
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, proc_call, msg, QUEUED, READ);

    -- v3
    v_local_vvc_cmd                     := shared_vvc_cmd.get(vvc_instance_idx);
    v_local_vvc_cmd.id                  := v_normalised_arid;
    v_local_vvc_cmd.addr                := v_normalised_araddr;
    v_local_vvc_cmd.len                 := arlen;
    v_local_vvc_cmd.size                := arsize;
    v_local_vvc_cmd.burst               := arburst;
    v_local_vvc_cmd.lock                := arlock;
    v_local_vvc_cmd.cache               := arcache;
    v_local_vvc_cmd.prot                := arprot;
    v_local_vvc_cmd.qos                 := arqos;
    v_local_vvc_cmd.region              := arregion;
    v_local_vvc_cmd.auser               := v_normalised_aruser;
    v_local_vvc_cmd.data_routing        := data_routing;
    v_local_vvc_cmd.parent_msg_id_panel := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(VVCT, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure;

  procedure axi_check(
    signal   VVCT                : inout t_vvc_target_record;
    constant vvc_instance_idx    : in integer;
    constant arid                : in std_logic_vector             := "";
    constant araddr              : in unsigned;
    constant arlen               : in unsigned(7 downto 0)         := (others => '0');
    constant arsize              : in integer range 1 to 128       := 4;
    constant arburst             : in t_axburst                    := INCR;
    constant arlock              : in t_axlock                     := NORMAL;
    constant arcache             : in std_logic_vector(3 downto 0) := (others => '0');
    constant arprot              : in t_axprot                     := UNPRIVILEGED_NONSECURE_DATA;
    constant arqos               : in std_logic_vector(3 downto 0) := (others => '0');
    constant arregion            : in std_logic_vector(3 downto 0) := (others => '0');
    constant aruser              : in std_logic_vector             := "";
    constant rdata_exp           : in t_slv_array;
    constant rresp_exp           : in t_xresp_array                := C_EMPTY_XRESP_ARRAY;
    constant ruser_exp           : in t_slv_array                  := C_EMPTY_SLV_ARRAY;
    constant msg                 : in string;
    constant alert_level         : in t_alert_level                := ERROR;
    constant scope               : in string                       := C_VVC_CMD_SCOPE_DEFAULT;
    constant parent_msg_id_panel : in t_msg_id_panel               := C_UNUSED_MSG_ID_PANEL -- Only intended for usage by parent HVVCs
  ) is
    constant proc_name : string := get_procedure_name_from_instance_name(vvc_instance_idx'instance_name);
    constant proc_call : string := proc_name & "(" & to_string(VVCT, vvc_instance_idx) -- First part common for all
                                   & ", " & to_string(araddr, HEX, AS_IS, INCL_RADIX) & ")";
    variable v_local_vvc_cmd     : t_vvc_cmd_record                                          := shared_vvc_cmd.get(vvc_instance_idx);
    variable v_normalised_arid   : std_logic_vector(v_local_vvc_cmd.id'length - 1 downto 0);
    variable v_normalised_araddr : unsigned(v_local_vvc_cmd.addr'length - 1 downto 0);
    variable v_normalised_aruser : std_logic_vector(v_local_vvc_cmd.auser'length - 1 downto 0);
    variable v_normalised_rdata  : t_slv_array(0 to v_local_vvc_cmd.data_array'length - 1)(v_local_vvc_cmd.data_array(0)'length - 1 downto 0);
    variable v_normalised_rresp  : t_xresp_array(0 to v_local_vvc_cmd.data_array'length - 1) := (others => ILLEGAL);
    variable v_normalised_ruser  : t_slv_array(0 to v_local_vvc_cmd.user_array'length - 1)(v_local_vvc_cmd.user_array(0)'length - 1 downto 0);
    variable v_msg_id_panel      : t_msg_id_panel                                            := shared_msg_id_panel.get(VOID);
  begin
    -- Normalizing inputs to the command record
    if arid'length = 0 then
      v_normalised_arid := C_VVC_CMD_DEFAULT.id;
    else
      v_normalised_arid := normalize_and_check(arid, v_local_vvc_cmd.id, ALLOW_WIDER_NARROWER, "arid", "shared_vvc_cmd.id", "Normalizing arid. " & add_msg_delimiter(msg));
    end if;
    v_normalised_araddr := normalize_and_check(araddr, v_local_vvc_cmd.addr, ALLOW_WIDER_NARROWER, "araddr", "shared_vvc_cmd.addr", msg);
    if aruser'length = 0 then
      v_normalised_aruser := C_VVC_CMD_DEFAULT.auser;
    else
      v_normalised_aruser := normalize_and_check(aruser, v_local_vvc_cmd.user, ALLOW_WIDER_NARROWER, "aruser", "shared_vvc_cmd.user", "Normalizing aruser. " & add_msg_delimiter(msg));
    end if;
    v_normalised_rdata  := normalize_and_check(rdata_exp, v_local_vvc_cmd.data_array, ALLOW_WIDER_NARROWER, "rdata_exp", "shared_vvc_cmd.data_array", "Normalizing rdata. " & add_msg_delimiter(msg));
    if rresp_exp'length = 1 and rresp_exp(0) = ILLEGAL then
      v_normalised_rresp := C_VVC_CMD_DEFAULT.resp_array;
    else
      if not rresp_exp'ascending then
        tb_error("The array rresp_exp is instantiated as 'downto', but only 'to' is supported" & add_msg_delimiter(msg), scope);
      else
        for i in 0 to minimum(rresp_exp'length, v_local_vvc_cmd.resp_array'length) - 1 loop
          v_normalised_rresp(i) := rresp_exp(i);
        end loop;
      end if;
    end if;
    if ruser_exp'length = 1 and ruser_exp(0)'length = 1 and ruser_exp(0) = "U" then
      v_normalised_ruser := C_VVC_CMD_DEFAULT.user_array;
    else
      v_normalised_ruser := normalize_and_check(ruser_exp, v_local_vvc_cmd.user_array, ALLOW_WIDER_NARROWER, "ruser_exp", "shared_vvc_cmd.user_array", "Normalizing ruser. " & add_msg_delimiter(msg));
    end if;
    -- Create command by setting common global 'VVCT' signal record and dedicated VVC 'shared_vvc_cmd' record
    -- locking semaphore in set_general_target_and_command_fields to gain exclusive right to VVCT and shared_vvc_cmd
    -- semaphore gets unlocked in await_cmd_from_sequencer of the targeted VVC
    set_general_target_and_command_fields(VVCT, vvc_instance_idx, proc_call, msg, QUEUED, CHECK);

    -- v3
    v_local_vvc_cmd                     := shared_vvc_cmd.get(vvc_instance_idx);
    v_local_vvc_cmd.id                  := v_normalised_arid;
    v_local_vvc_cmd.addr                := v_normalised_araddr;
    v_local_vvc_cmd.len                 := arlen;
    v_local_vvc_cmd.size                := arsize;
    v_local_vvc_cmd.burst               := arburst;
    v_local_vvc_cmd.lock                := arlock;
    v_local_vvc_cmd.cache               := arcache;
    v_local_vvc_cmd.prot                := arprot;
    v_local_vvc_cmd.qos                 := arqos;
    v_local_vvc_cmd.region              := arregion;
    v_local_vvc_cmd.auser               := v_normalised_aruser;
    v_local_vvc_cmd.data_array          := v_normalised_rdata;
    v_local_vvc_cmd.resp_array          := v_normalised_rresp;
    v_local_vvc_cmd.user_array          := v_normalised_ruser;
    v_local_vvc_cmd.alert_level         := alert_level;
    v_local_vvc_cmd.parent_msg_id_panel := parent_msg_id_panel;
    shared_vvc_cmd.set(v_local_vvc_cmd, vvc_instance_idx);

    if parent_msg_id_panel /= C_UNUSED_MSG_ID_PANEL then
      v_msg_id_panel := parent_msg_id_panel;
    end if;
    send_command_to_vvc(VVCT, std.env.resolution_limit, scope, v_msg_id_panel);
  end procedure;

  --==============================================================================
  -- Transaction info methods
  --==============================================================================
  procedure set_global_vvc_transaction_info(
    signal   vvc_transaction_info_trigger : inout std_logic;
    variable vvc_transaction_info_group   : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx                 : in natural;
    constant channel                      : in t_channel;
    constant vvc_cmd                      : in t_vvc_cmd_record;
    constant vvc_config                   : in t_vvc_config;
    constant scope                        : in string := C_VVC_CMD_SCOPE_DEFAULT
  ) is
    variable v_transaction_info_group : t_transaction_group := vvc_transaction_info_group.get(instance_idx, channel);
  begin
    case vvc_cmd.operation is
      when WRITE =>
        v_transaction_info_group.bt_wr.operation                             := vvc_cmd.operation;
        v_transaction_info_group.bt_wr.vvc_meta.msg(1 to vvc_cmd.msg'length) := vvc_cmd.msg;
        v_transaction_info_group.bt_wr.vvc_meta.cmd_idx                      := vvc_cmd.cmd_idx;
        v_transaction_info_group.bt_wr.transaction_status                    := IN_PROGRESS;
      when READ | CHECK =>
        v_transaction_info_group.bt_rd.operation                             := vvc_cmd.operation;
        v_transaction_info_group.bt_rd.vvc_meta.msg(1 to vvc_cmd.msg'length) := vvc_cmd.msg;
        v_transaction_info_group.bt_rd.vvc_meta.cmd_idx                      := vvc_cmd.cmd_idx;
        v_transaction_info_group.bt_rd.transaction_status                    := IN_PROGRESS;
      when others =>
        alert(TB_ERROR, "VVC operation not recognized");
    end case;

    vvc_transaction_info_group.set(v_transaction_info_group, instance_idx, channel);
    gen_pulse(vvc_transaction_info_trigger, 0 ns, "pulsing global vvc transaction info trigger", scope, ID_NEVER);
    wait for 0 ns;
  end procedure set_global_vvc_transaction_info;

  procedure set_arw_vvc_transaction_info(
    signal   vvc_transaction_info_trigger : inout std_logic;
    variable vvc_transaction_info_group   : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx                 : in natural;
    constant channel                      : in t_channel;
    constant vvc_cmd                      : in t_vvc_cmd_record;
    constant vvc_config                   : in t_vvc_config;
    constant scope                        : in string := C_VVC_CMD_SCOPE_DEFAULT
  ) is
    variable v_transaction_info_group : t_transaction_group := vvc_transaction_info_group.get(instance_idx, channel);
  begin
    case vvc_cmd.operation is
      when WRITE =>
        v_transaction_info_group.st_aw.operation                             := vvc_cmd.operation;
        v_transaction_info_group.st_aw.arwid                                 := vvc_cmd.aid;
        v_transaction_info_group.st_aw.arwaddr                               := vvc_cmd.addr;
        v_transaction_info_group.st_aw.arwlen                                := vvc_cmd.len;
        v_transaction_info_group.st_aw.arwsize                               := vvc_cmd.size;
        v_transaction_info_group.st_aw.arwburst                              := vvc_cmd.burst;
        v_transaction_info_group.st_aw.arwlock                               := vvc_cmd.lock;
        v_transaction_info_group.st_aw.arwcache                              := vvc_cmd.cache;
        v_transaction_info_group.st_aw.arwprot                               := vvc_cmd.prot;
        v_transaction_info_group.st_aw.arwqos                                := vvc_cmd.qos;
        v_transaction_info_group.st_aw.arwregion                             := vvc_cmd.region;
        v_transaction_info_group.st_aw.arwuser                               := vvc_cmd.auser;
        v_transaction_info_group.st_aw.vvc_meta.msg(1 to vvc_cmd.msg'length) := vvc_cmd.msg;
        v_transaction_info_group.st_aw.vvc_meta.cmd_idx                      := vvc_cmd.cmd_idx;
        v_transaction_info_group.st_aw.transaction_status                    := IN_PROGRESS;
      when READ | CHECK =>
        v_transaction_info_group.st_ar.operation                             := vvc_cmd.operation;
        v_transaction_info_group.st_ar.arwid                                 := vvc_cmd.aid;
        v_transaction_info_group.st_ar.arwaddr                               := vvc_cmd.addr;
        v_transaction_info_group.st_ar.arwlen                                := vvc_cmd.len;
        v_transaction_info_group.st_ar.arwsize                               := vvc_cmd.size;
        v_transaction_info_group.st_ar.arwburst                              := vvc_cmd.burst;
        v_transaction_info_group.st_ar.arwlock                               := vvc_cmd.lock;
        v_transaction_info_group.st_ar.arwcache                              := vvc_cmd.cache;
        v_transaction_info_group.st_ar.arwprot                               := vvc_cmd.prot;
        v_transaction_info_group.st_ar.arwqos                                := vvc_cmd.qos;
        v_transaction_info_group.st_ar.arwregion                             := vvc_cmd.region;
        v_transaction_info_group.st_ar.arwuser                               := vvc_cmd.auser;
        v_transaction_info_group.st_ar.vvc_meta.msg(1 to vvc_cmd.msg'length) := vvc_cmd.msg;
        v_transaction_info_group.st_ar.vvc_meta.cmd_idx                      := vvc_cmd.cmd_idx;
        v_transaction_info_group.st_ar.transaction_status                    := IN_PROGRESS;
      when others =>
        alert(TB_ERROR, "VVC operation not recognized");
    end case;

    vvc_transaction_info_group.set(v_transaction_info_group, instance_idx, channel);
    gen_pulse(vvc_transaction_info_trigger, 0 ns, "pulsing global vvc transaction info trigger", scope, ID_NEVER);
    wait for 0 ns;
  end procedure set_arw_vvc_transaction_info;

  procedure set_w_vvc_transaction_info(
    signal   vvc_transaction_info_trigger : inout std_logic;
    variable vvc_transaction_info_group   : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx                 : in natural;
    constant channel                      : in t_channel;
    constant vvc_cmd                      : in t_vvc_cmd_record;
    constant vvc_config                   : in t_vvc_config;
    constant scope                        : in string := C_VVC_CMD_SCOPE_DEFAULT
  ) is
    variable v_transaction_info_group : t_transaction_group := vvc_transaction_info_group.get(instance_idx, channel);
  begin
    v_transaction_info_group.st_w.operation                             := vvc_cmd.operation;
    v_transaction_info_group.st_w.wdata                                 := vvc_cmd.data_array;
    v_transaction_info_group.st_w.wstrb                                 := vvc_cmd.strb_array;
    v_transaction_info_group.st_w.wuser                                 := vvc_cmd.user_array;
    v_transaction_info_group.st_w.vvc_meta.msg(1 to vvc_cmd.msg'length) := vvc_cmd.msg;
    v_transaction_info_group.st_w.vvc_meta.cmd_idx                      := vvc_cmd.cmd_idx;
    v_transaction_info_group.st_w.transaction_status                    := IN_PROGRESS;

    vvc_transaction_info_group.set(v_transaction_info_group, instance_idx, channel);
    gen_pulse(vvc_transaction_info_trigger, 0 ns, "pulsing global vvc transaction info trigger", scope, ID_NEVER);
    wait for 0 ns;
  end procedure set_w_vvc_transaction_info;

  procedure set_b_vvc_transaction_info(
    signal   vvc_transaction_info_trigger : inout std_logic;
    variable vvc_transaction_info_group   : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx                 : in natural;
    constant channel                      : in t_channel;
    constant vvc_cmd                      : in t_vvc_cmd_record;
    constant vvc_config                   : in t_vvc_config;
    constant scope                        : in string := C_VVC_CMD_SCOPE_DEFAULT
  ) is
    variable v_transaction_info_group : t_transaction_group := vvc_transaction_info_group.get(instance_idx, channel);
  begin
    v_transaction_info_group.st_b.operation                             := vvc_cmd.operation;
    v_transaction_info_group.st_b.bid                                   := vvc_cmd.id;
    v_transaction_info_group.st_b.bresp                                 := vvc_cmd.resp;
    v_transaction_info_group.st_b.buser                                 := vvc_cmd.user;
    v_transaction_info_group.st_b.vvc_meta.msg(1 to vvc_cmd.msg'length) := vvc_cmd.msg;
    v_transaction_info_group.st_b.vvc_meta.cmd_idx                      := vvc_cmd.cmd_idx;
    v_transaction_info_group.st_b.transaction_status                    := IN_PROGRESS;

    vvc_transaction_info_group.set(v_transaction_info_group, instance_idx, channel);
    gen_pulse(vvc_transaction_info_trigger, 0 ns, "pulsing global vvc transaction info trigger", scope, ID_NEVER);
    wait for 0 ns;
  end procedure set_b_vvc_transaction_info;

  procedure set_r_vvc_transaction_info(
    signal   vvc_transaction_info_trigger : inout std_logic;
    variable vvc_transaction_info_group   : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx                 : in natural;
    constant channel                      : in t_channel;
    constant vvc_cmd                      : in t_vvc_cmd_record;
    constant vvc_config                   : in t_vvc_config;
    constant scope                        : in string := C_VVC_CMD_SCOPE_DEFAULT
  ) is
    variable v_transaction_info_group : t_transaction_group := vvc_transaction_info_group.get(instance_idx, channel);
  begin
    v_transaction_info_group.st_r.operation                             := vvc_cmd.operation;
    v_transaction_info_group.st_r.rid                                   := vvc_cmd.id;
    v_transaction_info_group.st_r.rdata                                 := vvc_cmd.data_array;
    v_transaction_info_group.st_r.rresp                                 := vvc_cmd.resp_array;
    v_transaction_info_group.st_r.ruser                                 := vvc_cmd.user_array;
    v_transaction_info_group.st_r.vvc_meta.msg(1 to vvc_cmd.msg'length) := vvc_cmd.msg;
    v_transaction_info_group.st_r.vvc_meta.cmd_idx                      := vvc_cmd.cmd_idx;
    v_transaction_info_group.st_r.transaction_status                    := IN_PROGRESS;

    vvc_transaction_info_group.set(v_transaction_info_group, instance_idx, channel);
    gen_pulse(vvc_transaction_info_trigger, 0 ns, "pulsing global vvc transaction info trigger", scope, ID_NEVER);
    wait for 0 ns;
  end procedure set_r_vvc_transaction_info;

  procedure reset_vvc_transaction_info(
    variable vvc_transaction_info_group : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx               : in natural;
    constant channel                    : in t_channel;
    constant vvc_cmd                    : in t_vvc_cmd_record
  ) is
    variable v_transaction_info_group : t_transaction_group := vvc_transaction_info_group.get(instance_idx, channel);
  begin
    case vvc_cmd.operation is
      when WRITE =>
        if vvc_cmd.cmd_idx = v_transaction_info_group.bt_wr.vvc_meta.cmd_idx then
          v_transaction_info_group.bt_wr := C_BASE_TRANSACTION_SET_DEFAULT;
          vvc_transaction_info_group.set(v_transaction_info_group, instance_idx, channel);
        end if;
      when READ | CHECK =>
        if vvc_cmd.cmd_idx = v_transaction_info_group.bt_rd.vvc_meta.cmd_idx then
          v_transaction_info_group.bt_rd := C_BASE_TRANSACTION_SET_DEFAULT;
          vvc_transaction_info_group.set(v_transaction_info_group, instance_idx, channel);
        end if;
      when others =>
        null;
    end case;
    wait for 0 ns;
  end procedure reset_vvc_transaction_info;

  procedure reset_arw_vvc_transaction_info(
    variable vvc_transaction_info_group : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx               : in natural;
    constant channel                    : in t_channel;
    constant vvc_cmd                    : in t_vvc_cmd_record
  ) is
    variable v_transaction_info_group : t_transaction_group := vvc_transaction_info_group.get(instance_idx, channel);
  begin
    case vvc_cmd.operation is
      when WRITE =>
        v_transaction_info_group.st_aw := C_ARW_TRANSACTION_DEFAULT;
        vvc_transaction_info_group.set(v_transaction_info_group, instance_idx, channel);
      when READ | CHECK =>
        v_transaction_info_group.st_ar := C_ARW_TRANSACTION_DEFAULT;
        vvc_transaction_info_group.set(v_transaction_info_group, instance_idx, channel);
      when others =>
        null;
    end case;
    wait for 0 ns;
  end procedure reset_arw_vvc_transaction_info;

  procedure reset_w_vvc_transaction_info(
    variable vvc_transaction_info_group : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx               : in natural;
    constant channel                    : in t_channel
  ) is
    variable v_transaction_info_group : t_transaction_group := vvc_transaction_info_group.get(instance_idx, channel);
  begin
    v_transaction_info_group.st_w := C_W_TRANSACTION_DEFAULT;
    vvc_transaction_info_group.set(v_transaction_info_group, instance_idx, channel);
  end procedure reset_w_vvc_transaction_info;

  procedure reset_b_vvc_transaction_info(
    variable vvc_transaction_info_group : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx               : in natural;
    constant channel                    : in t_channel
  ) is
    variable v_transaction_info_group : t_transaction_group := vvc_transaction_info_group.get(instance_idx, channel);
  begin
    v_transaction_info_group.st_b := C_B_TRANSACTION_DEFAULT;
    vvc_transaction_info_group.set(v_transaction_info_group, instance_idx, channel);
  end procedure reset_b_vvc_transaction_info;

  procedure reset_r_vvc_transaction_info(
    variable vvc_transaction_info_group : inout protected_vvc_transaction_info_pkg.t_prot_generic_array; -- v3 t_transaction_group;
    constant instance_idx               : in natural;
    constant channel                    : in t_channel
  ) is
    variable v_transaction_info_group : t_transaction_group := vvc_transaction_info_group.get(instance_idx, channel);
  begin
    v_transaction_info_group.st_r := C_R_TRANSACTION_DEFAULT;
    vvc_transaction_info_group.set(v_transaction_info_group, instance_idx, channel);
  end procedure reset_r_vvc_transaction_info;

  --==============================================================================
  -- VVC Activity
  --==============================================================================
  procedure update_vvc_activity_register(signal   global_trigger_vvc_activity_register : inout std_logic;
                                         variable vvc_status                           : inout protected_vvc_status_pkg.t_prot_generic_array;
                                         constant instance_idx                         : in natural;
                                         constant channel                              : in t_channel;
                                         constant activity                             : in t_activity;
                                         constant entry_num_in_vvc_activity_register   : in integer;
                                         constant last_cmd_idx_executed                : in natural;
                                         constant command_queue_is_empty               : in boolean;
                                         constant scope                                : in string := C_VVC_NAME) is
    variable v_activity   : t_activity   := activity;
    variable v_vvc_status : t_vvc_status := vvc_status.get(instance_idx, channel);
  begin
    -- Update vvc_status after a command has finished (during same delta cycle the activity register is updated)
    if activity = INACTIVE then
      v_vvc_status.previous_cmd_idx := last_cmd_idx_executed;
      v_vvc_status.current_cmd_idx  := 0;
    end if;
    vvc_status.set(v_vvc_status, instance_idx, channel);

    if v_activity = INACTIVE and not (command_queue_is_empty) then
      v_activity := ACTIVE;
    end if;
    shared_vvc_activity_register.priv_report_vvc_activity(vvc_idx               => entry_num_in_vvc_activity_register,
                                                          activity              => v_activity,
                                                          last_cmd_idx_executed => last_cmd_idx_executed);
    if global_trigger_vvc_activity_register /= 'L' then
      wait until global_trigger_vvc_activity_register = 'L';
    end if;
    gen_pulse(global_trigger_vvc_activity_register, 0 ns, "pulsing global trigger for vvc activity register", scope, ID_NEVER);
  end procedure;

end package body vvc_methods_pkg;

