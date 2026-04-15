/**
 * Fixture preset: screen recording permission denied, others granted.
 *
 * Apply via configureHandlers(page, permissionsDenied()) before navigation.
 */
import type { PartialHandlerValues } from "../setup/shim-registry";

export function permissionsDenied(): PartialHandlerValues {
  return {
    get_screen_recording_permission_status: "denied",
    get_accessibility_permission_status: "granted",
    get_microphone_permission_status: "granted",
    get_camera_permission_status: "granted",
    request_screen_recording_permission: false,
  };
}
