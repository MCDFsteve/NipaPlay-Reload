use gstreamer as gst;
use gst::prelude::*;
use gstreamer_app as gst_app;
use gstreamer_video as gst_video;
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};
use std::thread;

pub struct NipaPlayerNext {
    pipeline: Option<gst::Element>,
    video_sink: Option<gst_app::AppSink>,
    bus_thread: Option<thread::JoinHandle<()>>,
    bus_cancel: Option<Arc<AtomicBool>>,
    volume: f64,
    playback_rate: f64,
}

impl Default for NipaPlayerNext {
    fn default() -> Self {
        Self {
            pipeline: None,
            video_sink: None,
            bus_thread: None,
            bus_cancel: None,
            volume: 1.0,
            playback_rate: 1.0,
        }
    }
}

impl NipaPlayerNext {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn init(&self) -> Result<(), String> {
        gst::init().map_err(|e| e.to_string())
    }

    pub fn load(&mut self, input: &str) -> Result<(), String> {
        self.stop()?;
        let uri = ensure_uri(input)?;
        let playbin = gst::ElementFactory::make("playbin")
            .build()
            .map_err(|_| "Failed to create playbin element".to_string())?;
        let appsink = gst::ElementFactory::make("appsink")
            .build()
            .map_err(|_| "Failed to create appsink element".to_string())?
            .downcast::<gst_app::AppSink>()
            .map_err(|_| "Failed to downcast appsink".to_string())?;
        let caps = gst::Caps::builder("video/x-raw")
            .field("format", &"RGBA")
            .build();
        appsink.set_caps(Some(&caps));
        appsink.set_property("emit-signals", &false);
        appsink.set_property("sync", &false);
        appsink.set_property("drop", &true);
        appsink.set_property("max-buffers", &1u32);
        playbin.set_property("video-sink", &appsink);
        playbin.set_property("uri", &uri);
        playbin.set_property("volume", &self.volume);
        self.attach_bus_watch(&playbin);
        self.pipeline = Some(playbin);
        self.video_sink = Some(appsink);
        self.set_state(gst::State::Paused)?;
        Ok(())
    }

    pub fn play(&self) -> Result<(), String> {
        self.set_state(gst::State::Playing)
    }

    pub fn pause(&self) -> Result<(), String> {
        self.set_state(gst::State::Paused)
    }

    pub fn stop(&mut self) -> Result<(), String> {
        if let Some(pipeline) = &self.pipeline {
            let _ = pipeline.set_state(gst::State::Null);
        }
        self.pipeline = None;
        self.video_sink = None;
        self.clear_bus_watch();
        Ok(())
    }

    pub fn seek(&self, position_ms: i64) -> Result<(), String> {
        let pipeline = self.pipeline.as_ref().ok_or("Pipeline not initialized")?;
        let position_ms = position_ms.max(0) as u64;
        pipeline
            .seek_simple(
                gst::SeekFlags::FLUSH | gst::SeekFlags::KEY_UNIT,
                gst::ClockTime::from_mseconds(position_ms),
            )
            .map_err(|e| e.to_string())
    }

    pub fn set_volume(&mut self, volume: f64) -> Result<(), String> {
        let volume = volume.clamp(0.0, 1.0);
        self.volume = volume;
        if let Some(pipeline) = &self.pipeline {
            pipeline.set_property("volume", &volume);
        }
        Ok(())
    }

    pub fn set_playback_rate(&mut self, rate: f64) -> Result<(), String> {
        if rate <= 0.0 {
            return Err("Playback rate must be > 0".to_string());
        }
        self.playback_rate = rate;
        let pipeline = match &self.pipeline {
            Some(pipeline) => pipeline,
            None => return Ok(()),
        };
        let position = pipeline
            .query_position::<gst::ClockTime>()
            .unwrap_or(gst::ClockTime::ZERO);
        pipeline
            .seek(
                rate,
                gst::SeekFlags::FLUSH | gst::SeekFlags::ACCURATE,
                gst::SeekType::Set,
                position,
                gst::SeekType::None,
                gst::ClockTime::NONE,
            )
            .map_err(|e| e.to_string())
    }

    pub fn position_ms(&self) -> Result<i64, String> {
        let pipeline = self.pipeline.as_ref().ok_or("Pipeline not initialized")?;
        let position = pipeline
            .query_position::<gst::ClockTime>()
            .ok_or("Failed to query position".to_string())?;
        Ok(position.mseconds() as i64)
    }

    pub fn duration_ms(&self) -> Result<i64, String> {
        let pipeline = self.pipeline.as_ref().ok_or("Pipeline not initialized")?;
        let duration = pipeline
            .query_duration::<gst::ClockTime>()
            .ok_or("Failed to query duration".to_string())?;
        Ok(duration.mseconds() as i64)
    }

    pub fn buffered_position_ms(&self) -> Result<i64, String> {
        self.position_ms()
    }

    pub fn try_pull_frame(&mut self) -> Result<Option<VideoFrame>, String> {
        let appsink = self
            .video_sink
            .as_ref()
            .ok_or("Video sink not initialized")?;
        let sample = appsink.try_pull_sample(gst::ClockTime::from_mseconds(0));
        let Some(sample) = sample else {
            return Ok(None);
        };
        let caps = sample.caps().ok_or("Missing caps")?;
        let info = gst_video::VideoInfo::from_caps(caps)
            .map_err(|_| "Invalid video caps".to_string())?;
        let buffer = sample.buffer().ok_or("Missing buffer")?;
        let map = buffer.map_readable().map_err(|_| "Buffer not readable")?;
        let data = map.as_slice().to_vec();
        let stride = info.stride()[0].abs() as u32;
        Ok(Some(VideoFrame {
            width: info.width(),
            height: info.height(),
            stride: stride as u32,
            data,
        }))
    }

    fn set_state(&self, state: gst::State) -> Result<(), String> {
        let pipeline = self.pipeline.as_ref().ok_or("Pipeline not initialized")?;
        pipeline
            .set_state(state)
            .map(|_| ())
            .map_err(|e| format!("Failed to change state to {:?}: {:?}", state, e))
    }

    fn attach_bus_watch(&mut self, pipeline: &gst::Element) {
        self.clear_bus_watch();
        let Some(bus) = pipeline.bus() else {
            return;
        };
        let cancel = Arc::new(AtomicBool::new(false));
        let cancel_clone = cancel.clone();
        let bus_clone = bus.clone();
        let handle = thread::spawn(move || {
            while !cancel_clone.load(Ordering::Relaxed) {
                if let Some(msg) = bus_clone.timed_pop(gst::ClockTime::from_mseconds(200)) {
                    use gst::MessageView;
                    match msg.view() {
                        MessageView::StateChanged(state_changed) => {
                            let src = msg
                                .src()
                                .map(|s| s.path_string().to_string())
                                .unwrap_or_else(|| "unknown".to_string());
                            println!(
                                "[nipaplay-next] state-changed: {} {:?} -> {:?}",
                                src,
                                state_changed.old(),
                                state_changed.current()
                            );
                        }
                        MessageView::Error(err) => {
                            let src = err
                                .src()
                                .map(|s| s.path_string().to_string())
                                .unwrap_or_else(|| "unknown".to_string());
                            println!(
                                "[nipaplay-next] error from {}: {} ({:?})",
                                src,
                                err.error(),
                                err.debug()
                            );
                        }
                        MessageView::Eos(_) => {
                            println!("[nipaplay-next] end-of-stream");
                        }
                        _ => {}
                    }
                }
            }
        });
        self.bus_cancel = Some(cancel);
        self.bus_thread = Some(handle);
    }

    fn clear_bus_watch(&mut self) {
        if let Some(cancel) = &self.bus_cancel {
            cancel.store(true, Ordering::Relaxed);
        }
        if let Some(handle) = self.bus_thread.take() {
            let _ = handle.join();
        }
        self.bus_cancel = None;
    }
}

#[derive(Clone, Debug)]
pub struct VideoFrame {
    pub width: u32,
    pub height: u32,
    pub stride: u32,
    pub data: Vec<u8>,
}

fn ensure_uri(input: &str) -> Result<String, String> {
    if input.contains("://") {
        return Ok(input.to_string());
    }
    let path = std::path::Path::new(input);
    let abs = if path.is_absolute() {
        path.to_path_buf()
    } else {
        std::env::current_dir()
            .map_err(|e| e.to_string())?
            .join(path)
    };
    let url = url::Url::from_file_path(&abs)
        .map_err(|_| format!("Invalid file path: {}", abs.display()))?;
    Ok(url.to_string())
}
