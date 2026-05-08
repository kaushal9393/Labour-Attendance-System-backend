import { useEffect, useRef, useState } from "react";
import { Amplify } from "aws-amplify";
import { FaceLivenessDetector } from "@aws-amplify/ui-react-liveness";
import { ThemeProvider, defaultDarkModeOverride } from "@aws-amplify/ui-react";
import type { Theme } from "@aws-amplify/ui-react";
import "@aws-amplify/ui-react/styles.css";

// Cognito Identity Pool — gives unauthenticated browser users a temporary
// credential scoped to rekognition:StartFaceLivenessSession only.
const IDENTITY_POOL_ID = "ap-south-1:b05bdf96-4284-4c3c-bd51-13c79ce34798";
const REGION = "ap-south-1";

Amplify.configure({
  Auth: {
    Cognito: {
      identityPoolId: IDENTITY_POOL_ID,
      allowGuestAccess: true,
    },
  },
} as never);

// Same green accent as the Flutter app so the in-Custom-Tab UI feels
// continuous with the surrounding screens. The AWS oval/lights flash
// stay random colors (security-critical) but everything else inherits
// the brand colors.
const APP_GREEN = "#0F7A5C";
const APP_GREEN_DARK = "#0A5D45";
const APP_BG = "#F5F7FA";
const APP_TEXT = "#1F2A37";
const APP_SUBTEXT = "#6B7280";

const livenessTheme: Theme = {
  name: "garage-liveness",
  overrides: [defaultDarkModeOverride],
  tokens: {
    colors: {
      brand: {
        primary: {
          10:  { value: "#E6F4EF" },
          20:  { value: "#C0E3D7" },
          40:  { value: "#5BB394" },
          60:  { value: APP_GREEN },
          80:  { value: APP_GREEN_DARK },
          90:  { value: APP_GREEN_DARK },
          100: { value: APP_GREEN_DARK },
        },
      },
      background: {
        primary: { value: "#FFFFFF" },
        secondary: { value: APP_BG },
      },
      font: {
        primary: { value: APP_TEXT },
        secondary: { value: APP_SUBTEXT },
      },
    },
    radii: {
      small:  { value: "8px" },
      medium: { value: "12px" },
      large:  { value: "16px" },
    },
    components: {
      button: {
        primary: {
          backgroundColor: { value: APP_GREEN },
          _hover: { backgroundColor: { value: APP_GREEN_DARK } },
        },
      },
    },
  },
};

const API_BASE = "";
const URL_PARAMS = new URLSearchParams(window.location.search);
const COMPANY_CODE = URL_PARAMS.get("company_code") || "";
const SCAN_ID = URL_PARAMS.get("scan_id");

type Phase = "loading" | "ready" | "verifying" | "done" | "error";

export default function App() {
  const [phase, setPhase] = useState<Phase>("loading");
  const [sessionId, setSessionId] = useState<string | null>(null);
  const [errorMsg, setErrorMsg] = useState<string>("");
  const sessionStartedRef = useRef(false);

  function postToHost(payload: any) {
    const msg = JSON.stringify(payload);
    console.log("[Liveness->Host]", msg);
    const w = window as any;
    if (w.FlutterLiveness && typeof w.FlutterLiveness.postMessage === "function") {
      w.FlutterLiveness.postMessage(msg);
    }
  }

  function dismissTab() {
    setTimeout(() => {
      try { window.close(); } catch { /* ignore */ }
      window.location.replace("about:blank");
    }, 150);
  }

  useEffect(() => {
    if (!COMPANY_CODE) {
      setPhase("error");
      setErrorMsg("Missing company_code in URL");
      return;
    }
    if (sessionStartedRef.current) return;
    sessionStartedRef.current = true;
    fetch(`${API_BASE}/api/liveness/session`, { method: "POST" })
      .then((r) => r.json())
      .then((data) => {
        if (!data.session_id) throw new Error("No session_id from server");
        setSessionId(data.session_id);
        setPhase("ready");
      })
      .catch((e) => {
        setPhase("error");
        setErrorMsg(`Connect nahi ho paa raha: ${e.message}`);
      });
  }, []);

  function handleAnalysisComplete() {
    if (!sessionId) return;
    setPhase("verifying");
    fetch(`${API_BASE}/api/liveness/verify`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        session_id: sessionId,
        company_code: COMPANY_CODE,
        scan_id: SCAN_ID,
      }),
    })
      .then((r) => r.json())
      .then((data) => {
        postToHost(data);
        dismissTab();
      })
      .catch(() => {
        postToHost({ success: false, reason: "network_error" });
        dismissTab();
      });
  }

  function handleError(err: any) {
    setPhase("error");
    setErrorMsg(err?.state || err?.message || "Scan complete nahi hua");
    postToHost({ success: false, reason: "liveness_error" });
    dismissTab();
  }

  return (
    <ThemeProvider theme={livenessTheme}>
      <div style={styles.container}>
        {phase === "loading" && (
          <BrandPanel
            title="Tayyari ho rahi hai"
            subtitle="Camera permission ko Allow karein."
            showSpinner
          />
        )}
        {phase === "verifying" && (
          <BrandPanel
            title="Attendance mark ho rahi hai"
            subtitle="Bas ek second…"
            showSpinner
          />
        )}
        {phase === "error" && (
          <BrandPanel
            title="Kuch galat ho gaya"
            subtitle={errorMsg || "Dobara try karein."}
          />
        )}
        {phase === "ready" && sessionId && (
          <div style={styles.detectorWrap}>
            <FaceLivenessDetector
              sessionId={sessionId}
              region={REGION}
              onAnalysisComplete={handleAnalysisComplete as any}
              onError={handleError}
              disableStartScreen={true}
            />
          </div>
        )}
      </div>
    </ThemeProvider>
  );
}

function BrandPanel({
  title,
  subtitle,
  showSpinner,
}: {
  title: string;
  subtitle?: string;
  showSpinner?: boolean;
}) {
  return (
    <div style={styles.panel}>
      <div style={styles.logoCircle}>
        <span style={styles.logoMark}>G</span>
      </div>
      <div style={styles.title}>{title}</div>
      {subtitle && <div style={styles.subtitle}>{subtitle}</div>}
      {showSpinner && (
        <div style={styles.spinnerWrap}>
          <div style={styles.spinner} />
        </div>
      )}
    </div>
  );
}

const spinnerKeyframes = `
@keyframes garage-spin {
  to { transform: rotate(360deg); }
}
`;

if (typeof document !== "undefined" && !document.getElementById("garage-keyframes")) {
  const tag = document.createElement("style");
  tag.id = "garage-keyframes";
  tag.innerHTML = spinnerKeyframes;
  document.head.appendChild(tag);
}

const styles: Record<string, React.CSSProperties> = {
  container: {
    minHeight: "100vh",
    width: "100%",
    background: APP_BG,
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    padding: 16,
    fontFamily:
      "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif",
  },
  panel: {
    background: "white",
    borderRadius: 20,
    padding: "36px 28px",
    boxShadow: "0 8px 24px rgba(15, 122, 92, 0.08)",
    width: "100%",
    maxWidth: 360,
    textAlign: "center",
    border: "1px solid #E5E7EB",
  },
  logoCircle: {
    width: 72,
    height: 72,
    borderRadius: "50%",
    background: "#E6F4EF",
    border: `2px solid ${APP_GREEN}`,
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    margin: "0 auto 20px",
  },
  logoMark: {
    color: APP_GREEN,
    fontSize: 32,
    fontWeight: 800,
    letterSpacing: -1,
  },
  title: {
    fontSize: 20,
    fontWeight: 700,
    color: APP_TEXT,
    marginBottom: 8,
  },
  subtitle: {
    fontSize: 14,
    color: APP_SUBTEXT,
    lineHeight: 1.5,
  },
  spinnerWrap: {
    marginTop: 24,
    display: "flex",
    justifyContent: "center",
  },
  spinner: {
    width: 28,
    height: 28,
    borderRadius: "50%",
    border: `3px solid ${APP_BG}`,
    borderTopColor: APP_GREEN,
    animation: "garage-spin 0.9s linear infinite",
  },
  detectorWrap: {
    width: "100%",
    height: "100vh",
    maxWidth: "100%",
    display: "flex",
    alignItems: "stretch",
    justifyContent: "center",
  },
};
