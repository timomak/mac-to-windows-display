//! Build script for ThunderReceiver Windows app
//!
//! This embeds the application icon and metadata into the Windows executable.

fn main() {
    // Only run on Windows
    #[cfg(windows)]
    {
        let mut res = winres::WindowsResource::new();

        // Set application metadata
        res.set("ProductName", "ThunderReceiver");
        res.set("FileDescription", "ThunderMirror Windows Receiver - Display streamed content from Mac");
        res.set("LegalCopyright", "Copyright © 2024 ThunderMirror. MIT License.");
        res.set("CompanyName", "ThunderMirror");
        res.set("OriginalFilename", "ThunderReceiver.exe");

        // Set version info (major, minor, patch, build)
        res.set_version_info(winres::VersionInfo::PRODUCTVERSION, 0x0001_0000_0000_0000);
        res.set_version_info(winres::VersionInfo::FILEVERSION, 0x0001_0000_0000_0000);

        // Set icon if it exists
        let icon_path = "resources/app.ico";
        if std::path::Path::new(icon_path).exists() {
            res.set_icon(icon_path);
            println!("cargo:warning=Using app icon: {}", icon_path);
        } else {
            println!("cargo:warning=No app icon found at {}. Using default Windows icon.", icon_path);
        }

        // Compile resources
        if let Err(e) = res.compile() {
            println!("cargo:warning=Failed to compile Windows resources: {}", e);
        }
    }

    // Tell cargo to rerun if these files change
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-changed=resources/app.ico");
}

