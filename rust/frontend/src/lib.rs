use godot::classes::{RefCounted, WebSocketPeer};
use godot::prelude::*;
struct CoastExtension;
#[gdextension]
unsafe impl ExtensionLibrary for CoastExtension {}
#[derive(GodotClass)]
#[class(base=RefCounted)]
struct CoastTransport {
    peer: Gd<WebSocketPeer>,
    base: Base<RefCounted>,
}
#[godot_api]
impl IRefCounted for CoastTransport {
    fn init(base: Base<RefCounted>) -> Self {
        let mut peer = WebSocketPeer::new_gd();
        // Persisted order history and fleet telemetry can exceed Godot's 64 KiB default.
        peer.set_inbound_buffer_size(8 * 1024 * 1024);
        peer.set_outbound_buffer_size(1024 * 1024);
        Self { peer, base }
    }
}
#[godot_api]
impl CoastTransport {
    #[func]
    fn connect_backend(&mut self, url: GString) -> i64 {
        self.peer.connect_to_url(&url).ord() as i64
    }
    #[func]
    fn poll_json(&mut self) -> GString {
        self.peer.poll();
        let mut packets = Vec::new();
        while self.peer.get_available_packet_count() > 0 {
            let raw = self.peer.get_packet().get_string_from_utf8();
            if let Ok(value) = serde_json::from_str::<serde_json::Value>(&raw.to_string()) {
                packets.push(value);
            }
        }
        if packets.is_empty() {
            GString::new()
        } else {
            GString::from(serde_json::to_string(&packets).unwrap().as_str())
        }
    }
    #[func]
    fn send_json(&mut self, json: GString) -> i64 {
        if serde_json::from_str::<serde_json::Value>(&json.to_string()).is_err() {
            return -1;
        }
        self.peer.send_text(&json).ord() as i64
    }
    #[func]
    fn connected(&self) -> bool {
        self.peer.get_ready_state().ord() == 1
    }
}
