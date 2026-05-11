import Image from "next/image";

const proofPoints = [
  ["Native macOS", "Swift capture UI with system privacy flows"],
  ["Local-first", "Captures stay under your Pictures folder"],
  ["Open source", "Apache 2.0 with a small Swift + Rust stack"],
  ["Editor included", "Trim, preview, organize, and export"],
];

const featureHighlights = [
  {
    title: "Capture exactly what matters",
    eyebrow: "Display, window, or region",
    poster: "/feature-capture.svg",
    copy: "Choose a full display, a single app window, or draw a precise area before saving a polished screenshot.",
  },
  {
    title: "Polish without a cloud detour",
    eyebrow: "Native editing flow",
    poster: "/feature-editor.svg",
    copy: "Preview captures, keep project metadata organized, and move from rough screenshot to clean handoff on the same Mac.",
  },
  {
    title: "Export work you can trust",
    eyebrow: "Rust-backed bookkeeping",
    poster: "/feature-export.svg",
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
    title: "Capture and save",
    copy: "Save screenshots to Pictures with project metadata created automatically.",
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
    value: "Screenshot capture UI, Finder integration, privacy prompts",
  },
  {
    label: "Rust service",
    value: "Project metadata, path handling, screenshot indexing, exports",
  },
  {
    label: "Local paths",
    value: "~/Pictures/Open Recorder",
  },
];

export default function Home() {
  return (
    <main>
      <section className="hero-section" id="top">
        <nav className="top-nav" aria-label="Primary navigation">
          <a className="brand-mark" href="#top" aria-label="Open Recorder home">
            <Image
              src="/open-recorder-brand-image.png"
              alt=""
              width={44}
              height={44}
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
        </nav>

        <div className="hero-copy">
          <p className="eyebrow">Native macOS capture studio</p>
          <h1>Open Recorder</h1>
          <p className="hero-lede">
            Capture screenshots, polish the useful context, and export clean
            handoffs without sending your work through a cloud pipeline.
          </p>
          <div className="hero-actions">
            <a className="primary-action" href="https://github.com/imbhargav5/open-recorder">
              Get the source
            </a>
            <a className="secondary-action" href="#features">
              See the workflow
            </a>
          </div>
        </div>

        <div className="hero-media" aria-label="Open Recorder product preview">
          <div className="product-window">
            <div className="window-bar" aria-hidden="true">
              <span />
              <span />
              <span />
            </div>
            <div className="static-preview">
              <div className="preview-rail" aria-hidden="true">
                <span />
                <span />
                <span />
                <span />
              </div>
              <div className="preview-board">
                <div className="preview-card-large">
                  <Image
                    src="/open-recorder-brand-image.png"
                    alt=""
                    width={86}
                    height={86}
                    priority
                    unoptimized
                  />
                  <div>
                    <span>Screenshot library</span>
                    <strong>Local captures, ready to polish</strong>
                  </div>
                </div>
                <div className="capture-selection" aria-hidden="true">
                  <span />
                  <span />
                  <span />
                  <span />
                </div>
              </div>
              <div className="preview-side">
                <strong>Export queue</strong>
                <span>3 local assets</span>
                <div className="preview-meter">
                  <span />
                </div>
              </div>
            </div>
          </div>

          <div className="capture-pill" aria-hidden="true">
            <span />
            <div>
              <strong>Screenshot mode</strong>
              <small>Source selected</small>
            </div>
          </div>

          <div className="export-panel" aria-hidden="true">
            <div />
            <div />
            <div />
            <span />
          </div>
        </div>
      </section>

      <section className="proof-band" aria-label="Project highlights">
        <div className="proof-grid">
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
            <h2>A small native toolchain for polished docs and bug reports.</h2>
          </div>

          <div className="feature-grid">
            {featureHighlights.map((feature) => (
              <article className="feature-card" key={feature.title}>
                <div className="feature-visual">
                  <Image
                    src={feature.poster}
                    alt=""
                    width={760}
                    height={480}
                    unoptimized
                  />
                </div>
                <div className="feature-copy">
                  <p>{feature.eyebrow}</p>
                  <h3>{feature.title}</h3>
                  <span>{feature.copy}</span>
                </div>
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
          <Image
            src="/open-recorder-brand-image.png"
            alt=""
            width={76}
            height={76}
            unoptimized
          />
          <div>
            <p className="eyebrow">Open source on GitHub</p>
            <h2>Make your next product handoff feel finished.</h2>
          </div>
          <a className="primary-action" href="https://github.com/imbhargav5/open-recorder">
            View repository
          </a>
        </div>
      </section>
    </main>
  );
}
