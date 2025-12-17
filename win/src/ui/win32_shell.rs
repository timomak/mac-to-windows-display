#![cfg(windows)]

use std::io::{BufRead, BufReader};
use std::os::windows::process::CommandExt;
use std::process::Stdio;
use std::process::{Child, Command};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

use windows::core::w;
use windows::Win32::Foundation::{GetLastError, HWND, LPARAM, LRESULT, RECT, WPARAM, COLORREF};
use windows::Win32::Graphics::Gdi::{
    BeginPaint, CreateFontW, CreatePen, CreateSolidBrush, DeleteObject, EndPaint, FillRect,
    GetDeviceCaps, GetStockObject, InvalidateRect, LineTo, MoveToEx, RoundRect, SelectObject, 
    SetBkMode, SetTextColor, TextOutW, HBRUSH, HGDIOBJ, LOGPIXELSY, PAINTSTRUCT, PS_SOLID, 
    TRANSPARENT, DrawTextW, DT_CENTER, DT_VCENTER, DT_SINGLELINE,
};
use windows::Win32::System::LibraryLoader::GetModuleHandleW;
use windows::Win32::UI::WindowsAndMessaging::{
    CreateWindowExW, DefWindowProcW, DestroyWindow, DispatchMessageW, GetClientRect, GetMessageW,
    LoadCursorW, PostMessageW, PostQuitMessage, RegisterClassW, ShowWindow,
    TranslateMessage, CS_HREDRAW, CS_VREDRAW, CW_USEDEFAULT, IDC_ARROW,
    MSG, SW_SHOW, WM_APP, WM_CLOSE, WM_CREATE, WM_DESTROY, WM_ERASEBKGND, WM_PAINT,
    WM_LBUTTONDOWN, WM_LBUTTONUP, WNDCLASSW, WINDOW_EX_STYLE, WS_OVERLAPPEDWINDOW,
};

// Flag to hide console window when spawning child process
const CREATE_NO_WINDOW: u32 = 0x08000000;

const ID_BTN_START: usize = 1001;
const ID_BTN_STOP: usize = 1002;
const ID_BTN_FULLSCREEN: usize = 1003;

const WM_UI_UPDATE: u32 = WM_APP + 1;

static UI_CLASS_REGISTERED: AtomicBool = AtomicBool::new(false);

// Colors matching Swift app's dark theme
const COLOR_BG_DARK: u32 = 0x0D1117;      // Main background
const COLOR_BG_MEDIUM: u32 = 0x161B22;    // Card background
const COLOR_ACCENT_BLUE: u32 = 0x58A6FF;  // Accent blue
const COLOR_ACCENT_DARK_BLUE: u32 = 0x1F6FEB;
const COLOR_GREEN: u32 = 0x3FB950;        // Start button
const COLOR_GREEN_DARK: u32 = 0x238636;
const COLOR_RED: u32 = 0xF85149;          // Stop button
const COLOR_RED_DARK: u32 = 0xDA3633;
const COLOR_TEXT_PRIMARY: u32 = 0xFFFFFF; // White text
const COLOR_TEXT_SECONDARY: u32 = 0x8B949E; // Muted text
const COLOR_BORDER: u32 = 0x30363D;       // Card borders

// Convert RGB to Windows COLORREF (BGR format)
fn rgb_to_colorref(rgb: u32) -> COLORREF {
    let r = ((rgb >> 16) & 0xFF) as u8;
    let g = ((rgb >> 8) & 0xFF) as u8;
    let b = (rgb & 0xFF) as u8;
    COLORREF((b as u32) << 16 | (g as u32) << 8 | r as u32)
}

#[derive(Debug, Default)]
struct UiModel {
    process_status: String,
    connection_status: String,
    stats_line: String,
    fullscreen: bool,
}

struct ButtonRect {
    rect: RECT,
    id: usize,
    hover: bool,
    pressed: bool,
}

struct AppState {
    hwnd: HWND,
    child: Option<Child>,
    model: Arc<Mutex<UiModel>>,
    buttons: Vec<ButtonRect>,
    font_title: HGDIOBJ,
    font_normal: HGDIOBJ,
    font_mono: HGDIOBJ,
}

impl AppState {
    fn new(hwnd: HWND) -> Self {
        unsafe {
            // Get DPI for proper font scaling
            let hdc = windows::Win32::Graphics::Gdi::GetDC(hwnd);
            let dpi = GetDeviceCaps(hdc, LOGPIXELSY);
            let _ = windows::Win32::Graphics::Gdi::ReleaseDC(hwnd, hdc);
            
            // Scale fonts based on DPI (96 is standard DPI)
            let scale = dpi as f32 / 96.0;
            let title_size = (24.0 * scale) as i32;
            let normal_size = (16.0 * scale) as i32;
            let mono_size = (14.0 * scale) as i32;
            
            // Create fonts with proper sizing and quality
            // Using CLEARTYPE_QUALITY (5) for better rendering
            let font_title = CreateFontW(
                title_size, 0, 0, 0, 600, 0, 0, 0, 0, 0, 0, 5, 0,
                w!("Segoe UI"),
            );
            let font_normal = CreateFontW(
                normal_size, 0, 0, 0, 400, 0, 0, 0, 0, 0, 0, 5, 0,
                w!("Segoe UI"),
            );
            let font_mono = CreateFontW(
                mono_size, 0, 0, 0, 400, 0, 0, 0, 0, 0, 0, 5, 0,
                w!("Consolas"),
            );

            Self {
                hwnd,
                child: None,
                model: Arc::new(Mutex::new(UiModel {
                    process_status: "Stopped".to_string(),
                    connection_status: "Disconnected".to_string(),
                    stats_line: "—".to_string(),
                    fullscreen: false,
                })),
                buttons: vec![
                    ButtonRect {
                        rect: RECT { left: 24, top: 340, right: 180, bottom: 385 },
                        id: ID_BTN_START,
                        hover: false,
                        pressed: false,
                    },
                    ButtonRect {
                        rect: RECT { left: 192, top: 340, right: 348, bottom: 385 },
                        id: ID_BTN_STOP,
                        hover: false,
                        pressed: false,
                    },
                    ButtonRect {
                        rect: RECT { left: 24, top: 395, right: 348, bottom: 440 },
                        id: ID_BTN_FULLSCREEN,
                        hover: false,
                        pressed: false,
                    },
                ],
                font_title: HGDIOBJ(font_title.0),
                font_normal: HGDIOBJ(font_normal.0),
                font_mono: HGDIOBJ(font_mono.0),
            }
        }
    }
}

pub fn run() -> anyhow::Result<()> {
    unsafe {
        // Enable DPI awareness for crisp rendering on high-DPI displays
        let _ = windows::Win32::UI::HiDpi::SetProcessDpiAwarenessContext(
            windows::Win32::UI::HiDpi::DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2,
        );
        
        let hinstance = GetModuleHandleW(None)?;

        if !UI_CLASS_REGISTERED.swap(true, Ordering::SeqCst) {
            let class_name = w!("ThunderMirrorUI");
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
            WINDOW_EX_STYLE::default(),
            w!("ThunderMirrorUI"),
            w!("ThunderMirror"),
            WS_OVERLAPPEDWINDOW & !WS_MAXIMIZEBOX,
            CW_USEDEFAULT,
            CW_USEDEFAULT,
            390,
            500,
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

        let _ = ShowWindow(hwnd, SW_SHOW);

        let mut msg = MSG::default();
        while GetMessageW(&mut msg, None, 0, 0).into() {
            let _ = TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
    }

    Ok(())
}

const WS_MAXIMIZEBOX: windows::Win32::UI::WindowsAndMessaging::WINDOW_STYLE = 
    windows::Win32::UI::WindowsAndMessaging::WINDOW_STYLE(0x00010000);

unsafe extern "system" fn wndproc(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    match msg {
        WM_CREATE => {
            let state = Box::new(AppState::new(hwnd));
            windows::Win32::UI::WindowsAndMessaging::SetWindowLongPtrW(
                hwnd,
                windows::Win32::UI::WindowsAndMessaging::GWLP_USERDATA,
                Box::into_raw(state) as isize,
            );
            LRESULT(0)
        }
        WM_ERASEBKGND => {
            // We handle our own background
            LRESULT(1)
        }
        WM_PAINT => {
            paint_window(hwnd);
            LRESULT(0)
        }
        WM_LBUTTONDOWN => {
            let x = (lparam.0 & 0xFFFF) as i32;
            let y = ((lparam.0 >> 16) & 0xFFFF) as i32;
            
            if let Some(state) = get_state(hwnd) {
                for btn in &mut state.buttons {
                    if point_in_rect(x, y, &btn.rect) {
                        btn.pressed = true;
                    }
                }
                let _ = InvalidateRect(hwnd, None, false);
            }
            LRESULT(0)
        }
        WM_LBUTTONUP => {
            let x = (lparam.0 & 0xFFFF) as i32;
            let y = ((lparam.0 >> 16) & 0xFFFF) as i32;
            
            if let Some(state) = get_state(hwnd) {
                let mut clicked_id = None;
                for btn in &mut state.buttons {
                    if btn.pressed && point_in_rect(x, y, &btn.rect) {
                        clicked_id = Some(btn.id);
                    }
                    btn.pressed = false;
                }
                
                let _ = InvalidateRect(hwnd, None, false);
                
                if let Some(id) = clicked_id {
                    handle_button_click(hwnd, state, id);
                }
            }
            LRESULT(0)
        }
        WM_UI_UPDATE => {
            let _ = InvalidateRect(hwnd, None, false);
            LRESULT(0)
        }
        WM_CLOSE => {
            let _ = DestroyWindow(hwnd);
            LRESULT(0)
        }
        WM_DESTROY => {
            if let Some(state) = get_state(hwnd) {
                stop_child(state);
            }

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

fn point_in_rect(x: i32, y: i32, rect: &RECT) -> bool {
    x >= rect.left && x < rect.right && y >= rect.top && y < rect.bottom
}

unsafe fn handle_button_click(hwnd: HWND, state: &mut AppState, button_id: usize) {
    match button_id {
        ID_BTN_START => {
            if state.child.is_some() {
                return;
            }
            let fullscreen = state.model.lock().map(|m| m.fullscreen).unwrap_or(false);
            match spawn_receiver_child(hwnd, fullscreen, state.model.clone()) {
                Ok(child) => {
                    state.child = Some(child);
                    if let Ok(mut m) = state.model.lock() {
                        m.process_status = "Running".to_string();
                    }
                }
                Err(e) => {
                    if let Ok(mut m) = state.model.lock() {
                        m.process_status = format!("Error: {}", e);
                    }
                }
            }
            let _ = InvalidateRect(hwnd, None, false);
        }
        ID_BTN_STOP => {
            stop_child(state);
            if let Ok(mut m) = state.model.lock() {
                m.process_status = "Stopped".to_string();
                m.connection_status = "Disconnected".to_string();
            }
            let _ = InvalidateRect(hwnd, None, false);
        }
        ID_BTN_FULLSCREEN => {
            if let Ok(mut m) = state.model.lock() {
                m.fullscreen = !m.fullscreen;
            }
            
            // Restart if running
            if state.child.is_some() {
                stop_child(state);
                if let Ok(mut m) = state.model.lock() {
                    m.process_status = "Restarting...".to_string();
                    m.connection_status = "Disconnected".to_string();
                }
                let _ = InvalidateRect(hwnd, None, false);

                let fullscreen = state.model.lock().map(|m| m.fullscreen).unwrap_or(false);
                match spawn_receiver_child(hwnd, fullscreen, state.model.clone()) {
                    Ok(child) => {
                        state.child = Some(child);
                        if let Ok(mut m) = state.model.lock() {
                            m.process_status = "Running".to_string();
                        }
                    }
                    Err(e) => {
                        if let Ok(mut m) = state.model.lock() {
                            m.process_status = format!("Error: {}", e);
                        }
                    }
                }
            }
            let _ = InvalidateRect(hwnd, None, false);
        }
        _ => {}
    }
}

unsafe fn paint_window(hwnd: HWND) {
    let mut ps = PAINTSTRUCT::default();
    let hdc = BeginPaint(hwnd, &mut ps);
    
    let mut client_rect = RECT::default();
    let _ = GetClientRect(hwnd, &mut client_rect);
    
    // Fill background with dark gradient color
    let bg_brush = CreateSolidBrush(rgb_to_colorref(COLOR_BG_DARK));
    FillRect(hdc, &client_rect, bg_brush);
    let _ = DeleteObject(bg_brush);
    
    let state = match get_state(hwnd) {
        Some(s) => s,
        None => {
            let _ = EndPaint(hwnd, &ps);
            return;
        }
    };
    
    let _ = SetBkMode(hdc, TRANSPARENT);
    
    // Draw header
    let old_font = SelectObject(hdc, state.font_title);
    SetTextColor(hdc, rgb_to_colorref(COLOR_TEXT_PRIMARY));
    draw_text_utf16(hdc, "⚡ ThunderMirror", 24, 24);
    
    SelectObject(hdc, state.font_mono);
    SetTextColor(hdc, rgb_to_colorref(COLOR_TEXT_SECONDARY));
    draw_text_utf16(hdc, "v0.3.0", 24, 52);
    
    // Draw status badge
    let (status_text, status_color) = {
        let model = state.model.lock().unwrap();
        let color = match model.connection_status.as_str() {
            "Connected" => COLOR_GREEN,
            "Listening" => COLOR_ACCENT_BLUE,
            "Error" => COLOR_RED,
            _ => COLOR_TEXT_SECONDARY,
        };
        (model.connection_status.clone(), color)
    };
    
    // Status badge background
    let badge_rect = RECT { left: 260, top: 24, right: 355, bottom: 45 };
    let badge_brush = CreateSolidBrush(rgb_to_colorref(0x21262D));
    fill_rounded_rect(hdc, &badge_rect, badge_brush, 10);
    let _ = DeleteObject(badge_brush);
    
    // Status dot
    let dot_brush = CreateSolidBrush(rgb_to_colorref(status_color));
    let dot_rect = RECT { left: 270, top: 31, right: 278, bottom: 39 };
    fill_rounded_rect(hdc, &dot_rect, dot_brush, 4);
    let _ = DeleteObject(dot_brush);
    
    SetTextColor(hdc, rgb_to_colorref(COLOR_TEXT_SECONDARY));
    draw_text_utf16(hdc, &status_text, 284, 29);
    
    // Draw separator line
    let pen = CreatePen(PS_SOLID, 1, rgb_to_colorref(COLOR_BORDER));
    let old_pen = SelectObject(hdc, pen);
    MoveToEx(hdc, 24, 75, None);
    LineTo(hdc, client_rect.right - 24, 75);
    SelectObject(hdc, old_pen);
    let _ = DeleteObject(pen);
    
    // Connection Card
    draw_card(hdc, state, "CONNECTION", 24, 90, 342, 80);
    SelectObject(hdc, state.font_normal);
    SetTextColor(hdc, rgb_to_colorref(COLOR_TEXT_SECONDARY));
    draw_text_utf16(hdc, "Listening on", 40, 125);
    SetTextColor(hdc, rgb_to_colorref(COLOR_TEXT_PRIMARY));
    SelectObject(hdc, state.font_mono);
    draw_text_utf16(hdc, "0.0.0.0:9999", 150, 125);
    
    // Status Card
    draw_card(hdc, state, "STATUS", 24, 180, 342, 80);
    SelectObject(hdc, state.font_normal);
    SetTextColor(hdc, rgb_to_colorref(COLOR_TEXT_SECONDARY));
    draw_text_utf16(hdc, "Process", 40, 215);
    let process_status = state.model.lock().map(|m| m.process_status.clone()).unwrap_or_default();
    let process_color = if process_status == "Running" { COLOR_GREEN } else { COLOR_TEXT_PRIMARY };
    SetTextColor(hdc, rgb_to_colorref(process_color));
    draw_text_utf16(hdc, &process_status, 150, 215);
    
    // Stats Card
    draw_card(hdc, state, "STATISTICS", 24, 270, 342, 55);
    SelectObject(hdc, state.font_mono);
    SetTextColor(hdc, rgb_to_colorref(COLOR_TEXT_SECONDARY));
    let stats = state.model.lock().map(|m| m.stats_line.clone()).unwrap_or_else(|_| "—".to_string());
    draw_text_utf16(hdc, &stats, 40, 300);
    
    // Draw buttons
    let is_running = state.child.is_some();
    let is_fullscreen = state.model.lock().map(|m| m.fullscreen).unwrap_or(false);
    
    // Start button
    draw_button(
        hdc, 
        &state.buttons[0].rect, 
        "▶  Start", 
        if is_running { COLOR_BORDER } else { COLOR_GREEN },
        if is_running { COLOR_BORDER } else { COLOR_GREEN_DARK },
        state.buttons[0].pressed,
        state.font_normal,
    );
    
    // Stop button
    draw_button(
        hdc, 
        &state.buttons[1].rect, 
        "■  Stop", 
        if !is_running { COLOR_BORDER } else { COLOR_RED },
        if !is_running { COLOR_BORDER } else { COLOR_RED_DARK },
        state.buttons[1].pressed,
        state.font_normal,
    );
    
    // Fullscreen toggle
    let fs_text = if is_fullscreen { "Fullscreen: ON" } else { "Fullscreen: OFF" };
    let fs_color = if is_fullscreen { COLOR_ACCENT_BLUE } else { COLOR_BORDER };
    draw_button(
        hdc,
        &state.buttons[2].rect,
        fs_text,
        fs_color,
        if is_fullscreen { COLOR_ACCENT_DARK_BLUE } else { 0x21262D },
        state.buttons[2].pressed,
        state.font_normal,
    );
    
    SelectObject(hdc, old_font);
    let _ = EndPaint(hwnd, &ps);
}

unsafe fn draw_card(hdc: windows::Win32::Graphics::Gdi::HDC, state: &AppState, title: &str, x: i32, y: i32, w: i32, h: i32) {
    let rect = RECT { left: x, top: y, right: x + w, bottom: y + h };
    
    // Card background
    let bg_brush = CreateSolidBrush(rgb_to_colorref(COLOR_BG_MEDIUM));
    fill_rounded_rect(hdc, &rect, bg_brush, 12);
    let _ = DeleteObject(bg_brush);
    
    // Card border
    let border_pen = CreatePen(PS_SOLID, 1, rgb_to_colorref(COLOR_BORDER));
    let old_pen = SelectObject(hdc, border_pen);
    let null_brush = GetStockObject(windows::Win32::Graphics::Gdi::NULL_BRUSH);
    let old_brush = SelectObject(hdc, null_brush);
    RoundRect(hdc, rect.left, rect.top, rect.right, rect.bottom, 12, 12);
    SelectObject(hdc, old_brush);
    SelectObject(hdc, old_pen);
    let _ = DeleteObject(border_pen);
    
    // Card title
    SelectObject(hdc, state.font_mono);
    SetTextColor(hdc, rgb_to_colorref(COLOR_TEXT_SECONDARY));
    draw_text_utf16(hdc, title, x + 16, y + 10);
}

unsafe fn draw_button(
    hdc: windows::Win32::Graphics::Gdi::HDC,
    rect: &RECT,
    text: &str,
    color: u32,
    _color_dark: u32,
    pressed: bool,
    font: HGDIOBJ,
) {
    let adj_rect = if pressed {
        RECT {
            left: rect.left + 1,
            top: rect.top + 1,
            right: rect.right + 1,
            bottom: rect.bottom + 1,
        }
    } else {
        *rect
    };
    
    // Button background
    let bg_brush = CreateSolidBrush(rgb_to_colorref(color));
    fill_rounded_rect(hdc, &adj_rect, bg_brush, 10);
    let _ = DeleteObject(bg_brush);
    
    // Button text
    SelectObject(hdc, font);
    SetTextColor(hdc, rgb_to_colorref(COLOR_TEXT_PRIMARY));
    
    let mut text_rect = adj_rect;
    let wide: Vec<u16> = text.encode_utf16().chain(std::iter::once(0)).collect();
    DrawTextW(hdc, &mut wide[..wide.len()-1].to_vec(), &mut text_rect, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
}

unsafe fn fill_rounded_rect(hdc: windows::Win32::Graphics::Gdi::HDC, rect: &RECT, brush: HBRUSH, radius: i32) {
    let old_brush = SelectObject(hdc, brush);
    let null_pen = CreatePen(PS_SOLID, 0, rgb_to_colorref(0));
    let old_pen = SelectObject(hdc, null_pen);
    RoundRect(hdc, rect.left, rect.top, rect.right, rect.bottom, radius, radius);
    SelectObject(hdc, old_pen);
    SelectObject(hdc, old_brush);
    let _ = DeleteObject(null_pen);
}

unsafe fn draw_text_utf16(hdc: windows::Win32::Graphics::Gdi::HDC, text: &str, x: i32, y: i32) {
    let wide: Vec<u16> = text.encode_utf16().collect();
    TextOutW(hdc, x, y, &wide);
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

fn spawn_receiver_child(
    hwnd: HWND,
    fullscreen: bool,
    model: Arc<Mutex<UiModel>>,
) -> anyhow::Result<Child> {
    let ui_exe = std::env::current_exe()?;
    let dir = ui_exe
        .parent()
        .ok_or_else(|| anyhow::anyhow!("Failed to determine UI exe directory"))?;

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
    
    // Use CREATE_NO_WINDOW to prevent a console window from appearing
    cmd.creation_flags(CREATE_NO_WINDOW);

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
