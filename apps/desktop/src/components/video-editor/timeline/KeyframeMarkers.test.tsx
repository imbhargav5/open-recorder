// @vitest-environment jsdom

import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("dnd-timeline", () => ({
  useTimelineContext: () => ({
    sidebarWidth: 0,
    range: { start: 0, end: 10000 },
    valueToPixels: (v: number) => v / 10,
    pixelsToValue: (px: number) => px * 10,
  }),
}));

const { default: KeyframeMarkers } = await import("./KeyframeMarkers");

globalThis.IS_REACT_ACT_ENVIRONMENT = true;

async function flushEffects() {
  await act(async () => {
    await Promise.resolve();
    await new Promise((resolve) => setTimeout(resolve, 0));
  });
}

function fireMousMove(x = 100) {
  const event = new MouseEvent("mousemove", { bubbles: true, clientX: x });
  window.dispatchEvent(event);
}

describe("KeyframeMarkers – null ref guard", () => {
  let container: HTMLDivElement;
  let root: Root;

  beforeEach(() => {
    container = document.createElement("div");
    document.body.appendChild(container);
    root = createRoot(container);
  });

  afterEach(async () => {
    await act(async () => {
      root.unmount();
    });
    container.remove();
    document.body.style.cursor = "";
  });

  it("does not throw when timelineRef.current is null during mousemove", async () => {
    const timelineRef = { current: null as HTMLDivElement | null };
    const onKeyframeMove = vi.fn();

    await act(async () => {
      root.render(
        <KeyframeMarkers
          keyframes={[{ id: "kf1", time: 1000 }]}
          selectedKeyframeId={null}
          setSelectedKeyframeId={vi.fn()}
          onKeyframeMove={onKeyframeMove}
          videoDurationMs={5000}
          timelineRef={timelineRef as React.RefObject<HTMLDivElement>}
        />,
      );
    });
    await flushEffects();

    // Start a drag so the mousemove listener is registered
    const marker = container.querySelector("[title]");
    expect(marker).not.toBeNull();

    await act(async () => {
      marker!.dispatchEvent(
        new MouseEvent("mousedown", { bubbles: true, button: 0 }),
      );
    });
    await flushEffects();

    // Ensure ref is null (simulates unmount or rapid re-render)
    timelineRef.current = null;

    // Firing mousemove with a null ref should not throw
    expect(() => fireMousMove(200)).not.toThrow();

    // onKeyframeMove must NOT have been called when the ref was null
    expect(onKeyframeMove).not.toHaveBeenCalled();
  });

  it("does not throw when getBoundingClientRect throws during mousemove", async () => {
    const mockDiv = document.createElement("div");
    mockDiv.getBoundingClientRect = () => {
      throw new Error("layout not ready");
    };
    const timelineRef = { current: mockDiv as HTMLDivElement | null };
    const onKeyframeMove = vi.fn();

    await act(async () => {
      root.render(
        <KeyframeMarkers
          keyframes={[{ id: "kf2", time: 2000 }]}
          selectedKeyframeId={null}
          setSelectedKeyframeId={vi.fn()}
          onKeyframeMove={onKeyframeMove}
          videoDurationMs={5000}
          timelineRef={timelineRef as React.RefObject<HTMLDivElement>}
        />,
      );
    });
    await flushEffects();

    const marker = container.querySelector("[title]");
    expect(marker).not.toBeNull();

    await act(async () => {
      marker!.dispatchEvent(
        new MouseEvent("mousedown", { bubbles: true, button: 0 }),
      );
    });
    await flushEffects();

    // getBoundingClientRect will throw – the component should swallow it
    expect(() => fireMousMove(150)).not.toThrow();
    expect(onKeyframeMove).not.toHaveBeenCalled();
  });
});
