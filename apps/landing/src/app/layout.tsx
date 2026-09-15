import type { Metadata } from "next";
import type { ReactElement, ReactNode } from "react";
import "./redesign/design-tokens.css";
import "./redesign/redesign.css";

export const metadata: Readonly<Metadata> = {
  title: "Open Recorder | Native macOS capture studio",
  description:
    "Open Recorder is an open-source macOS screen recorder, screenshot tool, and native editor built with Swift and Rust.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: ReactNode;
}>): ReactElement {
  return (
    <html lang="en">
      <body className="rd-root dark">{children}</body>
    </html>
  );
}
