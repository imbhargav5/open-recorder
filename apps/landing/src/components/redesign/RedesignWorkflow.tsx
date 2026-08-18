import type { ReactElement } from "react";
import { StepList } from "./StepList";

const steps = [
  { number: "01", title: "Choose the source", description: "Pick a display, window, or hand-drawn region with a capture flow built natively for macOS." },
  { number: "02", title: "Record or screenshot", description: "Save clips to Movies and screenshots to Pictures with project metadata created automatically." },
  { number: "03", title: "Edit the timeline", description: "Refine clips with trims, speed changes, zoom effects, cursor overlays, and independently controlled camera segments." },
  { number: "04", title: "Export or compose", description: "Export MOV, MP4, GIF, or PNG assets with crop and aspect controls, styled backgrounds, and screenshot composition." },
] as const;

export function RedesignWorkflow(): ReactElement {
  return (
    <section className="rd-section rd-workflow" id="workflow">
      <div className="rd-inner rd-workflow-inner">
        <div className="rd-workflow-copy" data-reveal="left">
          <p className="rd-eyebrow">Built for repeated work</p>
          <h2 className="rd-h2">Every capture moves through one calm, local flow.</h2>
          <p className="rd-body">
            No accounts, no uploads, no cloud processing. Everything lives in
            your Movies and Pictures folders, organised by project.
          </p>
        </div>

        <StepList steps={steps} />
      </div>
    </section>
  );
}
