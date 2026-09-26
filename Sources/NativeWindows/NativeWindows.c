#define WIN32_LEAN_AND_MEAN
#define COBJMACROS
#include <windows.h>
#include <dwmapi.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <sddl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "NativeWindows.h"

#define MAX_HIDDEN 16384
#define MAX_FRAME (1024 * 1024)
#define WM_AW_TRAY (WM_APP + 1)
#define WM_AW_REGISTER (WM_APP + 2)
#define WM_AW_UNREGISTER (WM_APP + 3)
#define WM_AW_TEXT (WM_APP + 4)
#define HIDDEN_PROPERTY L"AeroSpace.Windows.HiddenOwner"
typedef struct { uint64_t hwnd, creation; uint32_t pid, owner; } HiddenEntry;
typedef struct { int id; UINT modifiers, key; } HotkeyRequest;
static HiddenEntry hidden[MAX_HIDDEN];
/* Keep recovery coverage after an asynchronous show. A previously queued hide
   can still run while the target UI thread is blocked. Entries are discarded
   only when their HWND/process/property identity no longer matches. */
static unsigned char showRequested[MAX_HIDDEN];
static uint32_t hiddenCount;
static CRITICAL_SECTION hiddenLock;
static int lockInitialized;
static wchar_t journalPath[32768], lockPath[32768], pipeName[1024];
static HANDLE instanceLock;
static HWND messageWindow;
static volatile LONG ready, stopping;
static AWEventCallback eventCallback;
static NOTIFYICONDATAW tray;
static int trayEnabled = 1;
static const CLSID desktopManagerClass = {0xaa509086,0x5ca9,0x4c25,{0x8f,0x95,0x58,0x9d,0x3c,0x07,0xb4,0x8a}};
static const IID desktopManagerInterface = {0xa5cd92ff,0x29be,0x454c,{0x8d,0x04,0xd8,0x28,0x79,0xfb,0x3f,0x1b}};
static SECURITY_ATTRIBUTES *userSecurity(SECURITY_ATTRIBUTES *attributes);

static wchar_t *wide(const char *text) {
    int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, -1, NULL, 0);
    if (!count) return NULL;
    wchar_t *result = calloc((size_t)count, sizeof(wchar_t));
    if (result) MultiByteToWideChar(CP_UTF8, 0, text, -1, result, count);
    return result;
}
static void utf8(const wchar_t *text, char *result, int capacity) {
    if (capacity <= 0) return;
    result[0] = 0;
    int required = WideCharToMultiByte(CP_UTF8, 0, text, -1, NULL, 0, NULL, NULL);
    if (!required) return;
    if (required <= capacity) {
        WideCharToMultiByte(CP_UTF8, 0, text, -1, result, capacity, NULL, NULL);
        return;
    }
    char *full = malloc((size_t)required);
    if (!full) return;
    if (WideCharToMultiByte(CP_UTF8, 0, text, -1, full, required, NULL, NULL)) {
        int copied = capacity - 1;
        while (copied > 0 && ((unsigned char)full[copied] & 0xc0) == 0x80) copied--;
        memcpy(result, full, (size_t)copied);
        result[copied] = 0;
    }
    free(full);
}
static AWRect rectangle(RECT r) { AWRect result = {r.left,r.top,r.right-r.left,r.bottom-r.top}; return result; }
static uint64_t creationTime(DWORD pid) {
    HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!process) return 0;
    FILETIME created, exited, kernel, user;
    uint64_t value = 0;
    if (GetProcessTimes(process, &created, &exited, &kernel, &user)) value = ((uint64_t)created.dwHighDateTime << 32) | created.dwLowDateTime;
    CloseHandle(process);
    return value;
}
static int paths(void) {
    HANDLE token;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) return 0;
    DWORD size = 0;
    GetTokenInformation(token, TokenUser, NULL, 0, &size);
    TOKEN_USER *user = malloc(size);
    wchar_t *sid = NULL;
    int result = user && GetTokenInformation(token, TokenUser, user, size, &size) && ConvertSidToStringSidW(user->User.Sid, &sid);
    CloseHandle(token);
    free(user);
    if (!result) return 0;
    DWORD session = 0;
    ProcessIdToSessionId(GetCurrentProcessId(), &session);
    swprintf_s(pipeName, 1024, L"\\\\.\\pipe\\AeroSpace-%ls-%lu", sid, session);
    LocalFree(sid);
    wchar_t *local = NULL;
    if (FAILED(SHGetKnownFolderPath(&FOLDERID_LocalAppData, 0, NULL, &local))) return 0;
    wchar_t directory[32768];
    swprintf_s(directory, 32768, L"%ls\\AeroSpace", local);
    CoTaskMemFree(local);
    if (!CreateDirectoryW(directory, NULL) && GetLastError() != ERROR_ALREADY_EXISTS) return 0;
    swprintf_s(journalPath, 32768, L"%ls\\hidden-%lu.bin", directory, session);
    swprintf_s(lockPath, 32768, L"%ls\\session-%lu.lock", directory, session);
    return 1;
}
static HANDLE acquireInstanceLock(void) {
    SECURITY_ATTRIBUTES attributes;
    if (!userSecurity(&attributes)) return INVALID_HANDLE_VALUE;
    HANDLE file = CreateFileW(lockPath, GENERIC_READ | GENERIC_WRITE, 0, &attributes,
                             OPEN_ALWAYS, FILE_ATTRIBUTE_HIDDEN, NULL);
    DWORD error = GetLastError();
    LocalFree(attributes.lpSecurityDescriptor);
    SetLastError(error);
    return file;
}
static int saveJournal(void) {
    wchar_t temporary[32768];
    swprintf_s(temporary, 32768, L"%ls.tmp", journalPath);
    SECURITY_ATTRIBUTES attributes;
    if (!userSecurity(&attributes)) return 0;
    HANDLE file = CreateFileW(temporary, GENERIC_WRITE, 0, &attributes, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    DWORD error = GetLastError();
    LocalFree(attributes.lpSecurityDescriptor);
    SetLastError(error);
    if (file == INVALID_HANDLE_VALUE) return 0;
    DWORD written = 0, size = hiddenCount * sizeof(HiddenEntry);
    int ok = WriteFile(file, hidden, size, &written, NULL) && written == size && FlushFileBuffers(file);
    CloseHandle(file);
    if (ok) ok = MoveFileExW(temporary, journalPath, MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH);
    if (!ok) DeleteFileW(temporary);
    return ok;
}
static int matches(HiddenEntry entry) {
    HWND hwnd = (HWND)(uintptr_t)entry.hwnd;
    DWORD pid = 0;
    GetWindowThreadProcessId(hwnd, &pid);
    return IsWindow(hwnd) && pid == entry.pid && entry.creation && creationTime(pid) == entry.creation &&
        (uintptr_t)GetPropW(hwnd, HIDDEN_PROPERTY) == entry.owner;
}
static int recoverJournal(void) {
    HANDLE file = CreateFileW(journalPath, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
    if (file == INVALID_HANDLE_VALUE) return GetLastError() == ERROR_FILE_NOT_FOUND;
    LARGE_INTEGER length;
    HiddenEntry *entries = NULL;
    DWORD received = 0;
    int ok = 0;
    if (GetFileSizeEx(file, &length) && length.QuadPart >= 0 && length.QuadPart <= sizeof(hidden) && length.QuadPart % sizeof(HiddenEntry) == 0) {
        entries = malloc((size_t)length.QuadPart + 1);
        if (entries && ReadFile(file, entries, (DWORD)length.QuadPart, &received, NULL) && received == length.QuadPart) {
            hiddenCount = 0;
            for (DWORD i=0; i<received/sizeof(HiddenEntry); i++) if (matches(entries[i])) {
                HWND hwnd = (HWND)(uintptr_t)entries[i].hwnd;
                ShowWindowAsync(hwnd, SW_SHOWNA);
                hidden[hiddenCount] = entries[i];
                showRequested[hiddenCount++] = 1;
            }
            ok = 1;
        }
    }
    free(entries);
    CloseHandle(file);
    if (ok && hiddenCount == 0) DeleteFileW(journalPath);
    /* Do not remove valid entries after merely queuing SW_SHOWNA. The target
       may be hung; the watchdog or a later launch must be able to retry. */
    if (!ok) SetLastError(ERROR_INVALID_DATA);
    return ok;
}
int32_t aw_initialize(void) {
    if (instanceLock) { SetLastError(ERROR_ALREADY_EXISTS); return 0; }
    if (!paths()) return 0;
    HANDLE ownership = acquireInstanceLock();
    if (ownership == INVALID_HANDLE_VALUE) return 0;
    instanceLock = ownership;
    if (!lockInitialized) { InitializeCriticalSection(&hiddenLock); lockInitialized = 1; }
    hiddenCount = 0;
    memset(showRequested, 0, sizeof(showRequested));
    InterlockedExchange(&ready, 0);
    InterlockedExchange(&stopping, 0);
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    if (!recoverJournal()) {
        DWORD error = GetLastError(); CloseHandle(instanceLock); instanceLock = NULL; SetLastError(error); return 0;
    }
    return 1;
}
uint32_t aw_pid(void) { return GetCurrentProcessId(); }
uint32_t aw_last_error(void) { return GetLastError(); }
void aw_free(void *memory) { free(memory); }
int32_t aw_window(uint64_t handle, AWWindow *result) {
    HWND hwnd = (HWND)(uintptr_t)handle;
    if (!result || !IsWindow(hwnd)) return 0;
    memset(result, 0, sizeof(*result));
    result->handle = handle;
    GetWindowThreadProcessId(hwnd, &result->pid);
    result->processCreation = creationTime(result->pid);
    RECT rect;
    if (FAILED(DwmGetWindowAttribute(hwnd, DWMWA_EXTENDED_FRAME_BOUNDS, &rect, sizeof(rect))) && !GetWindowRect(hwnd, &rect)) return 0;
    result->rect = rectangle(rect);
    result->visible = IsWindowVisible(hwnd);
    result->minimized = IsIconic(hwnd);
    result->maximized = IsZoomed(hwnd);
    LONG_PTR style = GetWindowLongPtrW(hwnd, GWL_STYLE);
    wchar_t className[256] = {0}, text[32768] = {0};
    GetClassNameW(hwnd, className, 256);
    result->dialog = GetWindow(hwnd, GW_OWNER) != NULL || wcscmp(className,L"#32770") == 0;
    result->resizable = (style & WS_THICKFRAME) != 0;
    GetWindowTextW(hwnd, text, 4096);
    utf8(text, result->title, sizeof(result->title));
    HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, result->pid);
    if (process) {
        DWORD capacity = 32768;
        if (QueryFullProcessImageNameW(process, 0, text, &capacity)) {
            utf8(text, result->executable, sizeof(result->executable));
            wchar_t *name = wcsrchr(text, L'\\');
            utf8(name ? name + 1 : text, result->name, sizeof(result->name));
        }
        CloseHandle(process);
    }
    DWORD currentPid = 0;
    return IsWindow(hwnd) && GetWindowThreadProcessId(hwnd, &currentPid) && currentPid == result->pid;
}
int32_t aw_is_fullscreen(uint64_t handle) {
    HWND hwnd = (HWND)(uintptr_t)handle;
    if (!IsWindow(hwnd) || IsIconic(hwnd)) return 0;
    LONG_PTR style = GetWindowLongPtrW(hwnd, GWL_STYLE);
    if (style & (WS_CAPTION | WS_THICKFRAME)) return 0;
    RECT frame;
    if (FAILED(DwmGetWindowAttribute(hwnd, DWMWA_EXTENDED_FRAME_BOUNDS, &frame, sizeof(frame))) && !GetWindowRect(hwnd, &frame)) return 0;
    MONITORINFO monitor = {sizeof(monitor)};
    if (!GetMonitorInfoW(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST), &monitor)) return 0;
    RECT bounds = monitor.rcMonitor;
    return abs(frame.left-bounds.left) <= 2 && abs(frame.top-bounds.top) <= 2 &&
           abs(frame.right-bounds.right) <= 2 && abs(frame.bottom-bounds.bottom) <= 2;
}
typedef struct { AWWindow *items; int count, capacity, failed; IVirtualDesktopManager *desktopManager; } WindowList;
static BOOL CALLBACK enumerateWindow(HWND hwnd, LPARAM context) {
    WindowList *list = (WindowList*)context;
    DWORD pid;
    GetWindowThreadProcessId(hwnd, &pid);
    if (pid == GetCurrentProcessId() || hwnd == GetShellWindow() || GetAncestor(hwnd,GA_ROOT) != hwnd) return TRUE;
    LONG_PTR ex = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
    if (ex & (WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE)) return TRUE;
    wchar_t cls[256] = {0};
    GetClassNameW(hwnd, cls, 256);
    if (!wcscmp(cls,L"Shell_TrayWnd") || !wcscmp(cls,L"Shell_SecondaryTrayWnd") || !wcscmp(cls,L"Progman") || !wcscmp(cls,L"WorkerW")) return TRUE;
    DWORD cloaked = 0;
    DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, &cloaked, sizeof(cloaked));
    if (cloaked) return TRUE;
    if (!IsWindowVisible(hwnd) && !aw_is_hidden((uint64_t)(uintptr_t)hwnd)) return TRUE;
    if (list->desktopManager) {
        BOOL current = TRUE;
        if (SUCCEEDED(IVirtualDesktopManager_IsWindowOnCurrentVirtualDesktop(list->desktopManager,hwnd,&current)) && !current) return TRUE;
    }
    AWWindow item;
    if (!aw_window((uint64_t)(uintptr_t)hwnd, &item) || !item.processCreation || !item.name[0]) return TRUE;
    if (!item.title[0] && !item.dialog) return TRUE;
    if (list->count == list->capacity) {
        int capacity = list->capacity ? list->capacity * 2 : 64;
        AWWindow *grown = realloc(list->items, capacity * sizeof(AWWindow));
        if (!grown) { list->failed = 1; return FALSE; }
        list->items = grown;
        list->capacity = capacity;
    }
    list->items[list->count++] = item;
    return TRUE;
}
AWWindow *aw_windows(int32_t *count) {
    if (!count) { SetLastError(ERROR_INVALID_PARAMETER); return NULL; }
    *count = 0;
    /* Keep the COM object in this enumeration's apartment and context. */
    HRESULT initialized = CoInitializeEx(NULL, COINIT_MULTITHREADED);
    IVirtualDesktopManager *manager = NULL;
    CoCreateInstance(&desktopManagerClass,NULL,CLSCTX_INPROC_SERVER,&desktopManagerInterface,(void**)&manager);
    WindowList list = {0};
    list.desktopManager = manager;
    EnumWindows(enumerateWindow,(LPARAM)&list);
    if (manager) IVirtualDesktopManager_Release(manager);
    if (SUCCEEDED(initialized)) CoUninitialize();
    if (list.failed) { free(list.items); SetLastError(ERROR_NOT_ENOUGH_MEMORY); return NULL; }
    /* A successful empty enumeration must be distinct from an allocation
       failure, so callers can garbage-collect the final closed window. */
    if (!list.items) list.items = calloc(1, sizeof(AWWindow));
    *count = list.count;
    return list.items;
}
typedef struct { AWMonitor *items; int count; } MonitorList;
static BOOL CALLBACK enumerateMonitor(HMONITOR handle, HDC dc, LPRECT bounds, LPARAM context) {
    (void)dc; (void)bounds;
    MonitorList *list = (MonitorList*)context;
    MONITORINFOEXW info = {0}; info.cbSize = sizeof(info);
    if (!GetMonitorInfoW(handle,(MONITORINFO*)&info)) return TRUE;
    AWMonitor *grown = realloc(list->items,(list->count+1)*sizeof(AWMonitor));
    if (!grown) return FALSE;
    list->items = grown;
    AWMonitor *item = &list->items[list->count++];
    memset(item,0,sizeof(*item));
    item->handle = (uint64_t)(uintptr_t)handle;
    item->rect = rectangle(info.rcMonitor); item->work = rectangle(info.rcWork);
    item->primary = (info.dwFlags & MONITORINFOF_PRIMARY) != 0;
    item->dpi = 96;
    HMODULE scaling = LoadLibraryExW(L"shcore.dll", NULL, LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (scaling) {
        typedef HRESULT (WINAPI *GetMonitorDpi)(HMONITOR, int, UINT *, UINT *);
        GetMonitorDpi getDpi = (GetMonitorDpi)GetProcAddress(scaling, "GetDpiForMonitor");
        UINT horizontal = 96, vertical = 96;
        if (getDpi && SUCCEEDED(getDpi(handle, 0, &horizontal, &vertical))) item->dpi = horizontal;
        FreeLibrary(scaling);
    }
    utf8(info.szDevice,item->name,sizeof(item->name));
    return TRUE;
}
AWMonitor *aw_monitors(int32_t *count) {
    MonitorList list = {0}; EnumDisplayMonitors(NULL,NULL,enumerateMonitor,(LPARAM)&list); *count=list.count; return list.items;
}
uint64_t aw_foreground(void) { return (uint64_t)(uintptr_t)GetForegroundWindow(); }
AWRect aw_cursor(void) { POINT p={0};GetCursorPos(&p);AWRect r={p.x,p.y,0,0};return r; }
int32_t aw_position(uint64_t handle, AWRect rect) {
    HWND hwnd=(HWND)(uintptr_t)handle;
    if (!IsWindow(hwnd) || IsIconic(hwnd)) return 0;
    if (IsZoomed(hwnd)) ShowWindowAsync(hwnd,SW_RESTORE);
    RECT outer, frame;
    int left=0,top=0,right=0,bottom=0;
    if (GetWindowRect(hwnd,&outer) && SUCCEEDED(DwmGetWindowAttribute(hwnd,DWMWA_EXTENDED_FRAME_BOUNDS,&frame,sizeof(frame)))) {
        left=frame.left-outer.left; top=frame.top-outer.top; right=outer.right-frame.right; bottom=outer.bottom-frame.bottom;
    }
    return SetWindowPos(hwnd,NULL,rect.x-left,rect.y-top,rect.width+left+right,rect.height+top+bottom,SWP_NOACTIVATE|SWP_NOZORDER|SWP_ASYNCWINDOWPOS);
}
int32_t aw_focus(uint64_t handle) {
    HWND hwnd=(HWND)(uintptr_t)handle;
    if (!IsWindow(hwnd)) return 0;
    DWORD pid = 0; GetWindowThreadProcessId(hwnd, &pid);
    uint64_t creation = creationTime(pid);
    if (IsIconic(hwnd)) {
        if (!ShowWindowAsync(hwnd,SW_RESTORE)) return 0;
    } else if (!IsWindowVisible(hwnd)) {
        if (aw_is_hidden(handle)) {
            if (!aw_show(handle)) return 0;
        } else if (!ShowWindowAsync(hwnd,SW_SHOWNA)) return 0;
    }
    /* Workspace layout may only just have queued SW_SHOWNA on another UI
       thread. Foreground activation before it is visible can be rejected.
       Bound the wait so a hung application cannot block the manager. */
    ULONGLONG deadline = GetTickCount64() + 200;
    while (!IsWindowVisible(hwnd) || IsIconic(hwnd)) {
        DWORD currentPid = 0; GetWindowThreadProcessId(hwnd, &currentPid);
        if (!IsWindow(hwnd) || currentPid != pid || GetTickCount64() >= deadline) return 0;
        Sleep(5);
    }
    DWORD currentPid = 0; GetWindowThreadProcessId(hwnd, &currentPid);
    if (!IsWindow(hwnd) || currentPid != pid || !creation || creationTime(pid) != creation) return 0;
    if (GetForegroundWindow() == hwnd) return 1;
    if (!SetForegroundWindow(hwnd) && GetForegroundWindow() != hwnd) return 0;
    deadline = GetTickCount64() + 50;
    while (GetForegroundWindow() != hwnd && GetTickCount64() < deadline) Sleep(5);
    return GetForegroundWindow() == hwnd;
}
int32_t aw_close(uint64_t handle) { return PostMessageW((HWND)(uintptr_t)handle,WM_CLOSE,0,0); }
static void pruneHidden(void) {
    int changed = 0;
    for (uint32_t i=0; i<hiddenCount;) {
        if (matches(hidden[i])) { i++; continue; }
        hiddenCount--;
        hidden[i] = hidden[hiddenCount];
        showRequested[i] = showRequested[hiddenCount];
        changed = 1;
    }
    if (changed) saveJournal();
}
int32_t aw_is_hidden(uint64_t handle) {
    if (!lockInitialized) return 0;
    EnterCriticalSection(&hiddenLock);
    int result=0;
    for (uint32_t i=0;i<hiddenCount;i++) if (hidden[i].hwnd == handle && matches(hidden[i])) {
        result = !IsWindowVisible((HWND)(uintptr_t)handle); break;
    }
    LeaveCriticalSection(&hiddenLock); return result;
}
int32_t aw_hide(uint64_t handle) {
    if (!lockInitialized || !instanceLock) { SetLastError(ERROR_INVALID_STATE); return 0; }
    HWND hwnd=(HWND)(uintptr_t)handle;
    EnterCriticalSection(&hiddenLock);
    if (!instanceLock) { LeaveCriticalSection(&hiddenLock); SetLastError(ERROR_INVALID_STATE); return 0; }
    pruneHidden();
    for (uint32_t i=0;i<hiddenCount;i++) if (hidden[i].hwnd==handle) {
        /* Queue hide again when a show was requested, even if the window has
           not shown yet. The target thread must receive the final intent. */
        int ok = (!showRequested[i] && !IsWindowVisible(hwnd)) || ShowWindowAsync(hwnd, SW_HIDE);
        if (ok) showRequested[i] = 0;
        LeaveCriticalSection(&hiddenLock); return ok;
    }
    if (!IsWindowVisible(hwnd) || IsIconic(hwnd) || hiddenCount == MAX_HIDDEN) { LeaveCriticalSection(&hiddenLock); return 0; }
    DWORD pid=0; GetWindowThreadProcessId(hwnd,&pid);
    HiddenEntry entry={handle,creationTime(pid),pid,GetCurrentProcessId()};
    if (!entry.creation || !SetPropW(hwnd,HIDDEN_PROPERTY,(HANDLE)(uintptr_t)entry.owner)) { LeaveCriticalSection(&hiddenLock); return 0; }
    hidden[hiddenCount]=entry;
    showRequested[hiddenCount++]=0;
    if (!saveJournal()) { hiddenCount--; RemovePropW(hwnd,HIDDEN_PROPERTY); LeaveCriticalSection(&hiddenLock); return 0; }
    int ok=ShowWindowAsync(hwnd,SW_HIDE);
    LeaveCriticalSection(&hiddenLock); return ok;
}
int32_t aw_show(uint64_t handle) {
    if (!lockInitialized || !instanceLock) { SetLastError(ERROR_INVALID_STATE); return 0; }
    EnterCriticalSection(&hiddenLock);
    if (!instanceLock) { LeaveCriticalSection(&hiddenLock); SetLastError(ERROR_INVALID_STATE); return 0; }
    int ok=1;
    pruneHidden();
    for (uint32_t i=0;i<hiddenCount;i++) if (hidden[i].hwnd==handle) {
        HWND hwnd=(HWND)(uintptr_t)handle;
        ok=(showRequested[i] && IsWindowVisible(hwnd)) || ShowWindowAsync(hwnd,SW_SHOWNA);
        if (ok) showRequested[i] = 1;
        break;
    }
    LeaveCriticalSection(&hiddenLock); return ok;
}
void aw_restore_all(void) {
    if (!lockInitialized || !instanceLock) return;
    EnterCriticalSection(&hiddenLock);
    if (!instanceLock) { LeaveCriticalSection(&hiddenLock); return; }
    pruneHidden();
    for (uint32_t i=0;i<hiddenCount;i++) {
        HWND hwnd=(HWND)(uintptr_t)hidden[i].hwnd;
        if (ShowWindowAsync(hwnd,SW_SHOWNA)) showRequested[i] = 1;
    }
    LeaveCriticalSection(&hiddenLock);
}
static void emit(int event,uint64_t value) { if (eventCallback && !stopping) eventCallback(event,value); }
static void CALLBACK windowEvent(HWINEVENTHOOK hook,DWORD event,HWND hwnd,LONG object,LONG child,DWORD thread,DWORD time) {
    (void)hook;(void)thread;(void)time;
    if (!hwnd || child != CHILDID_SELF || (object != OBJID_WINDOW && event != EVENT_SYSTEM_FOREGROUND)) return;
    int type = event == EVENT_SYSTEM_FOREGROUND ? 2 :
               event == EVENT_SYSTEM_MOVESIZESTART ? 8 :
               event == EVENT_SYSTEM_MOVESIZEEND ? 9 : 1;
    emit(type,(uint64_t)(uintptr_t)hwnd);
}
static void addTray(void) { Shell_NotifyIconW(NIM_ADD,&tray); tray.uVersion=NOTIFYICON_VERSION_4; Shell_NotifyIconW(NIM_SETVERSION,&tray); }
static LRESULT CALLBACK windowProcedure(HWND hwnd,UINT msg,WPARAM wp,LPARAM lp) {
    static UINT taskbarCreated;
    if (!taskbarCreated) taskbarCreated=RegisterWindowMessageW(L"TaskbarCreated");
    if (msg==taskbarCreated) { addTray(); return 0; }
    switch (msg) {
        case WM_AW_REGISTER: { HotkeyRequest *r=(HotkeyRequest*)lp; return RegisterHotKey(hwnd,r->id,r->modifiers|MOD_NOREPEAT,r->key); }
        case WM_AW_UNREGISTER: return UnregisterHotKey(hwnd,(int)wp);
        case WM_HOTKEY: emit(3,(uint64_t)wp); return 0;
        case WM_DISPLAYCHANGE: case WM_SETTINGCHANGE: emit(4,0); return 0;
        case WM_AW_TEXT:
            trayEnabled=(int)wp;
            wcsncpy_s(tray.szTip,128,(const wchar_t*)lp,_TRUNCATE);
            Shell_NotifyIconW(NIM_MODIFY,&tray); return 0;
        case WM_AW_TRAY:
            if (LOWORD(lp)==WM_CONTEXTMENU || LOWORD(lp)==WM_RBUTTONUP) {
                HMENU menu=CreatePopupMenu();
                AppendMenuW(menu,MF_STRING,5,trayEnabled?L"Disable":L"Enable");
                AppendMenuW(menu,MF_STRING,6,L"Reload config"); AppendMenuW(menu,MF_STRING,7,L"Quit");
                POINT point;GetCursorPos(&point);SetForegroundWindow(hwnd);
                int selection=TrackPopupMenu(menu,TPM_RETURNCMD|TPM_NONOTIFY,point.x,point.y,0,hwnd,NULL);
                DestroyMenu(menu); if(selection) emit(selection,0); PostMessageW(hwnd,WM_NULL,0,0);
            }
            return 0;
        case WM_QUERYENDSESSION: emit(7,0); return TRUE;
        case WM_CLOSE: DestroyWindow(hwnd); return 0;
        case WM_DESTROY: PostQuitMessage(0); return 0;
    }
    return DefWindowProcW(hwnd,msg,wp,lp);
}
void aw_run_loop(AWEventCallback callback) {
    eventCallback=callback;
    WNDCLASSW cls={0};cls.lpfnWndProc=windowProcedure;cls.hInstance=GetModuleHandleW(NULL);cls.lpszClassName=L"AeroSpace.Windows.Message";
    RegisterClassW(&cls);
    messageWindow=CreateWindowExW(WS_EX_TOOLWINDOW,cls.lpszClassName,L"AeroSpace",WS_OVERLAPPED,0,0,0,0,NULL,NULL,cls.hInstance,NULL);
    if (!messageWindow) { InterlockedExchange(&ready,-1);return; }
    memset(&tray,0,sizeof(tray));tray.cbSize=sizeof(tray);tray.hWnd=messageWindow;tray.uID=1;
    tray.uFlags=NIF_ICON|NIF_MESSAGE|NIF_TIP;tray.uCallbackMessage=WM_AW_TRAY;tray.hIcon=LoadIconW(NULL,IDI_APPLICATION);
    wcscpy_s(tray.szTip,128,L"AeroSpace");addTray();
    HWINEVENTHOOK hooks[5];
    hooks[0]=SetWinEventHook(EVENT_SYSTEM_FOREGROUND,EVENT_SYSTEM_FOREGROUND,NULL,windowEvent,0,0,WINEVENT_OUTOFCONTEXT|WINEVENT_SKIPOWNPROCESS);
    hooks[1]=SetWinEventHook(EVENT_OBJECT_CREATE,EVENT_OBJECT_HIDE,NULL,windowEvent,0,0,WINEVENT_OUTOFCONTEXT|WINEVENT_SKIPOWNPROCESS);
    hooks[2]=SetWinEventHook(EVENT_OBJECT_LOCATIONCHANGE,EVENT_OBJECT_NAMECHANGE,NULL,windowEvent,0,0,WINEVENT_OUTOFCONTEXT|WINEVENT_SKIPOWNPROCESS);
    hooks[3]=SetWinEventHook(EVENT_SYSTEM_MINIMIZESTART,EVENT_SYSTEM_MINIMIZEEND,NULL,windowEvent,0,0,WINEVENT_OUTOFCONTEXT|WINEVENT_SKIPOWNPROCESS);
    hooks[4]=SetWinEventHook(EVENT_SYSTEM_MOVESIZESTART,EVENT_SYSTEM_MOVESIZEEND,NULL,windowEvent,0,0,WINEVENT_OUTOFCONTEXT|WINEVENT_SKIPOWNPROCESS);
    for(int i=0;i<5;i++) if(!hooks[i]) { InterlockedExchange(&ready,-1); goto cleanup; }
    InterlockedExchange(&ready,1);
    MSG message;
    while(GetMessageW(&message,NULL,0,0)>0) { TranslateMessage(&message);DispatchMessageW(&message); }
cleanup:
    for(int i=0;i<5;i++) if(hooks[i]) UnhookWinEvent(hooks[i]);
    Shell_NotifyIconW(NIM_DELETE,&tray);messageWindow=NULL;
}
int32_t aw_loop_ready(void) { return ready; }
void aw_stop_loop(void) { InterlockedExchange(&stopping,1);if(messageWindow)PostMessageW(messageWindow,WM_CLOSE,0,0); }
void aw_shutdown(void) {
    aw_stop_loop();
    if (!lockInitialized) return;
    EnterCriticalSection(&hiddenLock);
    aw_restore_all();
    HANDLE ownership = instanceLock;
    instanceLock = NULL;
    LeaveCriticalSection(&hiddenLock);
    if (ownership) CloseHandle(ownership);
}
int32_t aw_register_hotkey(int32_t id,uint32_t modifiers,uint32_t key) { HotkeyRequest r={id,modifiers,key};return messageWindow && SendMessageW(messageWindow,WM_AW_REGISTER,0,(LPARAM)&r); }
void aw_unregister_hotkey(int32_t id) { if(messageWindow)SendMessageW(messageWindow,WM_AW_UNREGISTER,id,0); }
void aw_tray_text(const char *text,int32_t enabled) { wchar_t *value=wide(text);if(value && messageWindow)SendMessageW(messageWindow,WM_AW_TEXT,enabled,(LPARAM)value);free(value); }
void aw_message(const char *title,const char *text) { wchar_t *a=wide(title),*b=wide(text);if(a && b)MessageBoxW(NULL,b,a,MB_OK|MB_ICONERROR);free(a);free(b); }
int32_t aw_watchdog(uint32_t parent) {
    if (!parent || parent == GetCurrentProcessId()) return 1;
    if (!paths()) return 1;
    HANDLE process=OpenProcess(SYNCHRONIZE,FALSE,parent);
    if (process) {
        DWORD waited = WaitForSingleObject(process, INFINITE); CloseHandle(process);
        if (waited != WAIT_OBJECT_0) return 1;
    } else if (GetLastError() != ERROR_INVALID_PARAMETER) return 1;
    /* The file lock has process lifetime rather than thread ownership. A new
       manager recovers while acquiring it; never recover through that lock. */
    ULONGLONG deadline = GetTickCount64() + 5000;
    do {
        HANDLE ownership = acquireInstanceLock();
        if (ownership != INVALID_HANDLE_VALUE) {
            int ok = recoverJournal(); CloseHandle(ownership); return ok ? 0 : 1;
        }
        DWORD error = GetLastError();
        if (error != ERROR_SHARING_VIOLATION && error != ERROR_LOCK_VIOLATION) return 1;
        Sleep(50);
    } while (GetTickCount64() < deadline);
    return 0;
}
int32_t aw_start_watchdog(void) {
    wchar_t executable[32768],command[32768];
    if(!GetModuleFileNameW(NULL,executable,32768))return 0;
    swprintf_s(command,32768,L"\"%ls\" --watchdog %lu",executable,GetCurrentProcessId());
    STARTUPINFOW info={0};info.cb=sizeof(info);PROCESS_INFORMATION process;
    if(!CreateProcessW(executable,command,NULL,NULL,FALSE,CREATE_NO_WINDOW,NULL,NULL,&info,&process))return 0;
    CloseHandle(process.hThread);CloseHandle(process.hProcess);return 1;
}
int32_t aw_spawn(const char *executable,const char *commandLine,const uint16_t *environment) {
    wchar_t *path=wide(executable),*command=wide(commandLine);
    STARTUPINFOW info={0};info.cb=sizeof(info);PROCESS_INFORMATION process;
    int result=path && command && CreateProcessW(path,command,NULL,NULL,FALSE,CREATE_NO_WINDOW|CREATE_UNICODE_ENVIRONMENT,(void*)environment,NULL,&info,&process);
    if(result){CloseHandle(process.hThread);CloseHandle(process.hProcess);}free(path);free(command);return result;
}
void aw_open_file(const char *path) { wchar_t *value=wide(path);if(value)ShellExecuteW(NULL,L"open",value,NULL,NULL,SW_SHOWNORMAL);free(value); }
static SECURITY_ATTRIBUTES *userSecurity(SECURITY_ATTRIBUTES *attributes) {
    HANDLE token;
    if(!OpenProcessToken(GetCurrentProcess(),TOKEN_QUERY,&token))return NULL;
    DWORD size=0;GetTokenInformation(token,TokenUser,NULL,0,&size);TOKEN_USER *user=malloc(size);
    wchar_t *sid=NULL;int ok=user && GetTokenInformation(token,TokenUser,user,size,&size) && ConvertSidToStringSidW(user->User.Sid,&sid);
    CloseHandle(token);free(user);if(!ok)return NULL;
    wchar_t sddl[1024];swprintf_s(sddl,1024,L"D:P(A;;GA;;;%ls)",sid);LocalFree(sid);
    attributes->nLength=sizeof(*attributes);attributes->bInheritHandle=FALSE;
    if(!ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl,SDDL_REVISION_1,&attributes->lpSecurityDescriptor,NULL))return NULL;
    return attributes;
}
uint64_t aw_pipe_listen(void) {
    SECURITY_ATTRIBUTES attributes;
    if(!userSecurity(&attributes))return 0;
    HANDLE pipe=CreateNamedPipeW(pipeName,PIPE_ACCESS_DUPLEX,PIPE_TYPE_BYTE|PIPE_READMODE_BYTE|PIPE_WAIT|PIPE_REJECT_REMOTE_CLIENTS,16,65536,65536,5000,&attributes);
    LocalFree(attributes.lpSecurityDescriptor);return pipe==INVALID_HANDLE_VALUE?0:(uint64_t)(uintptr_t)pipe;
}
int32_t aw_pipe_accept(uint64_t pipe) { return ConnectNamedPipe((HANDLE)(uintptr_t)pipe,NULL) || GetLastError()==ERROR_PIPE_CONNECTED; }
uint64_t aw_pipe_connect(uint32_t timeoutMs) {
    if(!paths())return 0;
    ULONGLONG deadline=GetTickCount64()+timeoutMs;
    do {
        HANDLE pipe=CreateFileW(pipeName,GENERIC_READ|GENERIC_WRITE,0,NULL,OPEN_EXISTING,SECURITY_SQOS_PRESENT|SECURITY_IDENTIFICATION,NULL);
        if(pipe!=INVALID_HANDLE_VALUE)return (uint64_t)(uintptr_t)pipe;
        if(GetLastError()!=ERROR_PIPE_BUSY && GetLastError()!=ERROR_FILE_NOT_FOUND)return 0;
        WaitNamedPipeW(pipeName,50);Sleep(10);
    } while(GetTickCount64()<deadline);
    return 0;
}
static int readExact(HANDLE pipe,void *buffer,DWORD size) {
    char *p=buffer;while(size){DWORD received=0;if(!ReadFile(pipe,p,size,&received,NULL)||!received)return 0;p+=received;size-=received;}return 1;
}
static int writeExact(HANDLE pipe,const void *buffer,DWORD size) {
    const char *p=buffer;while(size){DWORD written=0;if(!WriteFile(pipe,p,size,&written,NULL)||!written)return 0;p+=written;size-=written;}return 1;
}
int32_t aw_pipe_read(uint64_t pipe,char **data,uint32_t *size) {
    *data=NULL;*size=0;uint32_t length;
    if(!readExact((HANDLE)(uintptr_t)pipe,&length,4)||length>MAX_FRAME)return 0;
    char *result=malloc((size_t)length+1);if(!result)return 0;
    if(!readExact((HANDLE)(uintptr_t)pipe,result,length)){free(result);return 0;}result[length]=0;*data=result;*size=length;return 1;
}
int32_t aw_pipe_write(uint64_t pipe,const char *data,uint32_t size) { return size<=MAX_FRAME && writeExact((HANDLE)(uintptr_t)pipe,&size,4) && writeExact((HANDLE)(uintptr_t)pipe,data,size); }
void aw_pipe_close(uint64_t pipe) { if(pipe)CloseHandle((HANDLE)(uintptr_t)pipe); }
void aw_allow_server_foreground(uint64_t pipe) {
    ULONG pid=0;
    if(pipe && GetNamedPipeServerProcessId((HANDLE)(uintptr_t)pipe,&pid))AllowSetForegroundWindow(pid);
}
void aw_stderr(const char *text) { DWORD written;WriteFile(GetStdHandle(STD_ERROR_HANDLE),text,(DWORD)strlen(text),&written,NULL); }
int32_t aw_stdin_is_terminal(void) { DWORD mode;return GetConsoleMode(GetStdHandle(STD_INPUT_HANDLE),&mode); }
void aw_exit(int32_t code) { fflush(NULL); ExitProcess((UINT)code); }
