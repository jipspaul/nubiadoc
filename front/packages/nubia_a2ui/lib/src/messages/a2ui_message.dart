import '../model/component_def.dart';

/// Server → client A2UI messages (a2ui.org). The renderer applies each one to
/// its surface set in order, enabling progressive rendering.
sealed class A2uiMessage {
  const A2uiMessage({required this.surfaceId});
  final String surfaceId;

  static A2uiMessage fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    final surfaceId = json['surfaceId'] as String? ?? 'default';
    switch (type) {
      case 'createSurface':
        return CreateSurface(
          surfaceId: surfaceId,
          root: json['root'] as String?,
          properties: (json['properties'] as Map?)?.cast<String, dynamic>() ?? const {},
        );
      case 'updateComponents':
        final comps = (json['components'] as List? ?? const [])
            .map((e) => ComponentDef.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
        return UpdateComponents(surfaceId: surfaceId, components: comps);
      case 'updateDataModel':
        return UpdateDataModel(
          surfaceId: surfaceId,
          patch: (json['data'] as Map?)?.cast<String, dynamic>() ?? const {},
        );
      case 'deleteSurface':
        return DeleteSurface(surfaceId: surfaceId);
      default:
        throw FormatException('Unknown A2UI message type: $type');
    }
  }
}

/// Create (or reset) a surface and optionally name its root component id.
class CreateSurface extends A2uiMessage {
  const CreateSurface({
    required super.surfaceId,
    this.root,
    this.properties = const {},
  });
  final String? root;
  final Map<String, dynamic> properties;
}

/// Add or replace component definitions within a surface.
class UpdateComponents extends A2uiMessage {
  const UpdateComponents({required super.surfaceId, required this.components});
  final List<ComponentDef> components;
}

/// Merge a JSON patch into a surface's data model.
class UpdateDataModel extends A2uiMessage {
  const UpdateDataModel({required super.surfaceId, required this.patch});
  final Map<String, dynamic> patch;
}

/// Remove a surface and its contents.
class DeleteSurface extends A2uiMessage {
  const DeleteSurface({required super.surfaceId});
}

/// Client → server event emitted by an action (v1.0 `actionResponse`-style).
class A2uiClientEvent {
  const A2uiClientEvent({
    required this.surfaceId,
    required this.action,
    this.args = const {},
  });
  final String surfaceId;
  final String action;
  final Map<String, dynamic> args;

  Map<String, dynamic> toJson() => {
        'surfaceId': surfaceId,
        'action': action,
        'args': args,
      };
}
