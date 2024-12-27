// com.cpp : Defines the entry point for the application.
//

#include "framework.h"
#include "com.h"
#include "send.h"

#include <objbase.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <WinSock2.h>

typedef enum {
    WM_USER_SOCK_ERROR = WM_USER,
    WM_USER_SOUND_ERROR,
} WM_USER_Messages;

#define MAX_LOADSTRING 100
#define SERVER_PORT     1967
#define HEADER_SIZE     4
#define PACKET_SIZE     2
#define MAX_PACKETS     100
#define EXPECTED_HEADER "COM\n"

// Global Variables:
static HINSTANCE hInst;                                // current instance
static WCHAR szTitle[MAX_LOADSTRING];                  // The title bar text
static WCHAR szWindowClass[MAX_LOADSTRING];            // the main window class name
static HANDLE hNetworkThread;							// thread handle

// Forward declarations of functions included in this code module:
ATOM                MyRegisterClass(HINSTANCE hInstance);
BOOL                InitInstance(HINSTANCE, int);
LRESULT CALLBACK    WndProc(HWND, UINT, WPARAM, LPARAM);
INT_PTR CALLBACK    About(HWND, UINT, WPARAM, LPARAM);
DWORD WINAPI		networkThread(LPVOID lpParameter);


int APIENTRY wWinMain(_In_ HINSTANCE hInstance,
                     _In_opt_ HINSTANCE hPrevInstance,
                     _In_ LPWSTR    lpCmdLine,
                     _In_ int       nCmdShow)
{
    UNREFERENCED_PARAMETER(hPrevInstance);
    UNREFERENCED_PARAMETER(lpCmdLine);

    // winsock required
    WSAData data;
    if (WSAStartup(MAKEWORD(2, 2), &data) != 0)
    {
        return FALSE;
    }

    // COM required
    HRESULT hr;
    hr = CoInitializeEx(NULL, COINIT_MULTITHREADED);
    if (hr != S_OK)
    {
        return FALSE;
    }

    // Initialize global strings
    LoadStringW(hInstance, IDS_APP_TITLE, szTitle, MAX_LOADSTRING);
    LoadStringW(hInstance, IDC_COM, szWindowClass, MAX_LOADSTRING);
    MyRegisterClass(hInstance);

    // Perform application initialization:
    if (!InitInstance (hInstance, nCmdShow))
    {
        return FALSE;
    }

    HACCEL hAccelTable = LoadAccelerators(hInstance, MAKEINTRESOURCE(IDC_COM));

    MSG msg;

    // Main message loop:
    while (GetMessage(&msg, nullptr, 0, 0))
    {
        if (!TranslateAccelerator(msg.hwnd, hAccelTable, &msg))
        {
            TranslateMessage(&msg);
            DispatchMessage(&msg);
        }
    }

    CoUninitialize();

    return (int) msg.wParam;
}



//
//  FUNCTION: MyRegisterClass()
//
//  PURPOSE: Registers the window class.
//
ATOM MyRegisterClass(HINSTANCE hInstance)
{
    WNDCLASSEXW wcex;

    wcex.cbSize = sizeof(WNDCLASSEX);

    wcex.style          = CS_HREDRAW | CS_VREDRAW;
    wcex.lpfnWndProc    = WndProc;
    wcex.cbClsExtra     = 0;
    wcex.cbWndExtra     = 0;
    wcex.hInstance      = hInstance;
    wcex.hIcon          = LoadIcon(hInstance, MAKEINTRESOURCE(IDI_COM));
    wcex.hCursor        = LoadCursor(nullptr, IDC_ARROW);
    wcex.hbrBackground  = (HBRUSH)(COLOR_WINDOW+1);
    wcex.lpszMenuName   = MAKEINTRESOURCEW(IDC_COM);
    wcex.lpszClassName  = szWindowClass;
    wcex.hIconSm        = LoadIcon(wcex.hInstance, MAKEINTRESOURCE(IDI_SMALL));

    return RegisterClassExW(&wcex);
}

//
//   FUNCTION: InitInstance(HINSTANCE, int)
//
//   PURPOSE: Saves instance handle and creates main window
//
//   COMMENTS:
//
//        In this function, we save the instance handle in a global variable and
//        create and display the main program window.
//
BOOL InitInstance(HINSTANCE hInstance, int nCmdShow)
{
   hInst = hInstance; // Store instance handle in our global variable

   HWND hWnd = CreateWindowW(szWindowClass, szTitle, WS_OVERLAPPEDWINDOW,
      CW_USEDEFAULT, 0, CW_USEDEFAULT, 0, nullptr, nullptr, hInstance, nullptr);

   if (!hWnd)
   {
      return FALSE;
   }

   // ShowWindow(hWnd, nCmdShow);
   UpdateWindow(hWnd);

   hNetworkThread = CreateThread(NULL, 0, networkThread, hWnd, 0, NULL);

   return TRUE;
}

//
//  FUNCTION: WndProc(HWND, UINT, WPARAM, LPARAM)
//
//  PURPOSE: Processes messages for the main window.
//
//  WM_COMMAND  - process the application menu
//  WM_PAINT    - Paint the main window
//  WM_DESTROY  - post a quit message and return
//
//
LRESULT CALLBACK WndProc(HWND hWnd, UINT message, WPARAM wParam, LPARAM lParam)
{
    switch (message)
    {
    case WM_COMMAND:
    {
        int wmId = LOWORD(wParam);
        // Parse the menu selections:
        switch (wmId)
        {
        case IDM_ABOUT:
            DialogBox(hInst, MAKEINTRESOURCE(IDD_ABOUTBOX), hWnd, About);
            break;
        case IDM_EXIT:
            DestroyWindow(hWnd);
            break;
        default:
            return DefWindowProc(hWnd, message, wParam, lParam);
        }
    }
    break;
    case WM_PAINT:
    {
        PAINTSTRUCT ps;
        HDC hdc = BeginPaint(hWnd, &ps);
        // TODO: Add any drawing code that uses hdc here...
        EndPaint(hWnd, &ps);
    }
    break;
    case WM_DESTROY:
        PostQuitMessage(0);
        break;
    case WM_USER_SOCK_ERROR:
    {
        WCHAR message[128];
        wsprintf(message, L"Socket error code %u", (unsigned)lParam);
        (void)MessageBox(hWnd, message, szTitle, MB_OK | MB_ICONWARNING | MB_DEFBUTTON2 | MB_TOPMOST | MB_SYSTEMMODAL);
    }
    break;
    case WM_USER_SOUND_ERROR:
    {
        WCHAR message[128];
        wsprintf(message, L"Sound error code 0x%x", (unsigned)lParam);
        (void)MessageBox(hWnd, message, szTitle, MB_OK | MB_ICONWARNING | MB_DEFBUTTON2 | MB_TOPMOST | MB_SYSTEMMODAL);
    }
    break;
    default:
        return DefWindowProc(hWnd, message, wParam, lParam);
    }
    return 0;
}

// Message handler for about box.
INT_PTR CALLBACK About(HWND hDlg, UINT message, WPARAM wParam, LPARAM lParam)
{
    UNREFERENCED_PARAMETER(lParam);
    switch (message)
    {
    case WM_INITDIALOG:
        return (INT_PTR)TRUE;

    case WM_COMMAND:
        if (LOWORD(wParam) == IDOK || LOWORD(wParam) == IDCANCEL)
        {
            EndDialog(hDlg, LOWORD(wParam));
            return (INT_PTR)TRUE;
        }
        break;
    }
    return (INT_PTR)FALSE;
}
// Thread procedure - listen on UDP port and take appropriate actions
DWORD WINAPI networkThread(LPVOID lpParameter)
{
    HWND hWnd = (HWND)lpParameter;

    int sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (sock < 0) {
        PostMessage(hWnd, WM_USER_SOCK_ERROR, 0, 1);
        return 0;
    }

    struct sockaddr_in server;
    memset(&server, 0, sizeof(server));
    server.sin_family = AF_INET;
    server.sin_addr.s_addr = INADDR_ANY;
    server.sin_port = htons(SERVER_PORT);

    if (bind(sock, (struct sockaddr*)&server, sizeof(server)) < 0) {
        PostMessage(hWnd, WM_USER_SOCK_ERROR, 0, 2);
        goto cleanup;
    }

    while (1)
    {
        struct sockaddr_in from;
        uint8_t buf[HEADER_SIZE + (MAX_PACKETS * PACKET_SIZE) + 1];
        int fromlen = sizeof(from);
        int bytes = recvfrom(sock, (char*) buf, sizeof(buf) - 1, 0, (struct sockaddr*)&from, &fromlen);
        if (bytes < 0) {
            PostMessage(hWnd, WM_USER_SOCK_ERROR, 0, 3);
            goto cleanup;
        }
        if ((bytes > HEADER_SIZE)
            && ((bytes % PACKET_SIZE) == 0)
            && (memcmp(buf, EXPECTED_HEADER, HEADER_SIZE) == 0))
        {
            // message appears valid - read packet data
            uint64_t packets[MAX_PACKETS];
            int packet_count = 0;
            int byte_index = HEADER_SIZE;
            while (((byte_index + PACKET_SIZE) <= bytes) && (packet_count < MAX_PACKETS))
            {
                // Each packet is encoded as 16-bit big-endian
                packets[packet_count] = ((uint64_t)buf[byte_index + 0] << 8)
                    | ((uint64_t)buf[byte_index + 1]);
                packet_count++;
                byte_index += PACKET_SIZE;
            }
            HRESULT hr = comSend(packet_count, packets);
            if (hr != S_OK)
            {
                PostMessage(hWnd, WM_USER_SOUND_ERROR, 0, (DWORD)hr);
            }
        }
    }
cleanup:
    closesocket(sock);
    return 0;
}