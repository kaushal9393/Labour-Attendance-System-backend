import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import path from "path";

// Build output goes into backend/static/liveness so FastAPI can serve it.
// Base path '/liveness/' matches the StaticFiles mount in backend/main.py.
export default defineConfig({
  plugins: [react()],
  base: "/liveness/",
  build: {
    outDir: path.resolve(__dirname, "../backend/static/liveness"),
    emptyOutDir: true,
  },
});
