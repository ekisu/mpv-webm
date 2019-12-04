#pragma once

#include <windows.h>
#include <string>
#include <optional>

#define PROCESS_WAIT_MS 50

class Process {
public:
    Process(PROCESS_INFORMATION pi, HANDLE _pipe_read, HANDLE _pipe_write);
    std::optional<std::string> read_line();
private:
    void read_into_buffer();

    PROCESS_INFORMATION _pi;
    HANDLE _pipe_read;
    HANDLE _pipe_write;
    bool _process_ended;
    std::string _process_output_buffer;
};

std::optional<Process> create_process(const char* argv[]);
