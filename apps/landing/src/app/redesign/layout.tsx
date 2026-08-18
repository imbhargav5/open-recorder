import type { Metadata } from "next";
import type { ReactElement, ReactNode } from "react";
import "./design-tokens.css";
import "./redesign.css";

export const metadata: Metadata = {
  title: "Open Recorder | Native macOS capture studio",
  description:
    "Open Recorder is an open-source macOS screen recorder, screenshot tool, and native editor built with Swift and Rust.",
};

export default function RedesignLayout({
  children,
}: Readonly<{ children: ReactNode }>): ReactElement {
  // Force dark class so dark tokens are always active
  return <div className="rd-root dark">{children}</div>;
}
