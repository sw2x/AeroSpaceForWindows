#ifndef AEROSPACE_NATIVE_WINDOWS_H
#define AEROSPACE_NATIVE_WINDOWS_H
#include <stdint.h>
#include <stddef.h>

typedef struct { int32_t x, y, width, height; } AWRect;
typedef struct {
    uint64_t handle;
    uint32_t pid;
    uint64_t processCreation;
    AWRect rect;
    int32_t minimized, visible, dialog, resizable, maximized;
    char title[2048], name[512], executable[4096];
} AWWindow;
typedef struct {
    uint64_t handle;
    AWRect rect, work;
    uint32_t dpi;
    int32_t primary;
    char name[512];
} AWMonitor;
typedef void (*AWEventCallback)(int32_t event, uint64_t value);
/* Events: 1 windows changed, 2 foreground, 3 hotkey, 4 displays,
   5 toggle enabled, 6 reload config, 7 quit,
   8 native move/resize started, 9 native move/resize ended (value: HWND). */
int32_t aw_initialize(void);
void aw_run_loop(AWEventCallback callback);
int32_t aw_loop_ready(void);
void aw_stop_loop(void);
void aw_shutdown(void);
AWWindow *aw_windows(int32_t *count);
AWMonitor *aw_monitors(int32_t *count);
void aw_free(void *memory);
int32_t aw_window(uint64_t handle, AWWindow *result);
int32_t aw_is_fullscreen(uint64_t handle);
uint64_t aw_foreground(void);
AWRect aw_cursor(void);
int32_t aw_position(uint64_t handle, AWRect rect);
int32_t aw_focus(uint64_t handle);
int32_t aw_close(uint64_t handle);
int32_t aw_hide(uint64_t handle);
int32_t aw_show(uint64_t handle);
int32_t aw_is_hidden(uint64_t handle);
void aw_restore_all(void);
int32_t aw_register_hotkey(int32_t id, uint32_t modifiers, uint32_t key);
void aw_unregister_hotkey(int32_t id);
void aw_tray_text(const char *text, int32_t enabled);
void aw_message(const char *title, const char *text);
uint32_t aw_pid(void);
uint32_t aw_last_error(void);
int32_t aw_watchdog(uint32_t parent);
int32_t aw_start_watchdog(void);
int32_t aw_spawn(const char *executable, const char *commandLine, const uint16_t *environment);
void aw_open_file(const char *path);
/* Pipe frames: uint32 little-endian size followed by UTF-8 JSON, <= 1 MiB. */
uint64_t aw_pipe_listen(void);
int32_t aw_pipe_accept(uint64_t pipe);
uint64_t aw_pipe_connect(uint32_t timeoutMs);
int32_t aw_pipe_read(uint64_t pipe, char **data, uint32_t *size);
int32_t aw_pipe_write(uint64_t pipe, const char *data, uint32_t size);
void aw_pipe_close(uint64_t pipe);
void aw_allow_server_foreground(uint64_t pipe);
void aw_stderr(const char *text);
int32_t aw_stdin_is_terminal(void);
void aw_exit(int32_t code);
#endif
