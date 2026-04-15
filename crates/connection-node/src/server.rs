use std::net::SocketAddr;

use anyhow::{Context, Result};
use axum::{routing::get, Router};
use tokio::net::TcpListener;
use tower_http::trace::TraceLayer;
use tracing::info;

use crate::config::AppConfig;

pub async fn run(config: &AppConfig) -> Result<()> {
    let (listener, actual_addr) = bind_listener(&config.server.listen_addr).await?;
    let app = Router::new()
        .route("/", get(|| async { "connection-node" }))
        .layer(TraceLayer::new_for_http());

    info!("listening on {}", actual_addr);
    axum::serve(listener, app).await?;
    Ok(())
}

async fn bind_listener(listen_addr: &str) -> Result<(TcpListener, SocketAddr)> {
    let listener = TcpListener::bind(listen_addr)
        .await
        .with_context(|| format!("failed to bind server listener at {listen_addr}"))?;
    let actual_addr = listener.local_addr()?;
    Ok((listener, actual_addr))
}
