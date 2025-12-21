//! mDNS/Bonjour service advertisement for auto-discovery
//!
//! This module advertises the ThunderMirror receiver on the local network
//! using mDNS (Bonjour), allowing Mac senders to find us automatically
//! without requiring static IP configuration.

use std::time::Duration;
use tokio::sync::oneshot;
use tracing::{debug, error, info, warn};

/// Service type for ThunderMirror (follows Bonjour naming convention)
pub const SERVICE_TYPE: &str = "_thunder-mirror._udp.local.";

/// mDNS service advertiser
pub struct ServiceAdvertiser {
    shutdown_tx: Option<oneshot::Sender<()>>,
    service_name: String,
}

impl ServiceAdvertiser {
    /// Create a new service advertiser
    pub fn new() -> Self {
        // Use hostname as service name for easy identification
        let hostname = hostname::get()
            .map(|h| h.to_string_lossy().to_string())
            .unwrap_or_else(|_| "ThunderMirror-Receiver".to_string());
        
        Self {
            shutdown_tx: None,
            service_name: hostname,
        }
    }
    
    /// Start advertising the service on the given port
    pub async fn start(&mut self, port: u16) -> anyhow::Result<()> {
        use mdns_sd::{ServiceDaemon, ServiceInfo};
        
        let (shutdown_tx, mut shutdown_rx) = oneshot::channel();
        self.shutdown_tx = Some(shutdown_tx);
        
        let service_name = self.service_name.clone();
        
        // Get all local IP addresses (including link-local 169.254.x.x)
        let addresses = get_local_addresses();
        if addresses.is_empty() {
            warn!("No local IP addresses found for mDNS advertisement");
        }
        
        info!("Starting mDNS advertisement:");
        info!("  Service: {}", SERVICE_TYPE);
        info!("  Name: {}", service_name);
        info!("  Port: {}", port);
        for addr in &addresses {
            info!("  Address: {}", addr);
        }
        
        // Spawn the mDNS daemon in a background task
        tokio::task::spawn_blocking(move || {
            let mdns = match ServiceDaemon::new() {
                Ok(m) => m,
                Err(e) => {
                    error!("Failed to create mDNS daemon: {}", e);
                    return;
                }
            };
            
            // Create service info with all our addresses
            let service_info = match ServiceInfo::new(
                SERVICE_TYPE,
                &service_name,
                &format!("{}.local.", service_name),
                &addresses.iter().map(|s| s.as_str()).collect::<Vec<_>>()[..],
                port,
                None, // No TXT properties needed
            ) {
                Ok(info) => info,
                Err(e) => {
                    error!("Failed to create service info: {}", e);
                    return;
                }
            };
            
            // Register the service
            if let Err(e) = mdns.register(service_info) {
                error!("Failed to register mDNS service: {}", e);
                return;
            }
            
            info!("mDNS service registered successfully");
            
            // Keep running until shutdown signal
            loop {
                match shutdown_rx.try_recv() {
                    Ok(_) | Err(oneshot::error::TryRecvError::Closed) => {
                        debug!("mDNS advertiser shutting down");
                        break;
                    }
                    Err(oneshot::error::TryRecvError::Empty) => {
                        std::thread::sleep(Duration::from_millis(100));
                    }
                }
            }
            
            // Unregister on shutdown (daemon handles cleanup on drop)
            info!("mDNS service unregistered");
        });
        
        Ok(())
    }
    
    /// Stop advertising
    pub fn stop(&mut self) {
        if let Some(tx) = self.shutdown_tx.take() {
            let _ = tx.send(());
        }
    }
}

impl Drop for ServiceAdvertiser {
    fn drop(&mut self) {
        self.stop();
    }
}

/// Get all local IP addresses including link-local (169.254.x.x)
fn get_local_addresses() -> Vec<String> {
    let mut addresses = Vec::new();
    
    match if_addrs::get_if_addrs() {
        Ok(ifaces) => {
            for iface in ifaces {
                // Skip loopback
                if iface.is_loopback() {
                    continue;
                }
                
                match iface.addr {
                    if_addrs::IfAddr::V4(ref addr) => {
                        let ip = addr.ip;
                        
                        // Include all non-loopback IPv4 addresses:
                        // - Regular private IPs (192.168.x.x, 10.x.x.x, 172.16-31.x.x)
                        // - Link-local IPs (169.254.x.x) - these are what Thunderbolt uses!
                        if !ip.is_loopback() {
                            debug!("Found interface {} with IP {}", iface.name, ip);
                            addresses.push(ip.to_string());
                        }
                    }
                    if_addrs::IfAddr::V6(_) => {
                        // Skip IPv6 for now - Thunderbolt bridge typically uses IPv4
                    }
                }
            }
        }
        Err(e) => {
            warn!("Failed to get network interfaces: {}", e);
        }
    }
    
    addresses
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_get_local_addresses() {
        let addrs = get_local_addresses();
        // Should find at least one non-loopback address on most systems
        println!("Found addresses: {:?}", addrs);
    }
}

