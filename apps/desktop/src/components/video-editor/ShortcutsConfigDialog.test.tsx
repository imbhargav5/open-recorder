// @vitest-environment jsdom

import { createElement } from 'react';
import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { DEFAULT_SHORTCUTS } from '@/lib/shortcuts';
import type { ShortcutsConfig } from '@/lib/shortcuts';

// ---------------------------------------------------------------------------
// Mocks – set up before the module under test is imported
// ---------------------------------------------------------------------------

vi.mock('@/contexts/ShortcutsContext', () => ({
  useShortcuts: vi.fn(),
}));

vi.mock('@/components/ui/dialog', () => ({
  Dialog: ({ children, open }: { children: React.ReactNode; open: boolean }) =>
    open ? createElement('div', { 'data-testid': 'dialog' }, children) : null,
  DialogContent: ({ children }: { children: React.ReactNode }) =>
    createElement('div', null, children),
  DialogHeader: ({ children }: { children: React.ReactNode }) =>
    createElement('div', null, children),
  DialogTitle: ({ children }: { children: React.ReactNode }) =>
    createElement('div', null, children),
  DialogFooter: ({ children }: { children: React.ReactNode }) =>
    createElement('div', null, children),
}));

vi.mock('@/components/ui/button', () => ({
  Button: ({ children, onClick, ...rest }: React.ButtonHTMLAttributes<HTMLButtonElement> & { children?: React.ReactNode }) =>
    createElement('button', { onClick, ...rest }, children),
}));

vi.mock('sonner', () => ({
  toast: { error: vi.fn(), success: vi.fn(), info: vi.fn() },
}));

// Lazy-import after mocks are registered
const { useShortcuts } = vi.mocked(await import('@/contexts/ShortcutsContext'));
const { ShortcutsConfigDialog } = await import('./ShortcutsConfigDialog');

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

globalThis.IS_REACT_ACT_ENVIRONMENT = true;

async function flushEffects() {
  await act(async () => {
    await Promise.resolve();
    await new Promise((resolve) => setTimeout(resolve, 0));
  });
}

function makeShortcutsContext(overrides: Partial<ReturnType<typeof useShortcuts>> = {}) {
  return {
    shortcuts: { ...DEFAULT_SHORTCUTS } as ShortcutsConfig,
    isMac: false,
    isConfigOpen: true,
    setShortcuts: vi.fn(),
    persistShortcuts: vi.fn().mockResolvedValue(undefined),
    openConfig: vi.fn(),
    closeConfig: vi.fn(),
    ...overrides,
  };
}

async function renderDialog(contextOverrides?: Partial<ReturnType<typeof useShortcuts>>) {
  useShortcuts.mockReturnValue(makeShortcutsContext(contextOverrides));

  const container = document.createElement('div');
  document.body.appendChild(container);
  const root: Root = createRoot(container);

  await act(async () => {
    root.render(<ShortcutsConfigDialog />);
  });
  await flushEffects();

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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

beforeEach(() => {
  vi.clearAllMocks();
});

afterEach(() => {
  document.body.innerHTML = '';
});

describe('ShortcutsConfigDialog – keydown listener lifecycle', () => {
  it('removes the keydown listener on unmount when captureFor is active', async () => {
    const removeEventListenerSpy = vi.spyOn(window, 'removeEventListener');

    const harness = await renderDialog();

    // Enter capture mode by clicking the first "Click to change" button
    const captureButton = Array.from(
      harness.container.querySelectorAll<HTMLButtonElement>('button[type="button"]'),
    ).find((btn) => btn.getAttribute('title') === 'Click to change');
    expect(captureButton).not.toBeUndefined();

    await act(async () => {
      captureButton!.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    });
    await flushEffects();

    // Confirm the dialog is in capture mode
    expect(harness.container.textContent).toContain('Press a key');

    // Unmount while captureFor is non-null
    await harness.unmount();

    // The window listener must have been removed
    const keydownRemoveCalls = removeEventListenerSpy.mock.calls.filter(
      ([event]) => event === 'keydown',
    );
    expect(keydownRemoveCalls.length).toBeGreaterThan(0);

    removeEventListenerSpy.mockRestore();
  });

  it('does NOT intercept keydown events after the component is unmounted', async () => {
    const harness = await renderDialog();

    // Enter capture mode
    const captureButton = Array.from(
      harness.container.querySelectorAll<HTMLButtonElement>('button[type="button"]'),
    ).find((btn) => btn.getAttribute('title') === 'Click to change');

    await act(async () => {
      captureButton!.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    });
    await flushEffects();

    // Unmount while capture is active
    await harness.unmount();

    // After unmount, keydown events must propagate normally and NOT be suppressed
    const preventDefaultSpy = vi.fn();
    const outsideHandler = vi.fn((e: Event) => {
      // Detect if the component's capture listener called preventDefault
      if ((e as KeyboardEvent).defaultPrevented) {
        preventDefaultSpy();
      }
    });

    // Add a non-capture listener to observe events from the outside
    window.addEventListener('keydown', outsideHandler);

    await act(async () => {
      window.dispatchEvent(new KeyboardEvent('keydown', { key: 'z', bubbles: true, cancelable: true }));
    });

    // The handler must fire (event was not stopped) and must not have been preventDefault'd
    expect(outsideHandler).toHaveBeenCalledTimes(1);
    expect(preventDefaultSpy).not.toHaveBeenCalled();

    window.removeEventListener('keydown', outsideHandler);
  });

  it('registers exactly one keydown listener on mount and removes it on unmount', async () => {
    const addSpy = vi.spyOn(window, 'addEventListener');
    const removeSpy = vi.spyOn(window, 'removeEventListener');

    const harness = await renderDialog();

    const keydownAdds = addSpy.mock.calls.filter(([event]) => event === 'keydown');
    expect(keydownAdds).toHaveLength(1);

    await harness.unmount();

    const keydownRemoves = removeSpy.mock.calls.filter(([event]) => event === 'keydown');
    expect(keydownRemoves).toHaveLength(1);

    addSpy.mockRestore();
    removeSpy.mockRestore();
  });

  it('ignores keydown events when captureFor is null (dialog open, no action selected)', async () => {
    const harness = await renderDialog();

    // No capture button clicked – captureFor is null
    const interceptedKeys: string[] = [];
    const observer = (e: KeyboardEvent) => {
      if (!e.defaultPrevented) interceptedKeys.push(e.key);
    };
    window.addEventListener('keydown', observer);

    await act(async () => {
      window.dispatchEvent(new KeyboardEvent('keydown', { key: 'z', bubbles: true, cancelable: true }));
    });

    // Key must have propagated without being defaultPrevented
    expect(interceptedKeys).toContain('z');

    window.removeEventListener('keydown', observer);
    await harness.unmount();
  });
});
