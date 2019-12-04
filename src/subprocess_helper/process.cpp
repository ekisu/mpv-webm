#include "process.hpp"
#include "command_line.hpp"
#include <algorithm>
#include <iostream>

Process::Process(PROCESS_INFORMATION pi, HANDLE pipe_read, HANDLE pipe_write) :
    _pi(pi),
    _pipe_read(pipe_read),
    _pipe_write(pipe_write),
    _process_ended(false),
    _process_output_buffer("") {}

std::optional<std::string> Process::read_line() {
    std::cout << "waiting for read." << std::endl;
    std::size_t newline_pos = std::string::npos;

    while ((newline_pos = _process_output_buffer.find("\n")) == std::string::npos
        && !_process_ended) {
        read_into_buffer();
    }

    if (_process_output_buffer.empty()) {
        return std::nullopt;
    }
    
    std::string ret;
    if (newline_pos != std::string::npos) {
        ret = _process_output_buffer.substr(0, newline_pos);
        _process_output_buffer = _process_output_buffer.substr(newline_pos + 1);
    } else {
        ret = _process_output_buffer;
        _process_output_buffer = "";
    }

    return ret;
}

void Process::read_into_buffer() {
    _process_ended = WaitForSingleObject(_pi.hProcess, PROCESS_WAIT_MS) == WAIT_OBJECT_0;
    char buf[1024];

    while (true) {
        DWORD readBytes = 0;
        DWORD availableBytes = 0;

        if (!PeekNamedPipe(_pipe_read, NULL, 0, NULL, &availableBytes, NULL)) {
            break;
        }

        if (!availableBytes) {
            break;
        }

        DWORD bytesToBeRead = std::min(static_cast<DWORD>(sizeof(buf) - 1), availableBytes);

        if (!ReadFile(_pipe_read, buf, bytesToBeRead, &readBytes, NULL)) {
            break;
        }

        buf[readBytes] = '\0';
        _process_output_buffer += buf;
    }
}

std::optional<Process> create_process(const char* argv[]) {
    HANDLE pipe_read, pipe_write;
    SECURITY_ATTRIBUTES sa;

    sa.nLength = sizeof(SECURITY_ATTRIBUTES);
    sa.bInheritHandle = TRUE;
    sa.lpSecurityDescriptor = NULL;

    if (!CreatePipe(&pipe_read, &pipe_write, &sa, 0)) {
        return std::nullopt;
    }

    std::wstring cmdline = argument_list_to_windows_cmdline(argv);

    STARTUPINFOW si = {sizeof(STARTUPINFOW)};
    si.dwFlags     = STARTF_USESHOWWINDOW | STARTF_USESTDHANDLES;
    si.hStdOutput  = pipe_write;
    si.hStdError   = pipe_write;
    si.wShowWindow = SW_HIDE; // Prevents cmd window from flashing.
                              // Requires STARTF_USESHOWWINDOW in dwFlags.

    PROCESS_INFORMATION pi = { 0 };

    // Not sure if the cast here is safe, but we won't use the cmdline after this anyway.
    BOOL create_success = CreateProcessW(NULL, (LPWSTR)cmdline.c_str(), NULL, NULL, TRUE, CREATE_NEW_CONSOLE, NULL, NULL, &si, &pi);
    if (!create_success)
    {
        CloseHandle(pipe_read);
        CloseHandle(pipe_write);
        return std::nullopt;
    }

    return std::make_optional(Process(pi, pipe_read, pipe_write));
}
