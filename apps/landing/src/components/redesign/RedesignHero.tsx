import Image from "next/image";
import type { ReactElement } from "react";

interface Props {
  docsUrl: string;
  sourceUrl: string;
}

export function RedesignHero({ docsUrl, sourceUrl }: Props): ReactElement {
  return (
    <section className="rd-hero" id="top">
      {/* Radiant bottom-left warm gradient bloom (matching inspiration) */}
      <div className="rd-hero-bloom" aria-hidden="true" />
      {/* Subtle architectural dot/line grid */}
      <div className="rd-hero-grid" aria-hidden="true" />

      <div className="rd-inner rd-hero-layout">
        {/* Left Column: Heading, Lead, CTAs, and Metadata */}
        <div className="rd-hero-left">
          <p className="rd-hero-tag">//01 LOCAL-FIRST MACOS</p>

          <h1 className="rd-hero-title">
            The native<br />
            recorder
          </h1>

          <p className="rd-hero-lead">
            A native screen recorder and timeline editor built specifically for macOS.
            Capture full displays, app windows, or exact regions with hardware-accelerated
            framerate and crystal clarity. No accounts. No cloud uploads.
          </p>

          <div className="rd-hero-actions">
            <a
              className="rd-btn rd-btn-primary rd-btn-md"
              href={docsUrl}
              target="_blank"
              rel="noopener noreferrer"
            >
              Get started
            </a>
            <a
              className="rd-btn rd-btn-outline rd-btn-md"
              href={sourceUrl}
              target="_blank"
              rel="noopener noreferrer"
            >
              <GitHubIcon />
              Source
            </a>
          </div>

          <div className="rd-hero-meta-grid">
            <div className="rd-hero-meta-item">
              <span className="rd-hero-meta-label">ENGINE</span>
              <span className="rd-hero-meta-val">Swift 6 · Rust</span>
            </div>
            <div className="rd-hero-meta-item">
              <span className="rd-hero-meta-label">PIPELINE</span>
              <span className="rd-hero-meta-val">100% Local-First</span>
            </div>
            <div className="rd-hero-meta-item">
              <span className="rd-hero-meta-label">LICENSE</span>
              <span className="rd-hero-meta-val">Apache 2.0</span>
            </div>
          </div>
        </div>

        {/* Right Column: Large Cinematic Video Showcase */}
        <div className="rd-hero-right">
          <div className="rd-hero-media-wrap">
            <span className="rd-hero-glow" aria-hidden="true" />
            <div className="rd-hero-media">
              <div className="rd-hero-media-chrome" aria-hidden="true">
                <span className="rd-chrome-dot" />
                <span className="rd-chrome-dot" />
                <span className="rd-chrome-dot" />
                <span className="rd-chrome-title">Open Recorder · Studio</span>
              </div>
              <Image
                src="/open-recorder-demo.gif"
                alt="Open Recorder showing a macOS capture and edit workflow"
                width={1280}
                height={720}
                priority
                unoptimized
              />
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}

function GitHubIcon(): ReactElement {
  return (
    <svg aria-hidden="true" viewBox="0 0 24 24" fill="currentColor">
      <path d="M12 .5C5.65.5.5 5.65.5 12c0 5.09 3.29 9.4 7.86 10.92.58.11.79-.25.79-.56 0-.28-.01-1.02-.02-2-3.2.7-3.88-1.54-3.88-1.54-.52-1.33-1.28-1.69-1.28-1.69-1.05-.72.08-.7.08-.7 1.16.08 1.77 1.19 1.77 1.19 1.03 1.77 2.7 1.26 3.36.96.1-.75.4-1.26.73-1.55-2.56-.29-5.25-1.28-5.25-5.69 0-1.26.45-2.28 1.19-3.09-.12-.29-.52-1.47.11-3.05 0 0 .97-.31 3.17 1.18.92-.26 1.9-.38 2.88-.39.98 0 1.96.13 2.88.39 2.2-1.49 3.17-1.18 3.17-1.18.63 1.58.23 2.76.11 3.05.74.81 1.19 1.83 1.19 3.09 0 4.42-2.7 5.39-5.27 5.68.42.36.79 1.07.79 2.16 0 1.56-.01 2.82-.01 3.2 0 .31.21.68.8.56A11.51 11.51 0 0 0 23.5 12C23.5 5.65 18.35.5 12 .5Z" />
    </svg>
  );
}
