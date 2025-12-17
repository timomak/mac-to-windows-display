# Run Thunder Receiver UI
$env:Path = "$env:USERPROFILE\.cargo\bin;$env:Path"

Set-Location -Path $PSScriptRoot
cargo run --bin thunder_receiver_ui

