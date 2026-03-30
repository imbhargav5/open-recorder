import { createActor } from "xstate";
import { describe, expect, it, vi } from "vitest";
import { microphoneMachine } from "./microphoneMachine";

function createTestActor(actions?: { enableMic?: () => void; disableMic?: () => void }) {
	const enableMic = actions?.enableMic ?? vi.fn();
	const disableMic = actions?.disableMic ?? vi.fn();

	const machine = microphoneMachine.provide({
		actions: { enableMic, disableMic },
	});

	const actor = createActor(machine).start();
	return { actor, enableMic, disableMic };
}

describe("microphoneMachine", () => {
	it("starts in the off state", () => {
		const { actor } = createTestActor();
		expect(actor.getSnapshot().value).toBe("off");
	});

	describe("off state", () => {
		it("transitions to selecting on CLICK and calls enableMic", () => {
			const { actor, enableMic } = createTestActor();
			actor.send({ type: "CLICK" });
			expect(actor.getSnapshot().value).toBe("selecting");
			expect(enableMic).toHaveBeenCalledOnce();
		});

		it("transitions to lockedOff on RECORDING_START", () => {
			const { actor } = createTestActor();
			actor.send({ type: "RECORDING_START" });
			expect(actor.getSnapshot().value).toBe("lockedOff");
		});
	});

	describe("on state", () => {
		it("transitions to selecting on CLICK", () => {
			const { actor } = createTestActor();
			// Get to "on" state: off -> CLICK -> selecting -> CLOSE_POPOVER -> on
			actor.send({ type: "CLICK" });
			actor.send({ type: "CLOSE_POPOVER" });
			expect(actor.getSnapshot().value).toBe("on");

			actor.send({ type: "CLICK" });
			expect(actor.getSnapshot().value).toBe("selecting");
		});

		it("transitions to lockedOn on RECORDING_START", () => {
			const { actor } = createTestActor();
			actor.send({ type: "CLICK" });
			actor.send({ type: "CLOSE_POPOVER" });
			expect(actor.getSnapshot().value).toBe("on");

			actor.send({ type: "RECORDING_START" });
			expect(actor.getSnapshot().value).toBe("lockedOn");
		});
	});

	describe("selecting state", () => {
		it("transitions to on on CLICK", () => {
			const { actor } = createTestActor();
			actor.send({ type: "CLICK" });
			expect(actor.getSnapshot().value).toBe("selecting");

			actor.send({ type: "CLICK" });
			expect(actor.getSnapshot().value).toBe("on");
		});

		it("transitions to on on CLOSE_POPOVER", () => {
			const { actor } = createTestActor();
			actor.send({ type: "CLICK" });
			actor.send({ type: "CLOSE_POPOVER" });
			expect(actor.getSnapshot().value).toBe("on");
		});

		it("transitions to off on DISABLE and calls disableMic", () => {
			const { actor, disableMic } = createTestActor();
			actor.send({ type: "CLICK" });
			expect(actor.getSnapshot().value).toBe("selecting");

			actor.send({ type: "DISABLE" });
			expect(actor.getSnapshot().value).toBe("off");
			expect(disableMic).toHaveBeenCalledOnce();
		});

		it("transitions to lockedOn on RECORDING_START", () => {
			const { actor } = createTestActor();
			actor.send({ type: "CLICK" });
			expect(actor.getSnapshot().value).toBe("selecting");

			actor.send({ type: "RECORDING_START" });
			expect(actor.getSnapshot().value).toBe("lockedOn");
		});
	});

	describe("lockedOn state", () => {
		it("transitions to on on RECORDING_STOP", () => {
			const { actor } = createTestActor();
			// Get to lockedOn: off -> CLICK -> selecting -> RECORDING_START -> lockedOn
			actor.send({ type: "CLICK" });
			actor.send({ type: "RECORDING_START" });
			expect(actor.getSnapshot().value).toBe("lockedOn");

			actor.send({ type: "RECORDING_STOP" });
			expect(actor.getSnapshot().value).toBe("on");
		});

		it("ignores CLICK events", () => {
			const { actor } = createTestActor();
			actor.send({ type: "CLICK" });
			actor.send({ type: "RECORDING_START" });
			expect(actor.getSnapshot().value).toBe("lockedOn");

			actor.send({ type: "CLICK" });
			expect(actor.getSnapshot().value).toBe("lockedOn");
		});
	});

	describe("lockedOff state", () => {
		it("transitions to off on RECORDING_STOP", () => {
			const { actor } = createTestActor();
			actor.send({ type: "RECORDING_START" });
			expect(actor.getSnapshot().value).toBe("lockedOff");

			actor.send({ type: "RECORDING_STOP" });
			expect(actor.getSnapshot().value).toBe("off");
		});

		it("ignores CLICK events", () => {
			const { actor } = createTestActor();
			actor.send({ type: "RECORDING_START" });
			expect(actor.getSnapshot().value).toBe("lockedOff");

			actor.send({ type: "CLICK" });
			expect(actor.getSnapshot().value).toBe("lockedOff");
		});
	});
});
