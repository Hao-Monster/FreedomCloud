use std::net::{IpAddr, Ipv4Addr, SocketAddr};

use flclash_strict_broker::{
    parse_strict_redirect_context, StrictRedirectLeaseBinding, StrictRedirectTransport,
};

const CONTEXT_BYTES: usize = 112;

fn put_u16(bytes: &mut [u8], offset: usize, value: u16) {
    bytes[offset..offset + 2].copy_from_slice(&value.to_le_bytes());
}

fn put_u32(bytes: &mut [u8], offset: usize, value: u32) {
    bytes[offset..offset + 4].copy_from_slice(&value.to_le_bytes());
}

fn put_u64(bytes: &mut [u8], offset: usize, value: u64) {
    bytes[offset..offset + 8].copy_from_slice(&value.to_le_bytes());
}

fn context() -> Vec<u8> {
    let mut bytes = vec![0_u8; CONTEXT_BYTES];
    put_u32(&mut bytes, 0, 0x4358_4346);
    put_u16(&mut bytes, 4, 1);
    put_u16(&mut bytes, 6, CONTEXT_BYTES as u16);
    put_u64(&mut bytes, 8, 9);
    put_u64(&mut bytes, 16, 7);
    bytes[24..56].copy_from_slice(&[0xab; 32]);
    bytes[56..72].copy_from_slice(&[0x11; 16]);
    put_u16(&mut bytes, 72, 1);
    bytes[74] = 4;
    bytes[75] = 6;
    put_u16(&mut bytes, 76, 443);
    bytes[80..84].copy_from_slice(&[203, 0, 113, 10]);
    bytes
}

fn binding() -> StrictRedirectLeaseBinding {
    StrictRedirectLeaseBinding::new(9, 7, &"ab".repeat(32), [0x11; 16], 2).unwrap()
}

#[test]
fn exact_kernel_context_binds_destination_group_and_live_lease() {
    let parsed =
        parse_strict_redirect_context(&context(), &binding(), StrictRedirectTransport::Tcp)
            .unwrap();

    assert_eq!(parsed.target_group_index(), 1);
    assert_eq!(
        parsed.original_destination(),
        SocketAddr::new(IpAddr::V4(Ipv4Addr::new(203, 0, 113, 10)), 443)
    );
    assert_eq!(parsed.transport(), StrictRedirectTransport::Tcp);
}

#[test]
fn stale_malformed_or_loopback_context_fails_closed() {
    let mut stale = context();
    put_u64(&mut stale, 8, 8);
    assert!(
        parse_strict_redirect_context(&stale, &binding(), StrictRedirectTransport::Tcp).is_err()
    );

    let mut loopback = context();
    loopback[80..84].copy_from_slice(&[127, 0, 0, 1]);
    assert!(
        parse_strict_redirect_context(&loopback, &binding(), StrictRedirectTransport::Tcp).is_err()
    );

    let mut udp = context();
    udp[75] = 17;
    assert!(parse_strict_redirect_context(&udp, &binding(), StrictRedirectTransport::Tcp).is_err());

    let mut oversized = context();
    oversized.push(0);
    assert!(
        parse_strict_redirect_context(&oversized, &binding(), StrictRedirectTransport::Tcp)
            .is_err()
    );
}
