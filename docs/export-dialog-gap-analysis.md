# Export Dialog Gap Analysis

Compared against the Electron editor from commit `c4882a1` (`apps/desktop/src/components/video-editor/VideoEditor.tsx` and `ExportDialog.tsx`), the Swift video export flow had regressed to an immediate save-panel export with no pre-export controls.

## Restored in this change

- Video export now opens a Swift export dialog instead of immediately exporting.
- MOV, MP4, and GIF export formats are available.
- Resolution choices are available for 480p, 720p, 1080p, and 4K movie exports.
- Frame-rate choices are available for 15, 24, 30, and 60 FPS movie exports.
- MP4 quality choices are available for Low, Medium, and High/source exports.
- GIF size choices are available for Medium, Large, and Original exports.
- GIF frame-rate choices are available for 15, 20, 25, and 30 FPS.
- GIF looping can be toggled per export.
- Export progress is shown while the render runs.
- Rendering exports can be canceled from the progress UI.
- Completed exports can be revealed in Finder.
- If the save panel is canceled after rendering, the completed temporary export is retained and can be saved again without re-exporting.
