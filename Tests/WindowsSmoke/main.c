#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "NativeWindows.h"

static int fixtureWindows;
static LRESULT CALLBACK fixtureProcedure(HWND hwnd,UINT message,WPARAM wp,LPARAM lp) {
    if(message==WM_APP+42) { ShowWindow(hwnd,SW_SHOW);SetForegroundWindow(hwnd);return AllowSetForegroundWindow(ASFW_ANY); }
    if(message==WM_DESTROY) { if(--fixtureWindows==0)PostQuitMessage(0);return 0; }
    return DefWindowProcW(hwnd,message,wp,lp);
}
static int fixture(void) {
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    WNDCLASSW cls={0};cls.hInstance=GetModuleHandleW(NULL);cls.lpfnWndProc=fixtureProcedure;cls.lpszClassName=L"AeroSpace.Smoke.Fixture";
    RegisterClassW(&cls);
    for(int i=0;i<2;i++) {
        wchar_t title[128];swprintf_s(title,128,L"AeroSpace smoke fixture %d",i+1);
        HWND hwnd=CreateWindowExW(0,cls.lpszClassName,title,WS_OVERLAPPEDWINDOW,100+i*80,100+i*80,480,320,NULL,NULL,cls.hInstance,NULL);
        if(!hwnd)return 1;
        fixtureWindows++;ShowWindow(hwnd,SW_SHOWNOACTIVATE);
    }
    MSG message;while(GetMessageW(&message,NULL,0,0)>0){TranslateMessage(&message);DispatchMessageW(&message);}return 0;
}
static PROCESS_INFORMATION launch(const wchar_t *executable,wchar_t *command) {
    STARTUPINFOW startup={0};startup.cb=sizeof(startup);PROCESS_INFORMATION process={0};
    CreateProcessW(executable,command,NULL,NULL,FALSE,CREATE_NO_WINDOW,NULL,NULL,&startup,&process);
    if(process.hThread){CloseHandle(process.hThread);process.hThread=NULL;}return process;
}
static int waitVisible(uint64_t handle,int visible) {
    for(int i=0;i<100;i++){if(!!IsWindowVisible((HWND)(uintptr_t)handle)==visible)return 1;Sleep(30);}return 0;
}
static int request(const char *arguments,char *response,size_t capacity) {
    char json[8192];snprintf(json,sizeof(json),"{\"args\":[%s],\"stdin\":\"\",\"windowId\":null,\"workspace\":null}",arguments);
    uint64_t pipe=aw_pipe_connect(5000);if(!pipe)return 0;
    aw_allow_server_foreground(pipe);
    char *data=NULL;uint32_t size=0;
    int ok=aw_pipe_write(pipe,json,(uint32_t)strlen(json)) && aw_pipe_read(pipe,&data,&size);
    if(ok){size_t n=0;for(uint32_t i=0;i<size && n+1<capacity;i++)if(data[i]!=' '&&data[i]!='\r'&&data[i]!='\n')response[n++]=data[i];response[n]=0;}
    aw_free(data);aw_pipe_close(pipe);return ok;
}
static void noEvent(int32_t event,uint64_t value){(void)event;(void)value;}
static DWORD WINAPI loopThread(void *ignored){(void)ignored;aw_run_loop(noEvent);return 0;}
static DWORD WINAPI shutdownThread(void *ignored){(void)ignored;aw_shutdown();return 0;}
#define CHECK(condition, name) do { if(!(condition)){fprintf(stderr,"FAIL: %s (Windows error %lu)\n",name,GetLastError());failed=1;goto cleanup;}printf("PASS: %s\n",name);fflush(stdout); } while(0)

int wmain(int argc,wchar_t **argv) {
    SetErrorMode(SEM_FAILCRITICALERRORS|SEM_NOGPFAULTERRORBOX);
    if(argc==2 && !wcscmp(argv[1],L"--fixture"))return fixture();
    if(argc==3 && !wcscmp(argv[1],L"--watchdog"))return aw_watchdog((uint32_t)wcstoul(argv[2],NULL,10));
    if(argc==3 && !wcscmp(argv[1],L"--crash-hide")) {
        if(!aw_initialize() || !aw_start_watchdog() || !aw_hide(_wcstoui64(argv[2],NULL,10)))return 1;
        Sleep(100);ExitProcess(42);
    }
    wchar_t own[32768],directory[32768],command[32768],appPath[32768],configPath[32768]={0};
    GetModuleFileNameW(NULL,own,32768);wcscpy_s(directory,32768,own);*wcsrchr(directory,L'\\')=0;
    if(argc==2)wcscpy_s(directory,32768,argv[1]); // Verify a separately packaged application.
    swprintf_s(command,32768,L"\"%ls\" --fixture",own);
    PROCESS_INFORMATION child=launch(own,command),app={0},crasher={0};
    HANDLE loop=NULL;int initialized=0,failed=0;uint64_t windows[2]={0};
    HWND previousForeground=GetForegroundWindow();
    char response[65536];
    CHECK(child.hProcess,"launch isolated fixture");
    CHECK(aw_initialize(),"initialize Win32 backend");initialized=1;
    for(int attempt=0;attempt<100 && !windows[1];attempt++) {
        int32_t count=0;AWWindow *list=aw_windows(&count);int n=0;
        for(int i=0;i<count && n<2;i++)if(list[i].pid==child.dwProcessId)windows[n++]=list[i].handle;
        aw_free(list);if(!windows[1])Sleep(30);
    }
    CHECK(windows[0]&&windows[1],"enumerate both fixture windows");
    int32_t monitorCount=0;AWMonitor *monitors=aw_monitors(&monitorCount);
    CHECK(monitors && monitorCount>0,"enumerate monitor work areas");
    AWRect rect=monitors[0].work;for(int i=0;i<monitorCount;i++)if(monitors[i].primary)rect=monitors[i].work;
    rect.width=600;rect.height=400;aw_free(monitors);
    CHECK(aw_position(windows[0],rect),"position window");Sleep(150);
    AWWindow info;CHECK(aw_window(windows[0],&info)&&abs(info.rect.x-rect.x)<=1&&abs(info.rect.y-rect.y)<=1&&abs(info.rect.width-rect.width)<=1,"read back physical frame");
    loop=CreateThread(NULL,0,loopThread,NULL,0,NULL);while(!aw_loop_ready())Sleep(10);
    CHECK(aw_loop_ready()==1,"start native message loop");
    CHECK(aw_register_hotkey(1,MOD_ALT|MOD_CONTROL,VK_F7),"register hotkey");
    CHECK(!aw_register_hotkey(2,MOD_ALT|MOD_CONTROL,VK_F7),"reject conflicting hotkey");aw_unregister_hotkey(1);
    CHECK(aw_hide(windows[0])&&waitVisible(windows[0],0),"hide managed window");
    CHECK(IsWindowVisible((HWND)(uintptr_t)windows[1]),"leave other window visible");
    CHECK(aw_show(windows[0])&&waitVisible(windows[0],1),"restore managed window");
    int visibilityQueued=1;
    for(int i=0;i<40;i++)visibilityQueued=visibilityQueued&&aw_hide(windows[0])&&aw_show(windows[0]);
    CHECK(visibilityQueued,"queue forty hide/show transitions safely");
    CHECK(waitVisible(windows[0],1),"rapid visibility changes preserve final state");
    HANDLE shutdown=CreateThread(NULL,0,shutdownThread,NULL,0,NULL);
    CHECK(shutdown && WaitForSingleObject(shutdown,3000)==WAIT_OBJECT_0,"shutdown from another thread");
    CloseHandle(shutdown);initialized=0;WaitForSingleObject(loop,3000);CloseHandle(loop);loop=NULL;

    swprintf_s(command,32768,L"\"%ls\" --crash-hide %llu",own,(unsigned long long)windows[0]);
    crasher=launch(own,command);CHECK(crasher.hProcess,"launch recovery test");
    CHECK(WaitForSingleObject(crasher.hProcess,10000)==WAIT_OBJECT_0,"terminate simulated manager");
    DWORD crashCode;GetExitCodeProcess(crasher.hProcess,&crashCode);
    CHECK(crashCode==42 && waitVisible(windows[0],1),"watchdog restores window after crash");
    CloseHandle(crasher.hProcess);crasher.hProcess=NULL;

    swprintf_s(appPath,32768,L"%ls\\AeroSpaceApp.exe",directory);
    swprintf_s(configPath,32768,L"%ls\\smoke-config.toml",directory);
    FILE *configuration=NULL;_wfopen_s(&configuration,configPath,L"wb");
    CHECK(configuration,"create isolated configuration");
    fputs("config-version = 2\npersistent-workspaces = ['1', '2']\n[mode.main.binding]\n",configuration);fclose(configuration);
    swprintf_s(command,32768,L"\"%ls\" --config-path \"%ls\" --manage-process %lu",appPath,configPath,child.dwProcessId);
    app=launch(appPath,command);CHECK(app.hProcess,"launch Swift manager for fixture PID only");
    CHECK(request("\"list-windows\",\"--workspace\",\"1\",\"--count\"",response,sizeof(response)) && strstr(response,"\"stdout\":\"2\""),"CLI transport and initial workspace membership");
    Sleep(200);AWWindow first,second;
    CHECK(aw_window(windows[0],&first)&&aw_window(windows[1],&second)&&first.rect.x!=second.rect.x,"tile both windows into distinct physical frames");
    CHECK(request("\"workspace\",\"2\"",response,sizeof(response)) && strstr(response,"\"exitCode\":0"),"switch to empty workspace");
    CHECK(waitVisible(windows[0],0)&&waitVisible(windows[1],0),"workspace switch hides both fixture windows");
    CHECK(request("\"enable\",\"off\"",response,sizeof(response)) && strstr(response,"\"exitCode\":0") && waitVisible(windows[0],1)&&waitVisible(windows[1],1),"disable restores every managed window");
    CHECK(request("\"list-windows\",\"--all\",\"--count\"",response,sizeof(response)) && strstr(response,"\"stdout\":\"2\""),"allow queries while disabled");
    CHECK(request("\"enable\",\"on\"",response,sizeof(response)) && strstr(response,"\"exitCode\":0"),"re-enable manager");
    CHECK(waitVisible(windows[0],0)&&waitVisible(windows[1],0),"re-enable keeps inactive workspace hidden");
    configuration=NULL;_wfopen_s(&configuration,configPath,L"wb");CHECK(configuration,"open config for rejection test");fputs("this is not TOML",configuration);fclose(configuration);
    int reloadReceived=request("\"reload-config\"",response,sizeof(response));
    if(reloadReceived&&!strstr(response,"\"exitCode\":2"))fprintf(stderr,"Reload response: %s\n",response);
    CHECK(reloadReceived && strstr(response,"\"exitCode\":2"),"reject invalid configuration");
    CHECK(request("\"list-workspaces\",\"--all\"",response,sizeof(response)) && strstr(response,"\"exitCode\":0"),"preserve prior configuration after reload failure");
    TerminateProcess(app.hProcess,42);WaitForSingleObject(app.hProcess,3000);CloseHandle(app.hProcess);app.hProcess=NULL;
    CHECK(waitVisible(windows[0],1)&&waitVisible(windows[1],1),"Swift manager crash restores all hidden windows");
    wchar_t defaultPath[32768];
    swprintf_s(defaultPath,32768,L"%ls\\AeroSpaceForWindows_AppBundle.resources\\default-config.toml",directory);
    swprintf_s(command,32768,L"\"%ls\" --config-path \"%ls\" --manage-process %lu",appPath,defaultPath,child.dwProcessId);
    app=launch(appPath,command);CHECK(app.hProcess,"launch bundled default configuration");
    CHECK(request("\"list-windows\",\"--all\",\"--count\"",response,sizeof(response))&&strstr(response,"\"stdout\":\"2\""),"register every default shortcut");
    CHECK(request("\"mode\",\"service\"",response,sizeof(response))&&strstr(response,"\"exitCode\":0"),"register service mode shortcuts");
    CHECK(request("\"mode\",\"main\"",response,sizeof(response))&&strstr(response,"\"exitCode\":0"),"restore main mode shortcuts");
    CHECK(request("\"layout\",\"--workspace\",\"1\",\"--root\",\"v_tiles\"",response,sizeof(response))&&strstr(response,"\"exitCode\":0"),"change tile orientation through CLI");
    Sleep(200);
    CHECK(aw_window(windows[0],&first)&&aw_window(windows[1],&second)&&first.rect.y!=second.rect.y,"apply vertical tile frames");
    CHECK(request("\"list-windows\",\"--focused\",\"--format\",\"%{window-id}\"",response,sizeof(response)),"resolve focused model window");
    char *focusedValue=strstr(response,"\"stdout\":\"");
    unsigned long targetID=focusedValue?strtoul(focusedValue+10,NULL,10):0;
    CHECK(targetID,"preserve native handle identity through model IDs");
    DWORD_PTR foregroundGranted=0;
    SendMessageTimeoutW((HWND)(uintptr_t)windows[0],WM_APP+42,0,0,SMTO_ABORTIFHUNG,1000,&foregroundGranted);
    char targetArguments[1024];snprintf(targetArguments,sizeof(targetArguments),"\"focus\",\"--window-id\",\"%lu\"",targetID);
    CHECK(request(targetArguments,response,sizeof(response)),"request explicit focus for current model target");
    DWORD foregroundPID=0;GetWindowThreadProcessId(GetForegroundWindow(),&foregroundPID);
    if(foregroundGranted)CHECK(strstr(response,"\"exitCode\":0")&&foregroundPID==child.dwProcessId,"activate an actual fixture window");
    else CHECK(strstr(response,"\"exitCode\":0")||strstr(response,"Windowsdeniedforegroundactivation"),"report foreground permission outcome explicitly");
    snprintf(targetArguments,sizeof(targetArguments),"\"fullscreen\",\"--window-id\",\"%lu\",\"on\"",targetID);
    CHECK(request(targetArguments,response,sizeof(response))&&strstr(response,"\"exitCode\":0"),"enter AeroSpace fullscreen");
    CHECK(request("\"list-windows\",\"--focused\",\"--format\",\"%{window-is-fullscreen}\"",response,sizeof(response))&&strstr(response,"\"stdout\":\"true\""),"publish fullscreen model state");
    snprintf(targetArguments,sizeof(targetArguments),"\"fullscreen\",\"--window-id\",\"%lu\",\"off\"",targetID);
    CHECK(request(targetArguments,response,sizeof(response))&&strstr(response,"\"exitCode\":0"),"leave AeroSpace fullscreen");
    snprintf(targetArguments,sizeof(targetArguments),"\"layout\",\"--window-id\",\"%lu\",\"floating\"",targetID);
    CHECK(request(targetArguments,response,sizeof(response))&&strstr(response,"\"exitCode\":0"),"convert target to floating");
    snprintf(targetArguments,sizeof(targetArguments),"\"resize\",\"--window-id\",\"%lu\",\"width\",\"+50\"",targetID);
    CHECK(request(targetArguments,response,sizeof(response))&&strstr(response,"\"exitCode\":0"),"resize floating target");
    snprintf(targetArguments,sizeof(targetArguments),"\"layout\",\"--window-id\",\"%lu\",\"tiling\"",targetID);
    CHECK(request(targetArguments,response,sizeof(response))&&strstr(response,"\"exitCode\":0"),"return floating target to tiling");
    TerminateProcess(app.hProcess,42);WaitForSingleObject(app.hProcess,3000);CloseHandle(app.hProcess);app.hProcess=NULL;
    CHECK(waitVisible(windows[0],1)&&waitVisible(windows[1],1),"restore fixture after default configuration test");
    configuration=NULL;_wfopen_s(&configuration,configPath,L"wb");CHECK(configuration,"restore valid diagnostic configuration");
    fputs("config-version = 2\npersistent-workspaces = ['1', '2']\n[mode.main.binding]\n",configuration);fclose(configuration);
    swprintf_s(command,32768,L"\"%ls\" --read-only --config-path \"%ls\" --manage-process %lu",appPath,configPath,child.dwProcessId);
    app=launch(appPath,command);CHECK(app.hProcess,"launch read-only diagnostic manager");
    CHECK(request("\"list-windows\",\"--all\",\"--count\"",response,sizeof(response))&&strstr(response,"\"stdout\":\"2\""),"read-only mode discovers windows");
    CHECK(request("\"enable\",\"on\"",response,sizeof(response))&&strstr(response,"\"exitCode\":2")&&waitVisible(windows[0],1)&&waitVisible(windows[1],1),"read-only mode rejects enabling window changes");

cleanup:
    if(app.hProcess){TerminateProcess(app.hProcess,42);WaitForSingleObject(app.hProcess,3000);CloseHandle(app.hProcess);waitVisible(windows[0],1);waitVisible(windows[1],1);}
    if(crasher.hProcess){TerminateProcess(crasher.hProcess,42);CloseHandle(crasher.hProcess);}
    if(initialized)aw_shutdown();
    if(loop){WaitForSingleObject(loop,3000);CloseHandle(loop);}
    if(child.hProcess){for(int i=0;i<2;i++)if(windows[i])PostMessageW((HWND)(uintptr_t)windows[i],WM_CLOSE,0,0);if(WaitForSingleObject(child.hProcess,3000)!=WAIT_OBJECT_0)TerminateProcess(child.hProcess,1);CloseHandle(child.hProcess);}
    if(configPath[0])DeleteFileW(configPath);
    if(previousForeground && IsWindow(previousForeground))SetForegroundWindow(previousForeground);
    return failed;
}
