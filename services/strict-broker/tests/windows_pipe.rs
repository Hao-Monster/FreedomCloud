#![cfg(windows)]

use std::time::{SystemTime, UNIX_EPOCH};

use flclash_strict_broker::{
    current_process_user_sid, exchange_windows_pipe_for_agent, BrokerAuthenticator, ClientRole,
    WindowsNamedPipeInstance,
};
use flclash_strict_contract::{BrokerErrorCode, BrokerResponse, BrokerResponseBody};

#[test]
fn named_pipe_uses_os_identity_and_capability_for_a_local_request() {
    let owner_sid = current_process_user_sid().unwrap();
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let pipe_name = format!(
        r"\\.\pipe\FlClashX.StrictBroker.Test.{}.{}",
        std::process::id(),
        nonce
    );
    let instance = WindowsNamedPipeInstance::create(&pipe_name, &owner_sid).unwrap();
    let frame = format!(
        r#"{{"protocol":1,"requestId":"pipe-test","sessionCapability":"{}","command":{{"type":"status"}}}}"#,
        "11".repeat(32)
    );
    let client_pipe_name = pipe_name.clone();
    let client = std::thread::spawn(move || {
        exchange_windows_pipe_for_agent(&client_pipe_name, frame.as_bytes()).unwrap()
    });

    let request = instance
        .connect_and_authenticate(&BrokerAuthenticator::new([0x11; 32]))
        .unwrap();
    instance
        .write_response(&BrokerResponse::error("pipe-test", BrokerErrorCode::Internal).unwrap())
        .unwrap();
    let response = client.join().unwrap();

    assert_eq!(request.authorized.principal().role(), ClientRole::Owner);
    assert_eq!(request.client_process_id, std::process::id());
    assert_eq!(request.client_sid, owner_sid);
    assert_eq!(request.authorized.request().request_id, "pipe-test");
    assert!(matches!(
        response.body,
        BrokerResponseBody::Error {
            code: BrokerErrorCode::Internal
        }
    ));
}
