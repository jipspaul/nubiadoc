import '../messages/a2ui_message.dart';
import '../model/component_def.dart';

/// A local fixture stream that demonstrates the renderer with no server:
/// createSurface → updateComponents → updateDataModel.
///
/// Used by each app's `/a2ui-demo` route and by widget/golden tests.
Stream<A2uiMessage> a2uiDemoStream() async* {
  const surface = 'demo';
  yield const CreateSurface(surfaceId: surface, root: 'root');
  yield const UpdateComponents(
    surfaceId: surface,
    components: [
      ComponentDef(
        id: 'root',
        component: 'Column',
        props: {'gap': 12},
        children: ['title', 'subtitle', 'status', 'cta'],
      ),
      ComponentDef(
        id: 'title',
        component: 'Text',
        props: {
          'value': {'path': '/title'}
        },
      ),
      ComponentDef(
        id: 'subtitle',
        component: 'Text',
        props: {
          'value': {'path': '/subtitle'},
          'maxLines': 2,
        },
      ),
      ComponentDef(
        id: 'status',
        component: 'StatusPill',
        props: {'label': 'Confirmé', 'status': 'success'},
      ),
      ComponentDef(
        id: 'cta',
        component: 'Button',
        props: {
          'label': {'path': '/ctaLabel'},
          'variant': 'primary',
          'onPressed': 'demo.cta',
        },
      ),
    ],
  );
  yield const UpdateDataModel(
    surfaceId: surface,
    patch: {
      'title': 'Bonjour 👋',
      'subtitle': 'Cette surface est rendue par A2UI depuis un flux local, '
          'mappée 1:1 sur les widgets Nubia.',
      'ctaLabel': 'Prendre rendez-vous',
    },
  );
}
