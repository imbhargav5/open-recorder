import type { Metadata } from "next";
import type { ReactElement, ReactNode } from "react";
import "./globals.css";

export const metadata: Metadata = {
  title: "Open Recorder - Native macOS capture studio",
  description:
    "Open Recorder is an open-source macOS screen recorder, screenshot tool, and lightweight editor built with Swift and Rust.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: ReactNode;
}>): ReactElement {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
