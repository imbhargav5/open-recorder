import { createStore } from "jotai/vanilla";
import { describe, expect, it } from "vitest";
import {
  cameraDeviceIdAtom,
  cameraEnabledAtom,
  microphoneDeviceIdAtom,
  microphoneEnabledAtom,
  recordingActiveAtom,
  systemAudioEnabledAtom,
} from "./recording";

describe("recording atoms – write / read", () => {
  it("recordingActiveAtom can be set to true", () => {
    const store = createStore();
    store.set(recordingActiveAtom, true);
    expect(store.get(recordingActiveAtom)).toBe(true);
  });

  it("recordingActiveAtom can be toggled back to false", () => {
    const store = createStore();
    store.set(recordingActiveAtom, true);
    store.set(recordingActiveAtom, false);
    expect(store.get(recordingActiveAtom)).toBe(false);
  });

  it("microphoneEnabledAtom can be enabled then disabled", () => {
    const store = createStore();
    store.set(microphoneEnabledAtom, true);
    expect(store.get(microphoneEnabledAtom)).toBe(true);
    store.set(microphoneEnabledAtom, false);
    expect(store.get(microphoneEnabledAtom)).toBe(false);
  });

  it("microphoneDeviceIdAtom can be set to a device ID string", () => {
    const store = createStore();
    store.set(microphoneDeviceIdAtom, "device-abc-123");
    expect(store.get(microphoneDeviceIdAtom)).toBe("device-abc-123");
  });

  it("microphoneDeviceIdAtom can be cleared back to undefined", () => {
    const store = createStore();
    store.set(microphoneDeviceIdAtom, "device-abc-123");
    store.set(microphoneDeviceIdAtom, undefined);
    expect(store.get(microphoneDeviceIdAtom)).toBeUndefined();
  });

  it("microphoneDeviceIdAtom accepts empty string", () => {
    const store = createStore();
    store.set(microphoneDeviceIdAtom, "");
    expect(store.get(microphoneDeviceIdAtom)).toBe("");
  });

  it("systemAudioEnabledAtom can be toggled", () => {
    const store = createStore();
    store.set(systemAudioEnabledAtom, true);
    expect(store.get(systemAudioEnabledAtom)).toBe(true);
    store.set(systemAudioEnabledAtom, false);
    expect(store.get(systemAudioEnabledAtom)).toBe(false);
  });

  it("cameraEnabledAtom can be toggled", () => {
    const store = createStore();
    store.set(cameraEnabledAtom, true);
    expect(store.get(cameraEnabledAtom)).toBe(true);
  });

  it("cameraDeviceIdAtom can be set to a device ID string", () => {
    const store = createStore();
    store.set(cameraDeviceIdAtom, "cam-xyz-456");
    expect(store.get(cameraDeviceIdAtom)).toBe("cam-xyz-456");
  });

  it("cameraDeviceIdAtom can be cleared to undefined", () => {
    const store = createStore();
    store.set(cameraDeviceIdAtom, "cam-xyz-456");
    store.set(cameraDeviceIdAtom, undefined);
    expect(store.get(cameraDeviceIdAtom)).toBeUndefined();
  });

  it("microphone and camera device IDs are independent", () => {
    const store = createStore();
    store.set(microphoneDeviceIdAtom, "mic-1");
    store.set(cameraDeviceIdAtom, "cam-2");
    expect(store.get(microphoneDeviceIdAtom)).toBe("mic-1");
    expect(store.get(cameraDeviceIdAtom)).toBe("cam-2");
  });

  it("writes to one store do not affect another store", () => {
    const storeA = createStore();
    const storeB = createStore();

    storeA.set(recordingActiveAtom, true);
    storeA.set(microphoneEnabledAtom, true);
    storeA.set(microphoneDeviceIdAtom, "mic-1");
    storeA.set(cameraEnabledAtom, true);

    expect(storeB.get(recordingActiveAtom)).toBe(false);
    expect(storeB.get(microphoneEnabledAtom)).toBe(false);
    expect(storeB.get(microphoneDeviceIdAtom)).toBeUndefined();
    expect(storeB.get(cameraEnabledAtom)).toBe(false);
  });
});
