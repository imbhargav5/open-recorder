import Image from "next/image";
import type { ReactElement } from "react";

export function RedesignNav(): ReactElement {
  return (
    <nav className="rd-nav" aria-label="Primary navigation">
      <div className="rd-nav-inner">
        <a className="rd-brand" href="/redesign" aria-label="Open Recorder home">
          <div className="rd-brand-icon-box">
            <Image src="/open-recorder-brand-image.png" alt="" width={20} height={20} priority unoptimized />
          </div>
          <span className="rd-brand-name">OPEN RECORDER</span>
        </a>


        <div className="rd-nav-links">
          <a className="rd-nav-link" href="#features">Features</a>
          <a className="rd-nav-link" href="#workflow">Workflow</a>
          <a className="rd-nav-link" href="#architecture">Architecture</a>
          <a
            className="rd-btn rd-btn-primary rd-btn-sm"
            href="https://docs.openrecorder.xyz/"
            target="_blank"
            rel="noopener noreferrer"
          >
            Docs
          </a>
        </div>
      </div>
    </nav>
  );
}
