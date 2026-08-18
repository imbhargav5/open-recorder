import type { ReactElement } from "react";

const features = [
  {
    eyebrow: "Capture",
    title: "Capture exactly what matters",
    copy: "Choose a full display, a single app window, or draw a precise area with microphone, system audio, camera, cursor, and click controls.",
    icon: <CaptureIcon />,
  },
  {
    eyebrow: "Edit",
    title: "Shape the story on the timeline",
    copy: "Add manual or automatic zoom sections, split clips, tune playback speed, style cursor motion, and place facecam segments independently.",
    icon: <EditIcon />,
  },
  {
    eyebrow: "Export",
    title: "Compose the final handoff",
    copy: "Crop and reframe videos for fixed aspect layouts, compose screenshots on styled backgrounds, and export MOV, MP4, GIF, or PNG outputs.",
    icon: <ExportIcon />,
  },
];

export function RedesignFeatures(): ReactElement {
  return (
    <section className="rd-section" id="features">
      <div className="rd-inner">
        <div className="rd-section-head" data-reveal>
          <p className="rd-eyebrow">Capture · Edit · Export</p>
          <h2 className="rd-h2">A native capture studio for polished demos, docs, and share-ready clips.</h2>
        </div>

        <div className="rd-features-grid">
          {features.map((f, i) => (
            <article
              className="rd-feature-card"
              key={f.title}
              data-reveal="scale"
              data-delay={i * 100}
            >
              <div className="rd-feature-icon" aria-hidden="true">{f.icon}</div>
              <p className="rd-feature-eyebrow">{f.eyebrow}</p>
              <h3 className="rd-feature-title">{f.title}</h3>
              <p className="rd-feature-copy">{f.copy}</p>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}

function CaptureIcon(): ReactElement {
  return (
    <svg viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.5" width="20" height="20" aria-hidden="true">
      <rect x="2" y="5" width="16" height="11" />
      <path d="M7 5V3h6v2" />
      <circle cx="10" cy="10.5" r="2.5" />
    </svg>
  );
}

function EditIcon(): ReactElement {
  return (
    <svg viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.5" width="20" height="20" aria-hidden="true">
      <path d="M2 15h16M2 11h10M2 7h6" />
      <rect x="12" y="8" width="6" height="3" fill="currentColor" stroke="none" opacity="0.3" />
      <path d="M12 8h6v3h-6z" strokeWidth="1" />
    </svg>
  );
}

function ExportIcon(): ReactElement {
  return (
    <svg viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.5" width="20" height="20" aria-hidden="true">
      <path d="M10 3v9M7 6l3-3 3 3" />
      <path d="M4 13v3h12v-3" />
    </svg>
  );
}
