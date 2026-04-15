/**
 * Fixture preset: all permissions granted.
 *
 * Apply via configureHandlers(page, permissionsGranted()) before navigation.
 */
import type { PartialHandlerValues } from "../setup/shim-registry";

export function permissionsGranted(): PartialHandlerValues {
  return {
    get_screen_recording_permission_status: "granted",
    get_accessibility_permission_status: "granted",
    get_microphone_permission_status: "granted",
    get_camera_permission_status: "granted",
    request_screen_recording_permission: true,
    request_accessibility_permission: true,
    request_microphone_permission: true,
    request_camera_permission: true,
  };
}
