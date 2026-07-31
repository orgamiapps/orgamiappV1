{{flutter_js}}
{{flutter_build_config}}

function completeAttendusStartup() {
  const loading = document.getElementById('attendus-loading');
  if (!loading) return;

  performance.mark('attendus-first-frame');
  loading.classList.add('attendus-loading--leaving');
  window.setTimeout(() => loading.remove(), 180);
}

_flutter.loader
  .load({
    onEntrypointLoaded: async function (engineInitializer) {
      try {
        performance.mark('attendus-entrypoint-loaded');
        const appRunner = await engineInitializer.initializeEngine();
        await appRunner.runApp();
        window.requestAnimationFrame(completeAttendusStartup);
      } catch (error) {
        window.attendusShowStartupError(error);
        throw error;
      }
    },
  })
  .catch(window.attendusShowStartupError);
