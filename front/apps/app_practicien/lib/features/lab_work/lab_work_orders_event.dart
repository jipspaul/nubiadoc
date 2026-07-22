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
