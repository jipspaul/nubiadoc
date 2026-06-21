import 'package:flutter/material.dart';

abstract class BookableSlotsEvent {
  const BookableSlotsEvent();
}

class BookableSlotsLoadRequested extends BookableSlotsEvent {
  const BookableSlotsLoadRequested();
}

class CreateSlotRequested extends BookableSlotsEvent {
  const CreateSlotRequested({
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.capacity,
  });

  final DateTime date;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final int capacity;
}
