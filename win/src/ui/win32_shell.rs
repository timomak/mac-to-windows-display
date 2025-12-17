#![cfg(windows)]

use std::io::{BufRead, BufReader};
use std::process::Stdio;
use std::process::{Child, Command};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

use windows::core::w;
use windows::core::PCWSTR;
use windows::Win32::Foundation::{GetLastError, HWND, LPARAM, LRESULT, WPARAM};
use windows::Win32::System::LibraryLoader::GetModuleHandleW;
use windows::Win32::UI::WindowsAndMessaging::{
    CreateWindowExW, DefWindowProcW, DestroyWindow, DispatchMessageW, GetMessageW, LoadCursorW,
    PostMessageW, PostQuitMessage, RegisterClassW, SetWindowTextW, ShowWindow, TranslateMessage,
    CREATESTRUCTW, CS_HREDRAW, CS_VREDRAW, CW_USEDEFAULT, HMENU, IDC_ARROW, MSG, SW_SHOW, WM_APP,
    WM_CLOSE, WM_COMMAND, WM_CREATE, WM_DESTROY, WNDCLASSW, WS_CHILD, WS_OVERLAPPEDWINDOW,
    WS_VISIBLE,
};

const ID_BTN_START: usize = 1001;
const ID_BTN_STOP: usize = 1002;
const ID_BTN_FULLSCREEN: usize = 1003;
const ID_LBL_STATUS: usize = 2001;
const ID_LBL_STATS: usize = 2002;

const WM_UI_UPDATE: u32 = WM_APP + 1;

static UI_CLASS_REGISTERED: AtomicBool = AtomicBool::new(false);

#[derive(Debug, Default)]
struct UiModel {
    process_status: String,
    connection_status: String,
    stats_line: String,
    fullscreen: bool,
}

struct AppState {
    hwnd: HWND,
    status_hwnd: HWND,
    stats_hwnd: HWND,
    fullscreen_btn_hwnd: HWND,
    child: Option<Child>,
    model: Arc<Mutex<UiModel>>,
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
                    hinstance,
                    None,
                );

                let stats_hwnd = CreateWindowExW(
                    Default::default(),
                    w!("STATIC"),
                    w!("Stats: (none)"),
                    WS_CHILD | WS_VISIBLE,
                    20,
                    45,
                    470,
                    24,
                    hwnd,
                    HMENU(ID_LBL_STATS as isize),
                    hinstance,
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
                    hinstance,
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
                    hinstance,
                    None,
                );

                let fullscreen_btn_hwnd = CreateWindowExW(
                    Default::default(),
                    w!("BUTTON"),
                    w!("Fullscreen: Off"),
                    WS_CHILD | WS_VISIBLE,
                    300,
                    70,
                    190,
                    32,
                    hwnd,
                    HMENU(ID_BTN_FULLSCREEN as isize),
                    hinstance,
                    None,
                );

                let model = Arc::new(Mutex::new(UiModel {
                    process_status: "Stopped".to_string(),
                    connection_status: "Disconnected".to_string(),
                    stats_line: "(none)".to_string(),
                    fullscreen: false,
                }));

                let state = Box::new(AppState {
                    hwnd,
                    status_hwnd,
                    stats_hwnd,
                    fullscreen_btn_hwnd,
                    child: None,
                    model,
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
                            let fullscreen =
                                state.model.lock().map(|m| m.fullscreen).unwrap_or(false);
                            match spawn_receiver_child(hwnd, fullscreen, state.model.clone()) {
                                Ok(child) => {
                                    state.child = Some(child);
                                    if let Ok(mut m) = state.model.lock() {
                                        m.process_status = "Running".to_string();
                                    }
                                    update_labels(state);
                                }
                                Err(e) => {
                                    set_status(
                                        state.status_hwnd,
                                        &format!("Status: Start failed: {e}"),
                                    );
                                }
                            }
                        }
                    }
                    LRESULT(0)
                }
                ID_BTN_STOP => {
                    if let Some(state) = get_state(hwnd) {
                        stop_child(state);
                        if let Ok(mut m) = state.model.lock() {
                            m.process_status = "Stopped".to_string();
                            m.connection_status = "Disconnected".to_string();
                        }
                        update_labels(state);
                    }
                    LRESULT(0)
                }
                ID_BTN_FULLSCREEN => {
                    if let Some(state) = get_state(hwnd) {
                        // Toggle setting.
                        if let Ok(mut m) = state.model.lock() {
                            m.fullscreen = !m.fullscreen;
                        }
                        update_fullscreen_button(state);

                        // If running, restart to apply.
                        if state.child.is_some() {
                            stop_child(state);
                            if let Ok(mut m) = state.model.lock() {
                                m.process_status = "Restarting".to_string();
                                m.connection_status = "Disconnected".to_string();
                            }
                            update_labels(state);

                            let fullscreen =
                                state.model.lock().map(|m| m.fullscreen).unwrap_or(false);
                            match spawn_receiver_child(hwnd, fullscreen, state.model.clone()) {
                                Ok(child) => {
                                    state.child = Some(child);
                                    if let Ok(mut m) = state.model.lock() {
                                        m.process_status = "Running".to_string();
                                    }
                                    update_labels(state);
                                }
                                Err(e) => {
                                    if let Ok(mut m) = state.model.lock() {
                                        m.process_status = format!("Start failed: {e}");
                                    }
                                    update_labels(state);
                                }
                            }
                        }
                    }
                    LRESULT(0)
                }
                _ => DefWindowProcW(hwnd, msg, wparam, lparam),
            }
        }
        WM_UI_UPDATE => {
            if let Some(state) = get_state(hwnd) {
                update_labels(state);
            }
            LRESULT(0)
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

fn update_fullscreen_button(state: &AppState) {
    let fullscreen = state.model.lock().map(|m| m.fullscreen).unwrap_or(false);
    let label = if fullscreen {
        "Fullscreen: On"
    } else {
        "Fullscreen: Off"
    };
    set_status(state.fullscreen_btn_hwnd, label);
}

fn update_labels(state: &mut AppState) {
    // Avoid stale "already running" when the child exited on its own.
    if let Some(child) = state.child.as_mut() {
        if let Ok(Some(_status)) = child.try_wait() {
            state.child = None;
            if let Ok(mut m) = state.model.lock() {
                m.process_status = "Stopped".to_string();
                m.connection_status = "Disconnected".to_string();
            }
        }
    }

    let (proc_status, conn_status, stats_line) = state
        .model
        .lock()
        .map(|m| {
            (
                m.process_status.clone(),
                m.connection_status.clone(),
                m.stats_line.clone(),
            )
        })
        .unwrap_or_else(|_| ("?".to_string(), "?".to_string(), "(none)".to_string()));

    set_status(
        state.status_hwnd,
        &format!("Status: {proc_status} | Connection: {conn_status}"),
    );
    set_status(state.stats_hwnd, &format!("Stats: {stats_line}"));
}

fn spawn_receiver_child(
    hwnd: HWND,
    fullscreen: bool,
    model: Arc<Mutex<UiModel>>,
) -> anyhow::Result<Child> {
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

    let mut cmd = Command::new(receiver_exe);
    cmd.arg("--log-level").arg("info");
    if fullscreen {
        cmd.arg("--fullscreen");
    }

    let mut child = cmd.stdout(Stdio::piped()).stderr(Stdio::piped()).spawn()?;

    if let Some(stdout) = child.stdout.take() {
        let model = model.clone();
        std::thread::spawn(move || {
            let reader = BufReader::new(stdout);
            for line in reader.lines().flatten() {
                handle_child_log_line(hwnd, &model, &line);
            }
            if let Ok(mut m) = model.lock() {
                if m.process_status != "Stopped" {
                    m.process_status = "Stopped".to_string();
                    m.connection_status = "Disconnected".to_string();
                }
            }
            unsafe {
                let _ = PostMessageW(hwnd, WM_UI_UPDATE, WPARAM(0), LPARAM(0));
            }
        });
    }

    if let Some(stderr) = child.stderr.take() {
        let model = model.clone();
        std::thread::spawn(move || {
            let reader = BufReader::new(stderr);
            for line in reader.lines().flatten() {
                handle_child_log_line(hwnd, &model, &line);
            }
        });
    }

    Ok(child)
}

fn handle_child_log_line(hwnd: HWND, model: &Arc<Mutex<UiModel>>, line: &str) {
    let mut changed = false;
    if let Ok(mut m) = model.lock() {
        if line.contains("Connection accepted from") {
            m.connection_status = "Connected".to_string();
            changed = true;
        } else if line.contains("Connection closed") {
            m.connection_status = "Disconnected".to_string();
            changed = true;
        } else if let Some(rest) = line.split("Stats: ").nth(1) {
            m.stats_line = rest.trim().to_string();
            changed = true;
        } else if line.contains("QUIC server listening") {
            m.connection_status = "Listening".to_string();
            changed = true;
        } else if line.contains("QUIC server error") || line.contains("Connection error") {
            m.connection_status = "Error".to_string();
            changed = true;
        }
    }

    if changed {
        unsafe {
            let _ = PostMessageW(hwnd, WM_UI_UPDATE, WPARAM(0), LPARAM(0));
        }
    }
}

fn to_wide_null(s: &str) -> Vec<u16> {
    use std::os::windows::ffi::OsStrExt;
    std::ffi::OsStr::new(s)
        .encode_wide()
        .chain(Some(0))
        .collect()
}
