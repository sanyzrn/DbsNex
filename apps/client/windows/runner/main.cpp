#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance,
                      _In_opt_ HINSTANCE prev,
                      _In_ wchar_t* command_line,
                      _In_ int show_command) {
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  flutter::DartProject project(L"data");
  project.set_dart_entrypoint_arguments(GetCommandLineArguments());

  const int width = 1120;
  const int height = 760;
  Win32Window::Point origin(
      (GetSystemMetrics(SM_CXSCREEN) - width) / 2,
      (GetSystemMetrics(SM_CYSCREEN) - height) / 2);
  Win32Window::Size size(width, height);

  FlutterWindow window(project);
  if (!window.Create(L"Nex", origin, size)) return EXIT_FAILURE;
  window.SetQuitOnClose(true);
  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }
  ::CoUninitialize();
  return EXIT_SUCCESS;
}