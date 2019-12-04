#include <windows.h>
#include <iostream>
#include <cstdio>
#include <optional>
#include "process.hpp"
#include "mpv_ipc.hpp"

void usage(const char* program_name) {
    printf(
        "Usage: %s ipc_socket script_name program [arguments...]\n"
        "where:\n"
        "\tipc_socket:\tthe mpv process input-ipc-server socket.\n"
        "\tscript_name:\tthe name of the script that the console output should be sent to.\n"
        "\tprogram:\tthe program name.\n"
        "\targuments:\targuments to the called program.\n", program_name);
}

void read_process_output_into_mpv_ipc(
    Process& process,
    MpvIPC& mpv_ipc,
    const std::string& script_name
) {
    std::optional<std::string> line;
    while (line = process.read_line()) {
        mpv_ipc.script_message_to(script_name, { "process-line", *line });
    }
}

int main(int argc, const char* argv[])
{
    if (argc < 4) {
        usage(argv[0]);
        return 1;
    }

    std::string pipe_name(argv[1]);
    std::string script_name(argv[2]);

    std::cout << "Piping to " << pipe_name << ", with script name " << script_name << std::endl;

    std::optional<MpvIPC> mpv_ipc;
    if (!(mpv_ipc = create_mpv_ipc(pipe_name))) {
        std::cerr << "Couldn't create MPV's IPC channel!" << std::endl;
        return 1;
    }

    std::optional<Process> process;
    if (!(process = create_process(&argv[3]))) {
        std::cerr << "Couldn't create process!" << std::endl;
        return 1;
    }

    read_process_output_into_mpv_ipc(*process, *mpv_ipc, script_name);

    mpv_ipc->close();
    return 0;
}
