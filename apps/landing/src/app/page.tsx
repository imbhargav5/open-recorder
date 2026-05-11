import Image from "next/image";

const featureVideos = [
  {
    title: "Capture the exact moment",
    eyebrow: "Display, window, or area",
    poster: "/feature-capture.svg",
    copy: "Choose a full display, a single window, or draw an interactive region before recording or taking a screenshot.",
  },
  {
    title: "Edit without leaving the app",
    eyebrow: "Timeline and screenshot studio",
    poster: "/feature-editor.svg",
    copy: "Trim recordings, crop, adjust playback speed, style screenshots, and keep every project organized locally.",
  },
  {
    title: "Export clean deliverables",
    eyebrow: "Native Swift with Rust backup",
    poster: "/feature-export.svg",
    copy: "Open Recorder tracks project metadata and exports through a small Rust service built for durable local workflows.",
  },
];

const stats = [
  ["macOS", "Native Swift app"],
  ["Apache 2.0", "Open-source license"],
  ["Local-first", "Projects stay on your Mac"],
];

const workflow = [
  "Pick a source",
  "Record or screenshot",
  "Polish the result",
  "Export and share",
];

export default function Home() {
  return (
    <main>
      <section className="hero-section">
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
            <a href="https://github.com/imbhargav5/open-recorder">GitHub</a>
          </div>
        </nav>

        <div className="hero-grid" id="top">
          <div className="hero-copy">
            <p className="eyebrow">macOS screen recording, screenshots, and editing</p>
            <h1>Open Recorder</h1>
            <p className="hero-lede">
              A native, local-first capture studio for makers who need polished
              recordings and screenshots without sending their work through a cloud
              pipeline.
            </p>
            <div className="hero-actions">
              <a className="primary-action" href="#features">
                See features
              </a>
              <a
                className="secondary-action"
                href="https://github.com/imbhargav5/open-recorder"
              >
                View source
              </a>
            </div>
          </div>

          <div className="hero-product" aria-label="Open Recorder product preview">
            <div className="window-bar">
              <span />
              <span />
              <span />
            </div>
            <div className="preview-stage">
              <div className="capture-frame">
                <div className="capture-target" />
                <div className="capture-panel">
                  <span>Area capture</span>
                  <strong>Recording in 3...</strong>
                </div>
              </div>
              <div className="timeline">
                <span />
                <span />
                <span />
                <span />
              </div>
            </div>
          </div>
        </div>
      </section>

      <section className="stats-band" aria-label="Project highlights">
        {stats.map(([value, label]) => (
          <div key={value}>
            <strong>{value}</strong>
            <span>{label}</span>
          </div>
        ))}
      </section>

      <section className="section-shell" id="features">
        <div className="section-heading">
          <p className="eyebrow">Feature previews</p>
          <h2>Everything needed for a clean capture workflow.</h2>
        </div>
        <div className="feature-grid">
          {featureVideos.map((feature) => (
            <article className="feature-card" key={feature.title}>
              <video
                aria-label={`${feature.title} placeholder video`}
                className="feature-video"
                controls
                poster={feature.poster}
                preload="none"
              />
              <div className="feature-copy">
                <p>{feature.eyebrow}</p>
                <h3>{feature.title}</h3>
                <span>{feature.copy}</span>
              </div>
            </article>
          ))}
        </div>
      </section>

      <section className="workflow-band" id="workflow">
        <div className="workflow-copy">
          <p className="eyebrow">Built for repeated work</p>
          <h2>From capture to export in one native flow.</h2>
        </div>
        <ol className="workflow-list">
          {workflow.map((item, index) => (
            <li key={item}>
              <span>{String(index + 1).padStart(2, "0")}</span>
              {item}
            </li>
          ))}
        </ol>
      </section>

      <section className="details-section">
        <div>
          <p className="eyebrow">Local-first architecture</p>
          <h2>Swift where the Mac matters. Rust where durability matters.</h2>
        </div>
        <p>
          Open Recorder uses Swift for the capture UI, recording controls,
          screenshot flow, playback, and Finder/privacy integrations. A Rust
          service handles paths, project metadata, recording registration,
          screenshot indexing, and export bookkeeping.
        </p>
      </section>
    </main>
  );
}
