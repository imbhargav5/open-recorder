# Export Dialog Gap Analysis

Compared against the Electron editor from commit `c4882a1` (`apps/desktop/src/components/video-editor/VideoEditor.tsx` and `ExportDialog.tsx`), the Swift video export flow had regressed to an immediate save-panel export with no pre-export controls.

## Restored in this change

- Video export now opens a Swift export dialog instead of immediately exporting.
- MOV is the currently supported video format.
- Resolution choices are available for Source, 2K, and 4K exports.
- Frame-rate choices are available for Source, 24 FPS, 30 FPS, and 60 FPS MOV exports.
- Export progress is shown while the MOV render runs.
- Rendering exports can be canceled from the progress UI.
- Completed exports can be revealed in Finder.
- If the save panel is canceled after rendering, the completed temporary export is retained and can be saved again without re-exporting.

## Still missing from the legacy Electron export experience

- MP4 output format selection.
- GIF output format selection.
- MP4 quality presets from the old quick settings popover: Low, Medium, and High/source.
- GIF frame-rate choices: 15, 20, 25, and 30 FPS.
- GIF size presets: Medium, Large, and Original.
- GIF loop toggle.
