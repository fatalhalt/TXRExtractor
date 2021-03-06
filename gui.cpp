/*
 * TXRExtractor GUI
 *
 *
 *
 *  MessageBox(hWnd, "foobar", TEXT("Info"), MB_ICONINFORMATION | MB_OK);
 *
 */

#define _CRT_SECURE_NO_WARNINGS
#define _WINSOCK_DEPRECATED_NO_WARNINGS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <shellapi.h>
#include <fcntl.h>
#include <io.h>
#include <direct.h>
#include <commdlg.h>
#include <shlobj_core.h>
#include "resource.h"
#include "TXRExtractor.h"

#define MAX_LOADSTRING 64
#define MIN_WINDOW_WIDTH 480
#define MIN_WINDOW_HEIGHT 300
#define TXREXTRACTOR_GUI_BUILD
#define PATHNAME_SIZE 512


static HINSTANCE hInst = 0; 
static UINT WM_TASKBAR = 0;
static HWND g_hWnd = 0, g_hWnd_tb1 = 0, g_hWnd_tb2 = 0, g_hWnd_tb3 = 0;
HWND g_hWnd_tb4 = 0;
static unsigned int g_pingCount = 0;
static HMENU Hmenu;
static NOTIFYICONDATA notifyIconData;
static TCHAR szTitle[MAX_LOADSTRING];     // title bar text
static TCHAR szClassName[MAX_LOADSTRING]; // the main window class name
static BOOL g_myTimerEngaged = FALSE;

/* function prototypess */
LRESULT CALLBACK WindowProcedure(HWND, UINT, WPARAM, LPARAM);
static void InitNotifyIconData(HWND);
static void chooseFilename(HWND, TCHAR*);
static void chooseFolder(HWND, TCHAR*);
static int extract(HWND, TCHAR *, TCHAR *, TCHAR *);

int WINAPI WinMain(HINSTANCE hThisInstance, HINSTANCE hPrevInstance, LPSTR lpszArgument, int nCmdShow)
{
    UNREFERENCED_PARAMETER(hPrevInstance);    // silence the  warning C4100: unreferenced formal parameter
    UNREFERENCED_PARAMETER(lpszArgument);
    hInst = hThisInstance;

    LoadString(hThisInstance, IDS_MYAPP_TITLE, szTitle, MAX_LOADSTRING);
    LoadString(hThisInstance, IDC_MYAPP, szClassName, MAX_LOADSTRING);
    if (FindWindow(szClassName, szTitle))
    {
        MessageBox(NULL, TEXT("Previous instance alredy running!"), szTitle, MB_OK);
        return 0;
    }

    WM_TASKBAR = RegisterWindowMessage("TaskbarCreated");

    MSG msg;
    WNDCLASSEX wincl;                         // a struct for the windowclass to be registered with RegisterClassEx()  */
    wincl.hInstance = hThisInstance;
    wincl.lpszClassName = szClassName;
    wincl.lpfnWndProc = WindowProcedure;      // our 'WindowProc callback function' that will get called when OS has any msg for us
    wincl.style = CS_DBLCLKS;                 // do send us double-click message/event to WindowProcedure
    wincl.cbSize = sizeof(WNDCLASSEX);
    wincl.hIcon = LoadIcon(GetModuleHandle(NULL), MAKEINTRESOURCE(ICO1));
    wincl.hIconSm = LoadIcon(GetModuleHandle(NULL), MAKEINTRESOURCE(ICO1));
    wincl.hCursor = LoadCursor(NULL, IDC_ARROW);
    wincl.lpszMenuName = MAKEINTRESOURCE(IDC_MYAPP);
    wincl.cbClsExtra = 0;                     // number of bytes to allocate windowclass struct
    wincl.cbWndExtra = 0;
    wincl.hbrBackground = (HBRUSH)(CreateSolidBrush(RGB(255, 255, 255)));
    if (!RegisterClassEx (&wincl))            // register the windowclass struct for CreateWindowEx() use
        return 0;

    HWND hWnd = CreateWindowEx(0, szClassName, szTitle, WS_OVERLAPPEDWINDOW & ~WS_MAXIMIZEBOX, CW_USEDEFAULT, CW_USEDEFAULT, MIN_WINDOW_WIDTH, MIN_WINDOW_HEIGHT,
               HWND_DESKTOP,        /* the window is a child-window to desktop, HWND_DESKTOP is NULL */
               NULL, hThisInstance, NULL);
    if (!hWnd)
    {
        MessageBox(NULL, "Can't create a window!", TEXT("Warning!"), MB_ICONERROR | MB_OK | MB_TOPMOST);
        return 1;
    }
    g_hWnd = hWnd;
    //CreateWindowEx(WS_EX_CLIENTEDGE, TEXT("Foo"), TEXT("bar"), WS_CHILD | WS_VISIBLE | WS_BORDER, x, y, w, h, hWnd, NULL, NULL, NULL);

    /* create GUI elements */
    static HWND hWnd_lbl1, hWnd_lbl2, hWnd_lbl3, hWnd_tb1, hWnd_tb2, hWnd_tb3, hWnd_tb4, hWnd_btn1, hWnd_btn2, hWnd_btn3, hWnd_btn4;  // declared as static so won't get lost once WM_CREATE returns control to OS
    int x, w, y, h;
    y = 10; h = 20;
    x = 10; w = 70;                           // create a label for "Archive" selection
    hWnd_lbl1 = CreateWindow(TEXT("static"), "ST_U", WS_CHILD | WS_VISIBLE | WS_TABSTOP, x, y, w, h, hWnd, (HMENU)IDG_LBl1, (HINSTANCE) GetWindowLong(hWnd, GWLP_HINSTANCE), NULL);
    SetWindowText(hWnd_lbl1, "Archive:");
    x += w; w = 250;                          // create textbox for Archive
    g_hWnd_tb1 = hWnd_tb1 = CreateWindow(TEXT("edit"), "", WS_CHILD | WS_VISIBLE | WS_TABSTOP | ES_LEFT | WS_BORDER, x, y, w, h, hWnd, (HMENU)IDG_TB1, (HINSTANCE)GetWindowLong(hWnd, GWLP_HINSTANCE), NULL);
    SetWindowText(hWnd_tb1, "C:\\WMN.DAT");
    x += w + 10; w = 50;                      // create a button to set "Archive" path
    hWnd_btn1 = CreateWindow(TEXT("BUTTON"), TEXT("Open"), WS_TABSTOP | WS_VISIBLE | WS_CHILD | BS_DEFPUSHBUTTON, x, y, w, h, hWnd, (HMENU)IDG_BTN1, (HINSTANCE)GetWindowLong(hWnd, GWLP_HINSTANCE), NULL);
    x += w + 10; w = 50;                      // create a button for "Extract"
    hWnd_btn2 = CreateWindow(TEXT("BUTTON"), TEXT("Extract"), WS_TABSTOP | WS_VISIBLE | WS_CHILD | BS_DEFPUSHBUTTON, x, y, w, h, hWnd, (HMENU)IDG_BTN2, (HINSTANCE)GetWindowLong(hWnd, GWLP_HINSTANCE), NULL);

    x = 10; y += h + 10; w = 70;              // create a label for "TOC" selection
    hWnd_lbl2 = CreateWindow(TEXT("static"), "ST_U", WS_CHILD | WS_VISIBLE | WS_TABSTOP, x, y, w, h, hWnd, (HMENU)IDG_LBl2, (HINSTANCE) GetWindowLong(hWnd, GWLP_HINSTANCE), NULL);
    SetWindowText(hWnd_lbl2, "TOC:");
    x += w; w = 250;                          // create textbox for TOC
    g_hWnd_tb2 = hWnd_tb2 = CreateWindow(TEXT("edit"), "", WS_CHILD | WS_VISIBLE | WS_TABSTOP | ES_LEFT | WS_BORDER, x, y, w, h, hWnd, (HMENU)IDG_TB2, (HINSTANCE)GetWindowLong(hWnd, GWLP_HINSTANCE), NULL);
    SetWindowText(hWnd_tb2, "C:\\WMN.TOC");
    x += w + 10; w = 50;                      // create a button to set "TOC" path
    hWnd_btn3 = CreateWindow(TEXT("BUTTON"), TEXT("Open"), WS_TABSTOP | WS_VISIBLE | WS_CHILD | BS_DEFPUSHBUTTON, x, y, w, h, hWnd, (HMENU)IDG_BTN3, (HINSTANCE)GetWindowLong(hWnd, GWLP_HINSTANCE), NULL);


    x = 10; y += h + 10; w = 70;              // create a label for "Output" directory
    hWnd_lbl3 = CreateWindow(TEXT("static"), "ST_U", WS_CHILD | WS_VISIBLE | WS_TABSTOP, x, y, w, h, hWnd, (HMENU)IDG_LBl3, (HINSTANCE) GetWindowLong(hWnd, GWLP_HINSTANCE), NULL);
    SetWindowText(hWnd_lbl3, "Output:");
    x += w; w = 250;                          // create textbox for "Output" path
    g_hWnd_tb3 = hWnd_tb3 = CreateWindow(TEXT("edit"), "", WS_CHILD | WS_VISIBLE | WS_TABSTOP | ES_LEFT | WS_BORDER, x, y, w, h, hWnd, (HMENU)IDG_TB3, (HINSTANCE)GetWindowLong(hWnd, GWLP_HINSTANCE), NULL);
    SetWindowText(hWnd_tb3, "C:\\TEMP");
    x += w + 10; w = 50;                      // create a button to set "Output" path
    hWnd_btn4 = CreateWindow(TEXT("BUTTON"), TEXT("Pick"), WS_TABSTOP | WS_VISIBLE | WS_CHILD | BS_DEFPUSHBUTTON, x, y, w, h, hWnd, (HMENU)IDG_BTN4, (HINSTANCE)GetWindowLong(hWnd, GWLP_HINSTANCE), NULL);

    x = 10; y += h + 10; w = 450; h = 120;    // create a textbox for file extraction list
    g_hWnd_tb4 = hWnd_tb4 = CreateWindow(TEXT("edit"), "", WS_CHILD | WS_VISIBLE | WS_VSCROLL | ES_MULTILINE | ES_READONLY | ES_AUTOVSCROLL | WS_TABSTOP | ES_LEFT | WS_BORDER, x, y, w, h, hWnd, (HMENU)(503), (HINSTANCE)GetWindowLong(hWnd, GWLP_HINSTANCE), NULL);


    if (!hWnd_lbl1 || !hWnd_tb1 || !hWnd_tb2 || !hWnd_btn1)
    {
        MessageBox(NULL, "Failed to create GUI elements", TEXT("Warning!"), MB_ICONERROR | MB_OK | MB_TOPMOST);
        return 1;
    }

    ShowWindow(hWnd, nCmdShow);
    UpdateWindow(hWnd);

    /* main message loop. It will run until GetMessage() returns 0 */
    while (GetMessage(&msg, NULL, 0, 0))
    {
        TranslateMessage(&msg);               // translate virtual-key messages into character messages
        DispatchMessage(&msg);                // send message to WindowProcedure
    }

    UnregisterClass(szClassName, hThisInstance);
    return (int) msg.wParam;
}

/* this function is called by the Windows function DispatchMessage() */
LRESULT CALLBACK WindowProcedure(HWND hWnd, UINT message, WPARAM wParam, LPARAM lParam)
{
    static TCHAR archivePath[512] = { 0 };
    static TCHAR tocPath[512] = { 0 };
    static TCHAR outputPath[512] = { 0 };

    if (message == WM_TASKBAR && !IsWindowVisible(hWnd)) {
        ShowWindow(hWnd, SW_HIDE);
        return 0;
    }

    switch (message) {
    case WM_ACTIVATE:
        break;
    case WM_CREATE:                           // WM_CREATE message gets sent during CreateWindowEx(), WARNING! global hWnd is still 0 during this time!
        ShowWindow(hWnd, SW_HIDE);            // but local hWnd carries the valid handle
        Hmenu = CreatePopupMenu();
        InitNotifyIconData(hWnd);             // initialize the NOTIFYICONDATA structure only once
        AppendMenu(Hmenu, MF_STRING, ID_TRAY_ABOUT, TEXT("About"));
        AppendMenu(Hmenu, MF_STRING, ID_TRAY_EXIT, TEXT("Exit"));
        Shell_NotifyIcon(NIM_ADD, &notifyIconData);  // send message to systemtray to add an icon
        break;
    case WM_SYSCOMMAND:
		switch (wParam & 0xFFF0) {
        case SC_MINIMIZE:
        case SC_CLOSE:  
            ShowWindow(hWnd, SW_HIDE);
            return 0;
        }
        break;

    case WM_COMMAND:
        switch (LOWORD(wParam)) {
        case BN_PUSHED:
        case BN_CLICKED:                      // initiate extract
            {
/*
            if (g_myTimerEngaged) {
                KillTimer(hWnd, IDT_MYTIMER);
                g_myTimerEngaged = FALSE;
                return 0;
            }
*/
            }
            break;

        case IDG_BTN1:
            {
            chooseFilename(hWnd, archivePath);
            SendMessage(g_hWnd_tb1, WM_SETTEXT, (WPARAM)PATHNAME_SIZE, (LPARAM)&archivePath);
            //SetTimer(hWnd, IDT_MYTIMER, 1500, (TIMERPROC) NULL);  // timer fires every 1.5sec
            /* g_myTimerEngaged = TRUE; */
            }
            break;
        case IDG_BTN2:
            {
            int ret = -1;
            SendMessage(g_hWnd_tb4, EM_LIMITTEXT, NULL, 131072);  // double the text output limit from 64KB
            ret = extract(hWnd, archivePath, tocPath, outputPath);

            if (ret == 0) {
                int outputTextboxLength = 0;
                outputTextboxLength = GetWindowTextLength(g_hWnd_tb4);
                SendMessage(g_hWnd_tb4, EM_SETSEL, (WPARAM) outputTextboxLength, (LPARAM) outputTextboxLength);  // set selection to end of text
                SendMessage(g_hWnd_tb4, EM_REPLACESEL, 0, (LPARAM) "Extraction complete.\r\n");
                }
            }
            break;
        case IDG_BTN3:
            {
            chooseFilename(hWnd, tocPath);
            SendMessage(g_hWnd_tb2, WM_SETTEXT, (WPARAM)PATHNAME_SIZE, (LPARAM)&tocPath);
            }
            break;
        case IDG_BTN4:
            {
            chooseFolder(hWnd, outputPath);
            SendMessage(g_hWnd_tb3, WM_SETTEXT, (WPARAM)PATHNAME_SIZE, (LPARAM)&outputPath);
            }
            break;

        case IDM_CLEAR:
            SendMessage(g_hWnd_tb4, WM_SETTEXT, 0, (LPARAM) "output cleared.\r\n");
            return 0;
        case ID_TRAY_ABOUT:
        case IDM_ABOUT:
            TCHAR aboutBuf[100];
            LoadString(hInst, IDS_MYAPP_ABOUT, aboutBuf, 100);
            MessageBox(hWnd, aboutBuf, TEXT("About"), MB_ICONINFORMATION | MB_OK);
            return 0;
        case ID_TRAY_EXIT:
        case IDM_EXIT:
            PostMessage(hWnd, WM_DESTROY, 0, 0);
            return 0;
        }
        break;

    case WM_GETMINMAXINFO:                    // message received when size or position of the window is about to change
        {
        LPMINMAXINFO lpMMI = (LPMINMAXINFO)lParam;
        lpMMI->ptMinTrackSize.x = MIN_WINDOW_WIDTH;
        lpMMI->ptMinTrackSize.y = MIN_WINDOW_HEIGHT;
        }
        break;

    case WM_MYEXTRACT:
        break;

    case WM_TIMER:
        switch (wParam) {
        case IDT_MYTIMER:
            return 0;
        }
        break;

    case WM_MYSYSICON:                        // our user defined WM_MYSYSICON message
    {
        switch (wParam)
        {
        case ID_TRAY_APP_ICON:
            SetForegroundWindow(hWnd);
            break;
        }

        switch (lParam) {
        case WM_LBUTTONUP:
            ShowWindow(hWnd, SW_SHOW);
            break;
        case WM_RBUTTONDOWN:
            POINT curPoint;
            GetCursorPos(&curPoint);          // get current mouse position
            SetForegroundWindow(hWnd);
            // TrackPopupMenu blocks the app until TrackPopupMenu returns (e.g. user makes the choice)
            UINT cmd = TrackPopupMenu(Hmenu, TPM_RETURNCMD | TPM_LEFTALIGN| TPM_NONOTIFY, curPoint.x, curPoint.y, 0, hWnd, NULL);
            //SendMessage(hWnd, WM_NULL, 0, 0); // send benign message to window to make sure the menu goes away
            SendMessage(hWnd, WM_COMMAND, cmd, 0);
            break;
        }
    }
    break;

    case WM_NCHITTEST:                        // among things, allows the app to be dragged with Ctrl+leftclick
        {
        UINT uHitTest = DefWindowProc(hWnd, WM_NCHITTEST, wParam, lParam);
        if (uHitTest == HTCLIENT)
            return HTCAPTION;
        else
            return uHitTest;
        }
        break;

    case WM_CLOSE:
        ShowWindow(hWnd, SW_HIDE);
        return 0;

    case WM_DESTROY:
        Shell_NotifyIcon(NIM_DELETE, &notifyIconData);
        PostQuitMessage(0);
        break;
    }

    return DefWindowProc(hWnd, message, wParam, lParam);
}

static void InitNotifyIconData(HWND hWnd)
{
    memset(&notifyIconData, 0, sizeof(NOTIFYICONDATA));

    notifyIconData.cbSize = sizeof(NOTIFYICONDATA);
    notifyIconData.hWnd = hWnd;
    notifyIconData.uID = ID_TRAY_APP_ICON;
    notifyIconData.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
    notifyIconData.uCallbackMessage = WM_MYSYSICON;  // user defined message
    notifyIconData.hIcon = (HICON)LoadIcon(GetModuleHandle(NULL), MAKEINTRESOURCE(ICO1)) ;
    strncpy(notifyIconData.szTip, szTitle, sizeof(szTitle));  // tooltip string
}

// depends on  #include <commdlg.h>  and  comdlg32.lib
static void chooseFilename(HWND hWnd, TCHAR* pathname)
{
    OPENFILENAME ofn;                         // common dialog box structure
	memset(&ofn, 0, sizeof(ofn));
	ofn.lStructSize = sizeof(ofn);
	ofn.hwndOwner = NULL;
	ofn.lpstrFile = pathname;
	ofn.lpstrFile[0] = '\0';
	ofn.nMaxFile = PATHNAME_SIZE;
	ofn.lpstrFilter = TEXT("All\0*.*\0Text\0*.TXT\0";)
	ofn.nFilterIndex = 1;
	ofn.lpstrFileTitle = NULL;
	ofn.nMaxFileTitle = 0;
	ofn.lpstrInitialDir= NULL;
	ofn.Flags = OFN_PATHMUSTEXIST | OFN_FILEMUSTEXIST;
	GetOpenFileName(&ofn);
}

// depends on  #include <shlobj_core.h>
static void chooseFolder(HWND hWnd, TCHAR* pathname)
{
    BROWSEINFO br;
    memset(&br, 0, sizeof(BROWSEINFO));
    br.lpfn = NULL;
    br.ulFlags = BIF_RETURNONLYFSDIRS | BIF_NEWDIALOGSTYLE;
    br.hwndOwner = hWnd;
    br.lpszTitle = "Choose output directory";
    br.lParam = NULL;

    LPITEMIDLIST pidl = NULL;
    if ((pidl = SHBrowseForFolder(&br)) != NULL)
        SHGetPathFromIDList(pidl, pathname);
}

static int extract(HWND hWnd, TCHAR *archive, TCHAR *toc, TCHAR *out)
{
	archive_unpack_f archive_unpack = NULL;
	int ret;

	/* avoid end-of-line conversions */
	_setmode(_fileno(stdin), O_BINARY);
	_setmode(_fileno(stdout), O_BINARY);

	FILE *fd_archive, *fd_toc;
	fd_archive = fopen(archive, "rb");
	fd_toc = fopen(toc, "rb");
    char str_buff[512] = { 0 };
	if (!fd_archive || !fd_toc) {
        sprintf(str_buff, "Failed to open required files: %s\n", strerror(errno));
		fprintf(stderr, "failed to open required files: %s\n", strerror(errno));
        MessageBox(NULL, str_buff, TEXT("Warning!"), MB_ICONERROR | MB_OK | MB_TOPMOST);
		return 2;
	}

	ret = txre_detect_archive(&archive_unpack, fd_archive, fd_toc);
	if (ret == 0) {
		// cd to output dir
		if (_chdir(out)) {
            sprintf(str_buff, "Couldn't enter output directory %s: %s\n", out, strerror(errno));
			fprintf(stderr, "couldn't cd into %s: %s\n", out, strerror(errno));
            MessageBox(NULL, str_buff, TEXT("Warning!"), MB_ICONERROR | MB_OK | MB_TOPMOST);
			return 12;
		}

		// unpack archive
		ret = archive_unpack(fd_archive, fd_toc);
	} else {
		fprintf(stdout, "unsupported archive\n");
        MessageBox(NULL, TEXT("Unsupported archive"), TEXT("Warning!"), MB_ICONERROR | MB_OK | MB_TOPMOST);
        return 13;
	}

	fclose(fd_archive);
	fclose(fd_toc);

	return 0;
}
