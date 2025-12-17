#![cfg(windows)]

use std::process::{Child, Command};
use std::sync::atomic::{AtomicBool, Ordering};

use windows::core::w;
use windows::core::PCWSTR;
use windows::Win32::Foundation::{GetLastError, HWND, LPARAM, LRESULT, WPARAM};
use windows::Win32::System::LibraryLoader::GetModuleHandleW;
use windows::Win32::UI::WindowsAndMessaging::{
    CreateWindowExW, DefWindowProcW, DestroyWindow, DispatchMessageW, GetMessageW, LoadCursorW,
    PostQuitMessage, RegisterClassW, SetWindowTextW, ShowWindow, TranslateMessage,
    CREATESTRUCTW, CS_HREDRAW, CS_VREDRAW, CW_USEDEFAULT, HMENU, IDC_ARROW, MSG, SW_SHOW,
    WM_CLOSE, WM_COMMAND, WM_CREATE, WM_DESTROY, WNDCLASSW, WS_CHILD, WS_OVERLAPPEDWINDOW,
    WS_VISIBLE,
};

const ID_BTN_START: usize = 1001;
const ID_BTN_STOP: usize = 1002;
const ID_LBL_STATUS: usize = 2001;

static UI_CLASS_REGISTERED: AtomicBool = AtomicBool::new(false);

struct AppState {
    status_hwnd: HWND,
    child: Option<Child>,
}

pub fn run() -> anyhow::Result<()> {
    unsafe {
        let hinstance = GetModuleHandleW(None)?;

        // Register class once (defensive in case we ever re-enter run()).
        if !UI_CLASS_REGISTERED.swap(true, Ordering::SeqCst) {
            let class_name = w!("ThunderReceiverUiWindow");
            let wc = WNDCLASSW {
                style: CS_HREDRAW | CS_VREDRAW,
                lpfnWndProc: Some(wndproc),
                hInstance: hinstance.into(),
                lpszClassName: class_name,
                hCursor: LoadCursorW(None, IDC_ARROW)?,
                ..Default::default()
            };

            let atom = RegisterClassW(&wc);
            if atom == 0 {
                return Err(anyhow::anyhow!(
                    "RegisterClassW failed: {:?}",
                    GetLastError()
                ));
            }
        }

        let hwnd = CreateWindowExW(
            Default::default(),
            w!("ThunderReceiverUiWindow"),
            w!("ThunderMirror - Windows Viewer UI"),
            WS_OVERLAPPEDWINDOW | WS_VISIBLE,
            CW_USEDEFAULT,
            CW_USEDEFAULT,
            520,
            180,
            None,
            None,
            hinstance,
            None,
        );

        if hwnd.0 == 0 {
            return Err(anyhow::anyhow!(
                "CreateWindowExW failed: {:?}",
                GetLastError()
            ));
        }

        ShowWindow(hwnd, SW_SHOW);

        let mut msg = MSG::default();
        while GetMessageW(&mut msg, None, 0, 0).into() {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
    }

    Ok(())
}

unsafe extern "system" fn wndproc(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    match msg {
        WM_CREATE => {
            let cs = lparam.0 as *const CREATESTRUCTW;
            if !cs.is_null() {
                let hinstance = GetModuleHandleW(None).unwrap_or_default();
                // Create child controls.
                let status_hwnd = CreateWindowExW(
                    Default::default(),
                    w!("STATIC"),
                    w!("Status: Stopped"),
                    WS_CHILD | WS_VISIBLE,
                    20,
                    20,
                    470,
                    24,
                    hwnd,
                    HMENU(ID_LBL_STATUS as isize),
                    hinstance.into(),
                    None,
                );

                let _start_hwnd = CreateWindowExW(
                    Default::default(),
                    w!("BUTTON"),
                    w!("Start"),
                    WS_CHILD | WS_VISIBLE,
                    20,
                    70,
                    120,
                    32,
                    hwnd,
                    HMENU(ID_BTN_START as isize),
                    hinstance.into(),
                    None,
                );

                let _stop_hwnd = CreateWindowExW(
                    Default::default(),
                    w!("BUTTON"),
                    w!("Stop"),
                    WS_CHILD | WS_VISIBLE,
                    160,
                    70,
                    120,
                    32,
                    hwnd,
                    HMENU(ID_BTN_STOP as isize),
                    hinstance.into(),
                    None,
                );

                let state = Box::new(AppState {
                    status_hwnd,
                    child: None,
                });

                // Store pointer in window user data.
                windows::Win32::UI::WindowsAndMessaging::SetWindowLongPtrW(
                    hwnd,
                    windows::Win32::UI::WindowsAndMessaging::GWLP_USERDATA,
                    Box::into_raw(state) as isize,
                );
            }
            LRESULT(0)
        }
        WM_COMMAND => {
            let id = (wparam.0 & 0xffff) as usize;
            match id {
                ID_BTN_START => {
                    if let Some(state) = get_state(hwnd) {
                        if state.child.is_some() {
                            set_status(state.status_hwnd, "Status: Already running");
                        } else {
                            match spawn_receiver_child() {
                                Ok(child) => {
                                    state.child = Some(child);
                                    set_status(state.status_hwnd, "Status: Running (CLI child)");
                                }
                                Err(e) => {
                                    set_status(state.status_hwnd, &format!("Status: Start failed: {e}"));
                                }
                            }
                        }
                    }
                    LRESULT(0)
                }
                ID_BTN_STOP => {
                    if let Some(state) = get_state(hwnd) {
                        stop_child(state);
                        set_status(state.status_hwnd, "Status: Stopped");
                    }
                    LRESULT(0)
                }
                _ => DefWindowProcW(hwnd, msg, wparam, lparam),
            }
        }
        WM_CLOSE => {
            DestroyWindow(hwnd);
            LRESULT(0)
        }
        WM_DESTROY => {
            if let Some(state) = get_state(hwnd) {
                stop_child(state);
            }

            // Free state allocation.
            let ptr = windows::Win32::UI::WindowsAndMessaging::GetWindowLongPtrW(
                hwnd,
                windows::Win32::UI::WindowsAndMessaging::GWLP_USERDATA,
            ) as *mut AppState;
            if !ptr.is_null() {
                drop(Box::from_raw(ptr));
                windows::Win32::UI::WindowsAndMessaging::SetWindowLongPtrW(
                    hwnd,
                    windows::Win32::UI::WindowsAndMessaging::GWLP_USERDATA,
                    0,
                );
            }

            PostQuitMessage(0);
            LRESULT(0)
        }
        _ => DefWindowProcW(hwnd, msg, wparam, lparam),
    }
}

fn get_state(hwnd: HWND) -> Option<&'static mut AppState> {
    unsafe {
        let ptr = windows::Win32::UI::WindowsAndMessaging::GetWindowLongPtrW(
            hwnd,
            windows::Win32::UI::WindowsAndMessaging::GWLP_USERDATA,
        ) as *mut AppState;
        if ptr.is_null() {
            None
        } else {
            Some(&mut *ptr)
        }
    }
}

fn stop_child(state: &mut AppState) {
    if let Some(mut child) = state.child.take() {
        let _ = child.kill();
        let _ = child.wait();
    }
}

fn set_status(hwnd: HWND, text: &str) {
    unsafe {
        let wide = to_wide_null(text);
        SetWindowTextW(hwnd, PCWSTR(wide.as_ptr()));
    }
}

fn spawn_receiver_child() -> anyhow::Result<Child> {
    let ui_exe = std::env::current_exe()?;
    let dir = ui_exe
        .parent()
        .ok_or_else(|| anyhow::anyhow!("Failed to determine UI exe directory"))?;

    // In dev builds, this should sit alongside thunder_receiver.exe:
    // target\debug\thunder_receiver_ui.exe
    // target\debug\thunder_receiver.exe
    let receiver_exe = dir.join("thunder_receiver.exe");
    if !receiver_exe.exists() {
        return Err(anyhow::anyhow!(
            "Could not find thunder_receiver.exe next to UI: {}",
            receiver_exe.display()
        ));
    }

    Ok(Command::new(receiver_exe)
        .arg("--log-level")
        .arg("info")
        .spawn()?)
}

fn to_wide_null(s: &str) -> Vec<u16> {
    use std::os::windows::ffi::OsStrExt;
    std::ffi::OsStr::new(s).encode_wide().chain(Some(0)).collect()
}


