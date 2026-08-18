"use client";
import { useEffect } from "react";

/**
 * Mounts once and:
 * 1. Observes all [data-reveal] elements to fade/slide in on scroll entry.
 * 2. Drives silky smooth [data-parallax] scroll offsets using requestAnimationFrame.
 */
export function MotionObserver(): null {
  useEffect(() => {
    // 1. Reveal observer
    const revealItems = document.querySelectorAll<HTMLElement>("[data-reveal]");
    if (revealItems.length) {
      const io = new IntersectionObserver(
        (entries) => {
          entries.forEach((entry) => {
            if (entry.isIntersecting) {
              const el = entry.target as HTMLElement;
              const delay = el.dataset.delay ?? "0";
              setTimeout(() => {
                el.setAttribute("data-visible", "true");
              }, Number(delay));
              io.unobserve(el);
            }
          });
        },
        { threshold: 0.1, rootMargin: "0px 0px -30px 0px" }
      );

      revealItems.forEach((el) => io.observe(el));
    }

    // 2. Parallax scroll handler
    const parallaxItems = document.querySelectorAll<HTMLElement>("[data-parallax]");
    if (!parallaxItems.length) return;

    let ticking = false;
    const onScroll = () => {
      if (!ticking) {
        window.requestAnimationFrame(() => {
          const vh = window.innerHeight;
          parallaxItems.forEach((el) => {
            const rect = el.getBoundingClientRect();
            if (rect.top < vh && rect.bottom > 0) {
              const speed = parseFloat(el.dataset.speed ?? "0.04");
              const centerY = rect.top + rect.height / 2;
              const offset = (centerY - vh / 2) * speed;
              el.style.transform = `translate3d(0, ${offset.toFixed(1)}px, 0)`;
            }
          });
          ticking = false;
        });
        ticking = true;
      }
    };

    window.addEventListener("scroll", onScroll, { passive: true });
    onScroll();

    return () => {
      window.removeEventListener("scroll", onScroll);
    };
  }, []);

  return null;
}
