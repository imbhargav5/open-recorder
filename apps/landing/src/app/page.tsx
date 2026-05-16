import Image from "next/image";

const proofPoints = [
  ["Native macOS", "Swift capture UI with system privacy flows"],
  ["Local-first", "Recordings stay under your Movies folder"],
  ["Open source", "Apache 2.0 with a small Swift + Rust stack"],
  ["Editor included", "Trim, preview, organize, and export"],
];

const featureHighlights = [
  {
    title: "Capture exactly what matters",
    eyebrow: "Display, window, or region",
    copy: "Choose a full display, a single app window, or draw a precise area before recording or taking a screenshot.",
  },
  {
    title: "Polish without a cloud detour",
    eyebrow: "Native editing flow",
    copy: "Preview recordings, keep project metadata organized, and move from rough capture to clean handoff on the same Mac.",
  },
  {
    title: "Export work you can trust",
    eyebrow: "Rust-backed bookkeeping",
    copy: "A durable local service handles paths, project registration, screenshot indexing, and export state behind the scenes.",
  },
];

const workflow = [
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
    title: "Preview and refine",
    copy: "Review captures in the native library, trim what is noisy, and keep the useful version close.",
  },
  {
    step: "04",
    title: "Export the handoff",
    copy: "Let the Rust service handle export bookkeeping so your final files stay clean and findable.",
  },
];

const architectureNotes = [
  {
    label: "Swift app",
    value: "Capture UI, AVKit playback, Finder integration, privacy prompts",
  },
  {
    label: "Rust service",
    value: "Project metadata, path handling, screenshot indexing, exports",
  },
  {
    label: "Local paths",
    value: "~/Movies/Open Recorder and ~/Pictures/Open Recorder",
  },
];

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
            <a href="https://github.com/imbhargav5/open-recorder">GitHub</a>
          </div>
        </div>
      </nav>

      <section className="hero-section" id="top">
        <div className="section-inner hero-inner">
          <p className="eyebrow">Native macOS capture studio</p>
          <h1>Open Recorder</h1>
          <p className="hero-lede">
            Record your screen, capture screenshots, trim the useful parts, and
            export clean handoffs without sending your work through a cloud
            pipeline.
          </p>
          <div className="hero-actions">
            <a className="primary-action" href="https://github.com/imbhargav5/open-recorder">
              Get the source
            </a>
            <a className="secondary-action" href="#features">
              See the workflow
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
            <h2>A small native toolchain for polished demos and documentation.</h2>
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
