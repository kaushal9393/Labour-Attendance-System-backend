import { useEffect, useRef, useState } from "react";
import { Amplify } from "aws-amplify";
import { FaceLivenessDetector } from "@aws-amplify/ui-react-liveness";
import { ThemeProvider } from "@aws-amplify/ui-react";
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

// API base — empty string means same origin (FastAPI serves both API + static).
const API_BASE = "";
const URL_PARAMS = new URLSearchParams(window.location.search);
const COMPANY_CODE = URL_PARAMS.get("company_code") || "";
// Mobile pre-allocates a scan_id and passes it on the URL so polling
// from the app and the result POST land in the same bucket.
const SCAN_ID = URL_PARAMS.get("scan_id");

type Phase = "loading" | "ready" | "verifying" | "done" | "error";

export default function App() {
  const [phase, setPhase] = useState<Phase>("loading");
  const [sessionId, setSessionId] = useState<string | null>(null);
  const [errorMsg, setErrorMsg] = useState<string>("");
  const [result, setResult] = useState<any>(null);
  const sessionStartedRef = useRef(false);

  // Kept only so the page is still usable when opened in a desktop browser
  // for testing — the mobile app doesn't read this anymore.
  function postToHost(payload: any) {
    const msg = JSON.stringify(payload);
    console.log("[Liveness->Host]", msg);
    const w = window as any;
    if (w.FlutterLiveness && typeof w.FlutterLiveness.postMessage === "function") {
      w.FlutterLiveness.postMessage(msg);
    }
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
        setErrorMsg(`Failed to start liveness: ${e.message}`);
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
        setResult(data);
        postToHost(data);
        // Stay on the "Verifying…" view — the Flutter app polls
        // /api/liveness/result/{scan_id} and shows the canonical
        // success/failed screen. Try to close the tab so the user
        // returns to the app immediately. window.close() only works
        // for tabs the page itself opened, so we also navigate to
        // about:blank as a graceful fallback (browsers won't auto-
        // close Custom Tabs from arbitrary pages).
        setTimeout(() => {
          try {
            window.close();
          } catch (_) { /* ignore */ }
          window.location.replace("about:blank");
        }, 200);
      })
      .catch((e) => {
        setPhase("error");
        setErrorMsg(`Verification failed: ${e.message}`);
        postToHost({ success: false, reason: "network_error" });
        setTimeout(() => {
          try { window.close(); } catch (_) { /* ignore */ }
          window.location.replace("about:blank");
        }, 200);
      });
  }

  function handleError(err: any) {
    setPhase("error");
    setErrorMsg(err?.state || err?.message || "Liveness check failed");
    postToHost({ success: false, reason: "liveness_error" });
  }

  return (
    <ThemeProvider>
      <div style={styles.container}>
        {phase === "loading" && (
          <Centered
            text="Starting face scan…"
            subtext="Camera permission ko Allow karein."
          />
        )}
        {phase === "error" && (
          <Centered
            text={`❌ ${errorMsg}`}
            subtext="App pe vaapas jaakar dobara try karein."
          />
        )}
        {phase === "verifying" && (
          <Centered
            text="Attendance mark ho rahi hai…"
            subtext="Ek second ruko."
          />
        )}
        {phase === "done" && result && <ResultView result={result} />}
        {phase === "ready" && sessionId && (
          <FaceLivenessDetector
            sessionId={sessionId}
            region={REGION}
            onAnalysisComplete={handleAnalysisComplete as any}
            onError={handleError}
            // Skip the AWS start screen — saves ~3 seconds and avoids the
            // extra "Begin check" tap on every scan.
            disableStartScreen={true}
          />
        )}
      </div>
    </ThemeProvider>
  );
}

function Centered({ text, subtext }: { text: string; subtext?: string }) {
  return (
    <div style={styles.center}>
      <div style={styles.text}>{text}</div>
      {subtext && <div style={styles.subtext}>{subtext}</div>}
    </div>
  );
}

function ResultView({ result }: { result: any }) {
  const ok = result.success;
  return (
    <div style={styles.center}>
      <div style={{ fontSize: 48, marginBottom: 12 }}>{ok ? "✅" : "❌"}</div>
      <div style={styles.text}>
        {ok ? `${result.employee_name} — ${result.action}` : (result.reason || "Failed")}
      </div>
      {ok && result.time && <div style={styles.subtext}>Time: {result.time}</div>}
      {result.liveness_confidence != null && (
        <div style={styles.subtext}>
          Liveness: {result.liveness_confidence.toFixed(1)}%
        </div>
      )}
    </div>
  );
}

const styles: Record<string, React.CSSProperties> = {
  container: {
    minHeight: "100vh",
    background: "#f5f7fa",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    padding: 16,
  },
  center: {
    textAlign: "center",
    background: "white",
    borderRadius: 12,
    padding: 32,
    boxShadow: "0 2px 12px rgba(0,0,0,0.08)",
    maxWidth: 420,
  },
  text: { fontSize: 18, fontWeight: 600, color: "#1f2a37" },
  subtext: { marginTop: 8, fontSize: 14, color: "#6b7280" },
};
