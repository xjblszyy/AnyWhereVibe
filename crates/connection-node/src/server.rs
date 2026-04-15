use std::io::ErrorKind;
use std::net::SocketAddr;

use anyhow::{Context, Result};
use axum::{routing::get, Router};
use tokio::net::TcpListener;
use tower_http::cors::CorsLayer;
use tower_http::trace::TraceLayer;
use tracing::{info, warn};

use crate::config::AppConfig;

pub async fn run(config: &AppConfig) -> Result<()> {
    let (listener, actual_addr) = bind_listener(&config.server.listen_addr).await?;
    let app = Router::new()
        .route("/", get(|| async { "connection-node" }))
        .layer(CorsLayer::permissive())
        .layer(TraceLayer::new_for_http());

    info!("listening on {}", actual_addr);
    axum::serve(listener, app).await?;
    Ok(())
}

async fn bind_listener(listen_addr: &str) -> Result<(TcpListener, SocketAddr)> {
    match TcpListener::bind(listen_addr).await {
        Ok(listener) => {
            let actual_addr = listener.local_addr()?;
            Ok((listener, actual_addr))
        }
        Err(error) if error.kind() == ErrorKind::PermissionDenied => {
            let fallback = fallback_addr(listen_addr)?;
            warn!(
                requested = listen_addr,
                fallback = %fallback,
                "permission denied binding requested address, falling back for local development"
            );
            let listener = TcpListener::bind(fallback).await?;
            let actual_addr = listener.local_addr()?;
            Ok((listener, actual_addr))
        }
        Err(error) => {
            Err(error).with_context(|| format!("failed to bind server listener at {listen_addr}"))
        }
    }
}

fn fallback_addr(listen_addr: &str) -> Result<SocketAddr> {
    let parsed: SocketAddr = listen_addr
        .parse()
        .with_context(|| format!("invalid listen address '{listen_addr}'"))?;
    Ok(SocketAddr::new(parsed.ip(), 8443))
}
