fetch(new URL(self.location.href).searchParams.get("u"), { mode: "no-cors" })
  .then(() => self.postMessage("ok"), () => self.postMessage("failed"));
