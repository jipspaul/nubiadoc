{{flutter_js}}
{{flutter_version_string}}
_flutter.loader.load({
  onEntrypointLoaded: async function(engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine({renderer: 'html'});
    await appRunner.runApp();
  },
});
