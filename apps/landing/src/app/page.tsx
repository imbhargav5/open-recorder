import Image from "next/image";

const docsUrl = "https://docs.openrecorder.xyz/";
const sourceUrl = "https://github.com/imbhargav5/open-recorder";

type ProofPoint = readonly [value: string, label: string];

type LandingContentBlock = Readonly<{
  title: string;
  eyebrow: string;
  copy: string;
}>;

type WorkflowStep = Readonly<{
  step: string;
  title: string;
  copy: string;
}>;

type ArchitectureNote = Readonly<{
  label: string;
  value: string;
}>;

const proofPoints: readonly ProofPoint[] = [
  ["Native macOS", "Swift capture UI with system privacy flows"],
  ["Local-first", "Recordings and projects stay on your Mac"],
  ["Open source", "Apache 2.0 with a small Swift + Rust stack"],
  ["Editor included", "Zooms, camera clips, cursor overlays, and exports"],
];

const featureHighlights: readonly LandingContentBlock[] = [
  {
    title: "Capture exactly what matters",
    eyebrow: "Display, window, or region",
    copy: "Choose a full display, a single app window, or draw a precise area with microphone, system audio, camera, cursor, and click controls.",
  },
  {
    title: "Shape the story on the timeline",
    eyebrow: "Zooms, clips, cursor, camera",
    copy: "Add manual or automatic zoom sections, split clips, tune playback speed, style cursor motion, and place facecam segments independently.",
  },
  {
    title: "Compose the final handoff",
    eyebrow: "Crop, aspect, screenshot, export",
    copy: "Crop and reframe videos for fixed aspect layouts, compose screenshots on styled backgrounds, and export MOV, MP4, GIF, or PNG outputs.",
  },
];

const workflow: readonly WorkflowStep[] = [
  {
    step: "01",
    title: "Choose the source",
    copy: "Pick a display, window, or hand-drawn region with a capture flow built for macOS.",
  },
  {
    step: "02",
    title: "Record or screenshot",
    copy: "Save clips to Movies and screenshots to Pictures with project metadata created automatically.",
  },
  {
    step: "03",
    title: "Edit the timeline",
    copy: "Refine clips with trims, speed changes, zoom effects, cursor overlays, and independently controlled camera segments.",
  },
  {
    step: "04",
    title: "Export or compose",
    copy: "Export MOV, MP4, GIF, or PNG assets with crop and aspect controls, styled backgrounds, and screenshot composition.",
  },
];

const architectureNotes: readonly ArchitectureNote[] = [
  {
    label: "Swift app",
    value: "Capture UI, editor timeline, screenshot composition, Finder integration",
  },
  {
    label: "Rust service",
    value: "Project metadata, path handling, screenshot indexing, exports",
  },
  {
    label: "Local paths",
    value: "~/Movies/Open Recorder, ~/Pictures/Open Recorder, and local project files",
  },
];

function GitHubIcon() {
  return (
    <svg
      aria-hidden="true"
      width="18"
      height="18"
      viewBox="0 0 24 24"
      fill="currentColor"
      focusable="false"
    >
      <path d="M12 .5C5.65.5.5 5.65.5 12c0 5.09 3.29 9.4 7.86 10.92.58.11.79-.25.79-.56 0-.28-.01-1.02-.02-2-3.2.7-3.88-1.54-3.88-1.54-.52-1.33-1.28-1.69-1.28-1.69-1.05-.72.08-.7.08-.7 1.16.08 1.77 1.19 1.77 1.19 1.03 1.77 2.7 1.26 3.36.96.1-.75.4-1.26.73-1.55-2.56-.29-5.25-1.28-5.25-5.69 0-1.26.45-2.28 1.19-3.09-.12-.29-.52-1.47.11-3.05 0 0 .97-.31 3.17 1.18.92-.26 1.9-.38 2.88-.39.98 0 1.96.13 2.88.39 2.2-1.49 3.17-1.18 3.17-1.18.63 1.58.23 2.76.11 3.05.74.81 1.19 1.83 1.19 3.09 0 4.42-2.7 5.39-5.27 5.68.42.36.79 1.07.79 2.16 0 1.56-.01 2.82-.01 3.2 0 .31.21.68.8.56A11.51 11.51 0 0 0 23.5 12C23.5 5.65 18.35.5 12 .5Z" />
    </svg>
  );
}

export default function Home() {
  return (
    <main>
      <nav className="top-nav" aria-label="Primary navigation">
        <div className="nav-inner">
          <a className="brand-mark" href="#top" aria-label="Open Recorder home">
            <Image
              src="/open-recorder-brand-image.png"
              alt=""
              width={28}
              height={28}
              priority
              unoptimized
            />
            <span>Open Recorder</span>
          </a>
          <div className="nav-links">
            <a href="#features">Features</a>
            <a href="#workflow">Workflow</a>
            <a href="#architecture">Architecture</a>
            <a href={docsUrl} target="_blank" rel="noreferrer">
              <span className="primary-action">Docs</span>
            </a>
          </div>
        </div>
      </nav>

      <section className="hero-section" id="top">
        <div className="section-inner hero-inner">
          <p className="eyebrow">Native macOS capture studio</p>
          <h1>Open Recorder</h1>
          <p className="hero-lede">
            Record your screen, capture screenshots, shape zooms, cursor, and
            camera on a native timeline, then export polished MOV, MP4, GIF, or
            PNG handoffs without a cloud pipeline.
          </p>
          <div className="hero-actions">
            <a className="primary-action" href={docsUrl} target="_blank" rel="noreferrer">
              Docs
            </a>
            <a className="secondary-action" href={sourceUrl}>
              <GitHubIcon /> Source
            </a>
          </div>

          <div className="hero-media" aria-label="Open Recorder product demo">
            <Image
              src="/open-recorder-demo.gif"
              alt="Open Recorder app demo showing a macOS capture workflow"
              width={1280}
              height={720}
              priority
              unoptimized
            />
          </div>
        </div>
      </section>

      <section className="proof-band" aria-label="Project highlights">
        <div className="section-inner proof-grid">
          {proofPoints.map(([value, label]) => (
            <div className="proof-item" key={value}>
              <strong>{value}</strong>
              <span>{label}</span>
            </div>
          ))}
        </div>
      </section>

      <section className="section-shell feature-section" id="features">
        <div className="section-inner">
          <div className="section-heading">
            <p className="eyebrow">Capture, edit, export</p>
            <h2>A native capture studio for polished demos, docs, and share-ready clips.</h2>
          </div>

          <div className="feature-grid">
            {featureHighlights.map((feature) => (
              <article className="feature-card" key={feature.title}>
                <p>{feature.eyebrow}</p>
                <h3>{feature.title}</h3>
                <span>{feature.copy}</span>
              </article>
            ))}
          </div>
        </div>
      </section>

      <section className="workflow-section" id="workflow">
        <div className="section-inner workflow-inner">
          <div className="workflow-copy">
            <p className="eyebrow">Built for repeated work</p>
            <h2>Every capture moves through one calm, local flow.</h2>
          </div>

          <ol className="workflow-list">
            {workflow.map((item) => (
              <li key={item.step}>
                <span>{item.step}</span>
                <div>
                  <h3>{item.title}</h3>
                  <p>{item.copy}</p>
                </div>
              </li>
            ))}
          </ol>
        </div>
      </section>

      <section className="architecture-section" id="architecture">
        <div className="section-inner architecture-inner">
          <div>
            <p className="eyebrow">Local-first architecture</p>
            <h2>Swift where the Mac matters. Rust where durability matters.</h2>
          </div>

          <div className="architecture-panel">
            {architectureNotes.map((note) => (
              <div className="architecture-row" key={note.label}>
                <strong>{note.label}</strong>
                <span>{note.value}</span>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section className="closing-section">
        <div className="section-inner closing-inner">
          <div>
            <p className="eyebrow">Open source on GitHub</p>
            <h2>Make your next product demo feel finished.</h2>
          </div>
          <a className="primary-action" href="https://github.com/imbhargav5/open-recorder">
            View repository
          </a>
        </div>
      </section>

      <footer className="site-footer">
        <div className="section-inner footer-inner">
          <span>Open Recorder</span>
          <span>Apache 2.0 · Built with Swift and Rust</span>
        </div>
      </footer>
    </main>
  );
}
