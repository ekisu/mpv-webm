#pragma once

#include "windows.h"
#include <string>
#include <vector>
#include <optional>

class MpvIPC {
public:
    MpvIPC(HANDLE pipe);
    void close();
    void script_message_to(std::string script_name, std::vector<std::string> args);
    void quit();
private:
    std::string escape_string_json(std::string unescaped);
    std::string build_command_json(std::string command, std::vector<std::string> command_args);
    void read_message();
    void send_message(std::string message);

    HANDLE _pipe;
};

#define PIPE_TIMEOUT 20000

std::optional<MpvIPC> create_mpv_ipc(std::string pipe_name);