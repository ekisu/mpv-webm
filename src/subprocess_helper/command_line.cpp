// Mostly a C++ rewrite of mpv's osdep/subprocess-win.c command line manipulation
// functions.

#include "command_line.hpp"
#include <cstring>
#include <string>
#include <sstream>
#include <vector>
#include <windows.h>

std::wstring from_utf8(std::string s) {
    int count = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, NULL, 0);
    if (count <= 0)
        abort();

    std::vector<wchar_t> buffer(count);
    MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, &buffer[0], count);

    return std::wstring(&buffer[0], count);
}

std::string escape_argument(const char* arg) {
    // Empty args must be represented as an empty quoted string
    if (!arg[0]) {
        return "\"\"";
    }

    // If the string doesn't have characters that need to be escaped, it's best
    // to leave it alone for the sake of Windows programs that don't process
    // quoted args correctly.
    if (!strpbrk(arg, " \t\"")) {
        return std::string(arg);
    }

    std::string ret("");

    // If there are characters that need to be escaped, write a quoted string
    ret += "\"";

    // Escape the argument. To match the behavior of CommandLineToArgvW,
    // backslashes are only escaped if they appear before a quote or the end of
    // the string.
    int num_slashes = 0;
    for (int pos = 0; arg[pos]; pos++) {
        switch (arg[pos]) {
        case '\\':
            // Count consecutive backslashes
            num_slashes++;
            break;
        case '"':
            // Write the argument up to the point before the quote
            ret += std::string(arg).substr(0, pos);
            arg += pos;
            pos = 0;

            // Double backslashes preceding the quote
            for (int i = 0; i < num_slashes; i++)
                ret += "\\";
            num_slashes = 0;

            // Escape the quote itself
            ret += "\\";
            break;
        default:
            num_slashes = 0;
        }
    }

    // Write the rest of the argument
    ret += arg;

    // Double backslashes at the end of the argument
    for (int i = 0; i < num_slashes; i++)
        ret += "\\";

    ret += "\"";

    return ret;
}

std::wstring argument_list_to_windows_cmdline(const char* argv[]) {
    std::stringstream cmdline("");

    // argv[0] should always be quoted. Otherwise, arguments may be interpreted
    // as part of the program name. Also, it can't contain escape sequences.
    cmdline << "\"" << argv[0] << "\"";

    for (int i = 1; argv[i]; i++) {
        cmdline << " " << escape_argument(argv[i]);
    }

    std::string ret = cmdline.str();

    return from_utf8(ret);
}
