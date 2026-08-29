use anyhow::{bail, Result};
use flclash_strict_contract::{parse_broker_request, BrokerCommand, BrokerRequest};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ClientRole {
    Owner,
    RecoveryAdministrator,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ClientPrincipal {
    is_local: bool,
    role: ClientRole,
}

impl ClientPrincipal {
    pub fn new(is_local: bool, role: ClientRole) -> Self {
        Self { is_local, role }
    }

    pub fn is_local(self) -> bool {
        self.is_local
    }

    pub fn role(self) -> ClientRole {
        self.role
    }
}

#[derive(Debug)]
pub struct AuthorizedBrokerRequest {
    principal: ClientPrincipal,
    request: BrokerRequest,
}

impl AuthorizedBrokerRequest {
    pub fn principal(&self) -> ClientPrincipal {
        self.principal
    }

    pub fn request(&self) -> &BrokerRequest {
        &self.request
    }

    pub fn into_request(self) -> BrokerRequest {
        self.request
    }
}

pub struct BrokerAuthenticator {
    expected_capability: [u8; 32],
}

impl BrokerAuthenticator {
    pub fn new(expected_capability: [u8; 32]) -> Self {
        Self {
            expected_capability,
        }
    }

    pub fn authenticate(
        &self,
        principal: &ClientPrincipal,
        frame: &str,
    ) -> Result<AuthorizedBrokerRequest> {
        let request = parse_broker_request(frame)?;
        if !principal.is_local {
            bail!("remote Broker clients are forbidden");
        }

        let provided = decode_sha256(&request.session_capability)?;
        if !constant_time_equal(&provided, &self.expected_capability) {
            bail!("Broker session capability is invalid");
        }
        if principal.role == ClientRole::RecoveryAdministrator
            && !matches!(
                request.command,
                BrokerCommand::Status {}
                    | BrokerCommand::Diagnostics {}
                    | BrokerCommand::ForceBlocking { .. }
                    | BrokerCommand::DisablePolicy { .. }
            )
        {
            bail!("recovery administrator command is not permitted");
        }

        Ok(AuthorizedBrokerRequest {
            principal: *principal,
            request,
        })
    }
}

fn decode_sha256(value: &str) -> Result<[u8; 32]> {
    if value.len() != 64 {
        bail!("Broker session capability has an invalid size");
    }
    let mut decoded = [0_u8; 32];
    for (index, pair) in value.as_bytes().chunks_exact(2).enumerate() {
        let high = decode_hex_digit(pair[0])?;
        let low = decode_hex_digit(pair[1])?;
        decoded[index] = (high << 4) | low;
    }
    Ok(decoded)
}

fn decode_hex_digit(value: u8) -> Result<u8> {
    match value {
        b'0'..=b'9' => Ok(value - b'0'),
        b'a'..=b'f' => Ok(value - b'a' + 10),
        b'A'..=b'F' => Ok(value - b'A' + 10),
        _ => bail!("Broker session capability is not hexadecimal"),
    }
}

fn constant_time_equal(left: &[u8; 32], right: &[u8; 32]) -> bool {
    let mut difference = 0_u8;
    for index in 0..left.len() {
        difference |= left[index] ^ right[index];
    }
    difference == 0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hexadecimal_capabilities_are_case_insensitive_bytes() {
        assert_eq!(decode_sha256(&"aB".repeat(32)).unwrap(), [0xab; 32]);
    }

    #[test]
    fn equality_checks_every_byte() {
        assert!(constant_time_equal(&[1; 32], &[1; 32]));
        let mut different = [1; 32];
        different[31] = 2;
        assert!(!constant_time_equal(&[1; 32], &different));
    }
}
