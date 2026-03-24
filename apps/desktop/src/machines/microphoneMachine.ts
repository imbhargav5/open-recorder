import { setup } from "xstate";

export const microphoneMachine = setup({
  types: {
    events: {} as
      | { type: "CLICK" }
      | { type: "CLOSE_POPOVER" }
      | { type: "DISABLE" }
      | { type: "RECORDING_START" }
      | { type: "RECORDING_STOP" },
  },
  actions: {
    enableMic: () => {},
    disableMic: () => {},
  },
}).createMachine({
  id: "microphone",
  initial: "off",
  states: {
    off: {
      on: {
        CLICK: {
          target: "selecting",
          actions: "enableMic",
        },
        RECORDING_START: "lockedOff",
      },
    },
    on: {
      on: {
        CLICK: "selecting",
        RECORDING_START: "lockedOn",
      },
    },
    selecting: {
      on: {
        CLICK: "on",
        CLOSE_POPOVER: "on",
        DISABLE: {
          target: "off",
          actions: "disableMic",
        },
        RECORDING_START: "lockedOn",
      },
    },
    lockedOn: {
      on: {
        RECORDING_STOP: "on",
      },
    },
    lockedOff: {
      on: {
        RECORDING_STOP: "off",
      },
    },
  },
});
