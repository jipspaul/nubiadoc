abstract class LabWorkOrdersEvent {
  const LabWorkOrdersEvent();
}

class LabWorkOrdersLoadRequested extends LabWorkOrdersEvent {
  const LabWorkOrdersLoadRequested();
}

class LabWorkOrdersStatusChangeRequested extends LabWorkOrdersEvent {
  const LabWorkOrdersStatusChangeRequested({
    required this.orderId,
    required this.status,
  });

  final String orderId;
  final String status;
}

/// Création d'un bon (#8031, `POST /v1/cabinet/lab-work-orders`).
class LabWorkOrdersCreateRequested extends LabWorkOrdersEvent {
  const LabWorkOrdersCreateRequested({
    required this.patientId,
    required this.labName,
    required this.purchasePriceCents,
    required this.expectedReturnAt,
  });

  final String patientId;
  final String labName;
  final int purchasePriceCents;
  final String expectedReturnAt;
}
