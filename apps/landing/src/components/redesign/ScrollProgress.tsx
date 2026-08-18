"use client";
import { useEffect, useRef } from "react";

export function ScrollProgress(): React.ReactElement {
  const barRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const update = () => {
      const el = barRef.current;
      if (!el) return;
      const total = document.documentElement.scrollHeight - window.innerHeight;
      const pct = total > 0 ? (window.scrollY / total) * 100 : 0;
      el.style.width = `${pct}%`;
    };
    window.addEventListener("scroll", update, { passive: true });
    return () => window.removeEventListener("scroll", update);
  }, []);

  return (
    <div className="rd-progress" aria-hidden="true">
      <div className="rd-progress-bar" ref={barRef} />
    </div>
  );
}
