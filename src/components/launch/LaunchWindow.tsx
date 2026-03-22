import { useEffect, useMemo, useRef, useState } from "react";
import { useActor } from "@xstate/react";
import { BsRecordCircle } from "react-icons/bs";
import { FaRegStopCircle } from "react-icons/fa";
import { FaFolderOpen } from "react-icons/fa6";
import { FiMinus, FiX } from "react-icons/fi";
import { MdMic, MdMicOff, MdMonitor, MdVideocam, MdVideocamOff, MdVideoFile, MdVolumeOff, MdVolumeUp } from "react-icons/md";
import { useCameraDevices } from "../../hooks/useCameraDevices";
import { RxDragHandleDots2 } from "react-icons/rx";
import { useMicrophoneDevices } from "../../hooks/useMicrophoneDevices";
import { useScreenRecorder } from "../../hooks/useScreenRecorder";
import { microphoneMachine } from "../../machines/microphoneMachine";
import { Button } from "../ui/button";
import { ContentClamp } from "../ui/content-clamp";
import { Popover, PopoverAnchor, PopoverContent } from "../ui/popover";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "../ui/select";
import { Switch } from "../ui/switch";
import styles from "./LaunchWindow.module.css";
import { getCurrentWindow } from "@tauri-apps/api/window";
import * as backend from "@/lib/backend";

const SYSTEM_DEFAULT_MICROPHONE_ID = "__system_default_microphone__";

export function LaunchWindow() {
  const {
    recording,
    toggleRecording,
    preparePermissions,
    setMicrophoneEnabled,
    microphoneDeviceId,
    setMicrophoneDeviceId,
    systemAudioEnabled,
    setSystemAudioEnabled,
    cameraEnabled,
    setCameraEnabled,
    cameraDeviceId,
    setCameraDeviceId,
  } = useScreenRecorder();
  const [recordingStart, setRecordingStart] = useState<number | null>(null);
  const [elapsed, setElapsed] = useState(0);
  const showCameraControls = cameraEnabled && !recording;

  const setMicEnabledRef = useRef(setMicrophoneEnabled);
  setMicEnabledRef.current = setMicrophoneEnabled;

  const providedMachine = useMemo(
    () =>
      microphoneMachine.provide({
        actions: {
          enableMic: () => setMicEnabledRef.current(true),
          disableMic: () => setMicEnabledRef.current(false),
        },
      }),
    [],
  );

  const [micState, micSend] = useActor(providedMachine);

  const isMicEnabled = micState.matches("on") || micState.matches("selecting") || micState.matches("lockedOn");
  const isPopoverOpen = micState.matches("selecting");

  const { devices, selectedDeviceId, setSelectedDeviceId, error: microphoneDevicesError } = useMicrophoneDevices(
    isPopoverOpen,
  );
  const {
    devices: cameraDevices,
    selectedDeviceId: selectedCameraDeviceId,
    setSelectedDeviceId: setSelectedCameraDeviceId,
  } = useCameraDevices(cameraEnabled);
  const micButtonRef = useRef<HTMLButtonElement | null>(null);
  const cameraPreviewRef = useRef<HTMLVideoElement | null>(null);

  useEffect(() => {
    if (selectedDeviceId && selectedDeviceId !== "default") {
      setMicrophoneDeviceId(selectedDeviceId);
    }
  }, [selectedDeviceId, setMicrophoneDeviceId]);

  useEffect(() => {
    if (selectedCameraDeviceId && selectedCameraDeviceId !== "default") {
      setCameraDeviceId(selectedCameraDeviceId);
    }
  }, [selectedCameraDeviceId, setCameraDeviceId]);

  // Sync recording state into the machine
  const prevRecording = useRef(recording);
  useEffect(() => {
    if (recording && !prevRecording.current) {
      micSend({ type: "RECORDING_START" });
    } else if (!recording && prevRecording.current) {
      micSend({ type: "RECORDING_STOP" });
    }
    prevRecording.current = recording;
  }, [recording, micSend]);

  useEffect(() => {
    if (!showCameraControls) {
      if (cameraPreviewRef.current) {
        cameraPreviewRef.current.srcObject = null;
      }
      return;
    }

    let mounted = true;
    let previewStream: MediaStream | null = null;
    const mediaDevices = navigator.mediaDevices;

    const loadPreview = async () => {
      if (!mediaDevices?.getUserMedia) {
        return;
      }

      try {
        previewStream = await mediaDevices.getUserMedia({
          video: cameraDeviceId
            ? {
                deviceId: { exact: cameraDeviceId },
                width: { ideal: 640, max: 640 },
                height: { ideal: 360, max: 360 },
                frameRate: { ideal: 30, max: 30 },
              }
            : {
                width: { ideal: 640, max: 640 },
                height: { ideal: 360, max: 360 },
                frameRate: { ideal: 30, max: 30 },
              },
          audio: false,
        });

        if (!mounted || !cameraPreviewRef.current) {
          previewStream?.getTracks().forEach((track) => track.stop());
          return;
        }

        cameraPreviewRef.current.srcObject = previewStream;
        await cameraPreviewRef.current.play().catch(() => {});
      } catch (error) {
        console.error("Failed to load facecam preview:", error);
      }
    };

    void loadPreview();

    return () => {
      mounted = false;
      if (cameraPreviewRef.current) {
        cameraPreviewRef.current.srcObject = null;
      }
      previewStream?.getTracks().forEach((track) => track.stop());
    };
  }, [cameraDeviceId, showCameraControls]);

  useEffect(() => {
    let timer: NodeJS.Timeout | null = null;
    if (recording) {
      if (!recordingStart) setRecordingStart(Date.now());
      timer = setInterval(() => {
        if (recordingStart) {
          setElapsed(Math.floor((Date.now() - recordingStart) / 1000));
        }
      }, 1000);
    } else {
      setRecordingStart(null);
      setElapsed(0);
      if (timer) clearInterval(timer);
    }
    return () => {
      if (timer) clearInterval(timer);
    };
  }, [recording, recordingStart]);

  const formatTime = (seconds: number) => {
    const m = Math.floor(seconds / 60).toString().padStart(2, "0");
    const s = (seconds % 60).toString().padStart(2, "0");
    return `${m}:${s}`;
  };

  const [selectedSource, setSelectedSource] = useState("Screen");
  const [hasSelectedSource, setHasSelectedSource] = useState(false);
  const [recordingsDirectory, setRecordingsDirectory] = useState<string | null>(null);

  useEffect(() => {
    const checkSelectedSource = async () => {
      try {
        const source = await backend.getSelectedSource();
        if (source) {
          setSelectedSource(source.name);
          setHasSelectedSource(true);
        } else {
          setSelectedSource("Screen");
          setHasSelectedSource(false);
        }
      } catch {
        // ignore
      }
    };

    void checkSelectedSource();
    const interval = setInterval(checkSelectedSource, 500);
    return () => clearInterval(interval);
  }, []);

  const openSourceSelector = async () => {
    const screenStatus = await backend.getScreenRecordingPermissionStatus().catch(() => "unknown");
    if (screenStatus !== "granted") {
      const granted = await backend.requestScreenRecordingPermission().catch(() => false);
      if (!granted) {
        await backend.openScreenRecordingPreferences().catch(() => {});
        alert(
          "Open Recorder needs Screen Recording permission to show live screen and window previews. System Settings has been opened. After enabling it, quit and reopen Open Recorder.",
        );
        return;
      }
    }

    const permissionsReady = await preparePermissions();
    if (!permissionsReady) {
      return;
    }

    backend.openSourceSelector().catch(() => {});
  };

  const openVideoFile = async () => {
    const path = await backend.openVideoFilePicker();
    if (!path) return;
    await backend.setCurrentVideoPath(path);
    await backend.switchToEditor();
  };

  const openProjectFile = async () => {
    const result = await backend.loadProjectFile();
    if (!result) return;
    await backend.switchToEditor();
  };

  const sendHudOverlayHide = () => {
    backend.hudOverlayHide().catch(() => {});
  };

  const sendHudOverlayClose = () => {
    backend.hudOverlayClose().catch(() => {});
  };

  const chooseRecordingsDir = async () => {
    const path = await backend.chooseRecordingsDirectory();
    if (path) {
      setRecordingsDirectory(path);
    }
  };

  useEffect(() => {
    const loadRecordingsDirectory = async () => {
      try {
        const dir = await backend.getRecordingsDirectory();
        setRecordingsDirectory(dir);
      } catch {
        // ignore
      }
    };

    void loadRecordingsDirectory();
  }, []);

  const recordingsDirectoryName = recordingsDirectory
    ? recordingsDirectory.split(/[\\/]/).filter(Boolean).pop() || recordingsDirectory
    : "recordings";
  const dividerClass = "mx-1 h-5 w-px shrink-0 bg-white/35";

  const toggleCamera = () => {
    if (!recording) {
      setCameraEnabled(!cameraEnabled);
    }
  };

  const microphoneSelectValue = devices.some((device) => device.deviceId === (microphoneDeviceId || selectedDeviceId))
    ? (microphoneDeviceId || selectedDeviceId)
    : SYSTEM_DEFAULT_MICROPHONE_ID;
  const cameraSelectValue = cameraDevices.some((device) => device.deviceId === (cameraDeviceId || selectedCameraDeviceId))
    ? (cameraDeviceId || selectedCameraDeviceId)
    : undefined;

  return (
    <div className="w-full h-full flex items-end justify-center bg-transparent overflow-hidden">
      <div className={`flex flex-col items-center gap-2 mx-auto ${styles.tauriDrag}`}>
        {showCameraControls && (
          <div
            className={`flex items-center gap-3 rounded-[22px] border border-white/15 bg-[rgba(18,18,26,0.92)] px-3 py-2 shadow-xl backdrop-blur-xl ${styles.tauriNoDrag}`}
          >
            <div className="h-14 w-24 overflow-hidden rounded-2xl border border-white/10 bg-black/30">
              <video
                ref={cameraPreviewRef}
                className="h-full w-full object-cover"
                muted
                playsInline
              />
            </div>
            <div className="flex flex-col gap-1.5">
              <div className="text-[10px] font-medium tracking-[0.18em] uppercase text-white/50">Facecam</div>
              <Select
                value={cameraSelectValue}
                onValueChange={(value) => {
                  setSelectedCameraDeviceId(value);
                  setCameraDeviceId(value);
                }}
                disabled={cameraDevices.length === 0}
              >
                <SelectTrigger
                  className={`h-8 max-w-[230px] rounded-full border-white/15 bg-[#131722] px-3 py-1 text-xs text-slate-100 outline-none ring-0 ring-offset-0 focus:ring-0 focus:ring-offset-0 ${styles.tauriNoDrag}`}
                >
                  <SelectValue placeholder="Select camera" />
                </SelectTrigger>
                <SelectContent
                  className="z-[100] border-white/15 bg-[#131722] text-slate-100"
                  position="popper"
                >
                  {cameraDevices.map((device) => (
                    <SelectItem
                      key={device.deviceId}
                      value={device.deviceId}
                      className="text-xs focus:bg-white/10 focus:text-white"
                    >
                      {device.label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>
        )}

        <div
          className={`w-full mx-auto flex items-center gap-1.5 px-3 py-2 ${styles.tauriDrag} ${styles.hudBar}`}
          style={{
            borderRadius: 9999,
            background: "linear-gradient(135deg, rgba(28,28,36,0.97) 0%, rgba(18,18,26,0.96) 100%)",
            backdropFilter: "blur(16px) saturate(140%)",
            WebkitBackdropFilter: "blur(16px) saturate(140%)",
            border: "1px solid rgba(80,80,120,0.25)",
            minHeight: 48,
          }}
        >
          <div
            className="flex items-center px-1 cursor-grab active:cursor-grabbing"
            onMouseDown={() => getCurrentWindow().startDragging()}
          >
            <RxDragHandleDots2 size={16} className="text-white/35" />
          </div>

          <Button
            variant="link"
            size="sm"
            className={`gap-1 text-white/80 bg-transparent hover:bg-transparent px-0 text-xs ${styles.tauriNoDrag}`}
            onClick={openSourceSelector}
            disabled={recording}
            title={selectedSource}
          >
            <MdMonitor size={14} className="text-white/80" />
            <ContentClamp truncateLength={6}>{selectedSource}</ContentClamp>
          </Button>

          <div className={dividerClass} />

          <div className={`flex items-center gap-1 ${styles.tauriNoDrag}`}>
            <Button
              variant="link"
              size="icon"
              onClick={() => !recording && setSystemAudioEnabled(!systemAudioEnabled)}
              disabled={recording}
              title={systemAudioEnabled ? "Disable system audio" : "Enable system audio"}
              className={`text-white/80 hover:bg-transparent ${styles.tauriNoDrag}`}
            >
              {systemAudioEnabled ? <MdVolumeUp size={16} className="text-[#2563EB]" /> : <MdVolumeOff size={16} className="text-white/35" />}
            </Button>
            <Popover open={isPopoverOpen}>
              <PopoverAnchor asChild>
                <Button
                  ref={micButtonRef}
                  variant="link"
                  size="icon"
                  onClick={() => micSend({ type: "CLICK" })}
                  disabled={recording}
                  title={isMicEnabled ? "Microphone settings" : "Enable microphone"}
                  className={`text-white/80 hover:bg-transparent ${styles.tauriNoDrag}`}
                >
                  {isMicEnabled ? <MdMic size={16} className="text-[#2563EB]" /> : <MdMicOff size={16} className="text-white/35" />}
                </Button>
              </PopoverAnchor>
              <PopoverContent
                align="center"
                side="top"
                sideOffset={10}
                className={`w-[280px] rounded-2xl border border-white/15 bg-[rgba(18,18,26,0.96)] p-3 text-slate-100 shadow-xl backdrop-blur-xl ${styles.tauriNoDrag}`}
                onPointerDownOutside={(e) => {
                  if (micButtonRef.current?.contains(e.target as Node)) {
                    e.preventDefault();
                  } else {
                    micSend({ type: "CLOSE_POPOVER" });
                  }
                }}
                onEscapeKeyDown={() => micSend({ type: "CLOSE_POPOVER" })}
                onFocusOutside={(e) => e.preventDefault()}
              >
                <div className="mb-2 flex items-center justify-between">
                  <span className="text-[10px] font-medium tracking-[0.18em] uppercase text-white/50">
                    Microphone
                  </span>
                  <Switch
                    checked={isMicEnabled}
                    onCheckedChange={(checked) => {
                      if (!checked) {
                        micSend({ type: "DISABLE" });
                      }
                    }}
                  />
                </div>
                <div className="mb-3 text-xs text-white/65">
                  {microphoneDevicesError
                    ? "Using the system default microphone in this window."
                    : "Choose which microphone to record."}
                </div>
                <Select
                  value={microphoneSelectValue}
                  onValueChange={(value) => {
                    if (value === SYSTEM_DEFAULT_MICROPHONE_ID) {
                      setSelectedDeviceId("default");
                      setMicrophoneDeviceId(undefined);
                    } else {
                      setSelectedDeviceId(value);
                      setMicrophoneDeviceId(value);
                    }
                  }}
                >
                  <SelectTrigger
                    className={`h-8 w-full rounded-full border-white/15 bg-[#131722] px-3 py-1 text-xs text-slate-100 outline-none ring-0 ring-offset-0 focus:ring-0 focus:ring-offset-0 ${styles.tauriNoDrag}`}
                  >
                    <SelectValue placeholder="Select microphone" />
                  </SelectTrigger>
                  <SelectContent
                    className="z-[100] border-white/15 bg-[#131722] text-slate-100"
                    position="popper"
                  >
                    <SelectItem
                      value={SYSTEM_DEFAULT_MICROPHONE_ID}
                      className="text-xs focus:bg-white/10 focus:text-white"
                    >
                      {microphoneDevicesError ? "System Default Microphone" : "Default Microphone"}
                    </SelectItem>
                    {devices.map((device) => (
                      <SelectItem
                        key={device.deviceId}
                        value={device.deviceId}
                        className="text-xs focus:bg-white/10 focus:text-white"
                      >
                        {device.label}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </PopoverContent>
            </Popover>
            <Button
              variant="link"
              size="icon"
              onClick={toggleCamera}
              disabled={recording}
              title={cameraEnabled ? "Disable facecam" : "Enable facecam"}
              className={`text-white/80 hover:bg-transparent ${styles.tauriNoDrag}`}
            >
              {cameraEnabled ? <MdVideocam size={16} className="text-[#2563EB]" /> : <MdVideocamOff size={16} className="text-white/35" />}
            </Button>
          </div>

          <div className={dividerClass} />

          <Button
            variant="link"
            size="sm"
            onClick={hasSelectedSource ? toggleRecording : openSourceSelector}
            disabled={!hasSelectedSource && !recording}
            className={`gap-1 text-white bg-transparent hover:bg-transparent px-0 text-xs ${styles.tauriNoDrag}`}
          >
            {recording ? (
              <>
                <FaRegStopCircle size={14} className="text-red-400" />
                <span className="text-red-400 font-medium tabular-nums">{formatTime(elapsed)}</span>
              </>
            ) : (
              <>
                <BsRecordCircle size={14} className={hasSelectedSource ? "text-white/85" : "text-white/35"} />
                <span className={hasSelectedSource ? "text-white/80" : "text-white/35"}>Record</span>
              </>
            )}
          </Button>

          <Button
            variant="link"
            size="sm"
            onClick={chooseRecordingsDir}
            disabled={recording}
            title={recordingsDirectory ? `Recording folder: ${recordingsDirectory}` : "Choose recordings folder"}
            className={`text-white/75 hover:bg-transparent px-1 text-[11px] underline decoration-white/45 underline-offset-2 ${styles.tauriNoDrag}`}
          >
            <ContentClamp truncateLength={18}>{`Path: /${recordingsDirectoryName}/`}</ContentClamp>
          </Button>

          <div className="ml-auto flex items-center gap-0.5">
            <div className={dividerClass} />
            <Button
              variant="link"
              size="icon"
              onClick={openVideoFile}
              disabled={recording}
              title="Open video file"
              className={`text-white/70 hover:bg-transparent ${styles.tauriNoDrag}`}
            >
              <MdVideoFile size={15} />
            </Button>
            <Button
              variant="link"
              size="icon"
              onClick={openProjectFile}
              disabled={recording}
              title="Open project"
              className={`text-white/70 hover:bg-transparent ${styles.tauriNoDrag}`}
            >
              <FaFolderOpen size={14} />
            </Button>
            <div className={dividerClass} />
            <Button
              variant="link"
              size="icon"
              onClick={sendHudOverlayHide}
              title="Hide HUD"
              className={`text-white/70 hover:bg-transparent ${styles.tauriNoDrag}`}
            >
              <FiMinus size={16} />
            </Button>
            <Button
              variant="link"
              size="icon"
              onClick={sendHudOverlayClose}
              title="Close App"
              className={`text-white/70 hover:bg-transparent ${styles.tauriNoDrag}`}
            >
              <FiX size={16} />
            </Button>
          </div>
        </div>
      </div>
    </div>
  );
}
