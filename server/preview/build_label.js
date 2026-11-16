// The interface build is local; the API build is fetched independently.
window.showSadohodBuild = function (server) {
  const local = window.SADOHOD_BUILD;
  const remote = server ? (server.label || server.version || 'неизвестна') : 'недоступен';
  const mismatch = server && (server.full_version !== local.full_version || server.release_id !== local.release_id);
  const text = `Админка: ${local.label} | API: ${remote}${mismatch ? ' — версии отличаются' : ''}`;
  document.querySelectorAll('[data-build-label]').forEach(el => { el.textContent = text; });
};
window.showSadohodBuild(null);
fetch('/health', {cache: 'no-store'})
  .then(response => { if (!response.ok) throw new Error('health'); return response.json(); })
  .then(window.showSadohodBuild)
  .catch(() => window.showSadohodBuild(null));
