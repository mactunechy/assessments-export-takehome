const form = document.querySelector<HTMLFormElement>("#export-form");
const out = document.querySelector<HTMLElement>("#export-status");

form?.addEventListener("submit", async (e) => {
  e.preventDefault();
  const button = form.querySelector("button")!;
  const say = (text: string) => { if (out) out.textContent = text; };
  button.disabled = true;
  say("Preparing export...");
  try {
    const params = new URLSearchParams(new FormData(form) as unknown as Record<string, string>);
    const res = await fetch(`/export?${params}`, { credentials: "same-origin" });
    if (!res.ok) { say((await res.text()) || `Export failed (${res.status})`); return; }
    const chunks: Uint8Array[] = [];
    let bytes = 0;
    const reader = res.body!.getReader();
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      chunks.push(value);
      bytes += value.length;
      say(`Downloading... ${(bytes / 1048576).toFixed(1)} MB`);
    }
    const a = document.createElement("a");
    a.href = URL.createObjectURL(new Blob(chunks as BlobPart[], { type: "text/csv" }));
    a.download = "assessments.csv";
    a.click();
    URL.revokeObjectURL(a.href);
    say(`Done: ${Math.round(bytes / 1024)} KB`);
  } catch {
    say("Export failed: network error");
  } finally {
    button.disabled = false;
  }
});
