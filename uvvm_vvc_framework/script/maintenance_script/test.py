import sys
import os
import shutil
import mock
from itertools import product


try:
    from hdlregression import HDLRegression
except:
    print('Unable to import HDLRegression module. See HDLRegression documentation for installation instructions.')
    sys.exit(1)

sys.path.append('../script/vvc_generator')
import vvc_generator


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


def test_vvc_framework(): 
    print('Verify UVVM VVC Framework')

    hr = HDLRegression()

    # Add util, fw and VIP Scoreboard
    hr.add_files("../../../uvvm_util/src/*.vhd", "uvvm_util")
    hr.add_files("../../src/*.vhd", "uvvm_vvc_framework")
    hr.add_files("../../../bitvis_vip_scoreboard/src/*.vhd", "bitvis_vip_scoreboard")

    # Add TB/TH and dependencies
    hr.add_files("../../../bitvis_vip_uart/src/*.vhd", "bitvis_vip_uart")
    hr.add_files("../../src_target_dependent/*.vhd", "bitvis_vip_uart")

    hr.add_files("../../../bitvis_vip_sbi/src/*.vhd", "bitvis_vip_sbi")
    hr.add_files("../../src_target_dependent/*.vhd", "bitvis_vip_sbi")

    hr.add_files("../../../bitvis_uart/src/*.vhd", "bitvis_uart")

    hr.add_files("../../../bitvis_vip_avalon_mm/src/*.vhd", "bitvis_vip_avalon_mm")
    hr.add_files("../../src_target_dependent/*.vhd", "bitvis_vip_avalon_mm")

    hr.add_files("../../../bitvis_vip_axistream/src/*.vhd", "bitvis_vip_axistream")
    hr.add_files("../../src_target_dependent/*.vhd", "bitvis_vip_axistream")

    hr.add_files("../../tb/maintenance_tb/vvc_th.vhd", "testbench_lib")
    hr.add_files("../../tb/maintenance_tb/*vvc_tb.vhd", "testbench_lib")

    sim_options    = None
    global_options = None
    simulator_name = hr.settings.get_simulator_name()
    # Set simulator name and compile options
    if simulator_name in ["MODELSIM", "RIVIERA"]:
        sim_options = "-t ns"
        com_options = ["-suppress", "1346,1246,1236", "-2008"]
        hr.set_simulator(simulator=simulator_name, com_options=com_options)
    elif simulator_name == "NVC":
        global_options = ["--stderr=error", "--messages=compact", "-M64m", "-H128m"]

    hr.start(sim_options=sim_options, global_options=global_options)

    num_failing_tests = hr.get_num_fail_tests()
    num_passing_tests = hr.get_num_pass_tests()
    if num_passing_tests == 0:
        return 1
    else:
        return num_failing_tests


#######################
# VVC Generator tests
#######################
# Test 1: name, extended_features, concurrent_channels, vvc_multiple_executors
@mock.patch('vvc_generator.input', side_effect=['test_1', 'n', 1, 'n'])
def test_1(mock_choice):
    vvc_generator.main()

# Test 2: name, extended_features, concurrent_channels, vvc_multiple_executors, num_executors, exec_1_name, exec_2_name, ch_NA_mult_exec
@mock.patch('vvc_generator.input', side_effect=['test_2', 'n', 1, 'y', 3, 'response', 'request', 'n'])
def test_2(mock_choice):
    vvc_generator.main()

# Test 3: name, extended_features, concurrent_channels, vvc_multiple_executors, num_executors, exec_1_name, exec_2_name, ch_NA_mult_exec, num_exec, exec_name
@mock.patch('vvc_generator.input', side_effect=['test_3', 'n', 1, 'y', 3, 'response', 'request', 'y', 2, 'response2'])
def test_3(mock_choice):
    vvc_generator.main()

# Test 4: name, extended_features, concurrent_channels, ch_0_name, ch_1_name, ch_num_executors
@mock.patch('vvc_generator.input', side_effect=['test_4', 'n', 2, 'RX', 'TX', 0])
def test_4(mock_choice):
    vvc_generator.main()

# Test 5: name, extended_features, concurrent_channels, ch_0_name, ch_1_name, ch_num_executors, ch_0_exec, ch_0_num_exec, ch_0_exec_name
@mock.patch('vvc_generator.input', side_effect=['test_5', 'n', 2, 'RX', 'TX', 1, 'y', 3, 'response', 'request'])
def test_5(mock_choice):
    vvc_generator.main()

# Test 6: name, extended_features, scoreboard, transaction_info, unwanted_activity, concurrent_channels, vvc_multiple_executors
@mock.patch('vvc_generator.input', side_effect=['test_6', 'y', 'n', 'n', 'n', 1, 'n'])
def test_6(mock_choice):
    vvc_generator.main()

# Test 7: name, extended_features, scoreboard, transaction_info, unwanted_activity, concurrent_channels, vvc_multiple_executors
@mock.patch('vvc_generator.input', side_effect=['test_7', 'y', 'n', 'y', 'n', 1, 'n'])
def test_7(mock_choice):
    vvc_generator.main()

# Test 8: name, extended_features, scoreboard, transaction_info, unwanted_activity, concurrent_channels, vvc_multiple_executors
@mock.patch('vvc_generator.input', side_effect=['test_8', 'y', 'y', 'n', 'n', 1, 'n'])
def test_8(mock_choice):
    vvc_generator.main()

# Test 9: name, extended_features, scoreboard, transaction_info, unwanted_activity, concurrent_channels, vvc_multiple_executors
@mock.patch('vvc_generator.input', side_effect=['test_9', 'y', 'y', 'y', 'n', 1, 'n'])
def test_9(mock_choice):
    vvc_generator.main()

# Test 10: name, extended_features, scoreboard, transaction_info, unwanted_activity, concurrent_channels, ch_0_name, ch_1_name, ch_num_executors, ch_0_exec, ch_0_num_exec, ch_0_exec_name
@mock.patch('vvc_generator.input', side_effect=['test_10', 'y', 'y', 'y', 'n', 2, 'RX', 'TX', 1, 'y', 3, 'response', 'request'])
def test_10(mock_choice):
    vvc_generator.main()

# Test 11: name, extended_features, scoreboard, transaction_info, unwanted_activity, concurrent_channels, vvc_multiple_executors
@mock.patch('vvc_generator.input', side_effect=['test_11', 'y', 'n', 'n', 'y', 1, 'n'])
def test_11(mock_choice):
    vvc_generator.main()

# Test 12: name, extended_features, scoreboard, transaction_info, unwanted_activity, concurrent_channels, vvc_multiple_executors
@mock.patch('vvc_generator.input', side_effect=['test_12', 'y', 'y', 'n', 'y', 1, 'n'])
def test_12(mock_choice):
    vvc_generator.main()

# Test 13: name, extended_features, scoreboard, transaction_info, unwanted_activity, concurrent_channels, vvc_multiple_executors
@mock.patch('vvc_generator.input', side_effect=['test_13', 'y', 'y', 'y', 'y', 1, 'n'])
def test_13(mock_choice):
    vvc_generator.main()

# Test 14: name, extended_features, scoreboard, transaction_info, unwanted_activity, concurrent_channels, ch_0_name, ch_1_name, ch_num_executors, ch_0_exec, ch_0_num_exec, ch_0_exec_name
@mock.patch('vvc_generator.input', side_effect=['test_14', 'y', 'y', 'y', 'y', 2, 'RX', 'TX', 1, 'y', 3, 'response', 'request'])
def test_14(mock_choice):
    vvc_generator.main()


def test_vvc_generator():
    print('Verify UVVM VVC Generator')

    # Generate the files with different inputs
    test_1()
    os.rename("output", "generated_vip_1")
    test_2()
    os.rename("output", "generated_vip_2")
    test_3()
    os.rename("output", "generated_vip_3")
    test_4()
    os.rename("output", "generated_vip_4")
    test_5()
    os.rename("output", "generated_vip_5")
    test_6()
    os.rename("output", "generated_vip_6")
    test_7()
    os.rename("output", "generated_vip_7")
    test_8()
    os.rename("output", "generated_vip_8")
    test_9()
    os.rename("output", "generated_vip_9")
    test_10()
    os.rename("output", "generated_vip_10")
    test_11()
    os.rename("output", "generated_vip_11")
    test_12()
    os.rename("output", "generated_vip_12")
    test_13()
    os.rename("output", "generated_vip_13")
    test_14()
    os.rename("output", "generated_vip_14")

    hr = HDLRegression()

    # Add util, fw and VIP Scoreboard
    hr.add_files("../../../uvvm_util/src/*.vhd", "uvvm_util")
    hr.add_files("../../src/*.vhd", "uvvm_vvc_framework")
    hr.add_files("../../../bitvis_vip_scoreboard/src/*.vhd", "bitvis_vip_scoreboard")

    # Add generated files
    hr.add_files("../../sim/generated_vip_1/*.vhd", "vip_test_1")
    hr.add_files("../../src_target_dependent/*.vhd", "vip_test_1")

    hr.add_files("../../sim/generated_vip_2/*.vhd", "vip_test_2")
    hr.add_files("../../src_target_dependent/*.vhd", "vip_test_2")

    hr.add_files("../../sim/generated_vip_3/*.vhd", "vip_test_3")
    hr.add_files("../../src_target_dependent/*.vhd", "vip_test_3")

    hr.add_files("../../sim/generated_vip_4/*.vhd", "vip_test_4")
    hr.add_files("../../src_target_dependent/*.vhd", "vip_test_4")

    hr.add_files("../../sim/generated_vip_5/*.vhd", "vip_test_5")
    hr.add_files("../../src_target_dependent/*.vhd", "vip_test_5")

    hr.add_files("../../sim/generated_vip_6/*.vhd", "vip_test_6")
    hr.add_files("../../src_target_dependent/*.vhd", "vip_test_6")

    hr.add_files("../../sim/generated_vip_7/*.vhd", "vip_test_7")
    hr.add_files("../../src_target_dependent/*.vhd", "vip_test_7")

    hr.add_files("../../sim/generated_vip_8/*.vhd", "vip_test_8")
    hr.add_files("../../src_target_dependent/*.vhd", "vip_test_8")

    hr.add_files("../../sim/generated_vip_9/*.vhd", "vip_test_9")
    hr.add_files("../../src_target_dependent/*.vhd", "vip_test_9")

    hr.add_files("../../sim/generated_vip_10/*.vhd", "vip_test_10")
    hr.add_files("../../src_target_dependent/*.vhd", "vip_test_10")

    hr.add_files("../../sim/generated_vip_11/*.vhd", "vip_test_11")
    hr.add_files("../../src_target_dependent/*.vhd", "vip_test_11")

    hr.add_files("../../sim/generated_vip_12/*.vhd", "vip_test_12")
    hr.add_files("../../src_target_dependent/*.vhd", "vip_test_12")

    hr.add_files("../../sim/generated_vip_13/*.vhd", "vip_test_13")
    hr.add_files("../../src_target_dependent/*.vhd", "vip_test_13")

    hr.add_files("../../sim/generated_vip_14/*.vhd", "vip_test_14")
    hr.add_files("../../src_target_dependent/*.vhd", "vip_test_14")

    # Add a testbench to detect whether compilation passed or failed using get_num_pass_tests()
    hr.add_files("../../tb/maintenance_tb/vvc_generator_tb.vhd", "testbench_lib")

    sim_options = None
    simulator_name = hr.settings.get_simulator_name()
    # Set simulator name and compile options
    if simulator_name in ["MODELSIM", "RIVIERA"]:
        sim_options = "-t ns"
        com_options = ["-suppress", "1346,1246,1236", "-2008"]
        hr.set_simulator(simulator=simulator_name, com_options=com_options)

    hr.start(sim_options=sim_options)

    num_passing_tests = hr.get_num_pass_tests()
    if num_passing_tests == 0:
        return 1
    else:
        return 0


def main():
    cleanup('Removing any previous runs.')
    num_fw_errors = test_vvc_framework()
    num_gen_errors = test_vvc_generator()

    # Remove output only if OK
    if num_fw_errors == 0 and num_gen_errors == 0:
        cleanup('Removing simulation output')
    # Return number of failing tests
    sys.exit(num_fw_errors + num_gen_errors)

if __name__ == '__main__':
    main()
