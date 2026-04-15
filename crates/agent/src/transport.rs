use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{bail, Context, Result};
use futures_util::{SinkExt, StreamExt};
use proto_gen::envelope::Payload;
use proto_gen::{DeviceRegister, DeviceType, Envelope};
use tokio::net::TcpStream;
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::{connect_async, MaybeTlsStream, WebSocketStream};
use uuid::Uuid;

use crate::config::Config;
use crate::wire::{decode_ws_binary_message, encode_ws_binary_message};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Transport {
    Local { listen_addr: String },
    Remote {
        node_url: String,
        device_id: String,
        display_name: String,
        auth_token: String,
    },
}

impl Transport {
    pub fn from_config(config: &Config) -> Result<Self> {
        if let Some(connection_node) = &config.connection_node {
            return Ok(Self::Remote {
                node_url: connection_node.url.clone(),
                device_id: connection_node.device_id.clone(),
                display_name: connection_node.display_name.clone(),
                auth_token: connection_node.auth_token.clone(),
            });
        }

        Ok(Self::Local {
            listen_addr: config.server.listen_addr.clone(),
        })
    }

    pub fn listen_addr(&self) -> Result<&str> {
        match self {
            Self::Local { listen_addr } => Ok(listen_addr),
            Self::Remote { .. } => bail!("connection node transport is not yet supported"),
        }
    }

    pub fn server_bind_addr(&self) -> &str {
        match self {
            Self::Local { listen_addr } => listen_addr,
            Self::Remote { .. } => "127.0.0.1:0",
        }
    }
}

pub type RemoteSocket = WebSocketStream<MaybeTlsStream<TcpStream>>;

pub async fn connect_and_register_remote(
    node_url: &str,
    device_id: &str,
    display_name: &str,
    auth_token: &str,
) -> Result<RemoteSocket> {
    let (mut socket, _) = connect_async(node_url)
        .await
        .with_context(|| format!("failed to connect to connection node at {node_url}"))?;

    let request_id = Uuid::new_v4().to_string();
    socket
        .send(Message::Binary(
            encode_ws_binary_message(&Envelope {
                protocol_version: 1,
                request_id,
                timestamp_ms: now_ms(),
                payload: Some(Payload::DeviceRegister(DeviceRegister {
                    device_id: device_id.to_owned(),
                    auth_token: auth_token.to_owned(),
                    device_type: DeviceType::Agent as i32,
                    display_name: display_name.to_owned(),
                    agent_version: env!("CARGO_PKG_VERSION").to_owned(),
                })),
            })?
            .into(),
        ))
        .await
        .context("failed to send device registration envelope")?;

    let Some(frame) = socket
        .next()
        .await
        .transpose()
        .context("failed to read device register ack frame")?
    else {
        bail!("connection node closed before acknowledging device registration");
    };

    let Message::Binary(bytes) = frame else {
        bail!("connection node returned a non-binary registration response");
    };

    let envelope = decode_ws_binary_message(&bytes)?;
    match envelope.payload {
        Some(Payload::DeviceRegisterAck(ack)) if ack.success => Ok(socket),
        Some(Payload::DeviceRegisterAck(ack)) => bail!(ack.message),
        other => bail!("expected device register ack, got {other:?}"),
    }
}

pub async fn bridge_remote_socket_to_local_server(
    mut remote_socket: RemoteSocket,
    local_server_url: String,
) -> Result<()> {
    let mut local_socket: Option<RemoteSocket> = None;

    loop {
        if let Some(socket) = local_socket.as_mut() {
            tokio::select! {
                remote_message = remote_socket.next() => {
                    let Some(message) = remote_message.transpose().context("failed to read connection node frame")? else {
                        return Ok(());
                    };

                    if !forward_remote_message_to_local(&mut local_socket, &local_server_url, message).await? {
                        return Ok(());
                    }
                }
                local_message = socket.next() => {
                    let Some(message) = local_message.transpose().context("failed to read local server frame")? else {
                        local_socket = None;
                        continue;
                    };

                    match message {
                        Message::Binary(bytes) => {
                            remote_socket
                                .send(Message::Binary(bytes))
                                .await
                                .context("failed to relay local server frame to connection node")?;
                        }
                        Message::Close(_) => {
                            local_socket = None;
                        }
                        Message::Ping(_) | Message::Pong(_) => {}
                        other => bail!("unexpected local server websocket message: {other:?}"),
                    }
                }
            }
        } else {
            let Some(message) = remote_socket
                .next()
                .await
                .transpose()
                .context("failed to read connection node frame")?
            else {
                return Ok(());
            };

            if !forward_remote_message_to_local(&mut local_socket, &local_server_url, message).await? {
                return Ok(());
            }
        }
    }
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock should be after unix epoch")
        .as_millis() as u64
}

async fn forward_remote_message_to_local(
    local_socket: &mut Option<RemoteSocket>,
    local_server_url: &str,
    message: Message,
) -> Result<bool> {
    match message {
        Message::Binary(bytes) => {
            if local_socket.is_none() {
                let (socket, _) = connect_async(local_server_url)
                    .await
                    .with_context(|| format!("failed to connect to local server at {local_server_url}"))?;
                *local_socket = Some(socket);
            }

            local_socket
                .as_mut()
                .expect("local socket should be initialized")
                .send(Message::Binary(bytes))
                .await
                .context("failed to relay connection node frame to local server")?;
            Ok(true)
        }
        Message::Close(_) => Ok(false),
        Message::Ping(_) | Message::Pong(_) => Ok(true),
        other => bail!("unexpected connection node websocket message: {other:?}"),
    }
}
