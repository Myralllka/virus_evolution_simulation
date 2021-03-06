#include <iostream>
#include <option_parser/ConfigFileOpt.h>
#include <speed_tester.h>
#include <cuda_impl/cuda_integrate.cuh>


int main(int argc, char *argv[]) {
//  //////////////////////////// Program Parameter Parsing ////////////////////////////
    std::string file_name = "execution.conf";
    if (argc == 2) {
        file_name = argv[1];
    } else if (argc > 2) {
        std::cerr << "Too many arguments. Usage:  <program> or "
                     "<program> <config-filename>\n" << std::endl;
        return 1;
    }

//  ////////////////////////////    Config File Parsing    ////////////////////////////
    ConfigFileOpt config{};
    try {
        config.parse(file_name);
    } catch (std::exception &ex) {
        std::cerr << "Error: " << ex.what() << std::endl;
        return 3;
    }

//  ////////////////////////////   Integration Initiation   ////////////////////////////
    size_t steps = config.get_init_steps();

    auto before = get_current_time_fenced();
    double cur_res = cuda_integrate(steps, config);

    double prev_res;
    bool to_continue = true;
    double abs_err = -1; // Just guard value
    double rel_err = -1; // Just guard value

//  ////////////////////////////   Main Calculation Cycle   ////////////////////////////
// #define PRINT_INTERMEDIATE_STEPS
    while (to_continue) {
#ifdef PRINT_INTERMEDIATE_STEPS
        std::cout << cur_res << " : " << steps << " steps" << std::endl;
#endif
        prev_res = cur_res;
        steps *= 2;
        cur_res = cuda_integrate(steps, config);
        std::cout << cur_res << std::endl;
        abs_err = fabs(cur_res - prev_res);
        rel_err = fabs((cur_res - prev_res) / cur_res);
#ifdef PRINT_INTERMEDIATE_STEPS
        std::cout << '\t' << "Abs err : rel err " << abs_err << " : " << rel_err << std::endl;
#endif
        to_continue = (abs_err > config.get_abs_pars());
        to_continue = to_continue && (rel_err > config.get_rel_pres());
        to_continue = to_continue && (steps < config.get_max_steps());
    }

    auto time_to_calculate = get_current_time_fenced() - before;

//  ////////////////////////////   Program Output Block   ////////////////////////////#
    std::cout << "Steps: " << steps << std::endl;
    std::cout << "Flows: " << config.get_flow_num() << std::endl;
    std::cout << "Result = " << cur_res << std::endl;
    std::cout << "Absolute_error = " << abs_err << std::endl;
    std::cout << "Relative_error = " << rel_err << std::endl;
    std::cout << "Time = " << to_us(time_to_calculate) << std::endl;

    return 0;
}
