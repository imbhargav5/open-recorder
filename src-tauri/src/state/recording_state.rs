use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum RecordingStatus {
    Idle,
    Recording,
    Paused,
    Processing,
}

impl Default for RecordingStatus {
    fn default() -> Self {
        Self::Idle
    }
}
