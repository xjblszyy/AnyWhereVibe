use anyhow::bail;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Transport {
    Local { listen_addr: String },
    RemoteStub,
}

impl Transport {
    pub fn listen_addr(&self) -> anyhow::Result<&str> {
        match self {
            Self::Local { listen_addr } => Ok(listen_addr),
            Self::RemoteStub => bail!("remote transport is not supported in the A-slice"),
        }
    }
}
