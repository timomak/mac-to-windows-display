#[cfg(windows)]
mod win32_shell;

/// Runs the Windows UI shell for the receiver.
///
/// On Windows, this shows a small native Win32 window with Start/Stop buttons and
/// launches/stops the existing `thunder_receiver` CLI as a child process.
#[cfg(windows)]
pub fn run() -> anyhow::Result<()> {
    win32_shell::run()
}

/// Non-Windows stub so `cargo build` on macOS/Linux still works.
#[cfg(not(windows))]
pub fn run() -> anyhow::Result<()> {
    eprintln!("thunder_receiver_ui is only supported on Windows.");
    Ok(())
}


