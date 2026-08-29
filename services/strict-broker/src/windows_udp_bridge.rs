use std::collections::HashMap;
use std::net::SocketAddr;
use std::time::{Duration, Instant};

use anyhow::{bail, Context, Result};

use crate::{StrictDriverDatagramFlags, StrictDriverDatagramRecord, StrictUdpReplayWindow};

pub const STRICT_DRIVER_UDP_MAX_ASSOCIATIONS: usize = 1024;
pub const STRICT_DRIVER_UDP_ASSOCIATION_IDLE: Duration = Duration::from_secs(90);

pub struct StrictDriverUdpAssociations {
    by_flow: HashMap<u64, DriverUdpAssociation>,
    by_association: HashMap<[u8; 16], u64>,
}

impl Default for StrictDriverUdpAssociations {
    fn default() -> Self {
        Self::new()
    }
}

struct DriverUdpAssociation {
    association_id: [u8; 16],
    target_group_index: u16,
    flags: StrictDriverDatagramFlags,
    local_endpoint: SocketAddr,
    remote_endpoint: SocketAddr,
    captured_replay: StrictUdpReplayWindow,
    reply_replay: StrictUdpReplayWindow,
    last_seen: Instant,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct StrictDriverUdpOutbound {
    association_id: [u8; 16],
    target_group_index: u16,
    destination: SocketAddr,
}

impl StrictDriverUdpOutbound {
    pub fn association_id(&self) -> [u8; 16] {
        self.association_id
    }

    pub fn target_group_index(&self) -> u16 {
        self.target_group_index
    }

    pub fn destination(&self) -> SocketAddr {
        self.destination
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct StrictDriverUdpReplyRoute {
    flow_token: u64,
    sequence: u64,
    target_group_index: u16,
    flags: StrictDriverDatagramFlags,
    local_endpoint: SocketAddr,
    remote_endpoint: SocketAddr,
}

impl StrictDriverUdpReplyRoute {
    pub fn flow_token(&self) -> u64 {
        self.flow_token
    }

    pub fn sequence(&self) -> u64 {
        self.sequence
    }

    pub fn target_group_index(&self) -> u16 {
        self.target_group_index
    }

    pub fn flags(&self) -> StrictDriverDatagramFlags {
        self.flags
    }

    pub fn local_endpoint(&self) -> SocketAddr {
        self.local_endpoint
    }

    pub fn remote_endpoint(&self) -> SocketAddr {
        self.remote_endpoint
    }
}

impl StrictDriverUdpAssociations {
    pub fn new() -> Self {
        Self {
            by_flow: HashMap::with_capacity(STRICT_DRIVER_UDP_MAX_ASSOCIATIONS),
            by_association: HashMap::with_capacity(STRICT_DRIVER_UDP_MAX_ASSOCIATIONS),
        }
    }

    pub fn len(&self) -> usize {
        self.by_flow.len()
    }

    pub fn is_empty(&self) -> bool {
        self.by_flow.is_empty()
    }

    pub fn route_captured(
        &mut self,
        record: &StrictDriverDatagramRecord<'_>,
        new_association_id: impl FnOnce() -> Result<[u8; 16]>,
    ) -> Result<StrictDriverUdpOutbound> {
        self.route_captured_at(record, new_association_id, Instant::now())
    }

    fn route_captured_at(
        &mut self,
        record: &StrictDriverDatagramRecord<'_>,
        new_association_id: impl FnOnce() -> Result<[u8; 16]>,
        now: Instant,
    ) -> Result<StrictDriverUdpOutbound> {
        let flow_token = record.flow_token();
        if let Some(association) = self.by_flow.get_mut(&flow_token) {
            if association.target_group_index != record.target_group_index()
                || association.flags != record.flags()
                || association.local_endpoint != record.local_endpoint()
                || association.remote_endpoint != record.remote_endpoint()
            {
                bail!("strict driver UDP flow metadata changed");
            }
            if !association.captured_replay.accept(record.sequence()) {
                bail!("strict driver UDP captured sequence is replayed or stale");
            }
            association.last_seen = now;
            return Ok(StrictDriverUdpOutbound {
                association_id: association.association_id,
                target_group_index: association.target_group_index,
                destination: association.remote_endpoint,
            });
        }

        if self.by_flow.len() >= STRICT_DRIVER_UDP_MAX_ASSOCIATIONS {
            self.sweep_expired_at(now, |_| {});
            if self.by_flow.len() >= STRICT_DRIVER_UDP_MAX_ASSOCIATIONS {
                bail!("strict driver UDP association limit is reached");
            }
        }
        let association_id = new_association_id().context("create strict UDP association ID")?;
        if association_id.iter().all(|byte| *byte == 0)
            || self.by_association.contains_key(&association_id)
        {
            bail!("strict driver UDP association ID is empty or duplicated");
        }
        let mut captured_replay = StrictUdpReplayWindow::default();
        if !captured_replay.accept(record.sequence()) {
            bail!("strict driver UDP initial captured sequence is invalid");
        }
        let association = DriverUdpAssociation {
            association_id,
            target_group_index: record.target_group_index(),
            flags: record.flags(),
            local_endpoint: record.local_endpoint(),
            remote_endpoint: record.remote_endpoint(),
            captured_replay,
            reply_replay: StrictUdpReplayWindow::default(),
            last_seen: now,
        };
        if self
            .by_association
            .insert(association_id, flow_token)
            .is_some()
        {
            bail!("strict driver UDP association index was unexpectedly occupied");
        }
        if self.by_flow.insert(flow_token, association).is_some() {
            self.by_association.remove(&association_id);
            bail!("strict driver UDP flow index was unexpectedly occupied");
        }
        Ok(StrictDriverUdpOutbound {
            association_id,
            target_group_index: record.target_group_index(),
            destination: record.remote_endpoint(),
        })
    }

    pub fn route_reply(
        &mut self,
        association_id: [u8; 16],
        sequence: u64,
        remote_endpoint: SocketAddr,
    ) -> Result<StrictDriverUdpReplyRoute> {
        self.route_reply_at(association_id, sequence, remote_endpoint, Instant::now())
    }

    fn route_reply_at(
        &mut self,
        association_id: [u8; 16],
        sequence: u64,
        remote_endpoint: SocketAddr,
        now: Instant,
    ) -> Result<StrictDriverUdpReplyRoute> {
        let flow_token = *self
            .by_association
            .get(&association_id)
            .context("strict driver UDP reply association is unknown or expired")?;
        let association = self
            .by_flow
            .get_mut(&flow_token)
            .context("strict driver UDP reply flow index is inconsistent")?;
        if association.association_id != association_id
            || association.remote_endpoint != remote_endpoint
        {
            bail!("strict driver UDP reply endpoint or association changed");
        }
        if !association.reply_replay.accept(sequence) {
            bail!("strict driver UDP reply sequence is replayed or stale");
        }
        association.last_seen = now;
        Ok(StrictDriverUdpReplyRoute {
            flow_token,
            sequence,
            target_group_index: association.target_group_index,
            flags: association.flags,
            local_endpoint: association.local_endpoint,
            remote_endpoint: association.remote_endpoint,
        })
    }

    pub fn sweep_expired(&mut self, on_expired: impl FnMut([u8; 16])) {
        self.sweep_expired_at(Instant::now(), on_expired);
    }

    fn sweep_expired_at(&mut self, now: Instant, mut on_expired: impl FnMut([u8; 16])) {
        let by_association = &mut self.by_association;
        self.by_flow.retain(|_, association| {
            if now.saturating_duration_since(association.last_seen)
                < STRICT_DRIVER_UDP_ASSOCIATION_IDLE
            {
                true
            } else {
                by_association.remove(&association.association_id);
                on_expired(association.association_id);
                false
            }
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        StrictDriverDatagramBatch, StrictDriverDatagramBatchBuilder, StrictDriverDatagramBatchKind,
        StrictDriverDatagramLeaseIdentity, STRICT_DRIVER_DATAGRAM_MAX_BATCH_BYTES,
    };

    const LOCAL: &str = "10.0.0.2:53000";
    const REMOTE: &str = "1.1.1.1:443";

    fn encoded_record(
        flow_token: u64,
        sequence: u64,
        target_group_index: u16,
        remote: &str,
    ) -> Vec<u8> {
        let identity =
            StrictDriverDatagramLeaseIdentity::new(7, 91, [0xab; 32], [0x5a; 16]).unwrap();
        let mut storage = vec![0_u8; STRICT_DRIVER_DATAGRAM_MAX_BATCH_BYTES];
        let mut builder = StrictDriverDatagramBatchBuilder::new(
            &mut storage,
            StrictDriverDatagramBatchKind::Captured,
            identity,
        )
        .unwrap();
        builder
            .push(
                flow_token,
                sequence,
                target_group_index,
                StrictDriverDatagramFlags::QUIC,
                LOCAL.parse().unwrap(),
                remote.parse().unwrap(),
                b"payload",
            )
            .unwrap();
        builder.finish().unwrap().to_vec()
    }

    fn with_record<T>(bytes: &[u8], body: impl FnOnce(&StrictDriverDatagramRecord<'_>) -> T) -> T {
        let identity =
            StrictDriverDatagramLeaseIdentity::new(7, 91, [0xab; 32], [0x5a; 16]).unwrap();
        let batch = StrictDriverDatagramBatch::decode(
            bytes,
            StrictDriverDatagramBatchKind::Captured,
            identity,
        )
        .unwrap();
        body(&batch.records().next().unwrap())
    }

    #[test]
    fn association_state_routes_async_replies_without_endpoint_or_group_drift() {
        let now = Instant::now();
        let mut table = StrictDriverUdpAssociations::new();
        let first = encoded_record(11, 1, 3, REMOTE);
        let outbound = with_record(&first, |record| {
            table.route_captured_at(record, || Ok([0x44; 16]), now)
        })
        .unwrap();
        assert_eq!(outbound.association_id(), [0x44; 16]);
        assert_eq!(outbound.target_group_index(), 3);
        assert_eq!(
            outbound.destination(),
            REMOTE.parse::<SocketAddr>().unwrap()
        );

        let second = encoded_record(11, 2, 3, REMOTE);
        let second = with_record(&second, |record| {
            table.route_captured_at(record, || Ok([0x55; 16]), now)
        })
        .unwrap();
        assert_eq!(second.association_id(), [0x44; 16]);

        let reply = table
            .route_reply_at([0x44; 16], 1, REMOTE.parse().unwrap(), now)
            .unwrap();
        assert_eq!(reply.flow_token(), 11);
        assert_eq!(reply.target_group_index(), 3);
        assert_eq!(reply.local_endpoint(), LOCAL.parse::<SocketAddr>().unwrap());
        assert_eq!(
            reply.remote_endpoint(),
            REMOTE.parse::<SocketAddr>().unwrap()
        );
        assert_eq!(reply.flags(), StrictDriverDatagramFlags::QUIC);
        assert_eq!(reply.sequence(), 1);

        assert!(table
            .route_reply_at([0x44; 16], 1, REMOTE.parse().unwrap(), now)
            .is_err());
        assert!(table
            .route_reply_at([0x44; 16], 2, "8.8.8.8:443".parse().unwrap(), now)
            .is_err());
        assert!(table
            .route_reply_at([0x66; 16], 1, REMOTE.parse().unwrap(), now)
            .is_err());
    }

    #[test]
    fn association_state_rejects_replay_mutation_and_identifier_collision() {
        let now = Instant::now();
        let mut table = StrictDriverUdpAssociations::new();
        let first = encoded_record(11, 2, 3, REMOTE);
        with_record(&first, |record| {
            table.route_captured_at(record, || Ok([0x44; 16]), now)
        })
        .unwrap();

        let replay = encoded_record(11, 2, 3, REMOTE);
        assert!(with_record(&replay, |record| {
            table.route_captured_at(record, || Ok([0x55; 16]), now)
        })
        .is_err());
        let changed_group = encoded_record(11, 3, 4, REMOTE);
        assert!(with_record(&changed_group, |record| {
            table.route_captured_at(record, || Ok([0x55; 16]), now)
        })
        .is_err());

        let other = encoded_record(12, 1, 3, REMOTE);
        assert!(with_record(&other, |record| {
            table.route_captured_at(record, || Ok([0x44; 16]), now)
        })
        .is_err());
    }

    #[test]
    fn association_state_has_a_hard_limit_and_idle_expiry() {
        let now = Instant::now();
        let mut table = StrictDriverUdpAssociations::new();
        for flow_token in 1..=STRICT_DRIVER_UDP_MAX_ASSOCIATIONS as u64 {
            let encoded = encoded_record(flow_token, 1, 0, REMOTE);
            with_record(&encoded, |record| {
                let mut association_id = [0_u8; 16];
                association_id[8..].copy_from_slice(&flow_token.to_le_bytes());
                table.route_captured_at(record, || Ok(association_id), now)
            })
            .unwrap();
        }
        assert_eq!(table.len(), STRICT_DRIVER_UDP_MAX_ASSOCIATIONS);
        let overflow = encoded_record(2_000, 1, 0, REMOTE);
        assert!(with_record(&overflow, |record| {
            table.route_captured_at(record, || Ok([0xff; 16]), now)
        })
        .is_err());

        let mut expired = Vec::new();
        table.sweep_expired_at(
            now + STRICT_DRIVER_UDP_ASSOCIATION_IDLE + Duration::from_millis(1),
            |association_id| expired.push(association_id),
        );
        assert_eq!(expired.len(), STRICT_DRIVER_UDP_MAX_ASSOCIATIONS);
        assert!(table.is_empty());
    }
}
