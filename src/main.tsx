import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { NexApp } from "./app/NexApp";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <NexApp />
  </StrictMode>,
);
