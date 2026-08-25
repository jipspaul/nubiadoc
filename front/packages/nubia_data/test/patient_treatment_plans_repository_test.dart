import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:nubia_data/src/remote/patient_treatment_plans/patient_treatment_plan_dto.dart';
import 'package:nubia_data/src/remote/patient_treatment_plans/patient_treatment_plans_api.dart';
import 'package:nubia_data/src/repositories/patient_treatment_plans_repository_impl.dart';

class MockPatientTreatmentPlansApi extends Mock
    implements PatientTreatmentPlansApi {}

const _draftDto = PatientTreatmentPlanDto(
  id: 'plan-draft',
  title: 'Plan brouillon',
  status: 'draft',
);

const _proposedDto = PatientTreatmentPlanDto(
  id: 'plan-proposed',
  title: 'Plan proposé',
  status: 'proposed',
);

void main() {
  late MockPatientTreatmentPlansApi api;
  late PatientTreatmentPlansRepositoryImpl repo;

  setUp(() {
    api = MockPatientTreatmentPlansApi();
    repo = PatientTreatmentPlansRepositoryImpl(api);
  });

  group('list — un patient ne doit jamais voir un plan draft (#5294)', () {
    test('exclut les plans status == draft renvoyés par la source', () async {
      when(() => api.list()).thenAnswer((_) async => [_draftDto, _proposedDto]);

      final result = await repo.list();

      final plans = result.fold((_) => throw StateError('expected Right'),
          (plans) => plans);
      expect(plans.map((p) => p.id), ['plan-proposed']);
      expect(plans.every((p) => p.status != 'draft'), isTrue);
    });
  });
}
