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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_recording_status_default_is_idle() {
        assert_eq!(RecordingStatus::default(), RecordingStatus::Idle);
    }

    #[test]
    fn test_recording_status_serialize_idle() {
        let json = serde_json::to_string(&RecordingStatus::Idle).unwrap();
        assert_eq!(json, "\"idle\"");
    }

    #[test]
    fn test_recording_status_serialize_recording() {
        let json = serde_json::to_string(&RecordingStatus::Recording).unwrap();
        assert_eq!(json, "\"recording\"");
    }

    #[test]
    fn test_recording_status_serialize_paused() {
        let json = serde_json::to_string(&RecordingStatus::Paused).unwrap();
        assert_eq!(json, "\"paused\"");
    }

    #[test]
    fn test_recording_status_serialize_processing() {
        let json = serde_json::to_string(&RecordingStatus::Processing).unwrap();
        assert_eq!(json, "\"processing\"");
    }

    #[test]
    fn test_recording_status_deserialize_idle() {
        let status: RecordingStatus = serde_json::from_str("\"idle\"").unwrap();
        assert_eq!(status, RecordingStatus::Idle);
    }

    #[test]
    fn test_recording_status_deserialize_recording() {
        let status: RecordingStatus = serde_json::from_str("\"recording\"").unwrap();
        assert_eq!(status, RecordingStatus::Recording);
    }

    #[test]
    fn test_recording_status_deserialize_paused() {
        let status: RecordingStatus = serde_json::from_str("\"paused\"").unwrap();
        assert_eq!(status, RecordingStatus::Paused);
    }

    #[test]
    fn test_recording_status_deserialize_processing() {
        let status: RecordingStatus = serde_json::from_str("\"processing\"").unwrap();
        assert_eq!(status, RecordingStatus::Processing);
    }

    #[test]
    fn test_recording_status_deserialize_invalid_value() {
        let result: Result<RecordingStatus, _> = serde_json::from_str("\"unknown\"");
        assert!(result.is_err());
    }

    #[test]
    fn test_recording_status_deserialize_uppercase_fails() {
        let result: Result<RecordingStatus, _> = serde_json::from_str("\"Idle\"");
        assert!(result.is_err());
    }

    #[test]
    fn test_recording_status_partial_eq() {
        assert_eq!(RecordingStatus::Idle, RecordingStatus::Idle);
        assert_eq!(RecordingStatus::Recording, RecordingStatus::Recording);
        assert_ne!(RecordingStatus::Idle, RecordingStatus::Recording);
        assert_ne!(RecordingStatus::Paused, RecordingStatus::Processing);
    }

    #[test]
    fn test_recording_status_clone() {
        let status = RecordingStatus::Recording;
        let cloned = status.clone();
        assert_eq!(status, cloned);
    }

    #[test]
    fn test_recording_status_debug() {
        let debug_str = format!("{:?}", RecordingStatus::Idle);
        assert_eq!(debug_str, "Idle");
    }

    #[test]
    fn test_recording_status_roundtrip_all_variants() {
        for status in [
            RecordingStatus::Idle,
            RecordingStatus::Recording,
            RecordingStatus::Paused,
            RecordingStatus::Processing,
        ] {
            let json = serde_json::to_string(&status).unwrap();
            let restored: RecordingStatus = serde_json::from_str(&json).unwrap();
            assert_eq!(status, restored);
        }
    }
}
