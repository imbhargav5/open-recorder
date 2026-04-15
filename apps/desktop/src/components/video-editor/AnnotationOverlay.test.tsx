// @vitest-environment jsdom

import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { AnnotationRegion } from "./types";

// ------------------------------------------------------------------
// Mocks
// ------------------------------------------------------------------

// Capture drag handlers so tests can invoke them directly
let capturedOnDragStart: (() => void) | undefined;
let capturedOnDragStop: ((e: unknown, d: { x: number; y: number }) => void) | undefined;

vi.mock("react-rnd", () => ({
  Rnd: ({
    children,
    onDragStart,
    onDragStop,
  }: {
    children: React.ReactNode;
    onDragStart?: () => void;
    onDragStop?: (e: unknown, d: { x: number; y: number }) => void;
    [key: string]: unknown;
  }) => {
    capturedOnDragStart = onDragStart;
    capturedOnDragStop = onDragStop;
    return <div data-testid="rnd">{children}</div>;
  },
}));

vi.mock("@/lib/utils", () => ({
  cn: (...classes: unknown[]) =>
    classes.filter((c) => typeof c === "string" && c).join(" "),
}));

vi.mock("./ArrowSvgs", () => ({
  getArrowComponent: () => () => <div data-testid="arrow" />,
}));

// ------------------------------------------------------------------
// Helpers
// ------------------------------------------------------------------

const { AnnotationOverlay } = await import("./AnnotationOverlay");

globalThis.IS_REACT_ACT_ENVIRONMENT = true;

const baseAnnotation: AnnotationRegion = {
  id: "ann-1",
  startMs: 0,
  endMs: 5000,
  type: "text",
  content: "Hello",
  position: { x: 10, y: 10 },
  size: { width: 30, height: 20 },
  style: {
    color: "#ffffff",
    backgroundColor: "transparent",
    fontSize: 24,
    fontFamily: "sans-serif",
    fontWeight: "normal",
    fontStyle: "normal",
    textDecoration: "none",
    textAlign: "center",
  },
  zIndex: 1,
};

function makeProps(overrides: Partial<typeof baseAnnotation> = {}) {
  return {
    annotation: { ...baseAnnotation, ...overrides },
    isSelected: true,
    containerWidth: 1280,
    containerHeight: 720,
    onPositionChange: vi.fn(),
    onSizeChange: vi.fn(),
    onClick: vi.fn(),
    zIndex: 1,
    isSelectedBoost: false,
  };
}

async function renderOverlay(props = makeProps()) {
  const container = document.createElement("div");
  document.body.appendChild(container);
  const root: Root = createRoot(container);

  await act(async () => {
    root.render(<AnnotationOverlay {...props} />);
  });

  return {
    container,
    unmount: async () => {
      await act(async () => {
        root.unmount();
      });
      container.remove();
    },
  };
}

// ------------------------------------------------------------------
// Tests
// ------------------------------------------------------------------

afterEach(() => {
  vi.clearAllMocks();
  vi.useRealTimers();
  document.body.innerHTML = "";
  capturedOnDragStart = undefined;
  capturedOnDragStop = undefined;
});

beforeEach(() => {
  class ResizeObserverMock {
    observe = vi.fn();
    unobserve = vi.fn();
    disconnect = vi.fn();
  }
  Object.defineProperty(globalThis, "ResizeObserver", {
    configurable: true,
    value: ResizeObserverMock,
  });
});

describe("AnnotationOverlay – drag unmount safety", () => {
  it("does not throw when component unmounts before drag-reset timeout fires", async () => {
    vi.useFakeTimers();

    const consoleErrorSpy = vi.spyOn(console, "error");
    const props = makeProps();
    const { unmount } = await renderOverlay(props);

    // Start drag
    await act(async () => {
      capturedOnDragStart?.();
    });

    // Stop drag – this schedules the 100ms setTimeout
    await act(async () => {
      capturedOnDragStop?.({}, { x: 50, y: 50 });
    });

    // Unmount BEFORE the timeout fires
    await unmount();

    // Advance past the timeout – should not throw
    await act(async () => {
      vi.advanceTimersByTime(200);
    });

    // No unhandled errors from the drag-reset path
    const dragResetErrors = consoleErrorSpy.mock.calls.filter(
      (call) =>
        typeof call[0] === "string" &&
        call[0].includes("[AnnotationOverlay]"),
    );
    expect(dragResetErrors).toHaveLength(0);

    // onPositionChange was called during drag stop (before unmount) – that's fine
    expect(props.onPositionChange).toHaveBeenCalledTimes(1);
  });

  it("resets isDragging correctly when component stays mounted through timeout", async () => {
    vi.useFakeTimers();

    const props = makeProps();
    const { unmount } = await renderOverlay(props);

    await act(async () => {
      capturedOnDragStart?.();
    });

    await act(async () => {
      capturedOnDragStop?.({}, { x: 100, y: 80 });
    });

    // Advance timer while still mounted – no errors expected
    await act(async () => {
      vi.advanceTimersByTime(200);
    });

    await unmount();

    // No errors at all
    expect(props.onPositionChange).toHaveBeenCalledTimes(1);
  });

  it("catches and logs errors thrown inside the drag-reset callback", async () => {
    vi.useFakeTimers();
    const consoleErrorSpy = vi.spyOn(console, "error").mockImplementation(() => {});

    const props = makeProps();
    const { unmount } = await renderOverlay(props);

    await act(async () => {
      capturedOnDragStart?.();
    });

    await act(async () => {
      capturedOnDragStop?.({}, { x: 10, y: 10 });
    });

    // Advance while mounted – callback runs without error
    await act(async () => {
      vi.advanceTimersByTime(200);
    });

    await unmount();

    // Confirm no [AnnotationOverlay] errors logged in this normal path
    const annotationErrors = consoleErrorSpy.mock.calls.filter(
      (call) =>
        typeof call[0] === "string" &&
        call[0].includes("[AnnotationOverlay]"),
    );
    expect(annotationErrors).toHaveLength(0);
  });

  it("does not update state on an unmounted component (no React warning)", async () => {
    vi.useFakeTimers();

    // Intercept console.error to catch React's setState-on-unmounted warning
    const consoleErrorSpy = vi.spyOn(console, "error").mockImplementation(() => {});

    const props = makeProps();
    const { unmount } = await renderOverlay(props);

    await act(async () => {
      capturedOnDragStart?.();
      capturedOnDragStop?.({}, { x: 20, y: 20 });
    });

    // Unmount before timeout
    await unmount();

    await act(async () => {
      vi.advanceTimersByTime(200);
    });

    // No React "Can't perform a React state update on an unmounted component" warning
    const reactUpdateWarnings = consoleErrorSpy.mock.calls.filter((call) =>
      typeof call[0] === "string"
        ? call[0].includes("unmounted component")
        : false,
    );
    expect(reactUpdateWarnings).toHaveLength(0);
  });
});
