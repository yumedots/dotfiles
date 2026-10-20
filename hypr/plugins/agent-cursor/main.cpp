// agent-cursor: streams the global mouse position to a FIFO for the quickshell widget.
//
// The position is written as "<x> <y>\n" lines in global layout coordinates, matching
// `hyprctl cursorpos`. Writes are best effort: the pipe is non blocking, so a slow reader
// drops frames instead of stalling the compositor. Cursor position is idempotent, so a
// dropped frame only costs latency, never correctness.
//
// The FIFO lives in this Hyprland instance's own directory, so a nested test session gets
// its own stream instead of competing with the live one for the same FIFO. Two readers on
// one FIFO each get an arbitrary share of the frames.

#define WLR_USE_UNSTABLE

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/helpers/math/Math.hpp>

#include <cerrno>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dirent.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>

using namespace Hyprutils::Math;

// Reopening a fifo with no reader fails immediately, so retry on a slow cadence
// instead of on every mouse move.
static const int64_t REOPEN_INTERVAL_MS = 500;

static std::string runtimeDir() {
    const char* runtime = getenv("XDG_RUNTIME_DIR");
    if (!runtime || !*runtime)
        return "/tmp";

    return runtime;
}

// The directory of this Hyprland instance, e.g. /run/user/1000/hypr/<signature>.
//
// The compositor does not export its instance signature to its own environment. It does
// keep a file open inside its instance directory, though, so the directory is found by
// looking for a path of our own that points into one.
static std::string instanceDir() {
    const std::string hyprDir = runtimeDir() + "/hypr";

    DIR* fdDir = opendir("/proc/self/fd");
    if (!fdDir)
        return hyprDir;

    struct dirent* fdEntry = nullptr;
    std::string found;

    while ((fdEntry = readdir(fdDir)) != nullptr) {
        const std::string fdName = fdEntry->d_name;

        if (fdName == "." || fdName == "..")
            continue;

        char link[512];
        const ssize_t count = readlink(("/proc/self/fd/" + fdName).c_str(), link, sizeof(link) - 1);

        if (count <= 0)
            continue;

        link[count] = '\0';

        const std::string target = link;
        const size_t marker = target.find("/hypr/");

        if (marker == std::string::npos)
            continue;

        // The instance directory is everything up to the next separator.
        const size_t end = target.find('/', marker + 6);

        if (end == std::string::npos)
            continue;

        const std::string candidate = target.substr(0, end);

        // Confirm it really is an instance directory.
        struct stat st;
        if (stat((candidate + "/.socket2.sock").c_str(), &st) != 0)
            continue;

        found = candidate;
        break;
    }

    closedir(fdDir);

    return found.empty() ? hyprDir : found;
}

static std::string fifoPath() {
    return instanceDir() + "/agent-cursor.fifo";
}

static int fifoFd = -1;
static int64_t lastOpenAttempt = 0;

static int64_t nowMs() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();
}

static void openFifo() {
    if (fifoFd >= 0)
        return;

    const int64_t now = nowMs();
    if (now - lastOpenAttempt < REOPEN_INTERVAL_MS)
        return;

    lastOpenAttempt = now;

    const auto path = fifoPath();

    // The fifo may have been removed while we were running (tmp cleanup, a reload).
    struct stat st;
    if (stat(path.c_str(), &st) != 0)
        mkfifo(path.c_str(), 0600);

    fifoFd = open(path.c_str(), O_WRONLY | O_NONBLOCK);
    if (fifoFd < 0)
        fifoFd = -1;
}

static void closeFifo() {
    if (fifoFd < 0)
        return;

    close(fifoFd);
    fifoFd = -1;
}

static void writePosition(double x, double y) {
    if (fifoFd < 0)
        openFifo();

    if (fifoFd < 0)
        return;

    char buffer[64];
    const int len = snprintf(buffer, sizeof(buffer), "%.0f %.0f\n", x, y);
    if (len <= 0)
        return;

    const ssize_t written = write(fifoFd, buffer, len);
    if (written < 0) {
        if (errno == EAGAIN)
            return; // Pipe buffer full. The reader is behind; dropping a frame is harmless.

        // No reader yet, or the reader went away. Drop the handle and retry later.
        closeFifo();
        return;
    }
}

// Do NOT change this function.
APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    const std::string HASH        = __hyprland_api_get_hash();
    const std::string CLIENT_HASH = __hyprland_api_get_client_hash();

    if (HASH != CLIENT_HASH) {
        HyprlandAPI::addNotification(handle, "[agent-cursor] Version mismatch between plugin headers and running Hyprland",
                                     CHyprColor{1.0, 0.2, 0.2, 1.0}, 5000);
        return {};
    }

    openFifo();

    // The reader may attach or detach at any time. Retrying on every tick means
    // the stream resumes even if the mouse never moves.
    static auto ticker = Event::bus()->m_events.tick.listen([]() {
        openFifo();
    });

    static auto listener = Event::bus()->m_events.input.mouse.move.listen([](Vector2D pos, Event::SCallbackInfo&) {
        writePosition(pos.x, pos.y);
    });

    return {
        .name        = "agent-cursor",
        .description = "Streams the mouse position to a fifo",
        .author      = "gabriel",
        .version     = "1.0.0",
    };
}

APICALL EXPORT void PLUGIN_EXIT() {
    closeFifo();
}
