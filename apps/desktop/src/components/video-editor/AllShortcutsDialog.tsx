import { useShortcuts } from "@/contexts/ShortcutsContext";
import { formatBinding, SHORTCUT_ACTIONS, SHORTCUT_LABELS } from "@/lib/shortcuts";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from "@/components/ui/dialog";

interface AllShortcutsDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

interface ShortcutEntry {
  label: string;
  mac: string;
  other: string;
}

export function AllShortcutsDialog({ open, onOpenChange }: AllShortcutsDialogProps) {
  const { shortcuts, isMac } = useShortcuts();

  const fileShortcuts: ShortcutEntry[] = [
    { label: "Open Project", mac: "⌘ + O", other: "Ctrl + O" },
    { label: "Save Project", mac: "⌘ + S", other: "Ctrl + S" },
    { label: "Save Project As", mac: "⌘ + ⇧ + S", other: "Ctrl + Shift + S" },
  ];

  const editShortcuts: ShortcutEntry[] = [
    { label: "Undo", mac: "⌘ + Z", other: "Ctrl + Z" },
    { label: "Redo", mac: "⌘ + ⇧ + Z", other: "Ctrl + Y" },
  ];

  const editorShortcuts: ShortcutEntry[] = SHORTCUT_ACTIONS.map((action) => ({
    label: SHORTCUT_LABELS[action],
    mac: formatBinding(shortcuts[action], true),
    other: formatBinding(shortcuts[action], false),
  }));

  const navigationShortcuts: ShortcutEntry[] = [
    { label: "Cycle Annotations Forward", mac: "Tab", other: "Tab" },
    { label: "Cycle Annotations Backward", mac: "⇧ + Tab", other: "Shift + Tab" },
    { label: "Delete Selected (alt)", mac: "Del / ⌫", other: "Del / Backspace" },
    {
      label: "Pan Timeline",
      mac: "⇧ + ⌘ + Scroll",
      other: "Shift + Ctrl + Scroll",
    },
    {
      label: "Zoom Timeline",
      mac: "⌘ + Scroll",
      other: "Ctrl + Scroll",
    },
  ];

  const sections = [
    { title: "File", shortcuts: fileShortcuts },
    { title: "Edit", shortcuts: editShortcuts },
    { title: "Editor", shortcuts: editorShortcuts },
    { title: "Navigation", shortcuts: navigationShortcuts },
  ];

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md bg-[#09090b] border-white/10 text-slate-200">
        <DialogHeader>
          <DialogTitle className="text-sm font-semibold text-slate-100">
            Keyboard Shortcuts
          </DialogTitle>
          <DialogDescription className="text-xs text-slate-500">
            {isMac ? "Showing macOS shortcuts" : "Showing Windows / Linux shortcuts"}
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4 max-h-[60vh] overflow-y-auto pr-1">
          {sections.map((section) => (
            <div key={section.title}>
              <h3 className="text-[11px] font-semibold text-slate-400 uppercase tracking-wider mb-2">
                {section.title}
              </h3>
              <div className="space-y-1">
                {section.shortcuts.map((shortcut) => (
                  <div
                    key={shortcut.label}
                    className="flex items-center justify-between py-1 px-2 rounded hover:bg-white/5"
                  >
                    <span className="text-xs text-slate-300">{shortcut.label}</span>
                    <kbd className="px-1.5 py-0.5 bg-white/5 border border-white/10 rounded text-[11px] text-[#2563EB] font-mono min-w-[40px] text-center">
                      {isMac ? shortcut.mac : shortcut.other}
                    </kbd>
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>
      </DialogContent>
    </Dialog>
  );
}
