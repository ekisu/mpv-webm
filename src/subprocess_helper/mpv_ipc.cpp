#include "mpv_ipc.hpp"
#include <iostream>
#include <sstream>
#include <iomanip>

MpvIPC::MpvIPC(HANDLE pipe) : _pipe(pipe) {

}

void MpvIPC::read_message() {
    // We don't really need to know what mpv replies, but we need to
    // clean the pipe buffers anyway.

    char buf[1024];
    BOOL success = TRUE;
    DWORD readBytes;

    do {
        success = ReadFile( 
            _pipe,    // pipe handle 
            buf,    // buffer to receive reply 
            sizeof(buf),  // size of buffer 
            &readBytes,  // number of bytes read 
            NULL);    // not overlapped 
 
        if (!success && GetLastError() != ERROR_MORE_DATA)
            break; 
    } while (!success);
}

void MpvIPC::send_message(std::string message) {
    std::cout << "MpvIPC::send_message: " << message << std::endl;

    auto length = message.size(); // We explictily discard the NULL terminator.
    DWORD writtenBytes;
    auto success = WriteFile(
        this->_pipe,
        message.c_str(), 
        length,
        &writtenBytes,
        NULL);
    
    if (!success) {
        auto lastError = GetLastError();
        std::cerr << "Couldn't write message " << message << " to mpv's IPC pipe. (GLE=" << lastError << ") Exiting." << std::endl;
        abort();
    }

    read_message(); // Read mpv's reply, to clean the pipe.
}

std::string MpvIPC::escape_string_json(std::string unescaped) {
    // copypasted code yummy
    std::ostringstream o;
    for (auto c = unescaped.cbegin(); c != unescaped.cend(); c++) {
        if (*c == '"' || *c == '\\' || ('\x00' <= *c && *c <= '\x1f')) {
            o << "\\u"
              << std::hex << std::setw(4) << std::setfill('0') << (int)*c;
        } else {
            o << *c;
        }
    }

    return o.str();
}

std::string MpvIPC::build_command_json(
    std::string command_name,
    std::vector<std::string> command_args) {
    std::stringstream ss;

    ss << "{ \"command\": [";
    // TODO escape the command name/args properly.
    ss << "\"" << escape_string_json(command_name) << "\"";

    for (auto& arg : command_args) {
        ss << ", \"" << escape_string_json(arg) << "\"";
    }

    ss << "] }\n";

    return ss.str();
}

void MpvIPC::script_message_to(
    std::string script_name,
    std::vector<std::string> args) {
    args.emplace(args.begin(), script_name);

    auto json_message = build_command_json("script-message-to", args);
    send_message(json_message);
}

void MpvIPC::quit() {
    auto json_message = build_command_json("quit", {});
    send_message(json_message);
}

void MpvIPC::close() {
    CloseHandle(_pipe);
}

std::optional<MpvIPC> create_mpv_ipc(std::string pipe_path) {
    HANDLE pipe;

    while (true) {
        pipe = CreateFileA(
            pipe_path.c_str(),
            GENERIC_READ | GENERIC_WRITE,  // read & write access
            0,              // no sharing 
            NULL,           // default security attributes
            OPEN_EXISTING,  // opens existing pipe 
            0,              // default attributes 
            NULL);          // no template file 
        
        if (pipe != INVALID_HANDLE_VALUE) {
            break;
        }

        if (GetLastError() != ERROR_PIPE_BUSY) {
            auto lastError = GetLastError();
            std::cerr << "Couldn't open pipe. GLE=" << lastError << std::endl;
            return std::nullopt;
        }

        if (!WaitNamedPipeA(pipe_path.c_str(), PIPE_TIMEOUT)) {
            std::cerr << "Timed out while waiting for named pipe." << std::endl;
            return std::nullopt;
        }
    }
    
    DWORD dwMode = PIPE_READMODE_MESSAGE; 
    auto success = SetNamedPipeHandleState( 
        pipe,    // pipe handle 
        &dwMode,  // new pipe mode 
        NULL,     // don't set maximum bytes 
        NULL);    // don't set maximum time 
    
    if (!success) {
        std::cerr << "SetNamedPipeHandleState failed. GLE=" << GetLastError() << std::endl;
        return std::nullopt;
    }

    return std::make_optional(MpvIPC(pipe));
}
