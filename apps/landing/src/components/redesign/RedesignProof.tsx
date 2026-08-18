import type { ReactElement } from "react";

const proofPoints = [
  { label: "Native macOS",    desc: "Swift capture UI with system privacy flows" },
  { label: "Local-first",     desc: "Recordings and projects stay on your Mac" },
  { label: "Open source",     desc: "Apache 2.0 · Swift + Rust stack" },
  { label: "Editor included", desc: "Zooms, camera clips, cursor overlays, exports" },
] as const;

export function RedesignProof(): ReactElement {
  return (
    <section className="rd-proof" aria-label="Project highlights">
      <div className="rd-inner rd-proof-grid">
        {proofPoints.map((p, i) => (
          <div
            className="rd-proof-item"
            key={p.label}
            data-reveal
            data-delay={i * 80}
          >
            <span className="rd-proof-label">{p.label}</span>
            <span className="rd-proof-desc">{p.desc}</span>
          </div>
        ))}
      </div>
    </section>
  );
}
