//! QUIC transport layer for ThunderMirror
//!
//! This module provides QUIC server and client functionality using quinn.

use std::net::SocketAddr;
use std::sync::Arc;

use quinn::{Endpoint, ServerConfig};
use rustls::{Certificate, PrivateKey, ServerConfig as RustlsServerConfig};

use crate::error::{Error, Result};

/// QUIC server for receiving connections
pub struct QuicServer {
    endpoint: Endpoint,
    addr: SocketAddr,
}

impl QuicServer {
    /// Create a new QUIC server bound to the given address
    ///
    /// # Arguments
    /// * `addr` - Socket address to bind to (e.g., "0.0.0.0:9999")
    ///
    /// # Returns
    /// A `QuicServer` instance ready to accept connections
    pub async fn new(addr: SocketAddr) -> Result<Self> {
        let server_config = Self::create_server_config()?;
        let endpoint = Endpoint::server(server_config, addr)?;

        Ok(Self {
            addr: endpoint.local_addr()?,
            endpoint,
        })
    }

    /// Get the address the server is bound to
    pub fn local_addr(&self) -> SocketAddr {
        self.addr
    }

    /// Accept the next incoming connection
    ///
    /// # Returns
    /// A `quinn::Connection` when a client connects
    pub async fn accept(&self) -> Result<quinn::Connection> {
        let incoming = self.endpoint.accept().await;
        let conn = incoming
            .ok_or_else(|| Error::transport("server endpoint closed"))?
            .await
            .map_err(|e| Error::transport(format!("connection failed: {}", e)))?;

        Ok(conn)
    }

    /// Create a server configuration with self-signed certificate
    ///
    /// For development/testing purposes, generates a self-signed certificate.
    /// In production, this should use proper certificates.
    fn create_server_config() -> Result<ServerConfig> {
        // Generate a self-signed certificate for testing
        let cert = rcgen::generate_simple_self_signed(vec!["localhost".into()])
            .map_err(|e| Error::transport(format!("certificate generation failed: {}", e)))?;

        let cert_der = cert
            .serialize_der()
            .map_err(|e| Error::transport(format!("certificate serialization failed: {}", e)))?;

        let key_der = cert.serialize_private_key_der();

        let cert = Certificate(cert_der);
        let key = PrivateKey(key_der);

        let mut rustls_config = RustlsServerConfig::builder()
            .with_safe_defaults()
            .with_no_client_auth()
            .with_single_cert(vec![cert], key)
            .map_err(|e| Error::transport(format!("TLS config failed: {}", e)))?;

        // Configure for low latency
        rustls_config.max_early_data_size = u32::MAX;
        rustls_config.alpn_protocols = vec![b"thunder-mirror".to_vec()];

        let mut server_config = ServerConfig::with_crypto(Arc::new(rustls_config));
        server_config.transport = Arc::new(quinn::TransportConfig::default());

        Ok(server_config)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;
    use tokio::time::timeout;

    #[tokio::test]
    async fn test_quic_server_accepts_connections() {
        // Bind to a random available port
        let addr: SocketAddr = "127.0.0.1:0".parse().unwrap();
        let server = QuicServer::new(addr).await.unwrap();
        let server_addr = server.local_addr();

        // Spawn a task to accept a connection
        let server_handle = tokio::spawn(async move {
            let conn = server.accept().await.unwrap();
            // Connection accepted successfully
            let remote_addr = conn.remote_address();
            assert_eq!(remote_addr.ip().to_string(), "127.0.0.1");
        });

        // Create a client and connect to the server
        let client_config = create_client_config();
        let client_endpoint = Endpoint::client("127.0.0.1:0".parse().unwrap()).unwrap();
        let client_conn = client_endpoint
            .connect_with(client_config, server_addr, "localhost")
            .unwrap()
            .await
            .unwrap();

        // Wait for server to accept the connection (with timeout)
        timeout(Duration::from_secs(5), server_handle)
            .await
            .expect("connection should be accepted within 5 seconds")
            .expect("server task should complete successfully");

        // Verify client connection is established
        assert_eq!(client_conn.remote_address(), server_addr);
        drop(client_endpoint);
    }

    fn create_client_config() -> quinn::ClientConfig {
        let roots = rustls::RootCertStore::empty();
        // For testing, we'll use a custom verifier that accepts any cert
        let mut client_config = rustls::ClientConfig::builder()
            .with_safe_defaults()
            .with_root_certificates(roots)
            .with_no_client_auth();

        // Disable certificate verification for testing
        client_config
            .dangerous()
            .set_certificate_verifier(Arc::new(NoVerifier));

        client_config.alpn_protocols = vec![b"thunder-mirror".to_vec()];

        quinn::ClientConfig::new(Arc::new(client_config))
    }

    struct NoVerifier;

    impl rustls::client::ServerCertVerifier for NoVerifier {
        fn verify_server_cert(
            &self,
            _end_entity: &rustls::Certificate,
            _intermediates: &[rustls::Certificate],
            _server_name: &rustls::ServerName,
            _scts: &mut dyn Iterator<Item = &[u8]>,
            _ocsp_response: &[u8],
            _now: std::time::SystemTime,
        ) -> std::result::Result<rustls::client::ServerCertVerified, rustls::Error> {
            Ok(rustls::client::ServerCertVerified::assertion())
        }
    }
}
