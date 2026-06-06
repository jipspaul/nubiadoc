import 'package:flutter/material.dart';
import 'package:nubia_patient/presentation/features/appointments/bloc/booking_bloc.dart';
import 'package:nubia_patient/presentation/features/appointments/widgets/slot_chip.dart';

/// Displays a scrollable grid of [AppointmentSlot] chips.
class SlotGrid extends StatelessWidget {
  const SlotGrid({
    super.key,
    required this.slots,
    required this.selectedSlot,
    required this.onSlotTap,
  });

  final List<AppointmentSlot> slots;
  final AppointmentSlot? selectedSlot;
  final ValueChanged<AppointmentSlot> onSlotTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: slots
          .map(
            (slot) => SlotChip(
              slot: slot,
              isSelected: selectedSlot?.id == slot.id,
              onTap: () => onSlotTap(slot),
            ),
          )
          .toList(),
    );
  }
}
