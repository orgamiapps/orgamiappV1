{{flutter_js}}
{{flutter_build_config}}

function completeAttendusStartup() {
  const loading = document.getElementById('attendus-loading');
  if (!loading) return;

  performance.mark('attendus-first-frame');
  loading.classList.add('attendus-loading--leaving');
  window.setTimeout(() => loading.remove(), 180);
}

// Unpackaged local development uses Flutter's default asset resolution.
const attendusReleaseBase = "__ATTENDUS_RELEASE_BASE__";
const attendusPackagedRelease = attendusReleaseBase.startsWith('/releases/');
_flutter.loader
  .load({
    config: attendusPackagedRelease ? {
      entrypointBaseUrl: attendusReleaseBase,
      canvasKitBaseUrl: `${attendusReleaseBase}canvaskit/`,
    } : {},
    onEntrypointLoaded: async function (engineInitializer) {
      try {
        performance.mark('attendus-entrypoint-loaded');
        const appRunner = await engineInitializer.initializeEngine(
          attendusPackagedRelease ? {assetBase: attendusReleaseBase} : {},
        );
        await appRunner.runApp();
        window.requestAnimationFrame(completeAttendusStartup);
      } catch (error) {
        window.attendusShowStartupError(error);
        throw error;
      }
    },
  })
  .catch(window.attendusShowStartupError);
