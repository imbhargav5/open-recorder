import type { ReactElement } from "react";
interface Props { sourceUrl: string }

export function RedesignCTA({ sourceUrl }: Props): ReactElement {
  return (
    <section className="rd-section rd-cta">
      <div className="rd-inner rd-cta-inner">
        <div className="rd-cta-copy" data-reveal>
          <p className="rd-eyebrow">Open source on GitHub</p>
          <p className="rd-cta-h2">Make your next product demo feel finished.</p>
        </div>
        <div data-reveal data-delay="150">
          <a
            className="rd-btn rd-btn-primary rd-btn-lg"
            href={sourceUrl}
            target="_blank"
            rel="noopener noreferrer"
          >
            View repository
          </a>
        </div>
      </div>
    </section>
  );
}
