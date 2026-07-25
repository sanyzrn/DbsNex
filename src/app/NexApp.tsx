/**
 * Phase 0: intentionally empty screen — mirrors apps/client/lib/app.dart.
 *
 * The status panel below reports which Phase 0 verifications ran in this
 * React/Vite environment vs. which require Flutter tooling locally.
 */
export function NexApp() {
  const checks = [
  { label: "React prototype builds (CI)", status: "pass" as const },
  { label: "Flutter analyze + test (CI)", status: "ci" as const },
  { label: "Flutter Android build (CI)", status: "ci" as const },
  { label: "Flutter Windows build (CI)", status: "ci" as const },
  { label: "flutter run on device (local)", status: "local" as const },
  ];

  return (
    <div
      style={{
        minHeight: "100vh",
        background: "#FFFFFF",
        color: "#111113",
        fontFamily:
          "system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial, sans-serif",
      }}
    >
      {/* Empty app surface — same bg-primary token as Flutter NexApp */}
      <div style={{ flex: 1, minHeight: "60vh" }} />

      <aside
        style={{
          borderTop: "1px solid #EBEAE8",
          padding: "16px 20px",
          background: "#F2F2F0",
          fontSize: "13px",
          lineHeight: 1.6,
        }}
      >
        <strong style={{ display: "block", marginBottom: 8 }}>
          Phase 0 — environment status
        </strong>
        <p style={{ margin: "0 0 12px", color: "#8B8B90" }}>
          Temporary React shell. Product target is{" "}
          <code>apps/client</code> (Flutter).
        </p>
        <ul style={{ margin: 0, paddingLeft: 20 }}>
          {checks.map((c) => (
            <li key={c.label}>
              {statusGlyph(c.status)} {c.label}
            </li>
          ))}
        </ul>
      </aside>
    </div>
  );
}

function statusGlyph(
  status: "pass" | "ci" | "local",
): string {
  switch (status) {
    case "pass":
      return "✓";
    case "ci":
      return "◎";
    case "local":
      return "○";
  }
}
