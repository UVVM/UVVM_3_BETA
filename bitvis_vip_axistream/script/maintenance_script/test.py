import sys
import os
import shutil
from itertools import product


try:
    from hdlregression import HDLRegression
except:
    print('Unable to import HDLRegression module. See HDLRegression documentation for installation instructions.')
    sys.exit(1)


# Clean the sim directory
def cleanup(msg='Cleaning up...'):
    print(msg)
    sim_path = os.getcwd()
    # Check if the current directory is 'sim'
    if os.path.basename(sim_path) == 'sim':
        for files in os.listdir(sim_path):
            path = os.path.join(sim_path, files)
            try:
                shutil.rmtree(path)
            except:
                os.remove(path)
    else:
        print('Current directory is not "sim". Skipping cleanup.')


# Create testbench configuration with TB generics
def create_config(data_widths, user_widths, id_widths, dest_widths, include_tuser=False, use_setup_and_hold=False):
    config = []
    for data_width, user_width, id_width, dest_width, tuser, setup_and_hold in product(data_widths, user_widths, id_widths, dest_widths, include_tuser, use_setup_and_hold):
        config.append([str(data_width), str(user_width), str(id_width), str(dest_width), str(tuser), str(setup_and_hold)])
    return config


print('Verify Bitvis VIP AXI Stream')

cleanup('Removing any previous runs.')

hr = HDLRegression()

# Add util, fw and VIP Scoreboard
hr.add_files("../../../uvvm_util/src/*.vhd", "uvvm_util")
hr.add_files("../../../uvvm_vvc_framework/src/*.vhd", "uvvm_vvc_framework")
hr.add_files("../../../bitvis_vip_scoreboard/src/*.vhd", "bitvis_vip_scoreboard")
# Add AXI-Stream VIP
hr.add_files("../../src/*.vhd", "bitvis_vip_axistream")
hr.add_files("../../../uvvm_vvc_framework/src_target_dependent/*.vhd", "bitvis_vip_axistream")
# Add TB/TH
hr.add_files("../../tb/maintenance_tb/*.vhd", "bitvis_vip_axistream")

# Setup TB test generics
configs = create_config(data_widths=[32], user_widths=[8], id_widths=[7], dest_widths=[4], include_tuser=[False], use_setup_and_hold=[True, False])
for config in configs:
    hr.add_generics(entity="axistream_bfm_tb",
                    generics=["GC_DATA_WIDTH", config[0], "GC_USER_WIDTH", config[1], "GC_ID_WIDTH", config[2], "GC_DEST_WIDTH", config[3], "GC_INCLUDE_TUSER", config[4], "GC_USE_SETUP_AND_HOLD", config[5]])

configs = create_config(data_widths=[8, 16, 24, 64, 128], user_widths=[8, 16], id_widths=[8], dest_widths=[4], include_tuser=[True], use_setup_and_hold=[True])
for config in configs:
    hr.add_generics(entity="axistream_vvc_tb",
                    generics=["GC_DATA_WIDTH", config[0], "GC_USER_WIDTH", config[1], "GC_ID_WIDTH", config[2], "GC_DEST_WIDTH", config[3], "GC_INCLUDE_TUSER", config[4], "GC_USE_SETUP_AND_HOLD", config[5]])

configs = create_config(data_widths=[32], user_widths=[1, 5], id_widths=[3, 7], dest_widths=[1], include_tuser=[True], use_setup_and_hold=[False])
for config in configs:
    hr.add_generics(entity="axistream_vvc_tb",
                    generics=["GC_DATA_WIDTH", config[0], "GC_USER_WIDTH", config[1], "GC_ID_WIDTH", config[2], "GC_DEST_WIDTH", config[3], "GC_INCLUDE_TUSER", config[4], "GC_USE_SETUP_AND_HOLD", config[5]])

hr.add_generics(entity="axistream_vvc_tb",
                generics=["GC_DATA_WIDTH", 32, "GC_USER_WIDTH", 1, "GC_ID_WIDTH", 1, "GC_DEST_WIDTH", 1, "GC_INCLUDE_TUSER", False, "GC_USE_SETUP_AND_HOLD", True])

hr.add_generics(entity="axistream_vvc_multiple_tb",
                generics=["GC_DATA_WIDTH", 32, "GC_USER_WIDTH", 1, "GC_ID_WIDTH", 1, "GC_DEST_WIDTH", 1, "GC_INCLUDE_TUSER", True, "GC_USE_SETUP_AND_HOLD", True])

hr.add_generics(entity="axistream_vvc_multiple_tb",
                generics=["GC_DATA_WIDTH", 32, "GC_USER_WIDTH", 8, "GC_ID_WIDTH", 7, "GC_DEST_WIDTH", 4, "GC_INCLUDE_TUSER", True, "GC_USE_SETUP_AND_HOLD", False])

hr.add_generics(entity="axistream_vvc_width_tb",
                generics=["GC_DATA_WIDTH", 32, "GC_USER_WIDTH", 1, "GC_ID_WIDTH", 1, "GC_DEST_WIDTH", 1, "GC_INCLUDE_TUSER", True, "GC_USE_SETUP_AND_HOLD", True])

# Set simulator name and options
sim_options    = None
global_options = None
simulator_name = hr.settings.get_simulator_name()
if simulator_name == "MODELSIM":
    sim_options = "-t ps"
elif simulator_name == "NVC":
    global_options = ["--stderr=error", "--messages=compact", "-M64m", "-H2g"]
elif simulator_name == "RIVIERA-PRO":
    com_options = ["-2008", "-nowarn", "COMP96_0564", "-nowarn", "COMP96_0048", "-nowarn", "DAGGEN_0001"]
    com_options += ["-O0"] # Needs optimization level 0 to avoid optimizing away some testbench signals
    hr.set_simulator(simulator=simulator_name, com_options=com_options)

hr.start(sim_options=sim_options, global_options=global_options)

num_failing_tests = hr.get_num_fail_tests()
num_passing_tests = hr.get_num_pass_tests()

# No tests run error
if num_passing_tests == 0:
    sys.exit(1)
# Remove output only if OK
if hr.check_run_results(exp_fail=0) is True:
    cleanup('Removing simulation output')

# Run alternative simulation scripts
if simulator_name == "MODELSIM" or simulator_name == "RIVIERA-PRO":
    print('\nVerify .do scripts...')
    (ret_txt, ret_code) = hr.run_command(["vsim", "-c", "-do", "do ../script/compile_src.do ../../uvvm_util ../../uvvm_util/sim; exit"], False)
    (ret_txt, ret_code) = hr.run_command(["vsim", "-c", "-do", "do ../script/compile_bfm.do; exit"], False)
    if ret_code == 0:
        print("SIMULATION SUCCESS")
        cleanup('Removing simulation output\n')
    else:
        print(ret_txt)
        num_failing_tests += 1

# Return number of failing tests
sys.exit(num_failing_tests)
