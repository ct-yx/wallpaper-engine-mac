const repository = "ct-yx/wallpaper-engine-mac";
const fallbackRelease = {
  tag_name: "v0.8.1",
  html_url: `https://github.com/${repository}/releases/tag/v0.8.1`,
  assets: [{
    name: "Open-Wallpaper-Engine-v0.8.1-macOS.zip",
    browser_download_url: `https://github.com/${repository}/releases/download/v0.8.1/Open-Wallpaper-Engine-v0.8.1-macOS.zip`
  }]
};

function applyRelease(release) {
  const download = release.assets?.find((asset) => asset.name.endsWith(".zip"));
  const downloadUrl = download?.browser_download_url || release.html_url;
  const version = release.tag_name || fallbackRelease.tag_name;

  document.querySelectorAll("[data-release-version]").forEach((element) => {
    element.textContent = version;
  });
  document.querySelectorAll("[data-release-download]").forEach((element) => {
    element.href = downloadUrl;
  });
  document.querySelectorAll("[data-release-page]").forEach((element) => {
    element.href = release.html_url;
  });
}

applyRelease(fallbackRelease);

fetch(`https://api.github.com/repos/${repository}/releases/latest`, {
  headers: { Accept: "application/vnd.github+json" }
})
  .then((response) => (response.ok ? response.json() : Promise.reject(response.status)))
  .then(applyRelease)
  .catch(() => {
    // The Release landing page still works even when GitHub's public API is rate-limited.
  });
