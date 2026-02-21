use nipaplay_next::NipaPlayerNext;
use once_cell::sync::Lazy;
use std::sync::Mutex;

static PLAYER: Lazy<Mutex<NipaPlayerNext>> = Lazy::new(|| Mutex::new(NipaPlayerNext::new()));

#[flutter_rust_bridge::frb]
pub struct VideoFrame {
    pub width: u32,
    pub height: u32,
    pub stride: u32,
    pub data: Vec<u8>,
}

fn map_frame(frame: nipaplay_next::VideoFrame) -> VideoFrame {
    VideoFrame {
        width: frame.width,
        height: frame.height,
        stride: frame.stride,
        data: frame.data,
    }
}

fn with_player<T>(f: impl FnOnce(&mut NipaPlayerNext) -> Result<T, String>) -> Result<T, String> {
    let mut guard = PLAYER
        .lock()
        .map_err(|_| "NipaPlayNext player lock poisoned".to_string())?;
    f(&mut guard)
}

#[flutter_rust_bridge::frb]
pub fn init() -> Result<(), String> {
    with_player(|player| player.init())
}

#[flutter_rust_bridge::frb]
pub fn load(url: String) -> Result<(), String> {
    with_player(|player| player.load(&url))
}

#[flutter_rust_bridge::frb]
pub fn play() -> Result<(), String> {
    with_player(|player| player.play())
}

#[flutter_rust_bridge::frb]
pub fn pause() -> Result<(), String> {
    with_player(|player| player.pause())
}

#[flutter_rust_bridge::frb]
pub fn stop() -> Result<(), String> {
    with_player(|player| player.stop())
}

#[flutter_rust_bridge::frb]
pub fn seek(position_ms: i64) -> Result<(), String> {
    with_player(|player| player.seek(position_ms))
}

#[flutter_rust_bridge::frb]
pub fn set_volume(volume: f64) -> Result<(), String> {
    with_player(|player| player.set_volume(volume))
}

#[flutter_rust_bridge::frb]
pub fn set_playback_rate(rate: f64) -> Result<(), String> {
    with_player(|player| player.set_playback_rate(rate))
}

#[flutter_rust_bridge::frb]
pub fn position_ms() -> Result<i64, String> {
    with_player(|player| player.position_ms())
}

#[flutter_rust_bridge::frb]
pub fn duration_ms() -> Result<i64, String> {
    with_player(|player| player.duration_ms())
}

#[flutter_rust_bridge::frb]
pub fn buffered_position_ms() -> Result<i64, String> {
    with_player(|player| player.buffered_position_ms())
}

#[flutter_rust_bridge::frb]
pub fn try_pull_frame() -> Result<Option<VideoFrame>, String> {
    with_player(|player| player.try_pull_frame().map(|frame| frame.map(map_frame)))
}
