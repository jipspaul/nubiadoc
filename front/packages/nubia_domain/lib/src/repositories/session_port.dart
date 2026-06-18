/// PORT — session boundary exposing access-control predicates to use cases.
///
/// Implementations live in the data layer (adapts [AuthSession] from
/// nubia_core). Clinical use cases depend on this port to check
/// [canAccessClinical] before performing any gated operation.
abstract class SessionPort {
  /// True when the current authenticated principal may access clinical data.
  ///
  /// Secretaries always return `false`; practitioners and admins return `true`.
  bool get canAccessClinical;
}
