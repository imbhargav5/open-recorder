/**
 * Performance instrumentation for Open Recorder.
 *
 * Uses OpenTelemetry API + a console-based span exporter so traces are
 * visible in the browser dev-tools console.  A React `<Profiler>` helper
 * is also exported – wrap it around any component tree to capture
 * per-component render counts and durations.
 *
 * Toggle at runtime (browser dev-tools console):
 *   __PERF_START()          // start collecting + auto-print every 3 s
 *   __PERF_STOP()           // stop + print final summary
 *   __PERF_DUMP()           // print summary now
 *   __PERF_RESET()          // clear counters
 *   __PERF_LAST             // read last dump as a string (if console is stripped)
 */

import { type Span, type Tracer, trace } from "@opentelemetry/api";
import { resourceFromAttributes } from "@opentelemetry/resources";
import {
	BasicTracerProvider,
	ConsoleSpanExporter,
	SimpleSpanProcessor,
} from "@opentelemetry/sdk-trace-web";

// ---------------------------------------------------------------------------
// Indirect console access — survives terser `drop_console: true`
// ---------------------------------------------------------------------------

const _noop = (..._args: unknown[]) => {
	/* noop */
};
const _print = (() => {
	try {
		const key = "console";
		const c = (globalThis as Record<string, unknown>)[key] as Console;
		return {
			log: c?.log?.bind(c) ?? _noop,
			warn: c?.warn?.bind(c) ?? _noop,
			table: c?.table?.bind(c) ?? c?.log?.bind(c) ?? _noop,
		};
	} catch {
		return { log: _noop, warn: _noop, table: _noop };
	}
})();

// ---------------------------------------------------------------------------
// Provider setup (runs once at import time)
// ---------------------------------------------------------------------------

const provider = new BasicTracerProvider({
	resource: resourceFromAttributes({
		"service.name": "open-recorder-ui",
	}),
	spanProcessors: [new SimpleSpanProcessor(new ConsoleSpanExporter())],
});

const tracer: Tracer = provider.getTracer("open-recorder-ui", "1.0.0");

// Also register globally so any code can use `trace.getTracer()`
trace.setGlobalTracerProvider(provider);

// ---------------------------------------------------------------------------
// Render stats (lightweight, always-on profiler bookkeeping)
// ---------------------------------------------------------------------------

interface RenderStat {
	count: number;
	totalMs: number;
	maxMs: number;
	lastRenderMs: number;
	lastTimestamp: number;
}

const renderStats = new Map<string, RenderStat>();

function recordRender(
	id: string,
	_phase: "mount" | "update" | "nested-update",
	actualDurationMs: number,
) {
	let stat = renderStats.get(id);
	if (!stat) {
		stat = {
			count: 0,
			totalMs: 0,
			maxMs: 0,
			lastRenderMs: 0,
			lastTimestamp: 0,
		};
		renderStats.set(id, stat);
	}
	stat.count += 1;
	stat.totalMs += actualDurationMs;
	stat.maxMs = Math.max(stat.maxMs, actualDurationMs);
	stat.lastRenderMs = actualDurationMs;
	stat.lastTimestamp = performance.now();
}

// ---------------------------------------------------------------------------
// Periodic summary (prints every N seconds while enabled)
// ---------------------------------------------------------------------------

let summaryIntervalId: ReturnType<typeof setInterval> | null = null;
const SUMMARY_INTERVAL_MS = 3_000;

function startSummaryInterval() {
	if (summaryIntervalId) return;
	summaryIntervalId = setInterval(() => {
		if (!isPerfEnabled()) return;
		dumpRenderStats();
	}, SUMMARY_INTERVAL_MS);
}

function stopSummaryInterval() {
	if (summaryIntervalId) {
		clearInterval(summaryIntervalId);
		summaryIntervalId = null;
	}
}

// ---------------------------------------------------------------------------
// Public helpers
// ---------------------------------------------------------------------------

/** Check if perf instrumentation is enabled at runtime. */
export function isPerfEnabled(): boolean {
	return (globalThis as Record<string, unknown>).__PERF_ENABLED === true;
}

/** Dump current render stats to console as a table. Also stores in __PERF_LAST. */
export function dumpRenderStats(): void {
	if (renderStats.size === 0) {
		const msg =
			"[perf] No render data collected yet. Make sure the app has rendered at least once.";
		_print.warn(msg);
		(globalThis as Record<string, unknown>).__PERF_LAST = msg;
		return;
	}

	const now = performance.now();
	const rows: Record<string, unknown>[] = [];

	for (const [id, stat] of renderStats) {
		rows.push({
			component: id,
			renders: stat.count,
			"avg (ms)": stat.count > 0 ? +(stat.totalMs / stat.count).toFixed(2) : 0,
			"max (ms)": +stat.maxMs.toFixed(2),
			"last (ms)": +stat.lastRenderMs.toFixed(2),
			"idle (s)": +((now - stat.lastTimestamp) / 1000).toFixed(1),
		});
	}

	// Print to console (survives terser)
	_print.warn("[perf] Render stats:");
	_print.table(rows);

	// Also store as string for retrieval via __PERF_LAST
	const lines = rows.map(
		(r) =>
			`${r.component}: renders=${r.renders}, avg=${r["avg (ms)"]}ms, max=${r["max (ms)"]}ms, last=${r["last (ms)"]}ms, idle=${r["idle (s)"]}s`,
	);
	const summary = `[perf] Render stats:\n${lines.join("\n")}`;
	(globalThis as Record<string, unknown>).__PERF_LAST = summary;
}

/** Reset all collected render stats. */
export function resetRenderStats(): void {
	renderStats.clear();
	_print.warn("[perf] Render stats reset.");
}

// ---------------------------------------------------------------------------
// React Profiler onRender callback
// ---------------------------------------------------------------------------

/**
 * Callback compatible with React `<Profiler onRender={onRenderProfiler}>`.
 *
 * Always records lightweight stats. When `__PERF_ENABLED` is true, also
 * creates an OTel span per render for detailed tracing.
 */
export function onRenderProfiler(
	id: string,
	phase: "mount" | "update" | "nested-update",
	actualDuration: number,
	baseDuration: number,
	startTime: number,
	commitTime: number,
): void {
	recordRender(id, phase, actualDuration);

	if (!isPerfEnabled()) return;

	const span: Span = tracer.startSpan(`react.render.${id}`, {
		attributes: {
			"react.component": id,
			"react.phase": phase,
			"react.actual_duration_ms": actualDuration,
			"react.base_duration_ms": baseDuration,
			"react.start_time": startTime,
			"react.commit_time": commitTime,
		},
	});
	span.end();
}

// ---------------------------------------------------------------------------
// Span helpers for non-React measurements
// ---------------------------------------------------------------------------

/** Start an OTel span. Returns a span that must be `.end()`ed by the caller. */
export function startSpan(
	name: string,
	attributes?: Record<string, string | number | boolean>,
): Span {
	return tracer.startSpan(name, { attributes });
}

// ---------------------------------------------------------------------------
// Attach globals for dev-tools console access
// ---------------------------------------------------------------------------

Object.assign(globalThis, {
	__PERF_ENABLED: false,
	__PERF_LAST: "",
	__PERF_DUMP: dumpRenderStats,
	__PERF_RESET: resetRenderStats,
	__PERF_START: () => {
		(globalThis as Record<string, unknown>).__PERF_ENABLED = true;
		startSummaryInterval();
		_print.warn(
			"[perf] Profiling started. Stats will print every 3 s. Read __PERF_LAST if console output is stripped.",
		);
	},
	__PERF_STOP: () => {
		(globalThis as Record<string, unknown>).__PERF_ENABLED = false;
		stopSummaryInterval();
		dumpRenderStats();
		_print.warn("[perf] Profiling stopped.");
	},
});

_print.warn(
	"[perf] Instrumentation loaded. Use __PERF_START() to begin, __PERF_DUMP() to view stats. If console is silent, read __PERF_LAST.",
);
