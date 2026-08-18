import type { ReactElement } from "react";

export function RedesignFooter(): ReactElement {
  return (
    <footer className="rd-footer">
      <div className="rd-inner rd-footer-inner">
        <span className="rd-footer-brand">Open Recorder</span>
        <span className="rd-footer-copy">Apache 2.0 · Built with Swift and Rust</span>
      </div>
    </footer>
  );
}
