const $ = (id) => document.getElementById(id);
$("origin").textContent = location.origin;

async function refreshStates() {
  const names = ["geolocation", "notifications", "camera", "clipboard-read"];
  const parts = [];
  for (const name of names) {
    try {
      parts.push(`${name}=${(await navigator.permissions.query({ name })).state}`);
    } catch (error) {
      parts.push(`${name}=unsupported`);
    }
  }
  $("states").textContent = `states: ${parts.join(" ")}`;
}

function report(id, label, text) {
  $(id).textContent = `${label}: ${text}`;
  refreshStates();
}

$("geo").addEventListener("click", () => {
  navigator.geolocation.getCurrentPosition(
    () => report("geo-result", "geolocation", "granted"),
    (error) => report("geo-result", "geolocation", `denied (${error.message || error.code})`));
});
$("notify").addEventListener("click", async () => {
  report("notify-result", "notifications", await Notification.requestPermission());
});
$("camera").addEventListener("click", async () => {
  try {
    const stream = await navigator.mediaDevices.getUserMedia({ video: true });
    stream.getTracks().forEach((track) => track.stop());
    report("camera-result", "camera", "granted");
  } catch (error) {
    report("camera-result", "camera", `denied (${error.name})`);
  }
});
$("clipboard").addEventListener("click", async () => {
  try {
    await navigator.clipboard.readText();
    report("clipboard-result", "clipboard", "granted");
  } catch (error) {
    report("clipboard-result", "clipboard", `denied (${error.name})`);
  }
});
refreshStates();
