import type { ReactElement } from "react";

export type Step = {
  number?: string; // "01" — omit for rows without numbers (Swift app / Rust service)
  title: string;
  description: string;
};

interface Props {
  steps: readonly Step[];
  parallax?: boolean;
}

export function StepList({ steps, parallax = true }: Props): ReactElement {
  return (
    <div
      className="step-list"
      data-reveal="right"
      {...(parallax ? { "data-parallax": "true", "data-speed": "0.04" } : {})}
    >
      {steps.map((step, i) => (
        <div
          key={step.title}
          className="step-row"
          style={{ transitionDelay: `${i * 60}ms` }}
        >
          {step.number && (
            <span className="step-number rd-mono">
              {step.number}
            </span>
          )}
          <div className="step-content">
            <h3>{step.title}</h3>
            <p>{step.description}</p>
          </div>
        </div>
      ))}
    </div>
  );
}
