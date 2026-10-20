{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  onEntrypointLoaded: async function(engineInitializer) {
    try {
      // Initialize Flutter Engine with HTML fallback support to prevent CanvasKit WASM network hangs
      const appRunner = await engineInitializer.initializeEngine();
      await appRunner.runApp();
    } catch (e) {
      console.warn('Flutter engine initialization error, trying fallback renderer:', e);
      try {
        const appRunner = await engineInitializer.initializeEngine({
          renderer: "html"
        });
        await appRunner.runApp();
      } catch (err) {
        console.error('Flutter initialization failed:', err);
      }
    } finally {
      const loading = document.querySelector('#loading');
      if (loading) loading.style.display = 'none';
    }
  }
});
