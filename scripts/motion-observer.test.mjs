import { readFileSync } from "node:fs";
import test from "node:test";
import assert from "node:assert/strict";

class HtmlTarget {
  constructor(attributes = {}) {
    this.attributes = new Map(Object.entries(attributes));
  }

  getAttribute(name) {
    return this.attributes.get(name) ?? null;
  }

  setAttribute(name, value) {
    this.attributes.set(name, String(value));
  }
}

function createHarness(revealItems) {
  let effect;
  let callback;
  const observed = [];
  const unobserved = [];
  const scheduled = [];

  class FakeIntersectionObserver {
    constructor(nextCallback) {
      callback = nextCallback;
    }

    observe(target) {
      observed.push(target);
    }

    unobserve(target) {
      unobserved.push(target);
    }

    disconnect() {}
  }

  const document = {
    querySelectorAll(selector) {
      if (selector === "[data-reveal]") return revealItems;
      if (selector === "[data-parallax]") return [];
      throw new Error(`Unexpected selector: ${selector}`);
    },
  };

  const source = readFileSync(
    new URL("../apps/landing/src/components/redesign/MotionObserver.tsx", import.meta.url),
    "utf8"
  )
    .replace(/^"use client";\n/, "")
    .replace(/^import \{ useEffect \} from "react";\n/, "")
    .replaceAll("querySelectorAll<HTMLElement>", "querySelectorAll")
    .replace("export function MotionObserver(): null {", "function MotionObserver() {");

  const MotionObserver = new Function(
    "useEffect",
    "document",
    "IntersectionObserver",
    "window",
    "setTimeout",
    `${source}\nreturn MotionObserver;`
  )(
    (nextEffect) => {
      effect = nextEffect;
    },
    document,
    FakeIntersectionObserver,
    {},
    (nextCallback, delay) => {
      scheduled.push({ nextCallback, delay });
      return scheduled.length;
    }
  );

  MotionObserver();
  assert.ok(effect, "MotionObserver should register an effect");
  effect();

  return { callback, observed, scheduled, unobserved };
}

test("reveal callback handles HTML targets with and without data-delay", () => {
  const delayedTarget = new HtmlTarget({ "data-delay": "125" });
  const immediateTarget = new HtmlTarget();
  const harness = createHarness([delayedTarget, immediateTarget]);

  assert.deepEqual(harness.observed, [delayedTarget, immediateTarget]);
  harness.callback([
    { isIntersecting: true, target: delayedTarget },
    { isIntersecting: true, target: immediateTarget },
  ]);

  assert.deepEqual(harness.unobserved, [delayedTarget, immediateTarget]);
  assert.deepEqual(
    harness.scheduled.map(({ delay }) => delay),
    [125, 0]
  );
  assert.equal(delayedTarget.getAttribute("data-visible"), null);
  assert.equal(immediateTarget.getAttribute("data-visible"), null);

  harness.scheduled.forEach(({ nextCallback }) => nextCallback());
  assert.equal(delayedTarget.getAttribute("data-visible"), "true");
  assert.equal(immediateTarget.getAttribute("data-visible"), "true");
});
